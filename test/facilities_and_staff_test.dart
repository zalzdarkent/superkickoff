import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/facilities_repository.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/scouting_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  late Directory dir;
  late Database db;
  late FacilitiesRepository facilitiesRepo;
  late SquadRepository squadRepo;
  late ScoutingRepository scoutingRepo;
  late CareerService careerService;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('facilities_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);

    facilitiesRepo = FacilitiesRepository(db);
    squadRepo = SquadRepository(db);
    scoutingRepo = ScoutingRepository(db);

    final ReferenceRepository refs = ReferenceRepository(db);
    final SeasonRepository seasons = SeasonRepository(db);
    final MatchRepository matches = MatchRepository(db);
    final MessageRepository messages = MessageRepository(db);
    final SeasonGenerator generator = SeasonGenerator(db);

    careerService = CareerService(
      db,
      refs: refs,
      seasons: seasons,
      squads: squadRepo,
      matches: matches,
      messages: messages,
      engine: MatchEngine(),
      generator: generator,
      scouting: scoutingRepo,
      facilities: facilitiesRepo,
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  group('Club Facilities & Staff Repository', () {
    test('default facilities start at level 1 and can be upgraded with budget deduction', () async {
      const int teamId = 42;
      // Set team budget to 15,000,000
      await db.update('teams', <String, dynamic>{'budget': 15000000}, where: 'team_id = ?', whereArgs: <Object>[teamId]);

      final ClubFacilities initial = await facilitiesRepo.getFacilities(teamId);
      expect(initial.trainingLevel, 1);
      expect(initial.medicalLevel, 1);
      expect(initial.trainingMaxPlayers, 3);
      expect(initial.trainingFitnessGain, 4);
      expect(initial.injuryReductionRate, 0.0);

      // Upgrade Training Ground to Level 2 (cost 1,200,000)
      final String? errTr1 = await facilitiesRepo.upgradeTrainingGround(teamId);
      expect(errTr1, isNull);

      final ClubFacilities afterTr1 = await facilitiesRepo.getFacilities(teamId);
      expect(afterTr1.trainingLevel, 2);
      expect(afterTr1.trainingMaxPlayers, 4);

      final int budgetAfterTr1 = (await db.query('teams', where: 'team_id = ?', whereArgs: <Object>[teamId])).first['budget'] as int;
      expect(budgetAfterTr1, 15000000 - 1200000);

      // Upgrade Medical Centre to Level 2 (cost 1,000,000)
      final String? errMed1 = await facilitiesRepo.upgradeMedicalCentre(teamId);
      expect(errMed1, isNull);

      final ClubFacilities afterMed1 = await facilitiesRepo.getFacilities(teamId);
      expect(afterMed1.medicalLevel, 2);
      expect(afterMed1.injuryReductionRate, greaterThan(0.0));

      final int budgetAfterMed1 = (await db.query('teams', where: 'team_id = ?', whereArgs: <Object>[teamId])).first['budget'] as int;
      expect(budgetAfterMed1, 15000000 - 1200000 - 1000000);
    });

    test('facility upgrade fails when budget is insufficient', () async {
      const int teamId = 42;
      await db.update('teams', <String, dynamic>{'budget': 100}, where: 'team_id = ?', whereArgs: <Object>[teamId]);

      final String? err = await facilitiesRepo.upgradeTrainingGround(teamId);
      expect(err, isNotNull);

      final ClubFacilities fac = await facilitiesRepo.getFacilities(teamId);
      expect(fac.trainingLevel, 1);
    });

    test('facility upgrades are capped at level 5', () async {
      const int teamId = 42;
      await db.update('teams', <String, dynamic>{'budget': 100000000}, where: 'team_id = ?', whereArgs: <Object>[teamId]);

      for (int i = 0; i < 6; i++) {
        await facilitiesRepo.upgradeTrainingGround(teamId);
      }

      final ClubFacilities fac = await facilitiesRepo.getFacilities(teamId);
      expect(fac.trainingLevel, 5);
      expect(fac.isMaxTraining, isTrue);
      expect(fac.trainingMaxPlayers, 7);
      expect(fac.trainingFitnessGain, 8);
    });

    test('staff recruitment market, hiring, firing, and payroll calculation', () async {
      const int teamId = 42;
      await db.update('teams', <String, dynamic>{'budget': 10000000}, where: 'team_id = ?', whereArgs: <Object>[teamId]);

      final List<ClubStaff> initialStaff = await facilitiesRepo.getStaff(teamId);
      expect(initialStaff, isEmpty);

      final List<ClubStaff> candidates = facilitiesRepo.availableStaffCandidates();
      expect(candidates, isNotEmpty);

      final ClubStaff physio = candidates.firstWhere((ClubStaff s) => s.role == 'head_physio');
      final int hiringFee = facilitiesRepo.hiringFeeForStaff(physio);

      // Hire physio
      final String? hireErr = await facilitiesRepo.hireStaff(
        teamId: teamId,
        candidate: physio,
        currentDate: '2025-08-01',
      );
      expect(hireErr, isNull);

      final List<ClubStaff> staffList = await facilitiesRepo.getStaff(teamId);
      expect(staffList.length, 1);
      expect(staffList.first.role, 'head_physio');
      expect(staffList.first.stars, physio.stars);

      final int budgetAfterHire = (await db.query('teams', where: 'team_id = ?', whereArgs: <Object>[teamId])).first['budget'] as int;
      expect(budgetAfterHire, 10000000 - hiringFee);

      // Weekly payroll should equal physio's salary
      final int payroll = await facilitiesRepo.totalWeeklyStaffWages(teamId);
      expect(payroll, physio.salary);

      // Fire staff
      await facilitiesRepo.fireStaff(teamId, 'head_physio');
      final List<ClubStaff> staffAfterFire = await facilitiesRepo.getStaff(teamId);
      expect(staffAfterFire, isEmpty);
      expect(await facilitiesRepo.totalWeeklyStaffWages(teamId), 0);
    });

    test('tactical analyst generates opponent tactical report', () async {
      const int userTeamId = 42;
      const int opponentTeamId = 43;

      // Hire tactical analyst with 4 stars
      final ClubStaff analyst = const ClubStaff(
        staffId: 0,
        teamId: userTeamId,
        role: 'tactical_analyst',
        name: 'Arrigo Sacchi',
        stars: 4,
        salary: 12000,
        specialty: 'High Press Counter',
      );
      await facilitiesRepo.hireStaff(
        teamId: userTeamId,
        candidate: analyst,
        currentDate: '2025-08-01',
      );

      final TacticalAnalysisReport report = await facilitiesRepo.generateTacticalReport(
        userTeamId: userTeamId,
        opponentTeamId: opponentTeamId,
      );

      expect(report.opponent.name, isNotEmpty);
      expect(report.formation, isNotEmpty);
      expect(report.predictedMentality, isNotEmpty);
      expect(report.vulnerabilities, isNotEmpty);
      expect(report.counterTactics, isNotEmpty);
      expect(report.analyst?.stars, 4);
    });
  });

  group('Match Engine & Housekeeping Integration', () {
    test('match engine accepts injury reduction and tactical bonuses', () async {
      final List<Player> homeSquad = await squadRepo.squadForTeam(42);
      final List<Player> awaySquad = await squadRepo.squadForTeam(43);

      final MatchEngine engine = MatchEngine();
      final MatchInput inputWithPhysio = MatchInput(
        homeSquad: homeSquad,
        awaySquad: awaySquad,
        homeTeamId: 42,
        awayTeamId: 43,
        homePower: 80,
        capacityGeneral: 10000,
        capacityStand: 5000,
        capacityTerrace: 3000,
        capacityBoxes: 500,
        homeInjuryReduction: 0.40, // 40% reduction from facilities & physio
        homeTacticalBonus: 3,     // +3 power bonus from analyst
      );

      final MatchResult result = engine.simulate(inputWithPhysio);
      expect(result.homeGoals, isNotNull);
      expect(result.awayGoals, isNotNull);
    });

    test('weekly housekeeping applies physio & medical recovery and processes staff payroll', () async {
      const int teamId = 42;
      await db.update('teams', <String, dynamic>{'budget': 50000000}, where: 'team_id = ?', whereArgs: <Object>[teamId]);

      // Upgrade medical facility to level 4
      for (int i = 0; i < 3; i++) {
        await facilitiesRepo.upgradeMedicalCentre(teamId);
      }

      // Hire 4-star Physio
      final String? hireErr = await facilitiesRepo.hireStaff(
        teamId: teamId,
        candidate: const ClubStaff(
          staffId: 0,
          teamId: teamId,
          role: 'head_physio',
          name: 'Eva Carneiro',
          stars: 4,
          salary: 8000,
          specialty: 'Muscle Recovery',
        ),
        currentDate: '2025-08-01',
      );
      expect(hireErr, isNull);

      // Set a player's fitness to 25 (exhausted/injured state)
      final List<Player> teamPlayers = await squadRepo.squadForTeam(teamId);
      final int hurtPlayerId = teamPlayers.first.playerId;

      await db.update(
        'players',
        <String, dynamic>{
          'fitness': 25,
        },
        where: 'player_id = ?',
        whereArgs: <Object>[hurtPlayerId],
      );

      final int budgetBefore = (await db.query('teams', where: 'team_id = ?', whereArgs: <Object>[teamId])).first['budget'] as int;

      // Run housekeeping
      await careerService.weeklyHousekeeping(userTeamId: teamId, seasonId: 1);

      // Verify budget deducted weekly salary (8,000)
      final int budgetAfter = (await db.query('teams', where: 'team_id = ?', whereArgs: <Object>[teamId])).first['budget'] as int;
      expect(budgetAfter, budgetBefore - 8000);

      // Verify player got extra recovery bonus
      final Map<String, dynamic> updatedPlayer = (await db.query(
        'players',
        where: 'player_id = ?',
        whereArgs: <Object>[hurtPlayerId],
      )).first;

      // Fitness should recover above 25
      expect(updatedPlayer['fitness'] as int, greaterThan(25));
    });

    test('training ground level scales training session capacity in squad repository', () async {
      const int teamId = 42;
      // Upgrade training ground to level 3
      await facilitiesRepo.upgradeTrainingGround(teamId);
      await facilitiesRepo.upgradeTrainingGround(teamId);

      final TrainingState state = await squadRepo.trainingStatus(teamId: teamId, seasonId: 1);
      expect(state.trainingLevel, 3);
      expect(state.maxPlayers, 5); // 3 + (3 - 1)
      expect(state.fitnessGain, 6); // 4 + (3 - 1)
      expect(state.powerGain, 2);   // level >= 3 gets +2 power gain
    });
  });
}
