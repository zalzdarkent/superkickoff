import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:superkickoff/data/db/app_database.dart';

void main() {
  test(
    'database opening refreshes team power from the top active players',
    () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'superkickoff_team_power_',
      );
      final String databasePath = p.join(tempDir.path, 'teams.db');

      try {
        await File(p.join('assets', 'data', 'superkickoff_2025.db'))
            .copy(databasePath);
        final db = await AppDatabase.openFile(databasePath);
        final List<Map<String, Object?>> rows = await db.rawQuery('''
        SELECT t.power,
          (
            SELECT CAST(ROUND(AVG(top_players.power)) AS INTEGER)
            FROM (
              SELECT p.power
              FROM players p
              JOIN team_players tp ON tp.player_id = p.player_id
              WHERE tp.team_id = t.team_id AND p.status_id = 1
              ORDER BY p.power DESC
              LIMIT 11
            ) AS top_players
          ) AS expected_power
        FROM teams t
        WHERE t.name = 'Persib'
      ''');

        expect(rows, hasLength(1));
        expect(rows.single['power'], rows.single['expected_power']);
        expect(rows.single['power'], lessThan(97));
      } finally {
        await AppDatabase.close();
        await tempDir.delete(recursive: true);
      }
    },
  );
}
