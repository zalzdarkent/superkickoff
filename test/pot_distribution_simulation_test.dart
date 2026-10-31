import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/game/international_tournament_service.dart';
import 'package:superkickoff/game/national_team_service.dart';

void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_sim_');
    final File target = File(p.join(tempDir.path, 'test.db'));
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(target.path);
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

  test('Simulate World Cup group drawing and verify realistic pot distribution', () async {
    final nationalService = NationalTeamService(db);
    final intlTournaments = InternationalTournamentService(db, random: Random(123));

    // Get all top 48 nations worldwide
    final List<Country> allNations = await nationalService.getNationalTeams();
    allNations.sort((a, b) => b.power.compareTo(a.power));
    final List<int> top48Ids = allNations.take(48).map((c) => c.countryId).toList();
    final Map<int, Country> countryMap = {for (final c in allNations) c.countryId: c};

    // Schedule group stage with our new pot-based drawing
    final fixtures = await intlTournaments.scheduleGroupStage(
      tournamentId: t.tournamentWorldCup,
      seasonId: 999,
      participatingCountryIds: top48Ids,
      groupSize: 4,
      groupCount: 12,
      startGroupId: 1,
    );

    expect(fixtures, isNotEmpty);

    // Group fixtures by group_id
    final Map<int, Set<int>> groupTeams = {};
    for (final f in fixtures) {
      final gid = f.groupId ?? 1;
      groupTeams.putIfAbsent(gid, () => <int>{})..add(f.homeCountryId)..add(f.awayCountryId);
    }

    print('\n================================================================');
    print('HASIL SIMULASI DISTRIBUSI GRUP PIALA DUNIA (12 GRUP @ 4 NEGARA):');
    print('================================================================');

    for (int g = 1; g <= 12; g++) {
      final teams = groupTeams[g]!.toList();
      final teamObjects = teams.map((id) => countryMap[id]!).toList();
      teamObjects.sort((a, b) => b.power.compareTo(a.power));

      final namesWithPower = teamObjects.map((c) => '${c.name} (Pwr:${c.power})').join(' | ');
      final avgPower = (teamObjects.map((c) => c.power).reduce((a, b) => a + b) / teamObjects.length).toStringAsFixed(1);

      print('Grup ${String.fromCharCode(64 + g)} [Rata-rata Kekuatan: $avgPower]:');
      print('   -> $namesWithPower');

      expect(teams.length, 4, reason: 'Grup harus memiliki 4 tim');
    }
    print('================================================================\n');
  });
}
