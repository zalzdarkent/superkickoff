import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../data/db/schema.dart' as t;

/// Configurable parameters for the Player Market Value (MV) system.
class PlayerValuationConfig {
  const PlayerValuationConfig({
    this.minValuation = 15000,
    this.maxValuation = 250000000,
    this.routineMaxGrowthRate = 0.15,
  });

  /// Hard safety boundaries for internal sanity.
  final int minValuation;
  final int maxValuation;

  /// Maximum percentage change per routine valuation adjustment (e.g. 15%).
  final double routineMaxGrowthRate;

  /// Anchor points for cubic spline / piecewise nonlinear interpolation of OVR base value (in EUR).
  static const List<(int, int)> ovrAnchors = <(int, int)>[
    (40, 20000),
    (45, 50000),
    (50, 100000),
    (55, 250000),
    (60, 500000),
    (65, 1200000),
    (70, 3200000),
    (73, 5500000),
    (76, 10000000),
    (79, 18000000),
    (82, 30000000),
    (84, 42000000),
    (86, 60000000),
    (88, 85000000),
    (90, 115000000),
    (92, 145000000),
    (94, 180000000),
    (96, 210000000),
    (99, 240000000),
  ];
}

/// Centralized, deterministic service for player market valuations, asking prices,
/// and transfer negotiation economics.
class PlayerValuationService {
  const PlayerValuationService({
    this.config = const PlayerValuationConfig(),
  });

  final PlayerValuationConfig config;

  /// Calculates the canonical base value derived nonlinearly from Overall Rating (OVR).
  double calculateBaseValue(int ovr) {
    final int clampedOvr = ovr.clamp(40, 99);
    final List<(int, int)> anchors = PlayerValuationConfig.ovrAnchors;

    for (int i = 0; i < anchors.length - 1; i++) {
      final (int x0, int y0) = anchors[i];
      final (int x1, int y1) = anchors[i + 1];
      if (clampedOvr >= x0 && clampedOvr <= x1) {
        final double t = (clampedOvr - x0) / (x1 - x0);
        // Smooth Hermite cubic interpolation: 3t^2 - 2t^3
        final double smoothT = t * t * (3 - 2 * t);
        return y0 + smoothT * (y1 - y0);
      }
    }
    return anchors.last.$2.toDouble();
  }

  /// Age multiplier curve recognizing speculative youth premium, prime years, and late-career resale discounts.
  double calculateAgeMultiplier(int age) {
    if (age <= 17) return 0.85; // High potential will boost this
    if (age <= 20) return 1.15; // Breakout youth premium
    if (age <= 24) return 1.25; // High resale peak growth window
    if (age <= 28) return 1.05; // Peak prime athletic years
    if (age <= 30) return 0.90; // Experienced prime, mild resale discount
    if (age <= 32) return 0.72; // Veteran resale decline
    if (age <= 34) return 0.50; // Older veteran discount
    if (age <= 36) return 0.35; // Late career discount
    return 0.25; // Elite longevity preservation (e.g. 37+)
  }

  /// Bounded potential multiplier that rewards young players with high ceilings,
  /// but diminishes naturally as players age towards peak ability.
  double calculatePotentialMultiplier({
    required int age,
    required int power,
    required int potential,
  }) {
    if (age >= 25 || potential <= power) return 1.0;
    final int gap = potential - power;
    // Age weight: 1.0 at age 16, decreasing linearly to ~0.11 at age 24
    final double ageWeight = max(0.0, (25 - age) / 9.0);
    // Bounded: maximum +35% potential premium
    final double premium = min(0.35, gap * 0.025 * ageWeight);
    return 1.0 + premium;
  }

  /// Position market demand factor.
  double calculatePositionMultiplier(int positionId) {
    switch (positionId) {
      case 1: // GK
        return 0.88;
      case 2: // CB
      case 3: // Sweeper CB
        return 0.93;
      case 4: // FB / Wing-back
        return 0.94;
      case 5: // Defensive Midfielder
        return 0.96;
      case 6: // Attacking Midfielder
        return 1.03;
      case 7: // Central Midfielder
      case 8: // Wide Midfielder
        return 1.00;
      case 9: // Winger
        return 1.05;
      case 10: // Striker
        return 1.08;
      case 11: // Second Striker
        return 1.06;
      default:
        return 1.00;
    }
  }

  /// Competition and club reputation visibility factor, strictly bounded [0.75, 1.25].
  double calculateReputationMultiplier({
    int confederation = 3,
    int teamPower = 75,
  }) {
    // Confederation strength: 3=UEFA (1.10), 1=CONCACAF/2=CONMEBOL (1.02), others (0.88)
    final double confMult = confederation == 3
        ? 1.10
        : (confederation == 1 || confederation == 2 ? 1.02 : 0.88);
    // Team power baseline 50-90 normalized to [0.85, 1.15]
    final double teamMult =
        0.85 + (teamPower.clamp(50, 90) - 50) / 40.0 * 0.30;
    return (confMult * teamMult).clamp(0.75, 1.25);
  }

  /// Performance modifier based on recent seasonal performance.
  /// Bounded strictly between 0.85 and 1.15, with sample size safeguard.
  double calculatePerformanceMultiplier({
    required int appearances,
    double? avgRating,
    int goals = 0,
    int assists = 0,
    int cleanSheets = 0,
    int positionId = 7,
  }) {
    // Sample size safeguard: require at least 5 appearances to apply performance modifiers
    if (appearances < 5 || avgRating == null || avgRating <= 0.0) {
      return 1.0;
    }

    // Rating impact: 6.8 is neutral baseline
    final double ratingDelta = (avgRating - 6.8).clamp(-1.0, 1.2);
    double modifier = 1.0 + (ratingDelta * 0.08); // e.g. 7.8 rating gives +8%

    // Position-specific goal/assist or clean-sheet contribution
    if (positionId >= 6 && positionId <= 11) {
      // Attackers / midfielders: goal/assist rate
      final double g90 = (goals + assists) / appearances.toDouble();
      if (g90 >= 0.5) modifier += 0.04;
      if (g90 >= 0.8) modifier += 0.03;
    } else if (positionId <= 3) {
      // GK & CB: clean sheets rate
      final double csRatio = cleanSheets / appearances.toDouble();
      if (csRatio >= 0.40) modifier += 0.04;
    }

    return modifier.clamp(0.85, 1.15);
  }

  /// Contract duration factor for Market Value.
  /// (Note: contract length influences Asking Price and Transfer Negotiations far more).
  double calculateContractMultiplier(int monthsRemaining) {
    if (monthsRemaining <= 6) return 0.90; // Minor markdown on baseline MV
    if (monthsRemaining <= 12) return 0.95;
    if (monthsRemaining <= 48) return 1.00;
    return 1.03; // Long term stability premium
  }

  /// Computes the uncompounded, canonical Target Market Value for a player.
  int calculateTargetMarketValue({
    required int power,
    int? potential,
    required int age,
    required int positionId,
    int confederation = 3,
    int teamPower = 75,
    int appearances = 0,
    double? avgRating,
    int goals = 0,
    int assists = 0,
    int cleanSheets = 0,
    int contractMonthsRemaining = 24,
  }) {
    final int effPotential = potential ?? power;
    final double base = calculateBaseValue(power);
    final double ageMult = calculateAgeMultiplier(age);
    final double potMult = calculatePotentialMultiplier(
      age: age,
      power: power,
      potential: effPotential,
    );
    final double posMult = calculatePositionMultiplier(positionId);
    final double repMult = calculateReputationMultiplier(
      confederation: confederation,
      teamPower: teamPower,
    );
    final double perfMult = calculatePerformanceMultiplier(
      appearances: appearances,
      avgRating: avgRating,
      goals: goals,
      assists: assists,
      cleanSheets: cleanSheets,
      positionId: positionId,
    );
    final double contractMult =
        calculateContractMultiplier(contractMonthsRemaining);

    final double rawVal = base *
        ageMult *
        potMult *
        posMult *
        repMult *
        perfMult *
        contractMult;

    final int clamped = rawVal
        .round()
        .clamp(config.minValuation, config.maxValuation);

    return roundValuationCleanly(clamped);
  }

  /// Smooths the transition of a player's persisted market value towards target value.
  /// Used during in-season updates to prevent sudden jarring value jumps or runaway spikes.
  int smoothValueUpdate({
    required int currentValue,
    required int targetValue,
    double? maxPercentageStep,
  }) {
    if (currentValue <= 0) return targetValue;
    final double maxStep = maxPercentageStep ?? config.routineMaxGrowthRate;

    final int diff = targetValue - currentValue;
    final int maxAllowedStep = (currentValue * maxStep).round();

    if (diff.abs() <= maxAllowedStep) {
      return targetValue;
    }

    if (diff > 0) {
      return roundValuationCleanly(currentValue + maxAllowedStep);
    } else {
      return roundValuationCleanly(
        max(config.minValuation, currentValue - maxAllowedStep),
      );
    }
  }

  /// Calculates the Asking Price demanded by the selling club for a player.
  /// Disentangles Asking Price from baseline Market Value.
  int calculateAskingPrice({
    required int marketValue,
    required int contractMonthsRemaining,
    bool isTransferListed = false,
    bool isUntouchable = false,
    double clubFinancialMultiplier = 1.0,
  }) {
    double markup = 1.0;

    // Contract remaining heavily influences seller leverage:
    if (contractMonthsRemaining <= 6) {
      markup *= 0.65; // Desperate to avoid losing on free transfer
    } else if (contractMonthsRemaining <= 12) {
      markup *= 0.85; // Final year discount
    } else if (contractMonthsRemaining >= 36) {
      markup *= 1.20; // Long contract seller premium
    }

    if (isTransferListed) {
      markup *= 0.85; // Surplus to requirements discount
    } else if (isUntouchable) {
      markup *= 1.35; // Crucial key player premium
    }

    // Financially pressured clubs might sell for less; rich clubs hold out
    markup *= clubFinancialMultiplier.clamp(0.80, 1.25);

    // Bounded asking price: minimum 55% of MV, maximum 180% of MV
    final int asking = (marketValue * markup.clamp(0.55, 1.80)).round();
    return roundValuationCleanly(asking);
  }

  /// Calculates a realistic negotiated transfer fee between buyer offer and seller asking price.
  int calculateNegotiatedFee({
    required int marketValue,
    required int askingPrice,
    required int initialOffer,
    double buyerLeverage = 0.5,
  }) {
    final double clampedLeverage = buyerLeverage.clamp(0.0, 1.0);
    // Compromise point between initial offer and asking price
    final double compromise =
        initialOffer * (1.0 - clampedLeverage) + askingPrice * clampedLeverage;
    // Bounded realistic window: between 70% and 150% of Market Value
    final int fee = compromise.round().clamp(
      (marketValue * 0.70).round(),
      (marketValue * 1.50).round(),
    );
    return roundValuationCleanly(fee);
  }

  /// Calculates a temporary loan fee (e.g. 6% to 12% of MV per season).
  int calculateLoanFee({
    required int marketValue,
    int loanSeasons = 1,
    double loanRate = 0.08,
  }) {
    final int fee = (marketValue * loanRate * loanSeasons).round();
    return roundValuationCleanly(max(10000, fee));
  }

  /// Formats clean rounded numbers for display and storage (e.g. nearest 5k, 10k, 100k, 500k).
  static int roundValuationCleanly(int val) {
    if (val >= 10000000) {
      return (val / 500000).round() * 500000;
    } else if (val >= 1000000) {
      return (val / 100000).round() * 100000;
    } else if (val >= 100000) {
      return (val / 10000).round() * 10000;
    } else {
      return (val / 5000).round() * 5000;
    }
  }

  /// Recalibrates all active players in a SQLite database to realistic market values.
  /// Preserves all IDs, players, contracts, transfers, and match histories.
  Future<int> migrateDatabase(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT p.player_id, p.power, p.potential, p.age, p.position_id, p.value,
             COALESCE(c.confederation, 3) AS confederation,
             COALESCE(tm.power, 70) AS team_power,
             COALESCE(pss.matches_played, 0) AS matches_played,
             COALESCE(pss.rating, 0.0) AS rating,
             COALESCE(pss.goals, 0) AS goals,
             COALESCE(pss.assists, 0) AS assists
      FROM ${t.players} p
      LEFT JOIN ${t.teamPlayers} tp ON tp.player_id = p.player_id
      LEFT JOIN ${t.teams} tm ON tm.team_id = tp.team_id
      LEFT JOIN ${t.countries} c ON c.country_id = tm.country_id
      LEFT JOIN (
        SELECT player_id,
               SUM(matches_played) AS matches_played,
               AVG(CASE WHEN matches_played > 0 THEN rating END) AS rating,
               SUM(goals) AS goals,
               SUM(assists) AS assists
        FROM ${t.playerSeasonStats}
        GROUP BY player_id
      ) pss ON pss.player_id = p.player_id
      WHERE p.status_id = ${t.statusActive}
    ''');

    final Batch batch = db.batch();
    int updatedCount = 0;

    for (final Map<String, Object?> r in rows) {
      final int pid = r['player_id'] as int;
      final int power = (r['power'] as int?) ?? 50;
      final int potential = (r['potential'] as int?) ?? power;
      final int age = (r['age'] as int?) ?? 24;
      final int posId = (r['position_id'] as int?) ?? 7;
      final int conf = (r['confederation'] as int?) ?? 3;
      final int teamPwr = (r['team_power'] as int?) ?? 70;
      final int apps = (r['matches_played'] as int?) ?? 0;
      final double? avgRating = (r['rating'] as num?)?.toDouble();
      final int goals = (r['goals'] as int?) ?? 0;
      final int assists = (r['assists'] as int?) ?? 0;

      final int targetVal = calculateTargetMarketValue(
        power: power,
        potential: potential,
        age: age,
        positionId: posId,
        confederation: conf,
        teamPower: teamPwr,
        appearances: apps,
        avgRating: avgRating,
        goals: goals,
        assists: assists,
      );

      batch.rawUpdate(
        'UPDATE ${t.players} SET value = ? WHERE player_id = ?',
        <Object?>[targetVal, pid],
      );
      updatedCount++;
    }

    await batch.commit(noResult: true);
    return updatedCount;
  }
}
