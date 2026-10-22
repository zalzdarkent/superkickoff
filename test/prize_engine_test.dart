import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/repositories/prize_repository.dart';
import 'package:superkickoff/game/prize_engine.dart';

void main() {
  group('PrizeEngine', () {
    test('classifies competition kinds from metadata', () {
      expect(
        PrizeEngine.kindOf(organization: 1, entrants: 20, nameHintSlots: 2),
        CompetitionKind.league,
      );
      expect(
        PrizeEngine.kindOf(organization: 3, entrants: 32, nameHintSlots: 1),
        CompetitionKind.domesticCup,
      );
      expect(
        PrizeEngine.kindOf(organization: 2, entrants: 32, nameHintSlots: 2),
        CompetitionKind.continental,
      );
      expect(
        PrizeEngine.kindOf(organization: 2, entrants: 2, nameHintSlots: 1),
        CompetitionKind.superCup,
      );
      expect(
        PrizeEngine.kindOf(organization: 2, entrants: 32, nameHintSlots: 32),
        CompetitionKind.intercontinental,
      );
    });

    test('league pays every club with a top-heavy distribution', () {
      const PrizeEngine engine = PrizeEngine();
      final CompetitionPrizeResult result = engine.leaguePrizes(
        tournamentId: 1,
        profile: const CompetitionProfile(
          kind: CompetitionKind.league,
          entrants: 20,
          countryPower: 80,
        ),
        rankedTeamIds: List<int>.generate(20, (int i) => i + 1),
      );

      expect(result.awards.length, 20);
      expect(result.awards.first.amount, greaterThan(result.awards.last.amount));
      expect(result.awards.every((PrizeAward a) => a.amount > 0), isTrue);
      // Pool is fully distributed across the table.
      final int expected = result.prizePool - result.awards.first.amount;
      expect(result.totalDistributed, greaterThanOrEqualTo(expected));
    });

    test('runaway prize money is bounded by economy scale', () {
      const PrizeEngine engine = PrizeEngine();
      final int rich = engine
          .leaguePrizes(
            tournamentId: 1,
            profile: const CompetitionProfile(
              kind: CompetitionKind.league,
              entrants: 20,
              countryPower: 95,
              confederation: 3,
            ),
            rankedTeamIds: List<int>.generate(20, (int i) => i + 1),
          )
          .prizePool;
      final int poor = engine
          .leaguePrizes(
            tournamentId: 2,
            profile: const CompetitionProfile(
              kind: CompetitionKind.league,
              entrants: 20,
              tier: 3,
              countryPower: 30,
              confederation: 5,
            ),
            rankedTeamIds: List<int>.generate(20, (int i) => i + 1),
          )
          .prizePool;

      expect(rich, greaterThan(poor * 3));
      expect(poor, greaterThan(0));
    });

    test('cup pays participation, progression and champion bonus', () {
      const PrizeEngine engine = PrizeEngine();
      final CompetitionPrizeResult result = engine.cupPrizes(
        tournamentId: 3,
        kind: CompetitionKind.domesticCup,
        profile: const CompetitionProfile(
          kind: CompetitionKind.domesticCup,
          entrants: 32,
          countryPower: 80,
        ),
        reachedRoundByTeam: <int, int>{1: 5, 2: 5, 3: 3, 4: 1},
        maxRound: 5,
        winnerTeamId: 1,
        runnerUpTeamId: 2,
      );

      final int champion = result.awards
          .firstWhere((PrizeAward a) => a.teamId == 1)
          .amount;
      final int runnerUp = result.awards
          .firstWhere((PrizeAward a) => a.teamId == 2)
          .amount;
      final int early = result.awards
          .firstWhere((PrizeAward a) => a.teamId == 3)
          .amount;
      final int firstRound = result.awards
          .firstWhere((PrizeAward a) => a.teamId == 4)
          .amount;

      expect(champion, greaterThan(runnerUp));
      expect(runnerUp, greaterThan(early));
      expect(early, greaterThan(firstRound));
    });

    test('continental adds win and draw bonuses', () {
      const PrizeEngine engine = PrizeEngine();
      final CompetitionPrizeResult result = engine.cupPrizes(
        tournamentId: 49,
        kind: CompetitionKind.continental,
        profile: const CompetitionProfile(
          kind: CompetitionKind.continental,
          entrants: 32,
          countryPower: 88,
          confederation: 3,
        ),
        reachedRoundByTeam: <int, int>{10: 4, 11: 1},
        maxRound: 4,
        winnerTeamId: 10,
        runnerUpTeamId: 11,
        winsByTeam: <int, int>{10: 6, 11: 2},
        drawsByTeam: <int, int>{10: 1, 11: 3},
      );

      expect(result.awards.firstWhere((a) => a.teamId == 10).amount,
          greaterThan(result.awards.firstWhere((a) => a.teamId == 11).amount));
    });

    test('per-competition override replaces the default rule', () {
      const PrizeEngine engine = PrizeEngine(
        configOverrides: <int, PrizeRule>{
          77: PrizeRule(basePool: 1000000, positionWeights: <int>[3, 1]),
        },
      );
      final CompetitionPrizeResult result = engine.leaguePrizes(
        tournamentId: 77,
        profile: const CompetitionProfile(
          kind: CompetitionKind.league,
          entrants: 2,
          countryPower: 100,
        ),
        rankedTeamIds: <int>[1, 2],
      );

      expect(result.awards.first.amount, greaterThan(result.awards.last.amount));
      expect(result.prizePool, lessThan(5000000));
    });
  });

  group('PrizeRepository', () {
    late Directory dir;
    late Database db;
    late PrizeRepository prizes;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('prize_test_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
      prizes = PrizeRepository(db);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test('pays each award once per season', () async {
      const CompetitionPrizeResult result = CompetitionPrizeResult(
        tournamentId: 1,
        kind: CompetitionKind.league,
        prizePool: 3000,
        awards: <PrizeAward>[
          PrizeAward(teamId: 42, amount: 2000, reason: 'champion'),
          PrizeAward(teamId: 42, amount: 1000, reason: 'duplicate'),
        ],
      );

      final int before = await _budget(db, 42);
      final List<PrizeAward> first = await prizes.pay(
        seasonId: 1,
        result: result,
        date: '2026-06-01',
      );
      expect(first.length, greaterThan(0));
      final int afterFirst = await _budget(db, 42);
      expect(afterFirst, before + first.first.amount);

      final List<PrizeAward> second = await prizes.pay(
        seasonId: 1,
        result: result,
        date: '2026-06-01',
      );
      expect(second, isEmpty);
      expect(await _budget(db, 42), afterFirst);
    });

    test('stores tournament rule overrides', () async {
      await db.insert('competition_prize_rules', <String, Object?>{
        'tournament_id': 7,
        'base_pool': 123456,
        'position_weights': '5,3,1',
      });
      final Map<int, PrizeRule> loaded = await prizes.overrides(<int>[7]);
      expect(loaded[7]!.basePool, 123456);
      expect(loaded[7]!.positionWeights, <int>[5, 3, 1]);
    });
  });
}

Future<int> _budget(Database db, int teamId) async {
  final List<Map<String, Object?>> rows = await db.query(
    'teams',
    columns: <String>['budget'],
    where: 'team_id = ?',
    whereArgs: <Object?>[teamId],
  );
  return (rows.first['budget'] as int?) ?? 0;
}
