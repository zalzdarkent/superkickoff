import 'dart:math' as math;

/// Competition classifications used by the prize engine. They are derived from
/// database metadata (organization, slots, division) so no per-tournament
/// configuration is required.
enum CompetitionKind {
  league,
  domesticCup,
  continental,
  intercontinental,
  superCup,
}

/// Inputs the engine needs to scale a competition's prize money.
class CompetitionProfile {
  const CompetitionProfile({
    required this.kind,
    this.tier = 1,
    this.entrants = 16,
    this.countryPower = 60,
    this.confederation = 0,
    this.slots = 1,
    this.legacyPrizeTeams = 0,
  });

  final CompetitionKind kind;

  /// 1 = top tier. Deeper divisions of the same country are worth less.
  final int tier;
  final int entrants;
  final int countryPower;
  final int confederation;

  /// League coefficient stored in tournaments.points (used as quality metric).
  final int slots;

  /// Legacy prize_teams column, used as a tuning hint when present.
  final int legacyPrizeTeams;
}

/// One club's payout for a completed competition.
class PrizeAward {
  const PrizeAward({
    required this.teamId,
    required this.amount,
    required this.reason,
  });

  final int teamId;
  final int amount;
  final String reason;
}

/// Result of evaluating a whole competition.
class CompetitionPrizeResult {
  const CompetitionPrizeResult({
    required this.tournamentId,
    required this.kind,
    required this.prizePool,
    required this.awards,
  });

  final int tournamentId;
  final CompetitionKind kind;
  final int prizePool;
  final List<PrizeAward> awards;

  int get totalDistributed => awards.fold<int>(
    0,
    (int sum, PrizeAward a) => sum + a.amount,
  );
}

/// Scales prize money by country strength and confederation wealth.
class EconomyScale {
  const EconomyScale._();

  /// National economy multiplier: 0.35 (power 0) up to ~2.1 (power 100).
  static double national(int countryPower) {
    final int power = countryPower.clamp(0, 100);
    return 0.35 + power * 0.0175;
  }

  /// Confederation wealth multiplier keyed by countries.confederation.
  static double confederation(int confederation) {
    return switch (confederation) {
      1 => 0.85, // North/Central America & Caribbean
      2 => 0.95, // Africa
      3 => 1.15, // Europe
      4 => 0.90, // South America
      5 => 0.85, // Asia
      6 => 0.80, // Oceania
      _ => 1.0,
    };
  }

  /// Tier multiplier: every division below the top is worth less.
  static double tier(int tier) {
    final int step = (tier - 1).clamp(0, 5);
    return 1 / (1 + step * 0.35);
  }
}

/// Distribution rule shared by every competition of a kind.
class PrizeRule {
  const PrizeRule({
    required this.basePool,
    this.participationPerClub = 0,
    this.winBonus = 0,
    this.drawBonus = 0,
    this.positionWeights = const <int>[],
    this.qualificationRounds = const <int, double>{},
    this.championBonus = 0,
    this.runnerUpBonus = 0,
  });

  /// Prize pool for an 8-club, top-tier competition at national power 50.
  final int basePool;
  final int participationPerClub;
  final int winBonus;
  final int drawBonus;

  /// Descending weights used for final table positions (index 0 = 1st).
  final List<int> positionWeights;

  /// Bonus for reaching a knockout round of a given total depth.
  final Map<int, double> qualificationRounds;
  final int championBonus;
  final int runnerUpBonus;
}

/// Generates prize distributions for every competition format in the game.
///
/// The engine is configuration-driven: defaults exist per
/// [CompetitionKind] and scale with entrants, country power, confederation and
/// tier. A [configOverrides] map can pin a specific competition to custom
/// values without touching the algorithm.
class PrizeEngine {
  const PrizeEngine({
    this.configOverrides = const <int, PrizeRule>{},
  });

  /// Optional per-tournament overrides keyed by tournament id.
  final Map<int, PrizeRule> configOverrides;

  /// Default rules. Amounts are in game currency (same scale as club budgets).
  /// Tuned generous so mid-table clubs can afford real transfers each summer.
  static const Map<CompetitionKind, PrizeRule> defaultRules =
      <CompetitionKind, PrizeRule>{
        // League: rewards final table position, weighted to the top.
        CompetitionKind.league: PrizeRule(
          basePool: 15000000,
          positionWeights: <int>[
            40, 30, 24, 20, 17, 15, 13, 11, 10, 9, //
            8, 7, 6, 5, 4, 3, 2, 2, 2, 1,
          ],
        ),
        // Domestic cup: participation plus round-by-round progression.
        CompetitionKind.domesticCup: PrizeRule(
          basePool: 20000000,
          participationPerClub: 150000,
          qualificationRounds: <int, double>{
            1: 0.06,
            2: 0.09,
            3: 0.13,
            4: 0.20,
            5: 0.30,
          },
          runnerUpBonus: 1250000,
          championBonus: 2500000,
        ),
        // Continental: groups + knockout rounds.
        CompetitionKind.continental: PrizeRule(
          basePool: 55000000,
          participationPerClub: 1000000,
          winBonus: 625000,
          drawBonus: 225000,
          qualificationRounds: <int, double>{
            1: 0.08,
            2: 0.12,
            3: 0.17,
            4: 0.24,
            5: 0.34,
          },
          runnerUpBonus: 5000000,
          championBonus: 10000000,
        ),
        // Intercontinental: broad global participation, top-heavy.
        CompetitionKind.intercontinental: PrizeRule(
          basePool: 100000000,
          participationPerClub: 1500000,
          winBonus: 1000000,
          drawBonus: 375000,
          qualificationRounds: <int, double>{
            1: 0.10,
            2: 0.16,
            3: 0.22,
            4: 0.30,
            5: 0.40,
          },
          runnerUpBonus: 7500000,
          championBonus: 15000000,
        ),
        // Super cup: two clubs, winner takes most.
        CompetitionKind.superCup: PrizeRule(
          basePool: 7500000,
          participationPerClub: 625000,
          runnerUpBonus: 500000,
          championBonus: 3750000,
        ),
      };

  /// Classifies a competition from its database metadata.
  static CompetitionKind kindOf({
    required int organization,
    required int entrants,
    required int nameHintSlots,
  }) {
    if (organization == 1) return CompetitionKind.league;
    if (organization == 3) return CompetitionKind.domesticCup;
    // organization == 2: continental, intercontinental or super cup.
    if (entrants <= 2) return CompetitionKind.superCup;
    // 32+ clubs is a global-scale competition; smaller fields are continental.
    if (entrants > 32 || (nameHintSlots >= 32 && entrants >= 24)) {
      return CompetitionKind.intercontinental;
    }
    return CompetitionKind.continental;
  }

  /// Prize pool for a competition (always scaled, never negative).
  int prizePool(CompetitionProfile profile, PrizeRule rule) {
    final double entrantsFactor =
        0.75 + math.log(math.max(profile.entrants, 2)) / 4;
    final double scale =
        EconomyScale.national(profile.countryPower) *
        EconomyScale.confederation(profile.confederation) *
        EconomyScale.tier(profile.tier) *
        entrantsFactor;
    final int leagueHint = profile.legacyPrizeTeams > 0
        ? profile.legacyPrizeTeams
        : 0;
    final int scaledBase = (rule.basePool * scale).round();
    final int pool = leagueHint > 0
        ? math.max(scaledBase, (scaledBase + leagueHint) ~/ 2)
        : scaledBase;
    return math.max(pool, 100000);
  }

  PrizeRule ruleFor(int tournamentId, CompetitionKind kind) =>
      configOverrides[tournamentId] ?? defaultRules[kind]!;

  /// League: distribution by final ranking.
  CompetitionPrizeResult leaguePrizes({
    required int tournamentId,
    required CompetitionProfile profile,
    required List<int> rankedTeamIds,
  }) {
    final PrizeRule rule = ruleFor(tournamentId, CompetitionKind.league);
    final int pool = prizePool(profile, rule);
    final int totalWeight = rankedTeamIds.length >= rule.positionWeights.length
        ? rule.positionWeights.fold<int>(0, (int s, int w) => s + w)
        : <int>[
            ...rule.positionWeights.take(rankedTeamIds.length),
          ].fold<int>(0, (int s, int w) => s + w);
    final int safeWeight = math.max(totalWeight, 1);
    final List<PrizeAward> awards = <PrizeAward>[];
    for (int i = 0; i < rankedTeamIds.length; i++) {
      final int weight = i < rule.positionWeights.length
          ? rule.positionWeights[i]
          : 1;
      final int amount = (pool * weight / safeWeight).round();
      awards.add(
        PrizeAward(
          teamId: rankedTeamIds[i],
          amount: amount,
          reason: 'League position ${i + 1}',
        ),
      );
    }
    return CompetitionPrizeResult(
      tournamentId: tournamentId,
      kind: CompetitionKind.league,
      prizePool: pool,
      awards: awards,
    );
  }

  /// Knockout cup: participation + round progression + winner bonus.
  CompetitionPrizeResult cupPrizes({
    required int tournamentId,
    required CompetitionKind kind,
    required CompetitionProfile profile,
    required Map<int, int> reachedRoundByTeam,
    required int maxRound,
    int? winnerTeamId,
    int? runnerUpTeamId,
    Map<int, int>? winsByTeam,
    Map<int, int>? drawsByTeam,
  }) {
    final PrizeRule rule = ruleFor(tournamentId, kind);
    final int pool = prizePool(profile, rule);
    final List<PrizeAward> awards = <PrizeAward>[];

    for (final MapEntry<int, int> entry in reachedRoundByTeam.entries) {
      int amount = rule.participationPerClub;
      final double? roundWeight = rule.qualificationRounds[entry.value];
      if (roundWeight != null) {
        amount += (pool * roundWeight).round();
      }
      if (entry.key == winnerTeamId) {
        amount += rule.championBonus;
      } else if (entry.key == runnerUpTeamId) {
        amount += rule.runnerUpBonus;
      }
      if (amount > 0) {
        awards.add(
          PrizeAward(
            teamId: entry.key,
            amount: amount,
            reason: 'Reached round ${entry.value}',
          ),
        );
      }
    }

    // Continental / intercontinental match bonuses.
    if (rule.winBonus > 0 && winsByTeam != null) {
      for (final MapEntry<int, int> entry in winsByTeam.entries) {
        final int amount = (rule.winBonus * entry.value);
        if (amount <= 0) continue;
        _addTo(awards, entry.key, amount, '${entry.value} wins');
      }
    }
    if (rule.drawBonus > 0 && drawsByTeam != null) {
      for (final MapEntry<int, int> entry in drawsByTeam.entries) {
        final int amount = (rule.drawBonus * entry.value);
        if (amount <= 0) continue;
        _addTo(awards, entry.key, amount, '${entry.value} draws');
      }
    }

    return CompetitionPrizeResult(
      tournamentId: tournamentId,
      kind: kind,
      prizePool: pool,
      awards: awards,
    );
  }

  void _addTo(List<PrizeAward> awards, int teamId, int amount, String reason) {
    final int index = awards.indexWhere((PrizeAward a) => a.teamId == teamId);
    if (index == -1) {
      awards.add(PrizeAward(teamId: teamId, amount: amount, reason: reason));
      return;
    }
    final PrizeAward existing = awards[index];
    awards[index] = PrizeAward(
      teamId: teamId,
      amount: existing.amount + amount,
      reason: '${existing.reason}; $reason',
    );
  }
}
