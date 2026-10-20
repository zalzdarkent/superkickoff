import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/game/season_generator.dart';

/// Integration test: generate a real 2025 season from the bundled database
/// into a throw-away copy so the asset stays untouched.
void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_test_');
    final File source = File(p.join('assets', 'data', 'superkickoff_2025.db'));
    expect(source.existsSync(), isTrue,
        reason: 'Bundled database asset must exist');
    final File target = File(p.join(tempDir.path, 'test.db'));
    await source.copy(target.path);
    db = await databaseFactory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<Map<String, Object?>> findTournament({
    required int countryId,
    required int organization,
    int? divisionId,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ?
        AND tu.organization = ?
        ${divisionId == null ? '' : 'AND tu.division_id = ?'}
      LIMIT 1
    ''', <Object?>[
      countryId,
      organization,
      ?divisionId,
    ]);
    expect(rows, isNotEmpty,
        reason: 'No tournament organization=$organization for country $countryId');
    return rows.first;
  }

  test('generates a full league + cup season', () async {
    const int countryId = 141; // Mexico, known to have an 18-team league.
    final Tournament league =
        Tournament.fromMap(await findTournament(
      countryId: countryId,
      organization: t.orgLeague,
      divisionId: 1,
    ));
    final Tournament cup = Tournament.fromMap(await findTournament(
      countryId: countryId,
      organization: t.orgNationalCup,
    ));

    final CareerPlan plan = await SeasonGenerator(db, random: null)
        .generateCareer(countryId: countryId, league: league, cup: cup);

    expect(plan.teamCount, greaterThanOrEqualTo(18));
    expect(plan.leagueRounds, 34);
    expect(plan.matchCount, 306,
        reason: '18-team double round robin: 34 rounds x 9 games');

    final List<Map<String, Object?>> seasons = await db.query(t.seasons);
    expect(seasons.length, 1);
    expect(seasons.first['start_year'], 2025);

    final List<Map<String, Object?>> registered = await db.query(
      t.seasonTeams,
      where: 'season_id = ?',
      whereArgs: <Object?>[plan.season.seasonId],
    );
    expect(registered.length, greaterThanOrEqualTo(18),
        reason: 'every cup participant is registered for the season');

    final List<Map<String, Object?>> matches = await db.query(
      t.matches,
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: <Object?>[plan.season.seasonId, league.tournamentId],
    );
    expect(matches.length, 306);

    // Each club plays 34 league games: 17 home + 17 away.
    final Map<int, int> appearances = <int, int>{};
    for (final Map<String, Object?> row in matches) {
      for (final String side in <String>['home_team_id', 'away_team_id']) {
        final int id = row[side] as int;
        appearances[id] = (appearances[id] ?? 0) + 1;
      }
    }
    expect(appearances.length, 18);
    expect(appearances.values.every((int v) => v == 34), isTrue);

    // All fixtures start scheduled, with parseable dates.
    for (final Map<String, Object?> row in matches) {
      expect(row['status'], t.matchScheduled);
      expect(DateTime.tryParse(row['date'] as String), isNotNull);
    }

    // Cup fixtures were generated for the same season.
    final List<Map<String, Object?>> cupMatches = await db.query(
      t.matches,
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: <Object?>[plan.season.seasonId, cup.tournamentId],
    );
    // 64 of the 74 clubs enter a six-round knockout bracket.
    expect(cupMatches.length, 32);
    expect(plan.cupRounds, 6);
  });

  test('double round robin pairs every team once per round', () {
    final List<int> ids = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9];
    final List<FixtureSlot> slots = doubleRoundRobin(ids);
    expect(slots.length, 9 * 8); // every ordered pair once
    final Set<String> pairs = <String>{
      for (final FixtureSlot s in slots) '${s.home}-${s.away}',
    };
    expect(pairs.length, slots.length);
    for (final FixtureSlot slot in slots) {
      expect(slot.home == slot.away, isFalse);
    }
  });
}
