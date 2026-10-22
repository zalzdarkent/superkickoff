import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/game/season_generator.dart';
import 'package:superkickoff/state/career_provider.dart';
import 'package:superkickoff/ui/screens/fixtures_tab.dart';

class FakeCareerProvider extends CareerProvider {
  FakeCareerProvider({
    required Season season,
    required Tournament league,
    required List<FixtureMatch> fixtures,
    required String nextDate,
  }) {
    this.season = season;
    this.league = league;
    this.nextDate = nextDate;
    _testFixtures = fixtures;
    teamCache = <int, Team>{
      1: Team.fromMap(<String, Object?>{
        'team_id': 1,
        'name': 'Home Club',
        'country_id': 1,
        'stadium_id': 1,
        'coach_id': 1,
      }),
      2: Team.fromMap(<String, Object?>{
        'team_id': 2,
        'name': 'Away Club',
        'country_id': 1,
        'stadium_id': 1,
        'coach_id': 1,
      }),
    };
  }

  late final List<FixtureMatch> _testFixtures;

  @override
  Future<List<FixtureMatch>> seasonFixtures() async => _testFixtures;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  late SeasonGenerator generator;
  late CareerPlan plan;
  const int countryId = 141; // Mexico

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('decider_fixtures_test_');
    final String path = p.join(tempDir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);

    Future<Tournament> find(int org, {int? division}) async =>
        Tournament.fromMap(
          (await db.rawQuery(
            '''SELECT tu.* FROM tournaments tu
               JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
               WHERE tc.country_id = ? AND tu.organization = ?
               ${division == null ? '' : 'AND tu.division_id = $division'} LIMIT 1''',
            <Object?>[countryId, org],
          )).first,
        );

    generator = SeasonGenerator(db, random: Random(42));
    plan = await generator.generateCareer(
      countryId: countryId,
      league: await find(t.orgLeague, division: 1),
      cup: await find(t.orgNationalCup),
    );
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('league title decider vibes only trigger ONCE, not on subsequent matches', () async {
    final ReferenceRepository refs = ReferenceRepository(db);
    final List<Team> clubs = await refs.teamsForDivision(countryId, 1);
    final Team userClub = clubs.first;

    // Simulate pre-season friendlies away.
    final List<FixtureMatch> friendlies = await db
        .query(
          t.matches,
          where: 'season_id = ? AND tournament_id = 9999',
          whereArgs: <Object?>[plan.season.seasonId],
        )
        .then((rows) => rows.map(FixtureMatch.fromMap).toList());
    for (final FixtureMatch f in friendlies) {
      await db.update(
        t.matches,
        <String, Object?>{
          'status': t.matchFinished,
          'home_goals': 1,
          'away_goals': 0,
          'winner_id': f.homeTeamId,
        },
        where: 'match_id = ?',
        whereArgs: <Object?>[f.matchId],
      );
    }

    // Set up a CareerProvider.
    final CareerProvider provider = CareerProvider();
    // Initialize provider fields manually with our test DB.
    await db.insert(t.managerProfile, <String, Object?>{
      'id': 1,
      'name': 'Test Manager',
      'country_id': countryId,
    });
    await db.insert(t.careerHistory, <String, Object?>{
      'team_id': userClub.teamId,
      'season_id': plan.season.seasonId,
      'country_id': countryId,
    });

    await provider.init(db);
    expect(provider.userTeamId, userClub.teamId);

    // Play league matches up to round 31: user wins every match, all others draw.
    final List<FixtureMatch> allLeague = await db
        .query(
          t.matches,
          where: 'season_id = ? AND tournament_id = ?',
          whereArgs: <Object?>[plan.season.seasonId, plan.leagueTournamentId],
          orderBy: 'round ASC, match_id ASC',
        )
        .then((rows) => rows.map(FixtureMatch.fromMap).toList());

    final int maxRound = allLeague.map((m) => m.round).reduce(max);
    expect(maxRound, 34);

    final FixtureMatch round32UserMatch = allLeague.firstWhere(
      (m) =>
          m.round == 32 &&
          (m.homeTeamId == userClub.teamId || m.awayTeamId == userClub.teamId),
    );

    // We want user team to have 77 points and 2nd place (runner up) to have 70 points at round 31.
    // That way, 2nd place max potential is 70 + 3*3 = 79 points (not sealed yet).
    // In round 32, user wins (+3) -> 80 points, while 2nd place gets at most 73 + 2*3 = 79 points -> CLINCHED!
    final Team secondClub = clubs[1];

    for (final FixtureMatch m in allLeague.where((m) => m.round <= 31)) {
      final bool userHome = m.homeTeamId == userClub.teamId;
      final bool userAway = m.awayTeamId == userClub.teamId;
      final bool secondHome = m.homeTeamId == secondClub.teamId;
      final bool secondAway = m.awayTeamId == secondClub.teamId;

      int hg = 1;
      int ag = 1;
      int? wid;

      if (userHome || userAway) {
        // User wins 25 matches, draws 2, loses 4 = 77 points.
        if (m.round <= 25) {
          hg = userHome ? 2 : 0;
          ag = userAway ? 2 : 0;
          wid = userHome ? m.homeTeamId : m.awayTeamId;
        } else if (m.round <= 27) {
          hg = 1;
          ag = 1;
          wid = null;
        } else {
          hg = userHome ? 0 : 2;
          ag = userAway ? 0 : 2;
          wid = userHome ? m.awayTeamId : m.homeTeamId;
        }
      } else if (secondHome || secondAway) {
        // 2nd place has 71 points at round 31:
        // Before R32: 71 + 9 = 80 max (> 77). NOT clinched yet.
        // After R32: 2nd place has 71 points with 2 games remaining (71 + 6 = 77 max).
        // User gets at least 78 points (draw or win) -> 78 > 77 -> CLINCHED!
        if (m.round <= 22) {
          hg = secondHome ? 2 : 0;
          ag = secondAway ? 2 : 0;
          wid = secondHome ? m.homeTeamId : m.awayTeamId;
        } else if (m.round <= 27) {
          hg = 1;
          ag = 1;
          wid = null;
        } else {
          hg = secondHome ? 0 : 2;
          ag = secondAway ? 0 : 2;
          wid = secondHome ? m.awayTeamId : m.homeTeamId;
        }
      }

      await db.update(
        t.matches,
        <String, Object?>{
          'status': t.matchFinished,
          'home_goals': hg,
          'away_goals': ag,
          'winner_id': wid,
        },
        where: 'match_id = ?',
        whereArgs: <Object?>[m.matchId],
      );
    }

    // Also finish any earlier matches in other competitions (like cups) before round 32.
    await db.update(
      t.matches,
      <String, Object?>{
        'status': t.matchFinished,
        'home_goals': 1,
        'away_goals': 0,
      },
      where: 'season_id = ? AND date < ? AND status = ?',
      whereArgs: <Object?>[
        plan.season.seasonId,
        round32UserMatch.date,
        t.matchScheduled,
      ],
    );

    await provider.refreshWorld();
    expect(provider.nextUserMatch?.round, 32);

    // Round 32: this match clinches the championship mathematically.
    await provider.startLiveMatch();
    final LiveMatchSession? sessionRound32 = provider.liveSession;
    expect(sessionRound32, isNotNull);
    expect(sessionRound32!.isLeagueDecider, isTrue,
        reason: 'Round 32 clinches the title for the first time');
    expect(sessionRound32.leagueTitleWon, isTrue,
        reason: 'Title officially won in Round 32');
    expect(sessionRound32.isUserChampion(userClub.teamId), isTrue,
        reason: 'User is champion in Round 32');

    // Finish the match session.
    await provider.finishLiveMatch();

    // Advance matches until the next league match (Round 33).
    while (provider.nextDate != null &&
        provider.nextUserMatch?.tournamentId != plan.leagueTournamentId) {
      if (provider.nextUserMatch != null) {
        await provider.startLiveMatch();
        await provider.finishLiveMatch();
      } else {
        await provider.playAiMatchday();
      }
    }

    // Round 33: NEXT MATCH. The championship has ALREADY been clinched.
    // It should NOT be a title decider, and no champion celebration should appear.
    expect(provider.nextUserMatch?.round, 33);

    await provider.startLiveMatch();
    final LiveMatchSession? sessionRound33 = provider.liveSession;
    expect(sessionRound33, isNotNull);
    expect(sessionRound33!.isLeagueDecider, isFalse,
        reason: 'Round 33 must NOT be a title decider: title was already won');
    expect(sessionRound33.leagueTitleWon, isFalse,
        reason: 'Round 33 must not re-trigger title won');
    expect(sessionRound33.isHighStakes, isFalse,
        reason: 'Round 33 is an ordinary matchday, no high stakes vibes');
    expect(sessionRound33.isUserChampion(userClub.teamId), isFalse,
        reason: 'Championship presentation must not repeat in Round 33');

    await provider.finishLiveMatch();

    while (provider.nextDate != null &&
        provider.nextUserMatch?.tournamentId != plan.leagueTournamentId) {
      if (provider.nextUserMatch != null) {
        await provider.startLiveMatch();
        await provider.finishLiveMatch();
      } else {
        await provider.playAiMatchday();
      }
    }

    // Round 34: FINAL MATCH. Title already won in Round 32 -> still NO decider vibes.
    expect(provider.nextUserMatch?.round, 34);

    await provider.startLiveMatch();
    final LiveMatchSession? sessionRound34 = provider.liveSession;
    expect(sessionRound34, isNotNull);
    expect(sessionRound34!.isLeagueDecider, isFalse,
        reason: 'Round 34 must NOT be a title decider: title was already won');
    expect(sessionRound34.leagueTitleWon, isFalse);
    expect(sessionRound34.isHighStakes, isFalse);
    expect(sessionRound34.isUserChampion(userClub.teamId), isFalse);

    await provider.finishLiveMatch();
  });

  testWidgets('FixturesTab mounts all rounds and resolves current matchday in late season', (
    WidgetTester tester,
  ) async {
    final Tournament league = Tournament.fromMap(<String, Object?>{
      'tournament_id': 1,
      'name': 'Liga MX',
      'organization': t.orgLeague,
    });
    final Season season = Season.fromMap(<String, Object?>{
      'season_id': 1,
      'name': '2025/26',
    });

    final List<FixtureMatch> fixtures = <FixtureMatch>[
      for (int round = 1; round <= 34; round++)
        FixtureMatch.fromMap(<String, Object?>{
          'match_id': round,
          'tournament_id': 1,
          'season_id': 1,
          'round': round,
          'phase': 1,
          'status': round < 30 ? t.matchFinished : t.matchScheduled,
          'home_team_id': 1,
          'away_team_id': 2,
          'stadium_id': 1,
          'home_goals': round < 30 ? 1 : null,
          'away_goals': round < 30 ? 0 : null,
          'date': '2026-0${(round % 9) + 1}-10',
        }),
    ];

    // Current matchday is Round 30.
    final String nextDate = fixtures[29].date!;
    final FakeCareerProvider provider = FakeCareerProvider(
      season: season,
      league: league,
      fixtures: fixtures,
      nextDate: nextDate,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<CareerProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: FixturesTab()),
        ),
      ),
    );

    // Initial pump triggers didChangeDependencies -> _load().
    await tester.pump();
    // Pump again for setState and postFrameCallback scroll animation.
    await tester.pump(const Duration(milliseconds: 300));

    // Check that all rounds are present in the SingleChildScrollView hierarchy.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.textContaining(RegExp(r'Round 1\s')), findsOneWidget);
    expect(find.textContaining(RegExp(r'Round 30\s')), findsOneWidget);
    expect(find.textContaining(RegExp(r'Round 34\s')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
