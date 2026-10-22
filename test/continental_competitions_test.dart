import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
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

  test('European countries qualify for UCL, UEL, Conference, Super Cup and World Cups', () async {
    const int spainCountryId = 64;
    final List<Tournament> cups = await refs.internationalCups(spainCountryId);
    final List<int> ids = cups.map((t) => t.tournamentId).toList();

    expect(ids, contains(49)); // Champions League
    expect(ids, contains(51)); // Europa League
    expect(ids, contains(135)); // Conference League (UECL)
    expect(ids, contains(54)); // UEFA Super Cup
    expect(ids, contains(56)); // Intercontinental Cup
    expect(ids, contains(163)); // FIFA Club World Cup
  });

  test('Asian countries qualify for ACL Elite, ACL Two, AFC Challenge League, AFC Super Cup and World Cups', () async {
    const int indonesiaCountryId = 94;
    final List<Tournament> cups = await refs.internationalCups(indonesiaCountryId);
    final List<int> ids = cups.map((t) => t.tournamentId).toList();

    expect(ids, contains(99)); // ACL Elite
    expect(ids, contains(164)); // ACL Two
    expect(ids, contains(1650)); // AFC Challenge League
    expect(ids, contains(1651)); // AFC Super Cup
    expect(ids, contains(56)); // Intercontinental Cup
    expect(ids, contains(163)); // FIFA Club World Cup
  });

  test('world cups take champions, then the strongest clubs by power', () async {
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
    );
    // First season: nobody has won anything yet, so Persib (power 97) must be
    // picked for the Indonesian Club World Cup slot every time.
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT 1 FROM matches WHERE season_id = ? AND tournament_id = 163 '
      'AND (home_team_id = 42 OR away_team_id = 42)',
      <Object?>[plan.season.seasonId],
    );
    expect(rows, isNotEmpty);
  });
}
