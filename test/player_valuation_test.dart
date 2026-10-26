import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/game/player_valuation_service.dart';

void main() {
  const PlayerValuationService service = PlayerValuationService();

  group('PlayerValuationService - Phase 12 Comprehensive Audit Suite', () {
    // 1. MV increases appropriately when OVR improves
    test('1. MV increases appropriately when OVR improves', () {
      final int v70 = service.calculateTargetMarketValue(
        power: 70,
        age: 24,
        positionId: 7,
      );
      final int v78 = service.calculateTargetMarketValue(
        power: 78,
        age: 24,
        positionId: 7,
      );
      final int v85 = service.calculateTargetMarketValue(
        power: 85,
        age: 24,
        positionId: 7,
      );
      final int v90 = service.calculateTargetMarketValue(
        power: 90,
        age: 24,
        positionId: 7,
      );

      expect(v70, lessThan(v78));
      expect(v78, lessThan(v85));
      expect(v85, lessThan(v90));
      expect(v70, greaterThan(1000000));
      expect(v90, greaterThan(70000000));
    });

    // 2. MV does not grow exponentially through repeated recalculation
    test('2. MV does not grow exponentially through repeated recalculation', () {
      int currentVal = 100000000;
      final int targetVal = service.calculateTargetMarketValue(
        power: 90,
        potential: 94,
        age: 22,
        positionId: 7,
      );

      // Repeat updates 10 times with static player state
      for (int i = 0; i < 10; i++) {
        currentVal = service.smoothValueUpdate(
          currentValue: currentVal,
          targetValue: targetVal,
        );
      }

      // Must converge smoothly to target, never explode exponentially
      expect(currentVal, equals(targetVal));
      expect(currentVal, lessThan(200000000));
    });

    // 3. Two players with same OVR have different values due to age, potential, and performance
    test('3. Same OVR players have differentiated values by age/potential/performance', () {
      final int youngProspect = service.calculateTargetMarketValue(
        power: 82,
        potential: 90,
        age: 20,
        positionId: 9,
      );
      final int primePlayer = service.calculateTargetMarketValue(
        power: 82,
        potential: 83,
        age: 26,
        positionId: 9,
      );
      final int veteranPlayer = service.calculateTargetMarketValue(
        power: 82,
        potential: 82,
        age: 33,
        positionId: 9,
      );

      expect(youngProspect, greaterThan(primePlayer));
      expect(primePlayer, greaterThan(veteranPlayer));
    });

    // 4. Young high-potential players receive a reasonable premium
    test('4. Young high-potential players receive bounded premium', () {
      final int normalYoung = service.calculateTargetMarketValue(
        power: 74,
        potential: 76,
        age: 19,
        positionId: 10,
      );
      final int wonderkid = service.calculateTargetMarketValue(
        power: 74,
        potential: 91,
        age: 19,
        positionId: 10,
      );

      final double ratio = wonderkid / normalYoung;
      expect(ratio, greaterThanOrEqualTo(1.15));
      expect(ratio, lessThanOrEqualTo(1.60)); // Premium is bounded
    });

    // 5. Potential alone does not create billion-dollar valuations
    test('5. Potential alone does not create extreme or billion-dollar valuations', () {
      final int unprovenWonderkid = service.calculateTargetMarketValue(
        power: 62,
        potential: 99,
        age: 17,
        positionId: 10,
      );

      // Even with 99 potential, a 62-rated player must remain realistic
      expect(unprovenWonderkid, lessThan(10000000));
      expect(unprovenWonderkid, greaterThan(300000));
    });

    // 6. Older players experience reasonable age-related adjustment
    test('6. Older players experience reasonable age discount', () {
      final double mult26 = service.calculateAgeMultiplier(26);
      final double mult31 = service.calculateAgeMultiplier(31);
      final double mult34 = service.calculateAgeMultiplier(34);
      final double mult37 = service.calculateAgeMultiplier(37);

      expect(mult26, greaterThanOrEqualTo(1.0));
      expect(mult31, lessThan(mult26));
      expect(mult34, lessThan(mult31));
      expect(mult37, lessThan(mult34));
      expect(mult37, greaterThanOrEqualTo(0.15)); // Never drops to zero
    });

    // 7. Exceptional older players retain significant value
    test('7. Exceptional older players retain significant market value', () {
      // 36yo superstar (e.g. 88 OVR veteran)
      final int veteranStar = service.calculateTargetMarketValue(
        power: 88,
        potential: 88,
        age: 36,
        positionId: 10,
      );

      expect(veteranStar, greaterThan(15000000));
      expect(veteranStar, lessThan(45000000));
    });

    // 8. Position-specific valuation works correctly
    test('8. Position-specific valuation behaves realistically', () {
      final int striker = service.calculateTargetMarketValue(
        power: 84,
        age: 25,
        positionId: 10, // CF
      );
      final int goalkeeper = service.calculateTargetMarketValue(
        power: 84,
        age: 25,
        positionId: 1, // GK
      );
      final int centralDefender = service.calculateTargetMarketValue(
        power: 84,
        age: 25,
        positionId: 4, // CB
      );

      expect(striker, greaterThan(centralDefender));
      expect(centralDefender, greaterThanOrEqualTo(goalkeeper));
    });

    // 9. Performance bonuses remain bounded
    test('9. Performance bonuses remain bounded within [0.85, 1.15]', () {
      final double stellar = service.calculatePerformanceMultiplier(
        appearances: 38,
        avgRating: 9.2,
        goals: 40,
        assists: 20,
      );
      final double poor = service.calculatePerformanceMultiplier(
        appearances: 30,
        avgRating: 5.5,
        goals: 0,
        assists: 0,
      );

      expect(stellar, lessThanOrEqualTo(1.15));
      expect(stellar, greaterThan(1.05));
      expect(poor, greaterThanOrEqualTo(0.85));
      expect(poor, lessThan(1.0));
    });

    // 10. Small statistical samples do not create extreme valuations
    test('10. Small statistical samples do not distort valuation', () {
      final double smallSample = service.calculatePerformanceMultiplier(
        appearances: 2,
        avgRating: 10.0,
        goals: 5,
        assists: 3,
      );

      expect(smallSample, equals(1.0)); // Ignored due to sample size threshold
    });

    // 11. League and club reputation adjustments remain bounded
    test('11. League and club reputation adjustments remain strictly bounded', () {
      final double topTier = service.calculateReputationMultiplier(
        confederation: 3, // UEFA
        teamPower: 92,
      );
      final double lowTier = service.calculateReputationMultiplier(
        confederation: 1,
        teamPower: 58,
      );

      expect(topTier, lessThanOrEqualTo(1.30));
      expect(lowTier, greaterThanOrEqualTo(0.80));
    });

    // 12. Contract duration affects transfer negotiations correctly
    test('12. Contract duration affects asking price correctly', () {
      const int mv = 40000000;
      final int shortContractAsking = service.calculateAskingPrice(
        marketValue: mv,
        contractMonthsRemaining: 6,
      );
      final int longContractAsking = service.calculateAskingPrice(
        marketValue: mv,
        contractMonthsRemaining: 48,
      );

      expect(shortContractAsking, lessThan(mv));
      expect(longContractAsking, greaterThan(mv));
    });

    // 13. MV is not set to zero solely because a contract expires
    test('13. MV is non-zero even with expiring contract', () {
      final int freeAgentMv = service.calculateTargetMarketValue(
        power: 82,
        age: 26,
        positionId: 7,
        contractMonthsRemaining: 0,
      );

      expect(freeAgentMv, greaterThan(15000000));
    });

    // 14. Transfer fees do not automatically overwrite MV
    test('14. Negotiated fee is bounded and distinct from baseline MV', () {
      const int mv = 50000000;
      final int negotiatedFee = service.calculateNegotiatedFee(
        marketValue: mv,
        askingPrice: 65000000,
        initialOffer: 45000000,
        buyerLeverage: 0.5,
      );

      expect(negotiatedFee, isNot(equals(mv)));
      expect(negotiatedFee, greaterThan(45000000));
      expect(negotiatedFee, lessThan(65000000));
    });

    // 15. Loan fees do not become permanent transfer values
    test('15. Loan fees are seasonal fractions of MV', () {
      const int mv = 60000000;
      final int loanFee1Season = service.calculateLoanFee(
        marketValue: mv,
        loanSeasons: 1,
      );
      final int loanFee2Seasons = service.calculateLoanFee(
        marketValue: mv,
        loanSeasons: 2,
      );

      expect(loanFee1Season, lessThan(mv * 0.15));
      expect(loanFee1Season, greaterThan(mv * 0.04));
      expect(loanFee2Seasons, greaterThan(loanFee1Season));
    });

    // 16. Repeated valuation updates do not stack identical bonuses
    test('16. Repeated valuation calls with identical inputs yield identical outputs', () {
      final int first = service.calculateTargetMarketValue(
        power: 84,
        potential: 89,
        age: 22,
        positionId: 10,
        appearances: 25,
        avgRating: 7.8,
      );
      final int second = service.calculateTargetMarketValue(
        power: 84,
        potential: 89,
        age: 22,
        positionId: 10,
        appearances: 25,
        avgRating: 7.8,
      );

      expect(first, equals(second));
    });

    // 17. Identical inputs produce identical target valuations
    test('17. Determinism: identical inputs produce identical target valuations', () {
      for (int ovr = 50; ovr <= 95; ovr += 5) {
        final int a = service.calculateTargetMarketValue(
          power: ovr,
          age: 25,
          positionId: 8,
        );
        final int b = service.calculateTargetMarketValue(
          power: ovr,
          age: 25,
          positionId: 8,
        );
        expect(a, equals(b));
      }
    });

    // 18. Clean currency rounding avoids double scaling
    test('18. Currency numbers are cleanly rounded and within bounds', () {
      final int v1 = PlayerValuationService.roundValuationCleanly(1234567);
      final int v2 = PlayerValuationService.roundValuationCleanly(45678901);

      expect(v1 % 50000, equals(0));
      expect(v2 % 500000, equals(0));
    });

    // 19. Numeric overflow and invalid values are handled safely
    test('19. Boundary and invalid values handled safely without overflow', () {
      final int underflow = service.calculateTargetMarketValue(
        power: -10,
        age: 10,
        positionId: -1,
      );
      final int overflow = service.calculateTargetMarketValue(
        power: 150,
        age: 60,
        positionId: 99,
      );

      expect(underflow, greaterThanOrEqualTo(10000));
      expect(overflow, lessThanOrEqualTo(250000000));
    });

    // 20. Migration safely updates active players in SQLite database
    test('20. Database migration updates active player valuations safely', () async {
      sqfliteFfiInit();
      final Database db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (Database db, int version) async {
            await db.execute('''
              CREATE TABLE players (
                player_id INTEGER PRIMARY KEY,
                name TEXT,
                power INTEGER,
                potential INTEGER,
                age INTEGER,
                position_id INTEGER,
                value INTEGER,
                status_id INTEGER
              )
            ''');
            await db.execute('''
              CREATE TABLE team_players (
                team_id INTEGER,
                player_id INTEGER PRIMARY KEY
              )
            ''');
            await db.execute('''
              CREATE TABLE teams (
                team_id INTEGER PRIMARY KEY,
                country_id INTEGER,
                power INTEGER
              )
            ''');
            await db.execute('''
              CREATE TABLE countries (
                country_id INTEGER PRIMARY KEY,
                confederation INTEGER
              )
            ''');
            await db.execute('''
              CREATE TABLE player_season_stats (
                player_id INTEGER,
                matches_played INTEGER,
                rating REAL,
                goals INTEGER,
                assists INTEGER
              )
            ''');
          },
        ),
      );

      // Insert an inflated player (e.g. 1 billion valuation)
      await db.insert('players', <String, Object?>{
        'player_id': 1,
        'name': 'Inflated Star',
        'power': 85,
        'potential': 90,
        'age': 23,
        'position_id': 10,
        'value': 1000000000, // 1 Billion inflated!
        'status_id': 1,
      });

      final int updated = await service.migrateDatabase(db);
      expect(updated, equals(1));

      final List<Map<String, Object?>> rows = await db.query('players');
      final int migratedValue = rows.first['value'] as int;
      expect(migratedValue, lessThan(100000000));
      expect(migratedValue, greaterThan(25000000));
      await db.close();
    });

    // 21. Market values remain stable when player attributes do not change
    test('21. Market values remain stable when player attributes do not change', () {
      final int target = service.calculateTargetMarketValue(
        power: 80,
        age: 26,
        positionId: 7,
      );
      final int updated = service.smoothValueUpdate(
        currentValue: target,
        targetValue: target,
      );

      expect(updated, equals(target));
    });

    // 22. Ordinary players do not routinely reach hundreds of millions
    test('22. Ordinary and lower-division players stay in realistic lower brackets', () {
      final int reserve = service.calculateTargetMarketValue(
        power: 58,
        age: 22,
        positionId: 3,
      );
      final int lowerLeaguePro = service.calculateTargetMarketValue(
        power: 68,
        age: 27,
        positionId: 5,
      );
      final int midTier = service.calculateTargetMarketValue(
        power: 76,
        age: 26,
        positionId: 8,
      );

      expect(reserve, lessThan(1000000));
      expect(lowerLeaguePro, lessThan(3000000));
      expect(midTier, lessThan(20000000));
    });

    // 23. Billion-dollar valuations do not emerge from multi-season development
    test('23. Billion-dollar valuations NEVER emerge across 4 seasons of progression', () {
      int power = 90;
      int potential = 95;
      int age = 21;
      int value = service.calculateTargetMarketValue(
        power: power,
        potential: potential,
        age: age,
        positionId: 10,
      );

      // Simulate 4 seasons of maximum development (+2 OVR each season)
      for (int s = 1; s <= 4; s++) {
        age++;
        power = min(99, power + 2);
        final int target = service.calculateTargetMarketValue(
          power: power,
          potential: potential,
          age: age,
          positionId: 10,
          appearances: 38,
          avgRating: 8.5,
          goals: 30,
        );
        value = service.smoothValueUpdate(
          currentValue: value,
          targetValue: target,
        );

        // Verification after each season:
        expect(value, lessThanOrEqualTo(250000000), reason: 'Season $s value exceeded 250M: $value');
        expect(value, isNot(greaterThan(1000000000)));
      }

      // Final value after 4 seasons must be realistic world-class superstar level
      expect(value, greaterThan(100000000));
      expect(value, lessThanOrEqualTo(250000000));
    });

    // 24. Exceptional world-class players can still command premium valuations
    test('24. Exceptional world-class players command realistic elite valuations', () {
      final int mbappeHaalandPrime = service.calculateTargetMarketValue(
        power: 94,
        potential: 96,
        age: 25,
        positionId: 10,
        confederation: 3,
        teamPower: 92,
        appearances: 38,
        avgRating: 8.8,
        goals: 42,
      );

      // Global superstar prime valuation: €150M - €250M
      expect(mbappeHaalandPrime, greaterThanOrEqualTo(150000000));
      expect(mbappeHaalandPrime, lessThanOrEqualTo(250000000));
    });
  });
}
