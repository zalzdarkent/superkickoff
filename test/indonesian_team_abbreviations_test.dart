import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:superkickoff/data/db/app_database.dart';

void main() {
  test('Indonesian clubs use their distinct abbreviations', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'superkickoff_abbreviations_',
    );
    final String databasePath = p.join(tempDir.path, 'teams.db');

    try {
      await File(p.join('assets', 'data', 'superkickoff_2025.db'))
          .copy(databasePath);
      var db = await AppDatabase.openFile(databasePath);
      expect(
        await db.rawQuery(
          "SELECT abbreviation FROM teams WHERE name = 'Persib'",
        ),
        <Map<String, Object?>>[
          <String, Object?>{'abbreviation': 'PSB'},
        ],
      );
      expect(
        await db.rawQuery(
          "SELECT abbreviation FROM teams WHERE name = 'Persija'",
        ),
        <Map<String, Object?>>[
          <String, Object?>{'abbreviation': 'PSJ'},
        ],
      );

      await db.execute(
        "UPDATE teams SET abbreviation = 'Per' WHERE name IN ('Persib', 'Persija')",
      );
      await AppDatabase.close();

      db = await AppDatabase.openFile(databasePath);
      expect(
        await db.rawQuery('''
          SELECT COUNT(*) AS count
          FROM teams
          WHERE country_id = (SELECT country_id FROM countries WHERE name = 'Indonesia')
            AND abbreviation = 'Per'
        '''),
        <Map<String, Object?>>[
          <String, Object?>{'count': 0},
        ],
      );
    } finally {
      await AppDatabase.close();
      await tempDir.delete(recursive: true);
    }
  });
}
