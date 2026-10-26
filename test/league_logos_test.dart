import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/ui/widgets/common.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Tournament model parses and serializes logoBase64', () {
    final Map<String, Object?> map = <String, Object?>{
      'tournament_id': 85,
      'name': 'BRI Super League',
      'organization': 1,
      'division_id': 1,
      'slots': '18',
      'promotion_slots': 0,
      'relegation_spots': 3,
      'points': 3.0,
      'prize_teams': 1000000,
      'prize_top_scorer': 50000,
      'prize_mvp': 50000,
      'play_days': '6,7',
      'rounds': 2,
      'logo_base64': 'dGVzdGxvZ28=',
    };

    final Tournament tournament = Tournament.fromMap(map);
    expect(tournament.tournamentId, 85);
    expect(tournament.name, 'BRI Super League');
    expect(tournament.logoBase64, 'dGVzdGxvZ28=');

    final Map<String, Object?> out = tournament.toMap();
    expect(out['logo_base64'], 'dGVzdGxvZ28=');
  });

  test('Database has logo_base64 for Indonesian and continental tournaments', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'superkickoff_league_logos_',
    );
    final String databasePath = p.join(tempDir.path, 'leagues.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(databasePath);
    final Database db = await AppDatabase.openFile(databasePath);
    final ReferenceRepository refs = ReferenceRepository(db);

    final List<Map<String, Object?>> leagues = await refs.leaguesForCountry(94);
    expect(leagues, isNotEmpty);

    // Div 1: BRI Super League (85)
    final Map<String, Object?> bri = leagues.firstWhere((Map<String, Object?> l) => l['tournament_id'] == 85);
    expect(bri['name'], 'BRI Super League');
    expect(bri['logo_base64'], isNotNull);
    expect((bri['logo_base64'] as String).length, greaterThan(100));

    // Div 2: Pegadaian Championship (86)
    final Map<String, Object?> pegadaian = leagues.firstWhere((Map<String, Object?> l) => l['tournament_id'] == 86);
    expect(pegadaian['name'], 'Pegadaian Championship');
    expect(pegadaian['logo_base64'], isNotNull);
    expect((pegadaian['logo_base64'] as String).length, greaterThan(100));

    // Div 3: Liga Nusantara (189)
    final Map<String, Object?> nusantara = leagues.firstWhere((Map<String, Object?> l) => l['tournament_id'] == 189);
    expect(nusantara['name'], 'Liga Nusantara');
    expect(nusantara['logo_base64'], isNotNull);
    expect((nusantara['logo_base64'] as String).length, greaterThan(100));

    // Cup: Piala Indonesia (87)
    final Map<String, Object?>? cup = await refs.nationalCup(94);
    expect(cup, isNotNull);
    expect(cup!['name'], 'Piala Indonesia');
    expect(cup['logo_base64'], isNotNull);
  });

  testWidgets('TournamentAvatar renders placeholder or image', (WidgetTester tester) async {
    // 1. Placeholder with no logo
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TournamentAvatar(
            name: 'BRI Super League',
            logoBase64: null,
            radius: 20,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);

    // 2. With valid 1x1 transparent PNG base64
    const String transparent1x1Png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TournamentAvatar(
            name: 'BRI Super League',
            logoBase64: transparent1x1Png,
            radius: 20,
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
  });
}
