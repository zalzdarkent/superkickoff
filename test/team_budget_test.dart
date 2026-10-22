import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';

void main() {
  test('backfills zero-budget clubs without changing existing budgets', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final Directory dir = await Directory.systemTemp.createTemp('budget_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    final Database db = await databaseFactory.openDatabase(path);

    await AppDatabase.ensureLocalTables(db);

    final Map<String, Object?> madrid = (await db.query(
      'teams',
      columns: <String>['budget'],
      where: 'name = ?',
      whereArgs: <Object?>['Real Madrid'],
      limit: 1,
    )).single;
    final Map<String, Object?> persib = (await db.query(
      'teams',
      columns: <String>['budget'],
      where: 'name = ?',
      whereArgs: <Object?>['Persib'],
      limit: 1,
    )).single;

    expect(madrid['budget'], greaterThan(0));
    expect(persib['budget'], 90000000);
    await db.close();
    await dir.delete(recursive: true);
  });
}
