import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  late Directory dir;
  late Database db;
  late ReferenceRepository refs;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('competitions_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);
    refs = ReferenceRepository(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('European countries qualify for UCL, UEL, Conference based on country allocation', () async {
    const int spainCountryId = 64;
    final List<Tournament> cups = await refs.internationalCups(spainCountryId);
    final List<int> ids = cups.map((t) => t.tournamentId).toList();

    expect(ids, contains(49)); // Champions League
    expect(ids, contains(51)); // Europa League
    expect(ids, contains(135)); // Conference League (UECL)
    // Feeder/super cups have no direct country allocation slots
    expect(ids, isNot(contains(54))); // UEFA Super Cup
    expect(ids, isNot(contains(56))); // Intercontinental Cup
    expect(ids, isNot(contains(163))); // FIFA Club World Cup
  });

  test(
    'Indonesia has direct ACL Elite and lower-tier AFC allocations',
    () async {
      const int indonesiaCountryId = 94;
      final List<Tournament> cups = await refs.internationalCups(
        indonesiaCountryId,
      );
      final List<int> ids = cups.map((t) => t.tournamentId).toList();

      expect(ids, contains(99)); // ACL Elite (Liga 1 champion)
      expect(ids, contains(164)); // ACL Two
      expect(ids, contains(1650)); // AFC Challenge League
      // Super/global cups are champion-based, not direct country allocations.
      expect(ids, isNot(contains(1651))); // AFC Super Cup
      expect(ids, isNot(contains(56))); // Intercontinental Cup
      expect(ids, isNot(contains(163))); // FIFA Club World Cup
      for (final int tournamentId in <int>[99, 164, 1650]) {
        final List<Map<String, Object?>> slots = await db.query(
          t.internationalSlots,
          where: 'tournament_id = ? AND country_id = ?',
          whereArgs: <Object?>[tournamentId, indonesiaCountryId],
        );
        expect(slots, hasLength(1));
        expect(slots.single['slots'], 1);
      }
    },
  );

  test(
    'previous Indonesian league champion enters ACL Elite, not ACL Two',
    () async {
      const int indonesiaId = 94;
      const int persibId = 42;
      final Tournament league = Tournament.fromMap(
        (await db.query(
          'tournaments',
          where: 'tournament_id = ?',
          whereArgs: <Object?>[85],
        )).first,
      );
      final List<Tournament> cups = await refs.internationalCups(indonesiaId);
      final SeasonGenerator generator = SeasonGenerator(db);
      final CareerPlan previous = await generator.generateCareer(
        countryId: indonesiaId,
        league: league,
        cup: null,
        internationals: cups,
        userTeamId: persibId,
      );

      final List<Map<String, Object?>> leagueFixtures = await db.query(
        'matches',
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[previous.season.seasonId, league.tournamentId],
      );
      expect(leagueFixtures, isNotEmpty);
      for (final Map<String, Object?> fixture in leagueFixtures) {
        final bool homeIsChampion = fixture['home_team_id'] == persibId;
        final bool awayIsChampion = fixture['away_team_id'] == persibId;
        await db.update(
          'matches',
          <String, Object?>{
            'status': t.matchFinished,
            'home_goals': homeIsChampion ? 8 : 1,
            'away_goals': awayIsChampion ? 8 : 0,
            'winner_id': homeIsChampion
                ? persibId
                : awayIsChampion
                ? persibId
                : fixture['home_team_id'],
          },
          where: 'match_id = ?',
          whereArgs: <Object?>[fixture['match_id']],
        );
      }

      final CareerPlan next = await generator.generateCareer(
        countryId: indonesiaId,
        league: league,
        cup: null,
        internationals: cups,
        startYear: previous.season.startYear + 1,
        userTeamId: persibId,
      );
      final List<Map<String, Object?>> entries = await db.rawQuery(
        '''
      SELECT DISTINCT tournament_id FROM matches
      WHERE season_id = ? AND tournament_id IN (99, 164)
        AND (home_team_id = ? OR away_team_id = ?)
      ''',
        <Object?>[next.season.seasonId, persibId, persibId],
      );
      final Set<int> entered = entries
          .map((Map<String, Object?> row) => row['tournament_id'] as int)
          .toSet();

      expect(entered, contains(99));
      expect(entered, isNot(contains(164)));
    },
  );

  test('user club without continental trophies does not enter FIFA Club World Cup or Super Cup', () async {
    const int indonesiaId = 94;
    final Tournament league = Tournament.fromMap(
      (await db.query('tournaments', where: 'tournament_id = 85')).first,
    );
    final List<Tournament> cups = await refs.internationalCups(indonesiaId);
    final gen = SeasonGenerator(db);
    final plan = await gen.generateCareer(
      countryId: indonesiaId,
      league: league,
      cup: null,
      internationals: cups,
      userTeamId: 42, // Persib
    );
    // First season: user has not won any feeder cup, so Persib must NOT be in 163 or 1651 or 56
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT 1 FROM matches WHERE season_id = ? AND tournament_id IN (163, 1651, 56) '
      'AND (home_team_id = 42 OR away_team_id = 42)',
      <Object?>[plan.season.seasonId],
    );
    expect(rows, isEmpty);
  });
}
