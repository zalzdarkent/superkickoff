import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/game/season_generator.dart';
import 'package:superkickoff/ui/theme.dart';

void main() {
  group('StandingRow positionChange tests', () {
    test('calculates correct position change when team moves up', () {
      final StandingRow row = StandingRow(
        teamId: 1,
        name: 'Persib',
        abbreviation: 'PSB',
        played: 5,
        wins: 4,
        draws: 0,
        losses: 1,
        goalsFor: 10,
        goalsAgainst: 3,
        points: 12,
        currentPosition: 2,
        previousPosition: 5,
      );

      // Moved up from 5th to 2nd => +3
      expect(row.positionChange(), equals(3));
      expect(row.positionChange(2), equals(3));
    });

    test('calculates correct position change when team moves down', () {
      final StandingRow row = StandingRow(
        teamId: 2,
        name: 'Persija',
        abbreviation: 'PSJ',
        played: 5,
        wins: 2,
        draws: 1,
        losses: 2,
        goalsFor: 6,
        goalsAgainst: 6,
        points: 7,
        currentPosition: 6,
        previousPosition: 3,
      );

      // Moved down from 3rd to 6th => -3
      expect(row.positionChange(), equals(-3));
      expect(row.positionChange(6), equals(-3));
    });

    test('returns 0 when team stays in the same position', () {
      final StandingRow row = StandingRow(
        teamId: 3,
        name: 'Bali United',
        abbreviation: 'BLI',
        played: 5,
        wins: 5,
        draws: 0,
        losses: 0,
        goalsFor: 12,
        goalsAgainst: 2,
        points: 15,
        currentPosition: 1,
        previousPosition: 1,
      );

      // Stays at 1st => 0
      expect(row.positionChange(), equals(0));
    });

    test('returns null when previousPosition is not available', () {
      final StandingRow row = StandingRow(
        teamId: 4,
        name: 'Arema',
        abbreviation: 'ARM',
        played: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        goalsFor: 0,
        goalsAgainst: 0,
        points: 0,
        currentPosition: 4,
        previousPosition: null,
      );

      expect(row.positionChange(), isNull);
    });
  });

  group('Standings Movement UI rendering tests', () {
    Widget buildMovementWidget(int? delta) {
      if (delta == null || delta == 0) {
        return const SizedBox.shrink();
      }
      final bool isUp = delta > 0;
      final Color color = isUp ? AppTheme.accent : AppTheme.danger;
      final int change = delta.abs();
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 14,
              color: color,
            ),
            Text(
              '$change',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
          ],
        ),
      );
    }

    testWidgets('renders up arrow and count when position improved', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: buildMovementWidget(2)),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.text('2'), findsOneWidget);

      final Icon icon = tester.widget(find.byIcon(Icons.arrow_drop_up));
      expect(icon.color, equals(AppTheme.accent));
    });

    testWidgets('renders down arrow and count when position worsened', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: buildMovementWidget(-1)),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.text('1'), findsOneWidget);

      final Icon icon = tester.widget(find.byIcon(Icons.arrow_drop_down));
      expect(icon.color, equals(AppTheme.danger));
    });

    testWidgets('renders nothing when position is unchanged (delta == 0)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: buildMovementWidget(0)),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders nothing when delta is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: buildMovementWidget(null)),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('SeasonRepository standings movement calculation in DB', () {
    late Directory dir;
    late Database db;
    late ReferenceRepository refs;
    late SeasonRepository seasons;
    late SeasonGenerator generator;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('standings_movement_test_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
      refs = ReferenceRepository(db);
      seasons = SeasonRepository(db);
      generator = SeasonGenerator(db, random: Random(42));
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('calculates correct position movements across matchdays', () async {
      const int indonesiaCountryId = 94;
      final List<Tournament> allLeagues = await refs.domesticLeagues(
        indonesiaCountryId,
      );
      final Tournament div1 = allLeagues.first;
      final CareerPlan plan = await generator.generateCareer(
        countryId: indonesiaCountryId,
        league: div1,
        cup: null,
        otherLeagues: allLeagues.sublist(1),
        startYear: 2025,
      );
      final int seasonId = plan.season.seasonId;
      final int tournamentId = div1.tournamentId;

      // 1. Initial table (no finished matches yet)
      final List<StandingRow> initial = await seasons.standings(
        seasonId,
        tournamentId,
      );
      expect(initial, isNotEmpty);
      for (final StandingRow row in initial) {
        expect(row.positionChange(), equals(0));
      }

      // Pick two teams: first team and last team from initial table
      final StandingRow firstTeam = initial.first;
      final StandingRow lastTeam = initial.last;

      // Finish one match in Round 1: last team wins 5-0 against first team
      await db.update(
        t.matches,
        <String, Object?>{
          'status': t.matchFinished,
          'home_goals': 5,
          'away_goals': 0,
          'winner_id': lastTeam.teamId,
        },
        where:
            'season_id = ? AND tournament_id = ? AND round = 1 AND home_team_id = ? AND away_team_id = ?',
        whereArgs: <Object?>[
          seasonId,
          tournamentId,
          lastTeam.teamId,
          firstTeam.teamId,
        ],
      );

      // If that exact fixture didn't happen in Round 1, insert a finished Round 1 fixture
      final int updatedCount = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM matches WHERE season_id = ? AND tournament_id = ? AND round = 1 AND status = ?',
          <Object?>[seasonId, tournamentId, t.matchFinished],
        ),
      )!;

      if (updatedCount == 0) {
        await db.insert(t.matches, <String, Object?>{
          'season_id': seasonId,
          'tournament_id': tournamentId,
          'round': 1,
          'phase': 0,
          'home_team_id': lastTeam.teamId,
          'away_team_id': firstTeam.teamId,
          'stadium_id': 1,
          'date': '2025-08-01',
          'status': t.matchFinished,
          'home_goals': 5,
          'away_goals': 0,
          'winner_id': lastTeam.teamId,
          'leg': 1,
        });
      }

      final List<StandingRow> afterRound1 = await seasons.standings(
        seasonId,
        tournamentId,
      );

      final StandingRow updatedLast = afterRound1.firstWhere(
        (StandingRow r) => r.teamId == lastTeam.teamId,
      );
      final StandingRow updatedFirst = afterRound1.firstWhere(
        (StandingRow r) => r.teamId == firstTeam.teamId,
      );

      // Last team won 5-0, so they jumped up to 1st place!
      expect(updatedLast.currentPosition, equals(1));
      expect(updatedLast.positionChange()!, greaterThan(0));

      // First team lost 0-5, so they dropped to the bottom!
      expect(updatedFirst.currentPosition, equals(afterRound1.length));
      expect(updatedFirst.positionChange()!, lessThan(0));

      // Round 2: first team wins 6-0
      await db.insert(t.matches, <String, Object?>{
        'season_id': seasonId,
        'tournament_id': tournamentId,
        'round': 2,
        'phase': 0,
        'home_team_id': firstTeam.teamId,
        'away_team_id': lastTeam.teamId,
        'stadium_id': 1,
        'date': '2025-08-08',
        'status': t.matchFinished,
        'home_goals': 6,
        'away_goals': 0,
        'winner_id': firstTeam.teamId,
        'leg': 1,
      });

      final List<StandingRow> afterRound2 = await seasons.standings(
        seasonId,
        tournamentId,
      );

      final StandingRow r2First = afterRound2.firstWhere(
        (StandingRow r) => r.teamId == firstTeam.teamId,
      );

      // At end of round 1, first team was in last place.
      // In round 2, first team won 6-0, so compared to round 1 they moved up!
      expect(r2First.previousPosition, equals(afterRound1.length));
      expect(r2First.positionChange()!, greaterThan(0));
    });
  });
}
