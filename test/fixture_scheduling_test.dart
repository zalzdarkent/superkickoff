import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/competition_config.dart';
import 'package:superkickoff/game/fixture_calendar.dart';
import 'package:superkickoff/game/fixture_scheduler.dart';
import 'package:superkickoff/game/fixture_validator.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

FixtureMatch fixture(
  int id,
  int home,
  int away, {
  int tournament = 1,
  int season = 1,
  int phase = 1,
  int round = 1,
  int leg = 1,
  int? groupId,
  String status = 'scheduled',
  int? homeGoals,
  int? awayGoals,
  int? winnerId,
  String? date,
  bool awayGoalsRule = false,
}) => FixtureMatch.fromMap(<String, Object?>{
  'match_id': id,
  'tournament_id': tournament,
  'season_id': season,
  'phase': phase,
  'round': round,
  'leg': leg,
  'group_id': groupId,
  'status': status == 'finished' ? t.matchFinished : t.matchScheduled,
  'home_team_id': home,
  'away_team_id': away,
  'stadium_id': 1,
  'home_goals': homeGoals,
  'away_goals': awayGoals,
  'winner_id': winnerId,
  'date': date,
  'away_goals_rule': awayGoalsRule ? 1 : 0,
});

/// Builds a map of club id -> H/A sequence ordered by round.
Map<int, List<int>> _homeAwaySequences(List<FixtureSlot> slots) {
  final Map<int, List<FixtureSlot>> byRound = <int, List<FixtureSlot>>{};
  final Set<int> clubs = <int>{};
  for (final FixtureSlot slot in slots) {
    byRound.putIfAbsent(slot.round, () => <FixtureSlot>[]).add(slot);
    clubs.add(slot.home);
    clubs.add(slot.away);
  }
  final Map<int, List<int>> sequences = <int, List<int>>{
    for (final int id in clubs) id: <int>[],
  };
  for (final int round in byRound.keys.toList()..sort()) {
    for (final FixtureSlot slot in byRound[round]!) {
      sequences[slot.home]!.add(1);
      sequences[slot.away]!.add(-1);
    }
  }
  return sequences;
}

int _longestRun(List<int> sequence) {
  int longest = sequence.isEmpty ? 0 : 1;
  int run = 1;
  for (int i = 1; i < sequence.length; i++) {
    if (sequence[i] == sequence[i - 1]) {
      run++;
    } else {
      run = 1;
    }
    if (run > longest) longest = run;
  }
  return longest;
}

void main() {
  group('round-robin scheduler', () {
    test('matches the mandatory double round-robin table', () {
      const List<(int, int, int, int, int)> cases = <(int, int, int, int, int)>[
        (20, 38, 380, 19, 19),
        (18, 34, 306, 17, 17),
        (12, 22, 132, 11, 11),
        (10, 18, 90, 9, 9),
        (8, 14, 56, 7, 7),
      ];
      for (final (int n, int rounds, int matches, int home, int away)
          in cases) {
        final List<int> ids = List<int>.generate(n, (int i) => i + 1);
        final List<FixtureSlot> slots = RoundRobinScheduler.schedule(
          ids,
          doubleRound: true,
          random: Random(7),
        );
        expect(slots.length, matches, reason: '$n clubs');
        final Set<int> roundNumbers = <int>{
          for (final FixtureSlot s in slots) s.round,
        };
        expect(roundNumbers.length, rounds, reason: '$n clubs');
        expect(
          roundNumbers.reduce(max),
          rounds,
          reason: 'round numbers are 1..$rounds',
        );

        final Map<int, int> homes = <int, int>{};
        final Map<int, int> aways = <int, int>{};
        final Map<int, Set<int>> roundClubs = <int, Set<int>>{};
        final Set<String> directed = <String>{};
        final Map<String, int> pairs = <String, int>{};
        for (final FixtureSlot s in slots) {
          expect(s.home == s.away, isFalse);
          homes[s.home] = (homes[s.home] ?? 0) + 1;
          aways[s.away] = (aways[s.away] ?? 0) + 1;
          directed.add('${s.home}-${s.away}');
          final String pair = s.home < s.away
              ? '${s.home}-${s.away}'
              : '${s.away}-${s.home}';
          pairs[pair] = (pairs[pair] ?? 0) + 1;
          final Set<int> playing = roundClubs.putIfAbsent(
            s.round,
            () => <int>{},
          );
          expect(playing.add(s.home), isTrue, reason: 'double booked');
          expect(playing.add(s.away), isTrue, reason: 'double booked');
        }
        expect(directed.length, matches, reason: 'no duplicate fixtures');
        for (final int id in ids) {
          expect(homes[id], home, reason: 'club $id home total');
          expect(aways[id], away, reason: 'club $id away total');
        }
        for (final MapEntry<String, int> entry in pairs.entries) {
          expect(entry.value, 2, reason: 'pair ${entry.key} meets twice');
          final List<String> parts = entry.key.split('-');
          final int a = int.parse(parts[0]);
          final int b = int.parse(parts[1]);
          expect(homes[a], home);
          // Exactly one fixture in each direction.
          expect(directed.contains('$a-$b'), isTrue);
          expect(directed.contains('$b-$a'), isTrue);
        }
        final Map<int, List<int>> sequences = _homeAwaySequences(slots);
        for (final List<int> sequence in sequences.values) {
          expect(
            _longestRun(sequence),
            lessThanOrEqualTo(2),
            reason: 'at most two consecutive home/away matches',
          );
        }
      }
    });

    test('odd-sized league uses a bye and keeps home/away equal', () {
      final List<int> ids = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9];
      final List<FixtureSlot> slots = RoundRobinScheduler.schedule(
        ids,
        doubleRound: true,
        random: Random(11),
      );
      expect(slots.length, 72);
      final Set<int> rounds = <int>{for (final FixtureSlot s in slots) s.round};
      expect(rounds.length, 18);

      final Map<int, int> homes = <int, int>{};
      final Map<int, int> aways = <int, int>{};
      final Map<int, int> perRound = <int, int>{};
      final Set<String> directed = <String>{};
      for (final FixtureSlot s in slots) {
        homes[s.home] = (homes[s.home] ?? 0) + 1;
        aways[s.away] = (aways[s.away] ?? 0) + 1;
        perRound[s.round] = (perRound[s.round] ?? 0) + 1;
        directed.add('${s.home}-${s.away}');
      }
      expect(directed.length, 72);
      for (final int id in ids) {
        expect(homes[id], 8, reason: 'club $id home total');
        expect(aways[id], 8, reason: 'club $id away total');
      }
      // One club rests in each of the 18 rounds.
      expect(perRound.values.every((int count) => count == 4), isTrue);
    });

    test('single round-robin covers every pair once', () {
      for (final int n in <int>[8, 9, 10, 12]) {
        final List<int> ids = List<int>.generate(n, (int i) => i + 1);
        final List<FixtureSlot> slots = RoundRobinScheduler.schedule(
          ids,
          doubleRound: false,
          random: Random(3),
        );
        expect(slots.length, n * (n - 1) ~/ 2, reason: '$n clubs');
        final Set<int> rounds = <int>{
          for (final FixtureSlot s in slots) s.round,
        };
        expect(rounds.length, n.isOdd ? n : n - 1, reason: '$n clubs');
        final Map<int, int> homes = <int, int>{};
        final Map<int, int> aways = <int, int>{};
        final Set<String> pairs = <String>{};
        for (final FixtureSlot s in slots) {
          homes[s.home] = (homes[s.home] ?? 0) + 1;
          aways[s.away] = (aways[s.away] ?? 0) + 1;
          final String pair = s.home < s.away
              ? '${s.home}-${s.away}'
              : '${s.away}-${s.home}';
          expect(pairs.add(pair), isTrue, reason: 'duplicate pair');
        }
        for (final int id in ids) {
          final int played = (homes[id] ?? 0) + (aways[id] ?? 0);
          expect(played, n - 1, reason: 'club $id plays every opponent');
          expect(
            ((homes[id] ?? 0) - (aways[id] ?? 0)).abs(),
            lessThanOrEqualTo(1),
          );
        }
      }
    });

    test('is deterministic for identical inputs', () {
      final List<FixtureSlot> first = RoundRobinScheduler.schedule(
        List<int>.generate(12, (int i) => i + 1),
        doubleRound: true,
        random: Random(42),
      );
      final List<FixtureSlot> second = RoundRobinScheduler.schedule(
        List<int>.generate(12, (int i) => i + 1),
        doubleRound: true,
        random: Random(42),
      );
      expect(first.length, second.length);
      for (int i = 0; i < first.length; i++) {
        expect(first[i].round, second[i].round);
        expect(first[i].leg, second[i].leg);
        expect(first[i].home, second[i].home);
        expect(first[i].away, second[i].away);
      }
    });

    test('doubleRoundRobin compatibility wrapper still works', () {
      final List<FixtureSlot> slots = doubleRoundRobin(<int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);
      expect(slots.length, 72);
      expect(slots.every((FixtureSlot s) => s.home != s.away), isTrue);
    });
  });

  group('league phase scheduler', () {
    void verifyLeaguePhase({
      required int clubs,
      required int opponents,
      required int home,
      required int away,
    }) {
      final LeaguePhaseSchedule plan = LeaguePhaseScheduler.generate(
        List<int>.generate(clubs, (int i) => i + 1),
        opponents: opponents,
        homeMatches: home,
      );
      expect(plan.opponentRounds, opponents);
      expect(plan.fixtures.length, clubs * opponents ~/ 2);

      final Map<int, Set<int>> opponentsOf = <int, Set<int>>{
        for (int i = 0; i < clubs; i++) i + 1: <int>{},
      };
      final Map<int, int> homes = <int, int>{};
      final Map<int, int> aways = <int, int>{};
      final Set<String> pairs = <String>{};
      final Map<int, Set<int>> perRound = <int, Set<int>>{};

      for (final FixtureSlot fixture in plan.fixtures) {
        expect(fixture.home == fixture.away, isFalse);
        opponentsOf[fixture.home]!.add(fixture.away);
        opponentsOf[fixture.away]!.add(fixture.home);
        homes[fixture.home] = (homes[fixture.home] ?? 0) + 1;
        aways[fixture.away] = (aways[fixture.away] ?? 0) + 1;
        final String pair = fixture.home < fixture.away
            ? '${fixture.home}-${fixture.away}'
            : '${fixture.away}-${fixture.home}';
        expect(pairs.add(pair), isTrue, reason: 'repeated opponent');
        final Set<int> playing = perRound.putIfAbsent(
          fixture.round,
          () => <int>{},
        );
        expect(playing.add(fixture.home), isTrue);
        expect(playing.add(fixture.away), isTrue);
      }
      expect(perRound.length, opponents);
      for (final int club in opponentsOf.keys) {
        expect(opponentsOf[club]!.length, opponents);
        expect(homes[club], home, reason: 'club $club home total');
        expect(aways[club], away, reason: 'club $club away total');
      }
    }

    test('Champions League profile: 36 clubs, 8 opponents, 4/4', () {
      verifyLeaguePhase(clubs: 36, opponents: 8, home: 4, away: 4);
    });

    test('Conference League profile: 36 clubs, 6 opponents, 3/3', () {
      verifyLeaguePhase(clubs: 36, opponents: 6, home: 3, away: 3);
    });

    test('every pair is unique across the whole phase', () {
      final LeaguePhaseSchedule plan = LeaguePhaseScheduler.generate(
        List<int>.generate(36, (int i) => i + 1),
        opponents: 8,
        homeMatches: 4,
      );
      final Set<String> pairs = <String>{};
      for (final FixtureSlot f in plan.fixtures) {
        final String pair = f.home < f.away
            ? '${f.home}-${f.away}'
            : '${f.away}-${f.home}';
        expect(pairs.add(pair), isTrue);
      }
      expect(pairs.length, 144);
    });
  });

  group('knockout scheduler', () {
    test('uses byes for a field that is not a power of two', () {
      final KnockoutPlan plan = KnockoutScheduler.planOpeningRound(<int>[
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(plan.bracketSize, 8);
      expect(plan.byes.length, 2);
      expect(plan.byes, <int>[1, 2]);
      expect(plan.pairs.length, 2);
      expect(plan.roundsToFinal, 3);
      final Set<int> involved = <int>{
        for (final (int a, int b) in plan.pairs) ...<int>[a, b],
        ...plan.byes,
      };
      expect(involved.length, 6);
    });

    test('trims to the largest power of two when configured', () {
      final KnockoutPlan plan = KnockoutScheduler.planOpeningRound(<int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
      ], trimToPowerOfTwo: true);
      expect(plan.bracketSize, 8);
      expect(plan.pairs.length, 4);
      expect(plan.byes, isEmpty);
    });

    test('pairs the next round and carries an odd survivor as a bye', () {
      final KnockoutPlan plan = KnockoutScheduler.pairNextRound(<int>[
        10,
        20,
        30,
      ]);
      expect(plan.pairs.length, 1);
      expect(plan.byes, <int>[30]);
    });

    test('power-of-two detection', () {
      expect(KnockoutScheduler.isPowerOfTwo(64), isTrue);
      expect(KnockoutScheduler.isPowerOfTwo(63), isFalse);
      expect(KnockoutScheduler.isPowerOfTwo(0), isFalse);
    });
  });

  group('competition configuration', () {
    test('UEFA profiles are explicit and season-aware', () {
      final CompetitionConfig ucl = CompetitionConfig.forTournament(
        Tournament.fromMap(<String, Object?>{
          'tournament_id': 49,
          'name': 'UEFA Champions League',
          'organization': t.orgInternational,
          'slots': 36,
          'rounds': 1,
        }),
      );
      expect(ucl.format, CompetitionFormat.leaguePhase);
      expect(ucl.leaguePhaseOpponents, 8);
      expect(ucl.leaguePhaseHomeMatches, 4);
      expect(ucl.leaguePhaseAwayMatches, 4);
      expect(ucl.leaguePhaseQualifiers, 16);
      expect(ucl.knockoutLegs, 2);
      expect(ucl.finalSingleMatch, isTrue);
      expect(ucl.neutralFinal, isTrue);
      expect(ucl.awayGoals, isFalse);
    });

    test('season-specific override wins over the bundled profile', () {
      final Tournament tournament = Tournament.fromMap(<String, Object?>{
        'tournament_id': 49,
        'name': 'UEFA Champions League',
        'organization': t.orgInternational,
        'slots': 36,
        'rounds': 1,
      });
      final CompetitionConfig override = CompetitionConfig.forTournament(
        tournament,
        seasonStartYear: 2030,
      ).copyWith(leaguePhaseOpponents: 6);
      CompetitionConfig.override(override);
      addTearDown(() => CompetitionConfig.clearOverrides());
      final CompetitionConfig resolved = CompetitionConfig.forTournament(
        tournament,
        seasonStartYear: 2030,
      );
      expect(resolved.leaguePhaseOpponents, 6);
      // Other seasons keep the reference profile.
      expect(
        CompetitionConfig.forTournament(
          tournament,
          seasonStartYear: 2031,
        ).leaguePhaseOpponents,
        8,
      );
    });

    test(
      'domestic leagues stay double round-robin regardless of rounds flag',
      () {
        final CompetitionConfig config = CompetitionConfig.forTournament(
          Tournament.fromMap(<String, Object?>{
            'tournament_id': 1,
            'name': 'League',
            'organization': t.orgLeague,
            'slots': 18,
            'rounds': 1,
            'division_id': 1,
          }),
        );
        expect(config.format, CompetitionFormat.doubleRoundRobin);
        expect(config.doubleRoundRobin, isTrue);
      },
    );
  });

  group('database-backed scheduling', () {
    late Directory dir;
    late Database db;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('fixture_scheduling_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
    });

    tearDownAll(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<Map<int, Team>> teams(int count) async {
      final List<Map<String, Object?>> rows = await db.query(
        t.teams,
        where: 'division = 1',
        limit: count,
      );
      return <int, Team>{
        for (final Map<String, Object?> row in rows)
          row['team_id'] as int: Team.fromMap(row),
      };
    }

    test(
      'season config persists and is restored with unavailable dates',
      () async {
        final Tournament tournament = Tournament.fromMap(<String, Object?>{
          'tournament_id': 49,
          'name': 'UEFA Champions League',
          'organization': t.orgInternational,
          'slots': 36,
          'rounds': 1,
        });
        final CompetitionConfig config =
            CompetitionConfig.forTournament(
              tournament,
              seasonStartYear: 2044,
            ).copyWith(
              minRestDays: 4,
              matchdayIntervalDays: 9,
              groupQualifiersPerGroup: 1,
              allowedWeekdays: <int>[DateTime.monday, DateTime.friday],
              unavailableDates: <DateTime>[DateTime(2044, 8, 9)],
            );
        final FixtureSchedulingService calendar = FixtureSchedulingService(db);

        await calendar.persistConfig(config);
        final CompetitionConfig restored = await calendar.resolveConfig(
          tournament,
          seasonStartYear: 2044,
        );

        expect(restored.minRestDays, 4);
        expect(restored.matchdayIntervalDays, 9);
        expect(restored.groupQualifiersPerGroup, 1);
        expect(restored.allowedWeekdays, <int>[
          DateTime.monday,
          DateTime.friday,
        ]);
        expect(restored.unavailableDates, <DateTime>[DateTime(2044, 8, 9)]);
        final DateTime? available = calendar.findAvailableDate(
          preferred: DateTime(2044, 8, 9),
          homeTeamId: 1,
          awayTeamId: 2,
          clubDates: <int, List<DateTime>>{},
          seasonStart: DateTime(2044, 8, 1),
          seasonEnd: DateTime(2044, 8, 31),
          minRestDays: restored.minRestDays,
          preferredRestDays: restored.minRestDays,
          unavailableDates: restored.unavailableDates,
        );
        expect(available, DateTime(2044, 8, 10));
      },
    );

    test(
      'a single-match final has one neutral fixture and no return leg',
      () async {
        final Map<int, Team> cache = await teams(2);
        final SeasonGenerator generator = SeasonGenerator(
          db,
          random: Random(1),
        );
        const int seasonId = 7001;
        final int scheduled = await generator.scheduleCupRound(
          seasonId,
          54,
          cache.keys.toList(),
          phase: 1,
          date: DateTime(2025, 8, 6),
          allTeams: cache,
        );
        expect(scheduled, 1);
        final List<Map<String, Object?>> rows = await db.query(
          t.matches,
          where: 'season_id = ? AND tournament_id = ?',
          whereArgs: <Object?>[seasonId, 54],
        );
        expect(rows.length, 1);
        expect(rows.first['leg'], 1);
        expect(rows.first['neutral_venue'], 1);
        expect(rows.first['extra_time'], 1);
        expect(rows.first['away_goals_rule'], 0);
      },
    );

    test(
      'two-legged ties reverse venues and keep aggregate metadata',
      () async {
        final Map<int, Team> cache = await teams(4);
        final SeasonGenerator generator = SeasonGenerator(
          db,
          random: Random(2),
        );
        const int seasonId = 7002;
        final int scheduled = await generator.scheduleCupRound(
          seasonId,
          164,
          cache.keys.toList(),
          phase: 1,
          date: DateTime(2025, 9, 16),
          allTeams: cache,
        );
        expect(scheduled, 4);
        final List<Map<String, Object?>> rows = await db.query(
          t.matches,
          where: 'season_id = ? AND tournament_id = ?',
          whereArgs: <Object?>[seasonId, 164],
        );
        expect(rows.length, 4);
        final Map<String, Map<String, Object?>> byTie =
            <String, Map<String, Object?>>{};
        for (final Map<String, Object?> row in rows) {
          final int h = row['home_team_id'] as int;
          final int a = row['away_team_id'] as int;
          final String key = '$h-$a';
          byTie[key] = row;
        }
        for (final Map<String, Object?> first in rows.where(
          (Map<String, Object?> r) => r['leg'] == 1,
        )) {
          final int h = first['home_team_id'] as int;
          final int a = first['away_team_id'] as int;
          final Map<String, Object?>? second = byTie['$a-$h'];
          expect(second, isNotNull, reason: 'return leg reverses venues');
          expect(second!['leg'], 2);
          expect(second['away_goals_rule'], 0);
        }
      },
    );

    test('byes are persisted for the next knockout phase', () async {
      final Map<int, Team> cache = await teams(6);
      final List<int> ids = cache.keys.toList();
      final KnockoutPlan plan = KnockoutScheduler.planOpeningRound(ids);
      expect(plan.byes.length, 2);
      final SeasonGenerator generator = SeasonGenerator(db, random: Random(3));
      const int seasonId = 7003;
      final int scheduled = await generator.scheduleCupRound(
        seasonId,
        56,
        ids,
        phase: 1,
        date: DateTime(2025, 12, 10),
        allTeams: cache,
        pairs: plan.pairs,
        byes: plan.byes,
      );
      expect(scheduled, plan.pairs.length);
      final List<int> byes = await generator.byesForPhase(seasonId, 56, 1);
      expect(byes.toSet(), plan.byes.toSet());
    });
  });

  group('unified calendar and postponements', () {
    late Directory dir;
    late Database db;
    late FixtureSchedulingService calendar;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('fixture_calendar_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
      calendar = FixtureSchedulingService(db);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<int> insertSeason(int id, int year) async {
      await db.insert(t.seasons, <String, Object?>{
        'season_id': id,
        'name': 'Season $year',
        'start_year': year,
        'end_year': year + 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return id;
    }

    Future<int> insertMatch({
      required int seasonId,
      required int tournamentId,
      required int home,
      required int away,
      required String date,
      int phase = 1,
      int status = t.matchScheduled,
      int stadiumId = 1,
    }) async {
      return db.insert(t.matches, <String, Object?>{
        'season_id': seasonId,
        'tournament_id': tournamentId,
        'home_team_id': home,
        'away_team_id': away,
        'stadium_id': stadiumId,
        'phase': phase,
        'round': 1,
        'leg': 1,
        'status': status,
        'date': date,
      });
    }

    test(
      'resolves same-day clashes, records the audit trail and is idempotent',
      () async {
        const int seasonId = 8001;
        await insertSeason(seasonId, 2025);
        final int first = await insertMatch(
          seasonId: seasonId,
          tournamentId: 1,
          home: 1,
          away: 2,
          date: '2025-09-06',
        );
        final int second = await insertMatch(
          seasonId: seasonId,
          tournamentId: 3,
          home: 1,
          away: 3,
          date: '2025-09-06',
        );
        final int moved = await calendar.resolveSeasonConflicts(seasonId);
        expect(moved, 1);
        final List<Map<String, Object?>> rows = await db.query(
          t.matches,
          where: 'season_id = ?',
          whereArgs: <Object?>[seasonId],
          orderBy: 'match_id',
        );
        expect(rows.length, 2);
        expect(rows[0]['match_id'], first);
        expect(rows[1]['match_id'], second);
        expect(rows[1]['date'], isNot('2025-09-06'));
        expect(rows[1]['original_date'], '2025-09-06');
        expect(rows[1]['reschedule_reason'], isNotNull);
        final List<Map<String, Object?>> audit = await db.query(
          'fixture_reschedules',
          where: 'match_id = ?',
          whereArgs: <Object?>[second],
        );
        expect(audit, isNotEmpty);

        final int secondRun = await calendar.resolveSeasonConflicts(seasonId);
        expect(secondRun, 0, reason: 'calendar resolution is idempotent');
        final List<Map<String, Object?>> after = await db.query(
          t.matches,
          where: 'season_id = ?',
          whereArgs: <Object?>[seasonId],
        );
        expect(
          after.length,
          2,
          reason: 'no fixtures are duplicated or discarded',
        );
      },
    );

    test('enforces the minimum rest period between club fixtures', () async {
      const int seasonId = 8002;
      await insertSeason(seasonId, 2025);
      await insertMatch(
        seasonId: seasonId,
        tournamentId: 1,
        home: 4,
        away: 5,
        date: '2025-09-06',
      );
      final int next = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 4,
        away: 6,
        date: '2025-09-07',
      );
      final int moved = await calendar.resolveSeasonConflicts(seasonId);
      expect(moved, greaterThanOrEqualTo(1));
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'season_id = ? ORDER BY date',
        whereArgs: <Object?>[seasonId],
      );
      final List<DateTime> dates = <DateTime>[
        for (final Map<String, Object?> row in rows)
          DateTime.parse(row['date'] as String),
      ];
      expect(dates.length, 2);
      expect(dates[1].difference(dates[0]).inDays, greaterThanOrEqualTo(2));
      final List<Map<String, Object?>> rescheduled = await db.query(
        t.matches,
        where: 'match_id = ?',
        whereArgs: <Object?>[next],
      );
      expect(rescheduled.first['original_date'], '2025-09-07');
    });

    test('resolves same-day stadium clashes', () async {
      const int seasonId = 8006;
      await insertSeason(seasonId, 2025);
      await insertMatch(
        seasonId: seasonId,
        tournamentId: 1,
        home: 20,
        away: 21,
        date: '2025-09-06',
        stadiumId: 101,
      );
      final int clash = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 22,
        away: 23,
        date: '2025-09-06',
        stadiumId: 101,
      );

      expect(await calendar.resolveSeasonConflicts(seasonId), 1);
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'match_id = ?',
        whereArgs: <Object?>[clash],
      );
      expect(rows.single['date'], isNot('2025-09-06'));
    });

    test('cancelled fixtures do not reserve clubs or stadiums', () async {
      const int seasonId = 8007;
      await insertSeason(seasonId, 2025);
      await insertMatch(
        seasonId: seasonId,
        tournamentId: 1,
        home: 24,
        away: 25,
        date: '2025-09-06',
        status: t.matchCancelled,
        stadiumId: 102,
      );
      final int scheduled = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 24,
        away: 26,
        date: '2025-09-06',
        stadiumId: 102,
      );

      expect(await calendar.resolveSeasonConflicts(seasonId), 0);
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'match_id = ?',
        whereArgs: <Object?>[scheduled],
      );
      expect(rows.single['date'], '2025-09-06');
    });

    test('does not reschedule a fixture beyond the season end', () async {
      const int seasonId = 8008;
      await insertSeason(seasonId, 2025);
      final int matchId = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 27,
        away: 28,
        date: '2026-06-27',
      );

      final FixtureRescheduleResult result = await calendar.rescheduleMatch(
        matchId,
        DateTime(2026, 7, 1),
      );

      expect(result.success, isFalse);
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'match_id = ?',
        whereArgs: <Object?>[matchId],
      );
      expect(rows.single['date'], '2026-06-27');
    });

    test('saving a result twice does not duplicate incidents', () async {
      const int seasonId = 8009;
      await insertSeason(seasonId, 2025);
      final int matchId = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 29,
        away: 30,
        date: '2025-09-06',
      );
      final MatchRepository repository = MatchRepository(db);
      final int injuredPlayerId =
          (await db.query(
                t.players,
                columns: <String>['player_id'],
                limit: 1,
              )).single['player_id']!
              as int;
      Future<void> save() => repository.saveResult(
        matchId: matchId,
        homeGoals: 1,
        awayGoals: 0,
        winnerId: 29,
        attendanceGeneral: 0,
        attendanceStand: 0,
        attendanceTerrace: 0,
        attendanceBoxes: 0,
        revenue: 0,
        events: <Map<String, Object?>>[
          <String, Object?>{'type': MatchRepository.evGoal},
        ],
        playerRows: const <Map<String, Object?>>[],
        injuredPlayerIds: <int>[injuredPlayerId],
        injuryReturnDates: <int, String>{injuredPlayerId: '2025-09-10'},
        suspendedPlayerIds: const <int>[],
      );

      await save();
      final Map<String, Object?> injuredPlayer = (await db.query(
        t.players,
        columns: <String>['fitness', 'injury_return_date'],
        where: 'player_id = ?',
        whereArgs: <Object?>[injuredPlayerId],
      )).single;
      expect(injuredPlayer['fitness'], 40);
      expect(injuredPlayer['injury_return_date'], '2025-09-10');
      await expectLater(save(), throwsA(isA<StateError>()));
      expect(
        await db.query(
          t.matchIncidents,
          where: 'match_id = ?',
          whereArgs: <Object?>[matchId],
        ),
        hasLength(1),
      );
    });

    test('postponement keeps the fixture identity and status', () async {
      const int seasonId = 8003;
      await insertSeason(seasonId, 2025);
      final int matchId = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 7,
        away: 8,
        date: '2025-09-06',
      );
      final FixtureRescheduleResult result = await calendar.postponeMatch(
        matchId,
        reason: 'Waterlogged pitch',
      );
      expect(result.success, isTrue);
      expect(result.oldDate, '2025-09-06');
      expect(result.newDate, isNotNull);
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[seasonId, 3],
      );
      expect(rows.length, 1, reason: 'no duplicate fixture was created');
      expect(rows.first['match_id'], matchId);
      expect(rows.first['date'], result.newDate);
      expect(rows.first['original_date'], '2025-09-06');
      expect(rows.first['reschedule_reason'], 'Waterlogged pitch');
      expect(rows.first['status'], t.matchScheduled);
      final int remaining = (await db.query(
        t.matches,
        where: 'season_id = ? AND status = ?',
        whereArgs: <Object?>[seasonId, t.matchScheduled],
      )).length;
      expect(remaining, 1, reason: 'postponed match still counts as scheduled');
    });

    test('completed fixtures cannot be postponed', () async {
      const int seasonId = 8004;
      await insertSeason(seasonId, 2025);
      final int matchId = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 9,
        away: 10,
        date: '2025-09-06',
        status: t.matchFinished,
      );
      final FixtureRescheduleResult result = await calendar.postponeMatch(
        matchId,
      );
      expect(result.success, isFalse);
      expect(result.message, contains('Completed'));
    });

    test('an explicitly requested conflicting date is moved safely', () async {
      const int seasonId = 8005;
      await insertSeason(seasonId, 2025);
      final int first = await insertMatch(
        seasonId: seasonId,
        tournamentId: 3,
        home: 11,
        away: 12,
        date: '2025-09-06',
      );
      await insertMatch(
        seasonId: seasonId,
        tournamentId: 1,
        home: 11,
        away: 13,
        date: '2025-09-10',
      );
      final FixtureRescheduleResult result = await calendar.rescheduleMatch(
        first,
        DateTime(2025, 9, 10),
        reason: 'Requested by broadcaster',
      );
      expect(result.success, isTrue);
      expect(result.newDate, isNot('2025-09-10'));
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'match_id = ?',
        whereArgs: <Object?>[first],
      );
      expect(rows.first['date'], result.newDate);
    });
  });

  group('fixture validator', () {
    test('league violations are actionable', () {
      final List<FixtureMatch> fixtures = <FixtureMatch>[
        fixture(1, 1, 2, round: 1),
        fixture(2, 2, 1, round: 2),
        fixture(3, 1, 1, round: 3, leg: 1),
      ];
      final FixtureValidationReport report = FixtureValidator.validateLeague(
        competitionId: 1,
        seasonId: 2,
        fixtures: fixtures,
        clubIds: <int>[1, 2],
      );
      expect(report.isValid, isFalse);
      expect(
        report.violations.any(
          (FixtureViolation v) => v.code == 'league_self_fixture',
        ),
        isTrue,
      );
      expect(
        report.violations.any(
          (FixtureViolation v) => v.code == 'league_pair_coverage',
        ),
        isTrue,
      );
      final String text = report.violations.first.toString();
      expect(text, contains('competition=1'));
      expect(text, contains('season=2'));
    });

    test('league-phase validation detects repeated opponents and totals', () {
      final List<FixtureMatch> fixtures = <FixtureMatch>[
        fixture(1, 1, 2, phase: 0, round: 1),
        fixture(2, 1, 2, phase: 0, round: 2),
        fixture(3, 3, 4, phase: 0, round: 1),
        fixture(4, 4, 3, phase: 0, round: 2),
      ];
      final FixtureValidationReport report =
          FixtureValidator.validateLeaguePhase(
            competitionId: 49,
            seasonId: 3,
            fixtures: fixtures,
            clubIds: <int>[1, 2, 3, 4],
            opponentsPerClub: 1,
            homeMatches: 1,
            awayMatches: 0,
          );
      expect(report.isValid, isFalse);
      expect(
        report.violations.any(
          (FixtureViolation v) => v.code == 'league_phase_repeated_opponent',
        ),
        isTrue,
      );
    });

    test('knockout validation checks reversals and winners', () {
      final List<FixtureMatch> valid = <FixtureMatch>[
        fixture(1, 1, 2, leg: 1, round: 1),
        fixture(2, 2, 1, leg: 2, round: 1),
      ];
      expect(
        FixtureValidator.validateKnockout(
          competitionId: 3,
          seasonId: 1,
          fixtures: valid,
          expectedLegs: 2,
        ).isValid,
        isTrue,
      );
      final List<FixtureMatch> invalid = <FixtureMatch>[
        fixture(1, 1, 2, leg: 1, round: 1),
        fixture(2, 1, 2, leg: 2, round: 1),
        fixture(
          3,
          3,
          4,
          leg: 1,
          round: 2,
          status: 'finished',
          homeGoals: 1,
          awayGoals: 1,
        ),
      ];
      final FixtureValidationReport report = FixtureValidator.validateKnockout(
        competitionId: 3,
        seasonId: 1,
        fixtures: invalid,
        expectedLegs: 2,
      );
      expect(report.isValid, isFalse);
      expect(
        report.violations.any(
          (FixtureViolation v) => v.code == 'knockout_no_reversal',
        ),
        isTrue,
      );
      expect(
        report.violations.any(
          (FixtureViolation v) => v.code == 'knockout_missing_winner',
        ),
        isTrue,
      );
    });

    test('calendar validation detects overlaps and short rest', () {
      final List<FixtureMatch> fixtures = <FixtureMatch>[
        fixture(1, 1, 2, date: '2025-09-06'),
        fixture(2, 1, 3, date: '2025-09-06'),
        fixture(3, 2, 4, date: '2025-09-07'),
      ];
      final FixtureValidationReport report = FixtureValidator.validateCalendar(
        fixtures: fixtures,
      );
      expect(
        report.violations.any(
          (FixtureViolation v) => v.code == 'calendar_overlap',
        ),
        isTrue,
      );
      expect(
        report.violations.any(
          (FixtureViolation v) => v.code == 'calendar_rest',
        ),
        isTrue,
      );
    });
  });

  group('league-phase integration', () {
    late Directory dir;
    late Database db;
    late SeasonGenerator generator;
    late Season season;
    late Map<int, Team> teamCache;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('league_phase_e2e_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);

      const int countryId = 185; // England
      final Tournament league = Tournament.fromMap(
        (await db.rawQuery(
          '''
          SELECT tu.* FROM tournaments tu
          JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
          WHERE tc.country_id = ? AND tu.organization = ?
            AND tu.division_id = 1
          LIMIT 1
        ''',
          <Object?>[countryId, t.orgLeague],
        )).first,
      );
      final Tournament cup = Tournament.fromMap(
        (await db.rawQuery(
          '''
          SELECT tu.* FROM tournaments tu
          JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
          WHERE tc.country_id = ? AND tu.organization = ?
          LIMIT 1
        ''',
          <Object?>[countryId, t.orgNationalCup],
        )).first,
      );
      generator = SeasonGenerator(db, random: Random(13));
      final CareerPlan plan = await generator.generateCareer(
        countryId: countryId,
        league: league,
        cup: cup,
      );
      season = plan.season;

      final List<Tournament> internationals = await ReferenceRepository(db)
          .internationalCups(countryId);
      final Tournament ucl = internationals.firstWhere(
        (Tournament tournament) => tournament.tournamentId == 49,
      );
      final List<Map<String, Object?>> registered = await db.rawQuery(
        '''
        SELECT tm.* FROM season_teams st
        JOIN teams tm ON tm.team_id = st.team_id
        WHERE st.season_id = ?
      ''',
        <Object?>[season.seasonId],
      );
      teamCache = <int, Team>{
        for (final Map<String, Object?> row in registered)
          row['team_id'] as int: Team.fromMap(row),
      };
      final int added = await generator.addInternationalCups(
        season: season,
        internationals: <Tournament>[ucl],
        teamCache: teamCache,
      );
      expect(added, 1);
    });

    tearDownAll(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('generates a complete, valid league phase', () async {
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[season.seasonId, 49],
      );
      expect(rows.length, 144);
      expect(
        rows.every(
          (Map<String, Object?> row) =>
              row['phase'] == 0 && row['group_id'] == null,
        ),
        isTrue,
      );
      final Set<int> clubs = <int>{};
      for (final Map<String, Object?> row in rows) {
        clubs.add(row['home_team_id'] as int);
        clubs.add(row['away_team_id'] as int);
      }
      expect(clubs.length, 36);

      final Map<int, Set<int>> opponents = <int, Set<int>>{
        for (final int id in clubs) id: <int>{},
      };
      final Map<int, int> homes = <int, int>{};
      final Map<int, int> aways = <int, int>{};
      final Map<int, Set<String>> dates = <int, Set<String>>{};
      for (final Map<String, Object?> row in rows) {
        final int h = row['home_team_id'] as int;
        final int a = row['away_team_id'] as int;
        opponents[h]!.add(a);
        opponents[a]!.add(h);
        homes[h] = (homes[h] ?? 0) + 1;
        aways[a] = (aways[a] ?? 0) + 1;
        dates.putIfAbsent(h, () => <String>{}).add(row['date'] as String);
        dates.putIfAbsent(a, () => <String>{}).add(row['date'] as String);
      }
      for (final int club in clubs) {
        expect(opponents[club]!.length, 8, reason: 'club $club opponents');
        expect(homes[club], 4, reason: 'club $club home matches');
        expect(aways[club], 4, reason: 'club $club away matches');
      }

      final FixtureValidationReport report = await FixtureSchedulingService(db)
          .validateSeason(season.seasonId);
      final List<FixtureViolation> leaguePhaseErrors = report.violations
          .where(
            (FixtureViolation v) =>
                v.isError &&
                (v.competitionId == 49 || v.code.startsWith('league_phase')),
          )
          .toList();
      expect(leaguePhaseErrors, isEmpty, reason: report.describe());
      expect(
        report.violations.where((FixtureViolation v) => v.isError),
        isEmpty,
        reason: report.describe(),
      );
    });

    test('top 16 progress to a two-legged knockout round', () async {
      await db.update(
        t.matches,
        <String, Object?>{'status': t.matchFinished},
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[season.seasonId, 49],
      );
      // Give every league-phase home club a win so the table is complete.
      await db.rawUpdate(
        '''
        UPDATE matches
        SET home_goals = 1, away_goals = 0, winner_id = home_team_id
        WHERE season_id = ? AND tournament_id = ? AND phase = 0
      ''',
        <Object?>[season.seasonId, 49],
      );

      final CareerService service = CareerService(
        db,
        refs: ReferenceRepository(db),
        seasons: SeasonRepository(db),
        squads: SquadRepository(db),
        matches: MatchRepository(db),
        messages: MessageRepository(db),
        engine: MatchEngine(random: Random(13)),
        generator: generator,
        random: Random(13),
      );
      final bool scheduled = await service.maybeScheduleNextCupRound(
        seasonId: season.seasonId,
        cupTournamentId: 49,
        teamCache: teamCache,
      );
      expect(scheduled, isTrue);

      final List<Map<String, Object?>> knockout = await db.query(
        t.matches,
        where:
            'season_id = ? AND tournament_id = ? AND phase = 1 '
            'AND group_id IS NULL',
        whereArgs: <Object?>[season.seasonId, 49],
      );
      expect(knockout.length, 16, reason: '8 ties x 2 legs');
      final List<Map<String, Object?>> leg1 = knockout
          .where((Map<String, Object?> row) => row['leg'] == 1)
          .toList();
      final List<Map<String, Object?>> leg2 = knockout
          .where((Map<String, Object?> row) => row['leg'] == 2)
          .toList();
      expect(leg1.length, 8);
      expect(leg2.length, 8);
      final Set<int> qualifiers = <int>{};
      for (final Map<String, Object?> row in leg1) {
        qualifiers.add(row['home_team_id'] as int);
        qualifiers.add(row['away_team_id'] as int);
      }
      expect(qualifiers.length, 16);
    });
  });

  group('existing competition validation', () {
    test(
      'representative UEFA, AFC and CONCACAF seasons validate cleanly',
      () async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        const List<(String, int)> countries = <(String, int)>[
          ('England', 185),
          ('Germany', 3),
          ('Indonesia', 94),
          ('Mexico', 141),
        ];
        for (final (String name, int countryId) in countries) {
          final Directory dir = await Directory.systemTemp.createTemp(
            'validate_$countryId',
          );
          final String path = p.join(dir.path, 'game.db');
          await File(p.join('assets', 'data', 'superkickoff_2025.db'))
              .copy(path);
          final Database db = await databaseFactory.openDatabase(path);
          try {
            await AppDatabase.ensureLocalTables(db);
            final List<Map<String, Object?>> leagueRows = await db.rawQuery(
              '''
            SELECT tu.* FROM tournaments tu
            JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
            WHERE tc.country_id = ? AND tu.organization = ?
              AND tu.division_id = 1
            LIMIT 1
          ''',
              <Object?>[countryId, t.orgLeague],
            );
            final List<Map<String, Object?>> cupRows = await db.rawQuery(
              '''
            SELECT tu.* FROM tournaments tu
            JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
            WHERE tc.country_id = ? AND tu.organization = ?
            LIMIT 1
          ''',
              <Object?>[countryId, t.orgNationalCup],
            );
            final Tournament league = Tournament.fromMap(leagueRows.first);
            final Tournament cup = Tournament.fromMap(cupRows.first);
            final List<Tournament> internationals = await ReferenceRepository(
              db,
            ).internationalCups(countryId);
            final CareerPlan plan =
                await SeasonGenerator(db, random: Random(17)).generateCareer(
                  countryId: countryId,
                  league: league,
                  cup: cup,
                  internationals: internationals,
                );
            final FixtureValidationReport report =
                await FixtureSchedulingService(db)
                    .validateSeason(plan.season.seasonId);
            expect(
              report.violations.where((FixtureViolation v) => v.isError),
              isEmpty,
              reason: '$name: ${report.describe()}',
            );
          } finally {
            await db.close();
            await dir.delete(recursive: true);
          }
        }
      },
    );
  });

  group('saved-game compatibility', () {
    test(
      'league schedule is unaffected by the generator random seed',
      () async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final Directory dir = await Directory.systemTemp.createTemp(
          'deterministic_schedule_',
        );
        addTearDown(() async {
          await dir.delete(recursive: true);
        });
        final String path = p.join(dir.path, 'game.db');
        await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
        final Database db = await databaseFactory.openDatabase(path);
        await AppDatabase.ensureLocalTables(db);
        final List<Map<String, Object?>> leagueRows = await db.rawQuery(
          '''
        SELECT tu.* FROM tournaments tu
        JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
        WHERE tc.country_id = ? AND tu.organization = ?
          AND tu.division_id = 1
        LIMIT 1
      ''',
          <Object?>[141, t.orgLeague],
        );
        final Tournament league = Tournament.fromMap(leagueRows.first);
        final CareerPlan first = await SeasonGenerator(db, random: Random(5))
            .generateCareer(
              countryId: 141,
              league: league,
              cup: null,
              startYear: 2045,
            );
        final CareerPlan second = await SeasonGenerator(db, random: Random(99))
            .generateCareer(
              countryId: 141,
              league: league,
              cup: null,
              startYear: 2045,
            );

        Future<List<String>> schedule(int seasonId) async {
          final List<Map<String, Object?>> rows = await db.query(
            t.matches,
            columns: <String>[
              'round',
              'leg',
              'home_team_id',
              'away_team_id',
              'date',
            ],
            where: 'season_id = ? AND tournament_id = ?',
            whereArgs: <Object?>[seasonId, league.tournamentId],
            orderBy: 'round, leg, home_team_id, away_team_id',
          );
          return rows
              .map((Map<String, Object?> row) => row.toString())
              .toList();
        }

        expect(
          await schedule(first.season.seasonId),
          await schedule(second.season.seasonId),
        );
        await db.close();
      },
    );

    test('migrations are idempotent and preserve existing rows', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final Directory dir = await Directory.systemTemp.createTemp('migration_');
      addTearDown(() async {
        await dir.delete(recursive: true);
      });
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      Database db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);

      await db.insert(t.matches, <String, Object?>{
        'match_id': 910001,
        'season_id': 9100,
        'tournament_id': 1,
        'home_team_id': 1,
        'away_team_id': 2,
        'stadium_id': 1,
        'phase': 1,
        'round': 1,
        'leg': 1,
        'status': t.matchFinished,
        'home_goals': 2,
        'away_goals': 1,
        'winner_id': 1,
        'date': '2024-09-07',
      });
      await db.close();

      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
      await db.execute(
        'ALTER TABLE competition_configs DROP COLUMN unavailable_dates',
      );
      await db.execute(
        'ALTER TABLE competition_configs '
        'DROP COLUMN group_qualifiers_per_group',
      );
      await db.execute(
        'ALTER TABLE competition_configs DROP COLUMN allowed_weekdays',
      );
      await AppDatabase.ensureLocalTables(db);
      final List<Map<String, Object?>> configColumns = await db.rawQuery(
        'PRAGMA table_info(competition_configs)',
      );
      final Set<String> configColumnNames = <String>{
        for (final Map<String, Object?> column in configColumns)
          column['name'] as String,
      };
      expect(
        configColumnNames,
        containsAll(<String>[
          'unavailable_dates',
          'group_qualifiers_per_group',
          'allowed_weekdays',
        ]),
      );
      final List<Map<String, Object?>> columns = await db.rawQuery(
        'PRAGMA table_info(${t.matches})',
      );
      final Set<String> names = <String>{
        for (final Map<String, Object?> column in columns)
          column['name'] as String,
      };
      expect(
        names,
        containsAll(<String>[
          'kickoff_time',
          'original_date',
          'reschedule_reason',
          'neutral_venue',
          'extra_time',
          'away_goals_rule',
        ]),
      );
      for (final String table in <String>[
        'competition_configs',
        'fixture_reschedules',
        'knockout_byes',
      ]) {
        final int? found = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
            <Object?>[table],
          ),
        );
        expect(found, 1, reason: '$table exists');
      }
      final List<Map<String, Object?>> preserved = await db.query(
        t.matches,
        where: 'match_id = ?',
        whereArgs: <Object?>[910001],
      );
      expect(preserved.length, 1);
      expect(preserved.first['home_goals'], 2);
      expect(preserved.first['winner_id'], 1);
      await db.close();
    });

    test('reloading a generated season does not duplicate fixtures', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final Directory dir = await Directory.systemTemp.createTemp('reload_');
      addTearDown(() async {
        await dir.delete(recursive: true);
      });
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      Database db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
      final SeasonGenerator generator = SeasonGenerator(db, random: Random(5));
      final List<Map<String, Object?>> leagueRows = await db.rawQuery(
        '''
        SELECT tu.* FROM tournaments tu
        JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
        WHERE tc.country_id = ? AND tu.organization = ?
          AND tu.division_id = 1
        LIMIT 1
      ''',
        <Object?>[141, t.orgLeague],
      );
      final Tournament league = Tournament.fromMap(leagueRows.first);
      // Use a real league for the season, but only the league (no cup).
      final CareerPlan plan = await generator.generateCareer(
        countryId: 141,
        league: league,
        cup: null,
      );
      final int before = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${t.matches} WHERE season_id = ?',
          <Object?>[plan.season.seasonId],
        ),
      )!;
      await db.close();

      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
      final int after = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${t.matches} WHERE season_id = ?',
          <Object?>[plan.season.seasonId],
        ),
      )!;
      expect(after, before);
      expect(after, greaterThan(0));
      await db.close();
    });
  });
}
