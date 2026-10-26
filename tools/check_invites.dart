import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/game/season_generator.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await Directory.systemTemp.createTemp('chk_');
  final path = p.join(dir.path, 'g.db');
  await File('assets/data/superkickoff_2025.db').copy(path);
  final db = await databaseFactory.openDatabase(path);
  const countryId = 94;
  final league = Tournament.fromMap((await db.query('tournaments', where: 'tournament_id = ?', whereArgs: [85])).first);
  final cup = Tournament.fromMap((await db.query('tournaments', where: 'tournament_id = ?', whereArgs: [87])).first);
  final refs = ReferenceRepository(db);
  final ints = await refs.internationalCups(countryId);
  for (final x in ints) { stdout.writeln('int ${x.tournamentId} ${x.name}'); }
  final gen = SeasonGenerator(db, random: Random(9));
  final plan = await gen.generateCareer(countryId: countryId, league: league, cup: cup, internationals: ints);
  for (final id in plan.internationalTournamentIds) {
    final rows = await db.query(t.matches, where: 'season_id = ? AND tournament_id = ?', whereArgs: [plan.season.seasonId, id]);
    final groups = <int?, int>{};
    for (final r in rows) { final int? gid = r['group_id'] as int?; groups[gid] = (groups[gid] ?? 0) + 1; }
    final teams = <int>{};
    for (final r in rows) { teams.add(r['home_team_id'] as int); teams.add(r['away_team_id'] as int); }
    stdout.writeln('tour $id matches=${rows.length} teams=${teams.length} groups=$groups');
  }
  await db.close();
  await dir.delete(recursive: true);
}
