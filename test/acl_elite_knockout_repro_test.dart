import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  late Directory dir;
  late Database db;
  late ReferenceRepository refs;
  late SeasonRepository seasons;
  late CareerService career;
  late SeasonGenerator generator;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('acl_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);
    refs = ReferenceRepository(db);
    seasons = SeasonRepository(db);
    generator = SeasonGenerator(db);
    career = CareerService(
      db,
      refs: refs,
      seasons: seasons,
      squads: SquadRepository(db),
      matches: MatchRepository(db),
      messages: MessageRepository(db),
      engine: MatchEngine(random: Random(11)),
      generator: generator,
      random: Random(11),
      marketTickChance: 0,
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('simulate ACL Elite knockout progression when Persib is in ACL Elite', () async {
    const int indonesiaId = 94;
    const int persibId = 42;
    final Tournament league = Tournament.fromMap(
      (await db.query('tournaments', where: 'tournament_id = ?', whereArgs: [85])).first,
    );
    final List<Tournament> cups = await refs.internationalCups(indonesiaId);
    final CareerPlan s1 = await generator.generateCareer(
      countryId: indonesiaId,
      league: league,
      cup: null,
      internationals: cups,
      userTeamId: persibId,
    );

    // Make Persib win Liga 1 in S1
    final leagueFixtures = await db.query(
      'matches',
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: [s1.season.seasonId, league.tournamentId],
    );
    for (final f in leagueFixtures) {
      final bool homeIsChampion = f['home_team_id'] == persibId;
      final bool awayIsChampion = f['away_team_id'] == persibId;
      await db.update(
        'matches',
        {
          'status': t.matchFinished,
          'home_goals': homeIsChampion ? 5 : 1,
          'away_goals': awayIsChampion ? 5 : 0,
          'winner_id': homeIsChampion ? persibId : (awayIsChampion ? persibId : f['home_team_id']),
        },
        where: 'match_id = ?',
        whereArgs: [f['match_id']],
      );
    }

    // Generate S2 with Persib in ACL Elite
    final CareerPlan s2 = await generator.generateCareer(
      countryId: indonesiaId,
      league: league,
      cup: null,
      internationals: cups,
      startYear: s1.season.startYear + 1,
      userTeamId: persibId,
    );

    final aclMatches = await db.query(
      'matches',
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: [s2.season.seasonId, 99],
    );

    final groupMatches = aclMatches.where((m) => m['phase'] == 0).toList();
    final groups = groupMatches.map((m) => m['group_id'] as int).toSet();
    print('ACL Elite S2 total group matches: ${groupMatches.length}, groups: ${groups.length}');

    // Load team cache
    final teamRows = await db.rawQuery('SELECT tm.* FROM season_teams st JOIN teams tm ON tm.team_id = st.team_id WHERE st.season_id = ?', [s2.season.seasonId]);
    final teamCache = {for (final r in teamRows) r['team_id'] as int: Team.fromMap(r)};

    // Finish all group matches
    for (final m in groupMatches) {
      await db.update(
        'matches',
        {
          'status': t.matchFinished,
          'home_goals': 2,
          'away_goals': 1,
          'winner_id': m['home_team_id'],
        },
        where: 'match_id = ?',
        whereArgs: [m['match_id']],
      );
    }

    // Now progress cup round by round
    int step = 0;
    while (step < 10) {
      step++;
      final bool scheduled = await career.maybeScheduleNextCupRound(
        seasonId: s2.season.seasonId,
        cupTournamentId: 99,
        teamCache: teamCache,
      );
      print('Step $step: maybeScheduleNextCupRound returned $scheduled');
      if (!scheduled) break;

      // Check current max phase
      final maxPhaseRow = await db.rawQuery('SELECT MAX(phase) as p FROM matches WHERE season_id = ? AND tournament_id = ?', [s2.season.seasonId, 99]);
      final int phase = maxPhaseRow.first['p'] as int;

      final phaseMatches = await db.query(
        'matches',
        where: 'season_id = ? AND tournament_id = ? AND phase = ?',
        whereArgs: [s2.season.seasonId, 99, phase],
      );

      final teamsInPhase = <int>{
        for (final m in phaseMatches) ...[m['home_team_id'] as int, m['away_team_id'] as int],
      };

      final dates = phaseMatches.map((m) => m['date']).toSet();
      print('Phase $phase: ${phaseMatches.length} matches, ${teamsInPhase.length} teams (${teamsInPhase.toList()}), dates: $dates');

      // Finish matches of this phase
      for (final m in phaseMatches) {
        final home = m['home_team_id'] as int;
        final leg = m['leg'] as int;
        await db.update(
          'matches',
          {
            'status': t.matchFinished,
            'home_goals': leg == 1 ? 2 : 1,
            'away_goals': 0,
            'winner_id': home,
          },
          where: 'match_id = ?',
          whereArgs: [m['match_id']],
        );
      }
    }
  });

  test('simulate S2 day-by-day to see when ACL Elite finishes and who wins', () async {
    const int indonesiaId = 94;
    const int persibId = 42;
    final Tournament league = Tournament.fromMap(
      (await db.query('tournaments', where: 'tournament_id = ?', whereArgs: [85])).first,
    );
    final List<Tournament> cups = await refs.internationalCups(indonesiaId);
    final CareerPlan s1 = await generator.generateCareer(
      countryId: indonesiaId,
      league: league,
      cup: null,
      internationals: cups,
      userTeamId: persibId,
    );

    // Make Persib win Liga 1 in S1
    final leagueFixtures = await db.query(
      'matches',
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: [s1.season.seasonId, league.tournamentId],
    );
    for (final f in leagueFixtures) {
      final bool homeIsChampion = f['home_team_id'] == persibId;
      final bool awayIsChampion = f['away_team_id'] == persibId;
      await db.update(
        'matches',
        {
          'status': t.matchFinished,
          'home_goals': homeIsChampion ? 5 : 1,
          'away_goals': awayIsChampion ? 5 : 0,
          'winner_id': homeIsChampion ? persibId : (awayIsChampion ? persibId : f['home_team_id']),
        },
        where: 'match_id = ?',
        whereArgs: [f['match_id']],
      );
    }

    // Generate S2 with Persib in ACL Elite
    final CareerPlan s2 = await generator.generateCareer(
      countryId: indonesiaId,
      league: league,
      cup: null,
      internationals: cups,
      startYear: s1.season.startYear + 1,
      userTeamId: persibId,
    );

    final teamRows = await db.rawQuery('SELECT tm.* FROM season_teams st JOIN teams tm ON tm.team_id = st.team_id WHERE st.season_id = ?', [s2.season.seasonId]);
    final teamCache = {for (final r in teamRows) r['team_id'] as int: Team.fromMap(r)};

    // Simulate matchday by matchday
    final seasonTournamentsRows = await db.rawQuery(
      'SELECT tu.* FROM season_tournaments st JOIN tournaments tu ON tu.tournament_id = st.tournament_id WHERE st.season_id = ?',
      [s2.season.seasonId],
    );
    final seasonTournaments = [for (final r in seasonTournamentsRows) Tournament.fromMap(r)];
    final cupTournaments = seasonTournaments.where((t) => t.tournamentId != league.tournamentId).toList();

    int days = 0;
    while (days < 400) {
      days++;
      final nextMatchRow = await db.rawQuery(
        'SELECT MIN(date) as d FROM matches WHERE season_id = ? AND status = ?',
        [s2.season.seasonId, t.matchScheduled],
      );
      final String? nextDate = nextMatchRow.first['d'] as String?;
      if (nextDate == null) {
        print('No more scheduled matches at day iteration $days');
        break;
      }

      // Simulate matches on this date
      await career.simulateMatchday(
        seasonId: s2.season.seasonId,
        date: nextDate,
        userTeamId: persibId,
        userLeagueId: league.tournamentId,
      );

      // Check next cup round
      for (final cup in cupTournaments) {
        await career.maybeScheduleNextCupRound(
          seasonId: s2.season.seasonId,
          cupTournamentId: cup.tournamentId,
          teamCache: teamCache,
        );
      }

      if (await career.seasonComplete(s2.season.seasonId)) {
        print('Season complete at date $nextDate (day iteration $days)');
        break;
      }
    }

    // Check ACL Elite matches and winner
    final aclAll = await db.query(
      'matches',
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: [s2.season.seasonId, 99],
    );
    print('ACL Elite total matches in S2: ${aclAll.length}');
    final phases = aclAll.map((m) => m['phase'] as int).toSet();
    print('ACL Elite phases present: $phases');
    for (final p in phases) {
      final pMatches = aclAll.where((m) => m['phase'] == p).toList();
      final finished = pMatches.where((m) => m['status'] == t.matchFinished).length;
      print('Phase $p: ${pMatches.length} matches ($finished finished)');
    }

    final winnerRows = await db.rawQuery(
      'SELECT winner_id FROM matches WHERE season_id = ? AND tournament_id = ? AND phase = (SELECT MAX(phase) FROM matches WHERE season_id = ? AND tournament_id = ?) AND winner_id IS NOT NULL',
      [s2.season.seasonId, 99, s2.season.seasonId, 99],
    );
    final int? winner = winnerRows.isEmpty ? null : winnerRows.first['winner_id'] as int?;
    print('ACL Elite knockout winner: $winner (${teamCache[winner]?.name})');

    final trophies = await seasons.clubTrophies(persibId);
    print('Persib trophies: ${trophies.map((tr) => tr.tournamentName).toList()}');

    print('--- Testing Offseason ---');
    final off1 = await career.beginOffseason(userTeamId: persibId, onProgress: (_) {});
    print('Offseason step: ${off1.current}');
    final res1 = await career.advanceOffseason(userTeamId: persibId, onProgress: (s) => print('Progress: $s'));
    print('Advance 1 (summary -> contracts) result: $res1');
    final off2 = await career.offseasonState();
    print('Offseason step after 1: ${off2?.current}');

    final stopwatch = Stopwatch()..start();
    final res2 = await career.advanceOffseason(userTeamId: persibId, onProgress: (s) => print('Progress: $s'));
    stopwatch.stop();
    print('Advance 2 (contracts -> development) took ${stopwatch.elapsedMilliseconds}ms, result: $res2');
    final off3 = await career.offseasonState();
    print('Offseason step after 2: ${off3?.current}');
  });
}
