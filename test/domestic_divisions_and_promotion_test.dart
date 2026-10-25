import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
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
  late SquadRepository squads;
  late MatchRepository matches;
  late MessageRepository messages;
  late SeasonGenerator generator;
  late CareerService service;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('multi_division_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);

    refs = ReferenceRepository(db);
    seasons = SeasonRepository(db);
    squads = SquadRepository(db);
    matches = MatchRepository(db);
    messages = MessageRepository(db);
    generator = SeasonGenerator(db, random: Random(42));
    service = CareerService(
      db,
      refs: refs,
      seasons: seasons,
      squads: squads,
      matches: matches,
      messages: messages,
      engine: MatchEngine(random: Random(42)),
      generator: generator,
      random: Random(42),
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('ReferenceRepository domesticLeagues returns all divisions in ascending order', () async {
    const int indonesiaCountryId = 94;
    final List<Tournament> leagues = await refs.domesticLeagues(indonesiaCountryId);

    expect(leagues.length, 3);
    expect(leagues[0].divisionId, 1);
    expect(leagues[0].name, 'BRI Super League');
    expect(leagues[1].divisionId, 2);
    expect(leagues[1].name, 'Pegadaian Championship');
    expect(leagues[2].divisionId, 3);
    expect(leagues[2].name, 'Liga Nusantara');
  });

  test('generateCareer creates fixtures and registrations for all domestic divisions', () async {
    const int indonesiaCountryId = 94;
    final List<Tournament> allLeagues = await refs.domesticLeagues(indonesiaCountryId);
    final Tournament div1 = allLeagues.first;
    final List<Tournament> others = allLeagues.sublist(1);

    final CareerPlan plan = await generator.generateCareer(
      countryId: indonesiaCountryId,
      league: div1,
      cup: null,
      otherLeagues: others,
      startYear: 2025,
    );

    // Verify all 3 domestic divisions are registered in season_tournaments
    final List<Map<String, Object?>> seasonTours = await db.query(
      t.seasonTournaments,
      where: 'season_id = ?',
      whereArgs: <Object?>[plan.season.seasonId],
    );
    final Set<int> tourIds = seasonTours.map((r) => r['tournament_id'] as int).toSet();
    expect(tourIds, contains(85));
    expect(tourIds, contains(86));
    expect(tourIds, contains(189));

    // Verify matches exist for each division
    for (final Tournament lg in allLeagues) {
      final int count = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM matches WHERE season_id = ? AND tournament_id = ?',
          <Object?>[plan.season.seasonId, lg.tournamentId],
        ),
      )!;
      expect(count, greaterThan(0), reason: 'League ${lg.name} should have fixtures');
    }
  });

  test('addDomesticLeagues provisions missing lower divisions on existing save', () async {
    const int indonesiaCountryId = 94;
    final List<Tournament> allLeagues = await refs.domesticLeagues(indonesiaCountryId);
    final Tournament div1 = allLeagues.first;

    // Simulate an old save that only generated Div 1
    final CareerPlan plan = await generator.generateCareer(
      countryId: indonesiaCountryId,
      league: div1,
      cup: null,
      startYear: 2025,
    );

    // Div 2 and Div 3 are not linked yet
    final int beforeCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM season_tournaments WHERE season_id = ?',
        <Object?>[plan.season.seasonId],
      ),
    )!;
    expect(beforeCount, 1);

    // Dynamically add missing domestic leagues
    final Map<int, Team> cache = <int, Team>{};
    final int added = await generator.addDomesticLeagues(
      season: plan.season,
      countryId: indonesiaCountryId,
      leagues: allLeagues,
      teamCache: cache,
    );

    expect(added, 2);

    final int afterCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM season_tournaments WHERE season_id = ?',
        <Object?>[plan.season.seasonId],
      ),
    )!;
    expect(afterCount, 3);
  });

  test('Promotion and relegation properly swaps top of Div 2 with bottom of Div 1', () async {
    const int indonesiaCountryId = 94;
    final List<Tournament> allLeagues = await refs.domesticLeagues(indonesiaCountryId);
    final Tournament div1 = allLeagues.first;
    final List<Tournament> others = allLeagues.sublist(1);

    final CareerPlan plan = await generator.generateCareer(
      countryId: indonesiaCountryId,
      league: div1,
      cup: null,
      otherLeagues: others,
      startYear: 2025,
    );

    final int userClubId = 1801; // Persib in Div 1
    await db.insert(t.careerHistory, <String, Object?>{
      'team_id': userClubId,
      'season_id': plan.season.seasonId,
      'country_id': indonesiaCountryId,
    });

    // Simulate all matches of this season
    while (!await service.seasonComplete(plan.season.seasonId)) {
      final String? date = await service.nextMatchDate(plan.season.seasonId);
      if (date == null) break;
      await service.simulateMatchday(seasonId: plan.season.seasonId, date: date);
    }

    final List<StandingRow> div1Before = await seasons.standings(plan.season.seasonId, 85);
    final List<StandingRow> div2Before = await seasons.standings(plan.season.seasonId, 86);
    expect(div1Before.length, 18);
    expect(div2Before.length, 20);

    // Top 3 of Div 2 and bottom 3 of Div 1
    final List<int> expectedPromoted = div2Before.take(3).map((r) => r.teamId).toList();
    final List<int> expectedRelegated = div1Before.reversed.take(3).map((r) => r.teamId).toList();

    // Complete season and rollover
    final Season nextSeason = await service.completeSeason(
      userTeamId: userClubId,
      onProgress: (_) {},
    );

    expect(nextSeason.seasonId, isNot(plan.season.seasonId));

    // Verify division counts remain identical
    final int div1ClubsCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM teams WHERE country_id = ? AND division = 1',
        <Object?>[indonesiaCountryId],
      ),
    )!;
    final int div2ClubsCount = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM teams WHERE country_id = ? AND division = 2',
        <Object?>[indonesiaCountryId],
      ),
    )!;
    expect(div1ClubsCount, 18);
    expect(div2ClubsCount, 20);

    // Verify the expected promoted teams are now in division 1
    for (final int teamId in expectedPromoted) {
      final int div = Sqflite.firstIntValue(
        await db.rawQuery('SELECT division FROM teams WHERE team_id = ?', <Object?>[teamId]),
      )!;
      expect(div, 1, reason: 'Promoted team $teamId should now be in Division 1');
    }

    // Verify the expected relegated teams are now in division 2
    for (final int teamId in expectedRelegated) {
      final int div = Sqflite.firstIntValue(
        await db.rawQuery('SELECT division FROM teams WHERE team_id = ?', <Object?>[teamId]),
      )!;
      expect(div, 2, reason: 'Relegated team $teamId should now be in Division 2');
    }
  });
}
