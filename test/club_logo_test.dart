import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/ui/widgets/common.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Team logo tests', () {
    test('Team fromMap and toMap handle logo_base64 properly', () {
      final Team teamWithLogo = Team(
        teamId: 101,
        name: 'Persib',
        abbreviation: 'PSB',
        countryId: 94,
        power: 75,
        value: 1000000,
        budget: 5000000,
        division: 1,
        stadiumId: 1,
        coachId: 1,
        foundedYear: 1933,
        logoBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

      final Map<String, Object?> map = teamWithLogo.toMap();
      expect(map['logo_base64'], isNotNull);
      expect(map['logo_base64'], equals(teamWithLogo.logoBase64));

      final Team fromMapTeam = Team.fromMap(map);
      expect(fromMapTeam.logoBase64, equals(teamWithLogo.logoBase64));
      expect(fromMapTeam.name, equals('Persib'));
    });

    testWidgets('CrestAvatar displays placeholder when logo is null', (
      WidgetTester tester,
    ) async {
      final Team team = Team(
        teamId: 999,
        name: 'Unknown FC',
        abbreviation: 'UFC',
        countryId: 94,
        power: 60,
        value: 10000,
        budget: 50000,
        division: 2,
        stadiumId: 1,
        coachId: 1,
        foundedYear: 2000,
        logoBase64: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CrestAvatar(team: team, radius: 24)),
        ),
      );

      expect(find.text('UFC'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('CrestAvatar displays Image.memory when logoBase64 is valid', (
      WidgetTester tester,
    ) async {
      const String dummyB64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

      final Team team = Team(
        teamId: 999,
        name: 'Persib',
        abbreviation: 'PSB',
        countryId: 94,
        power: 75,
        value: 10000,
        budget: 50000,
        division: 1,
        stadiumId: 1,
        coachId: 1,
        foundedYear: 1933,
        logoBase64: dummyB64,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CrestAvatar(team: team, radius: 24)),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });

    test(
      'SQLite template superkickoff_2025.db has logo_base64 column and seeded Indonesian clubs',
      () async {
        final File dbFile = File('assets/data/superkickoff_2025.db');
        expect(dbFile.existsSync(), isTrue);

        final Database db = await databaseFactory.openDatabase(
          dbFile.absolute.path,
          options: OpenDatabaseOptions(readOnly: true),
        );

        final List<Map<String, Object?>> columns = await db.rawQuery(
          'PRAGMA table_info(teams)',
        );
        final bool hasLogoColumn = columns.any(
          (c) => c['name'] == 'logo_base64',
        );
        expect(hasLogoColumn, isTrue);

        final List<Map<String, Object?>> persibRows = await db.rawQuery(
          "SELECT team_id, name, logo_base64 FROM teams WHERE name = 'Persib'",
        );
        expect(persibRows.isNotEmpty, isTrue);
        final String? persibLogo =
            persibRows.first['logo_base64'] as String?;
        expect(persibLogo, isNotNull);
        expect(persibLogo!.isNotEmpty, isTrue);
        expect(() => base64Decode(persibLogo), returnsNormally);

        await db.close();
      },
    );
  });
}
