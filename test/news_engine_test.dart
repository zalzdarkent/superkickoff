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
import 'package:superkickoff/data/repositories/news_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/news_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  late Directory dir;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('news_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('matchdays produce league, region and world stories without repeats', () async {
    const int indonesia = 94;
    final ReferenceRepository refs = ReferenceRepository(db);
    final Tournament league = Tournament.fromMap(
      (await db.query('tournaments', where: 'tournament_id = 85')).first,
    );
    final SeasonGenerator generator = SeasonGenerator(db, random: Random(5));
    final CareerPlan plan = await generator.generateCareer(
      countryId: indonesia,
      league: league,
      cup: null,
      internationals: await refs.internationalCups(indonesia),
    );
    final int seasonId = plan.season.seasonId;
    final CareerService service = CareerService(
      db,
      refs: refs,
      seasons: SeasonRepository(db),
      squads: SquadRepository(db),
      matches: MatchRepository(db),
      messages: MessageRepository(db),
      engine: MatchEngine(random: Random(5)),
      generator: generator,
      random: Random(5),
      marketTickChance: 0,
    );
    final NewsRepository repo = NewsRepository(db);
    final NewsEngine news = NewsEngine(db, repo);
    final String region = await refs.leagueRegion(85);
    expect(region, 'asia');

    final String firstDate = (await service.nextMatchDate(seasonId))!;
    await news.preview(
      seasonId: seasonId,
      date: firstDate,
      userLeagueId: 85,
      userRegion: region,
    );
    for (int i = 0; i < 40; i++) {
      final String? date = await service.nextMatchDate(seasonId);
      if (date == null) break;
      await service.simulateMatchday(seasonId: seasonId, date: date);
      await news.onMatchday(
        seasonId: seasonId,
        date: date,
        userLeagueId: 85,
        userRegion: region,
      );
    }

    for (final String scope in <String>['league', 'region', 'world']) {
      final List<NewsItem> feed = await repo.feed(scope);
      expect(feed, isNotEmpty, reason: '$scope feed is empty');
      expect(feed.every((NewsItem n) => n.headline.isNotEmpty && n.body.isNotEmpty), isTrue);
    }
    // League feed carries only domestic stories; ACL stories land in region.
    final List<NewsItem> leagueFeed = await repo.feed('league');
    expect(leagueFeed.every((NewsItem n) => n.scope == 'league'), isTrue);

    // Running the same matchday again adds nothing.
    final int before = (await db.rawQuery('SELECT COUNT(*) c FROM ${t.news}')).first['c'] as int;
    final String last = (await db.rawQuery('SELECT MAX(date) d FROM ${t.news}')).first['d'] as String;
    await news.onMatchday(seasonId: seasonId, date: last, userLeagueId: 85, userRegion: region);
    final int after = (await db.rawQuery('SELECT COUNT(*) c FROM ${t.news}')).first['c'] as int;
    expect(after, before);

    // Group stories must refer to the correct letter (groupId 1 -> Grup A, 2 -> Grup B).
    final List<Map<String, Object?>> groupStories = await db.rawQuery(
      "SELECT ref, headline FROM ${t.news} WHERE ref LIKE 'grp:%'",
    );
    for (final Map<String, Object?> row in groupStories) {
      final String ref = row['ref'] as String;
      final int groupId = int.parse(ref.split(':')[3]);
      final String expectedLetter = String.fromCharCode(64 + groupId);
      expect(
        (row['headline'] as String).contains('Grup $expectedLetter'),
        isTrue,
        reason: 'Group story for groupId $groupId must refer to Grup $expectedLetter',
      );
    }

  });
}
