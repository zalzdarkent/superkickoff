import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/ui/screens/annual_awards_gala_sheet.dart';

void main() {
  late Directory tempDir;
  late Database db;
  late SeasonRepository seasons;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_gala_test_');
    final File source = File(p.join('assets', 'data', 'superkickoff_2025.db'));
    final File target = File(p.join(tempDir.path, 'gala_test.db'));
    await source.copy(target.path);
    db = await databaseFactory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await AppDatabase.ensureLocalTables(db);
    seasons = SeasonRepository(db);
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'recordSeasonAwards generates all annual awards and gala summary',
    () async {
      const int testSeasonId = 999;
      const int testYear = 2025;
      const int userTeamId = 1;

      // Insert dummy season
      await db.insert('seasons', <String, Object?>{
        'season_id': testSeasonId,
        'name': '2025/2026',
        'start_year': testYear,
        'end_year': testYear + 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Ensure tournament 1 is a league tournament
      await db.update('tournaments', <String, Object?>{
        'organization': t.orgLeague,
      }, where: 'tournament_id = 1');

      // Pick 15 players with team_players to populate match stats
      final List<Map<String, Object?>> playerRows = await db.rawQuery('''
      SELECT p.player_id, tp.team_id, p.position_id, p.name, p.age
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      LIMIT 15
      ''');
      expect(playerRows.length, 15);

      // Make sure one player is a goalkeeper and one is young (< 21)
      for (int i = 0; i < playerRows.length; i++) {
        final int pId = playerRows[i]['player_id'] as int;
        final int posId = (i == 0) ? 1 : (i <= 4 ? 2 : (i <= 8 ? 5 : 9));
        await db.update(
          'players',
          <String, Object?>{'position_id': posId, 'age': (i == 1) ? 20 : 26},
          where: 'player_id = ?',
          whereArgs: <Object?>[pId],
        );
      }

      final List<int> matchIds = <int>[];
      for (int round = 1; round <= 10; round++) {
        matchIds.add(
          await db.insert('matches', <String, Object?>{
            'season_id': testSeasonId,
            'tournament_id': 1,
            'home_team_id': round.isOdd ? 1 : 2,
            'away_team_id': round.isOdd ? 2 : 1,
            'stadium_id': 1,
            'home_goals': round.isOdd ? 3 : 0,
            'away_goals': round.isOdd ? 0 : 2,
            'status': t.matchFinished,
            'round': round,
            'phase': 1,
            'winner_id': 1,
          }),
        );
      }

      // Populate match_players stats for the 15 players across the season.
      for (int i = 0; i < playerRows.length; i++) {
        final int pId = playerRows[i]['player_id'] as int;
        final int tId = playerRows[i]['team_id'] as int;
        final double rating = i == 14 ? 10.0 : 6.5 + (i * 0.2);
        for (int matchIndex = 0; matchIndex < matchIds.length; matchIndex++) {
          if (i == 14 && matchIndex >= 2) continue;
          await db.insert('match_players', <String, Object?>{
            'match_id': matchIds[matchIndex],
            'player_id': pId,
            'team_id': tId,
            'minutes': 90,
            'rating': rating,
            'goals': i == 14
                ? 5
                : i == 10
                ? 1
                : 0,
          });
        }
      }

      // Record the season awards
      await seasons.recordSeasonAwards(seasonId: testSeasonId, year: testYear);

      // Fetch gala awards summary
      final SeasonGalaSummary gala = await seasons.seasonGalaAwards(
        testSeasonId,
        userTeamId: userTeamId,
      );

      expect(gala.seasonId, testSeasonId);
      expect(gala.year, testYear);
      expect(gala.ballonDor, isNotNull);
      expect(gala.ballonDor!.label, 'Player of the Year');
      expect(gala.ballonDor!.type, t.awardBallonDor);
      expect(gala.ballonDor!.rating, isNotNull);
      expect(
        gala.ballonDor!.playerId,
        isNot(playerRows[14]['player_id']),
        reason: 'two appearances should not qualify for season awards',
      );

      expect(gala.goldenBoot, isNotNull);
      expect(gala.goldenBoot!.type, t.awardTopScorer);
      expect(gala.goldenBoot!.goals, greaterThanOrEqualTo(5));
      expect(gala.goldenBoot!.playerId, isNot(playerRows[14]['player_id']));

      expect(gala.goldenGlove, isNotNull);
      expect(gala.goldenGlove!.type, t.awardGoldenGlove);

      expect(gala.youngPlayer, isNotNull);
      expect(gala.youngPlayer!.type, t.awardYoungPlayer);

      expect(gala.managerOfTheYear, isNotNull);
      expect(gala.managerOfTheYear!.type, t.awardManagerOfTheYear);

      // Team of the Year
      expect(gala.teamOfTheYear, isNotEmpty);
      expect(
        gala.teamOfTheYear.every(
          (PlayerAward a) => a.type == t.awardTeamOfTheYear,
        ),
        isTrue,
      );
    },
  );

  testWidgets('AnnualAwardsGalaSheet renders tabs and displays award data', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const SeasonGalaSummary mockGala = SeasonGalaSummary(
      seasonId: 101,
      year: 2025,
      seasonName: '2025/2026',
      ballonDor: PlayerAward(
        awardId: 1,
        playerId: 10,
        playerName: 'Lionel Tester',
        teamName: 'FC Test',
        type: t.awardBallonDor,
        year: 2025,
        seasonId: 101,
        rating: 8.8,
        statSubtitle: '35 G+A • Avg Rating 8.80',
        positionId: 4,
      ),
      goldenBoot: PlayerAward(
        awardId: 2,
        playerId: 11,
        playerName: 'Erling Striker',
        teamName: 'Test City',
        type: t.awardTopScorer,
        year: 2025,
        seasonId: 101,
        goals: 28,
        statSubtitle: '28 Goals in 34 matches',
        positionId: 4,
      ),
      goldenGlove: PlayerAward(
        awardId: 3,
        playerId: 12,
        playerName: 'Thibaut Keeper',
        teamName: 'Test Madrid',
        type: t.awardGoldenGlove,
        year: 2025,
        seasonId: 101,
        statSubtitle: '18 Clean Sheets',
        positionId: 1,
      ),
      youngPlayer: PlayerAward(
        awardId: 4,
        playerId: 13,
        playerName: 'Lamine Wonder',
        teamName: 'FC Test',
        type: t.awardYoungPlayer,
        year: 2025,
        seasonId: 101,
        statSubtitle: 'Age 18 • Rating 7.95',
        positionId: 4,
      ),
      mvp: PlayerAward(
        awardId: 5,
        playerId: 10,
        playerName: 'Lionel Tester',
        teamName: 'FC Test',
        type: t.awardMvp,
        year: 2025,
        seasonId: 101,
        statSubtitle: 'Player of the Season',
        positionId: 4,
      ),
      managerOfTheYear: PlayerAward(
        awardId: 6,
        playerId: 0,
        playerName: 'Pep Tactician',
        teamName: 'FC Test',
        type: t.awardManagerOfTheYear,
        year: 2025,
        seasonId: 101,
        statSubtitle: 'Champion with 89 pts',
      ),
      teamOfTheYear: <PlayerAward>[
        PlayerAward(
          awardId: 100,
          playerId: 12,
          playerName: 'Thibaut Keeper',
          teamName: 'Test Madrid',
          type: t.awardTeamOfTheYear,
          year: 2025,
          seasonId: 101,
          positionId: 1,
          rating: 8.1,
        ),
      ],
      userClubAwards: <PlayerAward>[
        PlayerAward(
          awardId: 1,
          playerId: 10,
          playerName: 'Lionel Tester',
          teamName: 'FC Test',
          type: t.awardBallonDor,
          year: 2025,
          seasonId: 101,
        ),
      ],
      clubTrophies: <ClubTrophy>[
        ClubTrophy(
          tournamentId: 1,
          tournamentName: 'Liga Super Test',
          organization: 1,
          seasonId: 101,
          seasonName: '2025/2026',
          year: 2025,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnnualAwardsGalaSheet(gala: mockGala)),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title & Player of the Year
    expect(find.text('ANNUAL AWARDS GALA'), findsOneWidget);
    expect(find.text('PLAYER OF THE YEAR'), findsOneWidget);
    expect(find.text('Lionel Tester'), findsWidgets);
    expect(find.text('35 G+A • Avg Rating 8.80'), findsOneWidget);

    // Verify other awards are shown in Individual tab
    expect(find.text('GOLDEN BOOT'), findsOneWidget);
    expect(find.text('Erling Striker'), findsOneWidget);
    expect(find.text('GOLDEN GLOVE'), findsOneWidget);
    expect(find.text('Thibaut Keeper'), findsWidgets);
    expect(find.text('BEST YOUNG PLAYER'), findsOneWidget);
    expect(find.text('Lamine Wonder'), findsOneWidget);
    expect(find.text('MANAGER OF THE YEAR'), findsOneWidget);
    expect(find.text('Pep Tactician'), findsOneWidget);

    // Switch to Team of the Year Tab
    await tester.tap(find.text('Team of the Year'));
    await tester.pumpAndSettle();

    expect(find.text('ONCE IDEAL (4-3-3)'), findsOneWidget);
    expect(find.text('ROSTER XI TERBAIK'), findsOneWidget);

    // Switch to Club Honours Tab
    await tester.tap(find.text('Club Honours'));
    await tester.pumpAndSettle();

    expect(find.text('TROFI KLUB MUSIM INI'), findsOneWidget);
    expect(find.text('Liga Super Test'), findsOneWidget);
    expect(find.text('CHAMPION'), findsOneWidget);
    expect(find.text('PENGHARGAAN INDIVIDU KLUB ANDA'), findsOneWidget);
  });
}
