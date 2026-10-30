import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  test('FIFA rankings and international fixture postponements work cleanly', () async {
    sqfliteFfiInit();
    final tempDir = await Directory.systemTemp.createTemp('superkickoff_fifa_test_');
    final dbPath = '${tempDir.path}/sim_fifa.db';
    await File('assets/data/superkickoff_2025.db').copy(dbPath);

    final db = await AppDatabase.openFile(dbPath);
    final refRepo = ReferenceRepository(db);
    final seasonRepo = SeasonRepository(db);
    final squadRepo = SquadRepository(db);
    final matchRepo = MatchRepository(db);
    final msgRepo = MessageRepository(db);
    final engine = MatchEngine();
    final gen = SeasonGenerator(db);

    await squadRepo.refreshAllTeamPowers();

    final userTeamId = 42; // Persib
    final intlCups = await refRepo.internationalCups(94);
    final domesticLeagues = await refRepo.domesticLeagues(94);
    final league = domesticLeagues.first;
    final cupRow = await refRepo.nationalCup(94);
    final cup = Tournament.fromMap(cupRow!);

    final plan = await gen.generateCareer(
      countryId: 94,
      league: league,
      cup: cup,
      internationals: intlCups,
      otherLeagues: domesticLeagues.where((l) => l.tournamentId != league.tournamentId).toList(),
      startYear: 2025,
      userTeamId: userTeamId,
    );

    final careerService = CareerService(
      db,
      refs: refRepo,
      seasons: seasonRepo,
      squads: squadRepo,
      matches: matchRepo,
      messages: msgRepo,
      engine: engine,
      generator: gen,
    );

    // 1. Verify FIFA Rankings
    final rankings = await careerService.nationalTeams.getFifaRankings();
    expect(rankings, isNotEmpty);
    expect(rankings.first.power, greaterThanOrEqualTo(rankings[1].power));
    print('Top 3 FIFA Rankings:');
    for (int i = 0; i < 3; i++) {
      print('  #${i + 1} ${rankings[i].name} (Power: ${rankings[i].power}, Prev: ${rankings[i].previousRank})');
    }

    // Check Indonesia ranking
    final indo = rankings.firstWhere((c) => c.countryId == 94);
    final indoRank = rankings.indexOf(indo) + 1;
    print('Indonesia Rank: #$indoRank (Power: ${indo.power})');
    expect(indoRank, greaterThan(0));

    // Test rankMovement indicator
    expect(indo.rankMovement(indoRank), isNotNull);

    // 2. Check International Callups & Postponements
    // Simulate callups for October window (approx 2025-10-06)
    await careerService.ensureInternationalCallups(
      seasonId: plan.season.seasonId,
      date: '2025-10-06',
      userTeamId: userTeamId,
    );

    final duties = await careerService.dutiesForClub(userTeamId, '2025-10-06');
    print('Pemain Persib di Timnas saat jeda Oktober: ${duties.length}');

    // Reschedule clashing fixtures
    final postponed = await careerService.rescheduleClashingDutyFixtures(
      plan.season.seasonId,
      userTeamId: userTeamId,
    );
    print('Fixture klub yang digeser dari jeda internasional: $postponed');

    // 3. Verify International match simulation through date
    final scheduledBeforeSim = await careerService.internationalSimulation.simulatePendingMatchesThroughDate(
      plan.season.seasonId,
      '2025-10-15',
    );
    print('Pertandingan timnas yang berhasil disimulasikan dan ada skornya: $scheduledBeforeSim');

    final intlMatches = await careerService.countryMatchesForSeason(plan.season.seasonId);
    final finishedMatches = intlMatches.where((m) => m.status == 2).toList();
    expect(finishedMatches, isNotEmpty, reason: 'Laga internasional yang lewat tanggal harus sudah ada skornya (status 2)');
    print('Laga internasional selesai dengan skor: ${finishedMatches.length}');
    for (final m in finishedMatches.take(3)) {
      print('  - ${m.date}: Negara ${m.homeCountryId} ${m.homeGoals} - ${m.awayGoals} Negara ${m.awayCountryId}');
    }

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
