import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/training.dart';

/// Covers the profile/club-insight queries added on top of the existing data
/// model, including the stadium expansion transaction.
void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_insights_');
    final File source = File(p.join('assets', 'data', 'superkickoff_2025.db'));
    final File target = File(p.join(tempDir.path, 'insights.db'));
    await source.copy(target.path);
    db = await databaseFactory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await AppDatabase.ensureLocalTables(db);
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('club overview, player profile and stadium expansion', () async {
    final ReferenceRepository refs = ReferenceRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final List<Team> clubs = await refs.teamsForDivision(141, 1);
    expect(clubs, isNotEmpty);

    ClubOverview? club;
    for (final Team team in clubs) {
      final ClubOverview? candidate = await squads.clubOverview(team.teamId);
      if (candidate != null && !candidate.atMaxCapacity) {
        club = candidate;
        break;
      }
    }
    expect(club, isNotNull, reason: 'expected a stadium with room to expand');
    expect(club!.stadiumName, isNotEmpty);
    expect(club.capacity, greaterThan(0));
    expect(
      club.maxGeneral + club.maxStand + club.maxTerrace + club.maxBoxes,
      greaterThanOrEqualTo(club.capacity),
    );

    final List<Player> squad = await squads.squadForTeam(club.team.teamId);
    expect(squad, isNotEmpty);
    final PlayerDetail? detail = await squads.playerDetail(
      squad.first.playerId,
    );
    expect(detail, isNotNull);
    expect(detail!.player.playerId, squad.first.playerId);
    expect(detail.clubName, club.team.name);
    expect(detail.contract, isNotNull);
    expect(detail.stats.isEmpty, isTrue);

    // Give the club enough money, then expand one tier step.
    await db.update(
      t.teams,
      <String, Object?>{'budget': 500000000},
      where: 'team_id = ?',
      whereArgs: <Object?>[club.team.teamId],
    );
    final int oldCapacity = club.capacity;
    final String? error = await squads.expandStadium(club.team.teamId);
    expect(error, isNull);
    final ClubOverview? expanded = await squads.clubOverview(club.team.teamId);
    expect(expanded, isNotNull);
    expect(expanded!.capacity, greaterThan(oldCapacity));
    expect(expanded.team.budget, lessThan(500000000));
  });

  test('transfer history includes both directions', () async {
    final ReferenceRepository refs = ReferenceRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final Team club = (await refs.teamsForDivision(141, 1)).first;
    final List<Player> squad = await squads.squadForTeam(club.teamId);
    await db.insert(t.playerTransfers, <String, Object?>{
      'player_id': squad.first.playerId,
      'from_team_id': club.teamId,
      'to_team_id': null,
      'type': 1,
      'value': 1200000,
      'date': '2026-01-01',
    });
    final List<TransferRecord> history = await squads.transferHistory(
      club.teamId,
    );
    expect(history, isNotEmpty);
    expect(history.first.playerId, squad.first.playerId);
    expect(history.first.fromTeamId, club.teamId);
  });

  test(
    'contract renewal extends the deal and charges a signing bonus',
    () async {
      final ReferenceRepository refs = ReferenceRepository(db);
      final SquadRepository squads = SquadRepository(db);
      final Team club = (await refs.teamsForDivision(141, 1)).first;
      final List<Player> squad = await squads.squadForTeam(club.teamId);
      PlayerDetail? target;
      for (final Player player in squad) {
        final PlayerDetail? detail = await squads.playerDetail(player.playerId);
        if (detail?.contract != null) {
          target = detail;
          break;
        }
      }
      expect(target, isNotNull, reason: 'expected a contracted squad player');
      final PlayerDetail targetDetail = target!;
      final int oldSalary = targetDetail.contract!.salary;
      final int oldEndYear = int.parse(
        targetDetail.contract!.endDate.substring(0, 4),
      );
      final int expectedEndYear = (oldEndYear > 2026 ? oldEndYear : 2026) + 2;
      await db.update(
        t.teams,
        <String, Object?>{'budget': 500000000},
        where: 'team_id = ?',
        whereArgs: <Object?>[club.teamId],
      );
      final String? error = await squads.renewContract(
        playerId: targetDetail.player.playerId,
        teamId: club.teamId,
        currentYear: 2026,
      );
      expect(error, isNull);
      final PlayerDetail? renewed = await squads.playerDetail(
        targetDetail.player.playerId,
      );
      expect(renewed, isNotNull);
      expect(renewed!.contract!.salary, greaterThan(oldSalary));
      expect(renewed.contract!.endDate.substring(0, 4), '$expectedEndYear');
      expect(renewed.player.salary, renewed.contract!.salary);
      final ClubOverview? overview = await squads.clubOverview(club.teamId);
      expect(overview!.team.budget, lessThan(500000000));
    },
  );

  test('suspensions reach the squad map and player profile', () async {
    final ReferenceRepository refs = ReferenceRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final Team club = (await refs.teamsForDivision(141, 1)).first;
    final Player player = (await squads.squadForTeam(club.teamId)).first;
    await db.insert(t.suspensions, <String, Object?>{
      'player_id': player.playerId,
      'type': 2,
      'matches_remaining': 2,
    });
    final Map<int, int> banned = await squads.suspensionsForTeam(club.teamId);
    expect(banned[player.playerId], 2);
    final PlayerDetail? detail = await squads.playerDetail(player.playerId);
    expect(detail!.suspensionMatches, 2);
  });

  test('each training focus can be used once per matchday', () async {
    final ReferenceRepository refs = ReferenceRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final Team club = (await refs.teamsForDivision(141, 1)).first;
    await db.update(
      t.teams,
      <String, Object?>{'budget': 1000000},
      where: 'team_id = ?',
      whereArgs: <Object?>[club.teamId],
    );
    const int seasonId = 999;
    TrainingState state = await squads.trainingStatus(
      teamId: club.teamId,
      seasonId: seasonId,
    );
    expect(state.doneFocuses, isEmpty);
    final TrainingFocus focus = TrainingFocus.values.firstWhere(
      (TrainingFocus f) => (state.eligible[f.name] ?? 0) > 0,
    );
    final TrainingOutcome outcome = await squads.runTraining(
      teamId: club.teamId,
      seasonId: seasonId,
      focus: focus,
    );
    expect(outcome.ok, isTrue);
    expect(outcome.improved, isNotEmpty);
    expect(outcome.cost, TrainingRules.cost);
    state = await squads.trainingStatus(
      teamId: club.teamId,
      seasonId: seasonId,
    );
    expect(state.doneFocuses, <String>{focus.name});
    expect(state.sessions, 1);
    final TrainingOutcome second = await squads.runTraining(
      teamId: club.teamId,
      seasonId: seasonId,
      focus: focus,
    );
    expect(second.ok, isFalse);

    // A different focus is still available on the same matchday.
    final TrainingFocus? other = TrainingFocus.values
        .where((TrainingFocus f) => f != focus && (state.eligible[f.name] ?? 0) > 0)
        .firstOrNull;
    if (other != null) {
      final TrainingOutcome third = await squads.runTraining(
        teamId: club.teamId,
        seasonId: seasonId,
        focus: other,
      );
      expect(third.ok, isTrue, reason: third.error);
    }
  });
}
