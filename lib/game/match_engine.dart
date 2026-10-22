import 'dart:math';

import '../data/models/models.dart';
import 'formation.dart';

/// Formation line-up selection for the match engine.
///
/// Given a squad (active players, fitness above the floor, not suspended),
/// picks the best XI for a 4-4-2 with affinity bonuses for natural position
/// groups, plus a bench of substitutes.
///
/// Position types: 1 GK, 2 DEF, 3 MID, 4 ATT.
class Lineup {
  Lineup._(this.starters, this.substitutes, this.unavailableIds);

  final List<Player> starters;
  final List<Player> substitutes;
  final Set<int> unavailableIds;

  static const int needGK = 1;

  static int groupOf(Player p) {
    if (p.positionId == 1) return 1;
    if (p.positionId <= 4) return 2;
    if (p.positionId <= 8) return 3;
    return 4;
  }

  static double effective(Player p) =>
      p.power * (0.70 + 0.30 * (p.fitness.clamp(0, 100) / 100.0));

  /// Builds the best available XI for [formation] plus a substitution bench.
  static Lineup best(
    List<Player> squad, {
    Formation formation = Formation.f442,
    int fitnessFloor = 35,
    Set<int> bannedIds = const <int>{},
    List<int> preferredIds = const <int>[],
  }) {
    final Set<int> unavailable = <int>{};
    final List<Player> eligible = <Player>[];
    for (final Player p in squad) {
      if (p.statusId != 1) continue;
      final bool injured = p.fitness < fitnessFloor && p.positionId != 1;
      final bool banned = bannedIds.contains(p.playerId);
      if (injured || banned) {
        unavailable.add(p.playerId);
        continue;
      }
      eligible.add(p);
    }
    final List<Player> sorted = List<Player>.of(eligible)
      ..sort((Player a, Player b) => effective(b).compareTo(effective(a)));

    if (preferredIds.isNotEmpty) {
      return _withPreferred(
        preferredIds: preferredIds,
        eligible: eligible,
        sorted: sorted,
        formation: formation,
        unavailable: unavailable,
      );
    }

    final Map<int, int> need = <int, int>{
      1: needGK,
      2: formation.defenders,
      3: formation.midfielders,
      4: formation.forwards,
    };
    final Map<int, List<Player>> chosen = <int, List<Player>>{
      1: <Player>[],
      2: <Player>[],
      3: <Player>[],
      4: <Player>[],
    };
    final List<Player> unassigned = <Player>[];

    // First pass: each player fills his own group while slots remain.
    for (final Player p in sorted) {
      final int g = groupOf(p);
      if (chosen[g]!.length < need[g]!) {
        chosen[g]!.add(p);
      } else {
        unassigned.add(p);
      }
    }

    // Cross-fill deficits with role changes (GK cannot play outfield).
    const Map<int, List<int>> adjacency = <int, List<int>>{
      1: <int>[],
      2: <int>[3, 4],
      3: <int>[2, 4],
      4: <int>[3],
    };
    for (int g = 1; g <= 4; g++) {
      while (chosen[g]!.length < need[g]!) {
        Player? best;
        int bestDistance = 99;
        for (final Player p in unassigned) {
          final int pg = groupOf(p);
          if (!adjacency[g]!.contains(pg)) continue;
          final int distance = (pg - g).abs();
          if (distance < bestDistance) {
            best = p;
            bestDistance = distance;
          }
        }
        if (best == null) break;
        chosen[g]!.add(best);
        unassigned.remove(best);
      }
    }

    final List<Player> bench = unassigned.take(7).toList();
    final List<Player> starters = <Player>[
      ...chosen[1]!,
      ...chosen[2]!,
      ...chosen[3]!,
      ...chosen[4]!,
    ];
    return Lineup._(starters, bench, unavailable);
  }

  /// Starts the players the manager dragged into the XI, then fills any
  /// remaining slot from the best available squad members.
  static Lineup _withPreferred({
    required List<int> preferredIds,
    required List<Player> eligible,
    required List<Player> sorted,
    required Formation formation,
    required Set<int> unavailable,
  }) {
    final Map<int, Player> byId = <int, Player>{
      for (final Player p in eligible) p.playerId: p,
    };
    final Set<int> used = <int>{};
    final List<Player> starters = <Player>[];
    for (final int id in preferredIds) {
      if (starters.length >= 11) break;
      final Player? p = byId[id];
      if (p == null || used.contains(id)) continue;
      starters.add(p);
      used.add(id);
    }

    final Map<int, int> need = <int, int>{
      1: needGK,
      2: formation.defenders,
      3: formation.midfielders,
      4: formation.forwards,
    };
    int count(int group) =>
        starters.where((Player p) => groupOf(p) == group).length;
    final List<Player> remaining = sorted
        .where((Player p) => !used.contains(p.playerId))
        .toList();

    Player? take(int group) {
      for (int i = 0; i < remaining.length; i++) {
        if (groupOf(remaining[i]) == group) {
          final Player p = remaining.removeAt(i);
          used.add(p.playerId);
          return p;
        }
      }
      return null;
    }

    // A saved XI may be missing a keeper after transfers; always field one.
    if (count(1) == 0) {
      final Player? gk = take(1);
      if (gk != null) {
        if (starters.length >= 11) starters.removeLast();
        starters.add(gk);
      }
    }

    for (int g = 1; g <= 4; g++) {
      while (starters.length < 11 && count(g) < need[g]!) {
        final Player? p = take(g);
        if (p == null) break;
        starters.add(p);
      }
    }

    const Map<int, List<int>> adjacency = <int, List<int>>{
      1: <int>[],
      2: <int>[3, 4],
      3: <int>[2, 4],
      4: <int>[3],
    };
    if (starters.length < 11) {
      for (int g = 1; g <= 4; g++) {
        while (starters.length < 11 && count(g) < need[g]!) {
          Player? p;
          for (final int from in adjacency[g]!) {
            p = take(from);
            if (p != null) break;
          }
          if (p == null) break;
          starters.add(p);
        }
      }
    }
    while (starters.length < 11 && remaining.isNotEmpty) {
      starters.add(remaining.removeAt(0));
    }

    return Lineup._(starters, remaining.take(7).toList(), unavailable);
  }

  // ----- team strength metrics ------------------------------------------------

  /// Attacking strength (heavily forwards, some midfield).
  static double attackOn(List<Player> starters) =>
      6.0 * _lineMean(starters, 4) +
      2.4 * _lineMean(starters, 3) +
      _lineMean(starters, 2);

  /// Midfield control (pure midfield line).
  static double midfieldOn(List<Player> starters) =>
      6.0 * _lineMean(starters, 3) +
      _lineMean(starters, 4) +
      _lineMean(starters, 2);

  /// Defensive solidity (defense + a bit of the keeper).
  static double defenseOn(List<Player> starters) =>
      6.0 * _lineMean(starters, 2) +
      2.4 * _lineMean(starters, 3) +
      2.0 * _lineMean(starters, 1);

  static double _lineMean(List<Player> starters, int group) {
    double sum = 0;
    int count = 0;
    for (final Player p in starters) {
      if (groupOf(p) == group) {
        sum += p.power;
        count++;
      }
    }
    return count == 0 ? 50 : sum / count;
  }
}

/// A single match event (goal, card, save, VAR, injury, substitution...).
class MatchEvent {
  MatchEvent({
    required this.minute,
    required this.type,
    required this.side, // 'home' | 'away'
    this.playerId,
    this.playerName,
    this.detail,
  });

  final int minute;
  final String type;
  final String side;
  final int? playerId;
  final String? playerName;
  final String? detail;

  Map<String, Object?> toMap() => <String, Object?>{
    'minute': minute,
    'type': type,
    'side': side,
    'player_id': playerId,
    'player_name': playerName,
    'detail': detail,
  };

  static MatchEvent fromMap(Map<String, Object?> m) => MatchEvent(
    minute: (m['minute'] as int?) ?? 0,
    type: m['type'] as String,
    side: m['side'] as String? ?? 'home',
    playerId: m['player_id'] as int?,
    playerName: m['player_name'] as String?,
    detail: m['detail'] as String?,
  );

  bool get isHome => side == 'home';

  static const String goal = 'goal';
  static const String assist = 'assist';
  static const String save = 'save';
  static const String yellow = 'yellow_card';
  static const String red = 'red_card';
  static const String penaltyScored = 'penalty_scored';
  static const String penaltyMissed = 'penalty_missed';
  static const String ownGoal = 'own_goal';
  static const String injury = 'injury';
  static const String subIn = 'substitution_in';
  static const String subOut = 'substitution_out';
  static const String varCheck = 'var_check';
  static const String varGoalDisallowed = 'var_goal_disallowed';

  /// Shootout kick, `detail` holds `scored` or `missed`.
  static const String shootout = 'shootout_kick';
}

/// Per-player row persisted into match_players.
class MatchPlayerRow {
  MatchPlayerRow({
    required this.playerId,
    required this.playerName,
    required this.teamId,
    required this.starter,
    required this.minutes,
    required this.goals,
    required this.assists,
    required this.yellowCards,
    required this.redCards,
    required this.mvp,
    required this.rating, // stored *10 (20..100)
    required this.points,
  });

  final int playerId;
  final String playerName;
  final int teamId;
  int starter;
  int minutes;
  int goals;
  int assists;
  int yellowCards;
  int redCards;
  int mvp;
  int rating;
  int points;
}

/// Input for simulating one match: squads + venue + meta.
class MatchInput {
  MatchInput({
    required this.homeSquad,
    required this.awaySquad,
    required this.capacityGeneral,
    required this.capacityStand,
    required this.capacityTerrace,
    required this.capacityBoxes,
    required this.homePower,
    this.homeFormation = Formation.f442,
    this.awayFormation = Formation.f442,
    this.homeTeamId = 0,
    this.awayTeamId = 0,
    this.homeLineupIds = const <int>[],
    this.awayLineupIds = const <int>[],
    this.refereeTemper = 2,
  });

  final List<Player> homeSquad;
  final List<Player> awaySquad;
  final int homeTeamId;
  final int awayTeamId;
  final int capacityGeneral;
  final int capacityStand;
  final int capacityTerrace;
  final int capacityBoxes;
  final int homePower;
  final Formation homeFormation;
  final Formation awayFormation;
  final List<int> homeLineupIds;
  final List<int> awayLineupIds;
  final int refereeTemper; // 1 lenient ... 5 grumpy
}

/// Result produced by [MatchEngine.simulate].
class MatchResult {
  MatchResult({
    required this.homeGoals,
    required this.awayGoals,
    required this.events,
    required this.playerRows,
    required this.attendanceGeneral,
    required this.attendanceStand,
    required this.attendanceTerrace,
    required this.attendanceBoxes,
    required this.revenue,
    required this.homeShots,
    required this.awayShots,
    required this.homeShotsOnTarget,
    required this.awayShotsOnTarget,
    required this.homeSaves,
    required this.awaySaves,
    required this.homePossession,
    required this.input,
  });

  final int homeGoals;
  final int awayGoals;
  final MatchInput input;
  final List<MatchEvent> events;
  final List<MatchPlayerRow> playerRows;
  final int attendanceGeneral;
  final int attendanceStand;
  final int attendanceTerrace;
  final int attendanceBoxes;
  final int revenue;

  // Match statistics (for the post-match report).
  final int homeShots;
  final int awayShots;
  final int homeShotsOnTarget;
  final int awayShotsOnTarget;
  final int homeSaves;
  final int awaySaves;
  final int homePossession;
}

/// Outcome of a knockout penalty shootout.
class MatchPenaltyShootout {
  const MatchPenaltyShootout({
    required this.homeScore,
    required this.awayScore,
    required this.events,
  });

  final int homeScore;
  final int awayScore;
  final List<MatchEvent> events;
}

/// The match engine: pure Dart, no DB or UI dependency so it runs inside
/// quick sims and the live viewer alike.
class MatchEngine {
  MatchEngine({Random? random}) : _rng = random ?? Random();

  final Random _rng;

  // Tunables
  //
  // Chances are modelled as shots. A strong attack creates many more shots
  // against a weak defence, and the quality of those shots also rises, so a
  // dominant side can realistically win 4-0 instead of being capped at 1-0.
  static const double _baseChancePerMinute = 0.090;
  static const double _conversionBase = 0.130;
  static const double _onTargetShare = 0.35;
  static const double _penaltyPool = 0.060; // expected penalties / match
  static const double _penaltyConvert = 0.76;
  static const double _ownGoalPool = 0.020;
  static const double _yellowPool = 3.6;
  static const double _redPool = 0.12;
  static const double _injuryPool = 0.40;
  static const double _attackerInjuryBias = 0.30;
  static const List<int> _tierPrices = <int>[14, 38, 21, 120];

  MatchResult simulate(
    MatchInput input, {
    bool recordEvents = true,
    Set<int> bannedIds = const <int>{},
  }) {
    final Lineup homeLineup = Lineup.best(
      input.homeSquad,
      formation: input.homeFormation,
      bannedIds: bannedIds,
      preferredIds: input.homeLineupIds,
    );
    final Lineup awayLineup = Lineup.best(
      input.awaySquad,
      formation: input.awayFormation,
      bannedIds: bannedIds,
      preferredIds: input.awayLineupIds,
    );
    return _simulate(input, homeLineup, awayLineup, recordEvents: recordEvents);
  }

  MatchResult _simulate(
    MatchInput input,
    Lineup home,
    Lineup away, {
    required bool recordEvents,
  }) {
    final double homeBonus = 1.08 + input.homePower / 2000.0;
    final double homeAttack = Lineup.attackOn(home.starters) * homeBonus;
    final double awayAttack = Lineup.attackOn(away.starters);
    final double homeDefense = Lineup.defenseOn(home.starters);
    final double awayDefense = Lineup.defenseOn(away.starters);
    final double tempMid = tempsFactor(input.refereeTemper);

    // Chance production: attack against opposing defense.
    final double homeRate =
        _baseChancePerMinute * homeAttack / (awayDefense + 40);
    final double awayRate =
        _baseChancePerMinute * awayAttack / (homeDefense + 40);
    final double homeConversion = _conversion(homeAttack, awayDefense);
    final double awayConversion = _conversion(awayAttack, homeDefense);
    final double penaltyRate = _penaltyPool / 90 / 2;
    final double ownGoalRate = _ownGoalPool / 90 / 2;
    final double yellowRate = _yellowPool / 90 / 2 * tempMid;
    final double redRate = _redPool / 90 / 2 * tempMid;
    final double injuryRate = _injuryPool / 90 / 2;

    int homeGoals = 0;
    int awayGoals = 0;
    int homeSaves = 0;
    int awaySaves = 0;
    int homeShots = 0;
    int awayShots = 0;
    int homeShotsOnTarget = 0;
    int awayShotsOnTarget = 0;
    final List<MatchEvent> events = <MatchEvent>[];
    final List<_OnPitch> homeOn = <_OnPitch>[];
    final List<_OnPitch> awayOn = <_OnPitch>[];
    final Map<int, MatchPlayerRow> rows = <int, MatchPlayerRow>{};
    final Set<int> injuredIds = <int>{};
    final Set<int> sentOffIds = <int>{};

    void register(Player p, bool starter, int teamId) {
      rows[p.playerId] ??= MatchPlayerRow(
        playerId: p.playerId,
        playerName: p.name,
        teamId: teamId,
        starter: starter ? 1 : 0,
        minutes: 0,
        goals: 0,
        assists: 0,
        yellowCards: 0,
        redCards: 0,
        mvp: 0,
        rating: 50,
        points: 0,
      );
    }

    for (final Player p in home.starters) {
      register(p, true, input.homeTeamId);
    }
    for (final Player p in away.starters) {
      register(p, true, input.awayTeamId);
    }
    for (final Player p in home.substitutes) {
      register(p, false, input.homeTeamId);
    }
    for (final Player p in away.substitutes) {
      register(p, false, input.awayTeamId);
    }

    for (final Player p in home.starters) {
      homeOn.add(_OnPitch(p));
    }
    for (final Player p in away.starters) {
      awayOn.add(_OnPitch(p));
    }

    void addEvent(
      String type,
      int minute,
      bool isHome, {
      Player? player,
      String? detail,
    }) {
      if (!recordEvents) return;
      events.add(
        MatchEvent(
          minute: minute,
          type: type,
          side: isHome ? 'home' : 'away',
          playerId: player?.playerId,
          playerName: player?.name,
          detail: detail,
        ),
      );
    }

    // Picks a squad member off the pitch by weight (forwards score more,
    // defenders foul more).
    Player? weighted(List<Player> pool, double Function(Player) weight) {
      if (pool.isEmpty) return null;
      double total = 0;
      for (final Player p in pool) {
        total += weight(p);
      }
      if (total <= 0) return pool.first;
      double r = _rng.nextDouble() * total;
      for (final Player p in pool) {
        r -= weight(p);
        if (r <= 0) return p;
      }
      return pool.last;
    }

    Player? pickScorer(bool isHome, {bool setPiece = false}) {
      final List<_OnPitch> on = isHome ? homeOn : awayOn;
      return weighted(on.map((_OnPitch o) => o.player).toList(), (Player p) {
        final int g = Lineup.groupOf(p);
        double w = g == 4 ? 3.0 : (g == 3 ? 1.4 : (g == 2 ? 0.55 : 0.04));
        if (setPiece) w += p.power / 250.0;
        return w;
      });
    }

    Player? pickAssister(bool isHome, Player scorer) {
      final List<_OnPitch> on = isHome ? homeOn : awayOn;
      final List<Player> pool = on
          .map((_OnPitch o) => o.player)
          .where((Player p) => p != scorer && Lineup.groupOf(p) != 1)
          .toList();
      return weighted(pool, (Player p) => 1.0);
    }

    Player? pickFouler(bool isHome) {
      final List<_OnPitch> on = isHome ? homeOn : awayOn;
      return weighted(on.map((_OnPitch o) => o.player).toList(), (Player p) {
        final int g = Lineup.groupOf(p);
        return g == 2 ? 1.6 : (g == 3 ? 1.3 : 0.9);
      });
    }

    Player? pickInjured(bool isHome) {
      final List<_OnPitch> on = isHome ? homeOn : awayOn;
      return weighted(
        on.map((_OnPitch o) => o.player).toList(),
        (Player p) => Lineup.groupOf(p) == 4 ? 1.0 + _attackerInjuryBias : 1.0,
      );
    }

    Player? pickKeeper(bool isHome) {
      for (final _OnPitch o in isHome ? homeOn : awayOn) {
        if (Lineup.groupOf(o.player) == 1) return o.player;
      }
      return null;
    }

    _OnPitch? findOnPitch(bool isHome, Player p) {
      final List<_OnPitch> on = isHome ? homeOn : awayOn;
      for (final _OnPitch o in on) {
        if (o.player == p) return o;
      }
      return null;
    }

    void makeSubstitution(bool isHome, int minute) {
      final List<_OnPitch> on = isHome ? homeOn : awayOn;
      final List<Player> bench = isHome ? home.substitutes : away.substitutes;
      if (bench.isEmpty || on.length <= 7) return;
      // Replace the weakest outfield player on the pitch.
      _OnPitch? worst;
      for (final _OnPitch o in on) {
        if (Lineup.groupOf(o.player) == 1) continue;
        if (worst == null || o.player.power < worst.player.power) worst = o;
      }
      if (worst == null) return;
      final Player incoming = bench.removeAt(0);
      register(incoming, false, isHome ? input.homeTeamId : input.awayTeamId);
      // Seal the outgoing player's minutes at his exit.
      final MatchPlayerRow? outRow = rows[worst.player.playerId];
      if (outRow != null) {
        final int entry = worst.enteredAt;
        outRow.minutes = entry <= 0 ? minute : minute - entry;
      }
      on.remove(worst);
      on.add(_OnPitch(incoming, enteredAt: minute));
      rows[incoming.playerId]!.starter = 0;

      addEvent(MatchEvent.subOut, minute, isHome, player: worst.player);
      addEvent(MatchEvent.subIn, minute, isHome, player: incoming);
    }

    void scoreGoal(
      bool isHome,
      int minute,
      Player? scorer,
      Player? assister, {
      bool fromPenalty = false,
    }) {
      if (scorer == null) return;
      final MatchPlayerRow? row = rows[scorer.playerId];
      if (row == null) return;
      homeGoals += isHome ? 1 : 0;
      awayGoals += isHome ? 0 : 1;
      row.goals += 1;
      if (assister != null && !fromPenalty) {
        final MatchPlayerRow? assistRow = rows[assister.playerId];
        if (assistRow != null) {
          assistRow.assists += 1;
          addEvent(MatchEvent.assist, minute, isHome, player: assister);
        }
      }
      if (fromPenalty) {
        addEvent(
          MatchEvent.penaltyScored,
          minute,
          isHome,
          player: scorer,
          detail: 'converted',
        );
      } else {
        addEvent(MatchEvent.goal, minute, isHome, player: scorer);
        // VAR check on goals.
        if (recordEvents && _rng.nextDouble() < 0.10) {
          addEvent(MatchEvent.varCheck, minute, isHome);
          if (_rng.nextDouble() < 0.20) {
            addEvent(
              MatchEvent.varGoalDisallowed,
              minute,
              isHome,
              player: scorer,
              detail: 'goal disallowed',
            );
            homeGoals -= isHome ? 1 : 0;
            awayGoals -= isHome ? 0 : 1;
            row.goals -= 1;
          }
        }
      }
    }

    for (int minute = 1; minute <= 90; minute++) {
      // ----- home attack chance
      if (_rng.nextDouble() < homeRate) {
        homeShots++;
        final Player? scorer = pickScorer(true);
        final Player? assistPlayer = scorer == null
            ? null
            : pickAssister(true, scorer);
        final double roll = _rng.nextDouble();
        if (roll < homeConversion) {
          homeShotsOnTarget++;
          scoreGoal(true, minute, scorer, assistPlayer);
        } else if (roll < homeConversion + _onTargetShare) {
          // On target but kept out by the away keeper.
          homeShotsOnTarget++;
          awaySaves++;
          addEvent(MatchEvent.save, minute, false, player: pickKeeper(false));
        }
      }
      // ----- away attack chance
      if (_rng.nextDouble() < awayRate) {
        awayShots++;
        final Player? scorer = pickScorer(false);
        final Player? assistPlayer = scorer == null
            ? null
            : pickAssister(false, scorer);
        final double roll = _rng.nextDouble();
        if (roll < awayConversion) {
          awayShotsOnTarget++;
          scoreGoal(false, minute, scorer, assistPlayer);
        } else if (roll < awayConversion + _onTargetShare) {
          // On target but kept out by the home keeper.
          awayShotsOnTarget++;
          homeSaves++;
          addEvent(MatchEvent.save, minute, true, player: pickKeeper(true));
        }
      }

      // ----- penalties
      if (_rng.nextDouble() < penaltyRate) {
        homeShots++;
        final bool scored = _rng.nextDouble() < _penaltyConvert;
        if (scored) {
          homeShotsOnTarget++;
          scoreGoal(
            true,
            minute,
            pickScorer(true, setPiece: true),
            null,
            fromPenalty: true,
          );
        } else {
          addEvent(
            MatchEvent.penaltyMissed,
            minute,
            true,
            player: pickScorer(true, setPiece: true),
          );
        }
      }
      if (_rng.nextDouble() < penaltyRate) {
        awayShots++;
        final bool scored = _rng.nextDouble() < _penaltyConvert;
        if (scored) {
          awayShotsOnTarget++;
          scoreGoal(
            false,
            minute,
            pickScorer(false, setPiece: true),
            null,
            fromPenalty: true,
          );
        } else {
          addEvent(
            MatchEvent.penaltyMissed,
            minute,
            false,
            player: pickScorer(false, setPiece: true),
          );
        }
      }

      // ----- own goals (benefiting side is opposite of the fouler)
      if (_rng.nextDouble() < ownGoalRate) {
        final bool benefitsHome = _rng.nextBool();
        final Player? culprit = weighted(
          (benefitsHome ? awayOn : homeOn)
              .map((_OnPitch o) => o.player)
              .toList(),
          (Player p) => Lineup.groupOf(p) == 2 ? 2.0 : 1.0,
        );
        addEvent(
          MatchEvent.ownGoal,
          minute,
          !benefitsHome,
          player: culprit,
          detail: 'deflected in',
        );
        if (benefitsHome) {
          homeGoals++;
          homeShots++;
          homeShotsOnTarget++;
        } else {
          awayGoals++;
          awayShots++;
          awayShotsOnTarget++;
        }
      }

      // ----- cards
      if (_rng.nextDouble() < yellowRate) {
        final bool isHome = _rng.nextBool();
        final Player? fouler = pickFouler(isHome);
        if (fouler != null) {
          final MatchPlayerRow? row = rows[fouler.playerId];
          if (row != null) {
            row.yellowCards += 1;
            addEvent(MatchEvent.yellow, minute, isHome, player: fouler);
            if (row.yellowCards >= 2) {
              row.redCards = 1;
              row.yellowCards = 1;
              sentOffIds.add(fouler.playerId);
              final _OnPitch? o = findOnPitch(isHome, fouler);
              if (o != null) {
                final int entry = o.enteredAt;
                row.minutes = entry <= 0 ? minute : minute - entry;
                (isHome ? homeOn : awayOn).remove(o);
              }
              addEvent(
                MatchEvent.red,
                minute,
                isHome,
                player: fouler,
                detail: 'second yellow',
              );
            } else {
              row.rating -= 4;
            }
          }
        }
      }
      if (_rng.nextDouble() < redRate) {
        final bool isHome = _rng.nextBool();
        final Player? fouler = pickFouler(isHome);
        if (fouler != null) {
          final MatchPlayerRow? row = rows[fouler.playerId];
          if (row != null) {
            row.redCards = 1;
            sentOffIds.add(fouler.playerId);
            final _OnPitch? o = findOnPitch(isHome, fouler);
            if (o != null) {
              final int entry = o.enteredAt;
              row.minutes = entry <= 0 ? minute : minute - entry;
              (isHome ? homeOn : awayOn).remove(o);
            }
            addEvent(
              MatchEvent.red,
              minute,
              isHome,
              player: fouler,
              detail: 'straight red',
            );
          }
        }
      }

      // ----- injuries
      if (_rng.nextDouble() < injuryRate) {
        final bool isHome = _rng.nextBool();
        final Player? hurt = pickInjured(isHome);
        if (hurt != null) {
          injuredIds.add(hurt.playerId);
          addEvent(MatchEvent.injury, minute, isHome, player: hurt);
          makeSubstitution(isHome, minute);
        }
      }

      // ----- routine substitutions both sides
      if (minute == 62 || minute == 72 || minute == 84) {
        if (_rng.nextDouble() < 0.85) makeSubstitution(true, minute);
        if (_rng.nextDouble() < 0.85) makeSubstitution(false, minute);
      }
    }

    // ------------------------------------------- finalize player minutes
    // Everyone still on the pitch at full time played 90 minus subs entry
    // time; players already sealed (sent off / subbed off / injured) keep
    // their recorded minutes.
    void sealMinutes(_OnPitch o) {
      final MatchPlayerRow? row = rows[o.player.playerId];
      if (row == null) return;
      final int entry = o.enteredAt;
      row.minutes = entry <= 0 ? 90 : 90 - entry;
    }

    for (final _OnPitch o in homeOn) {
      sealMinutes(o);
    }
    for (final _OnPitch o in awayOn) {
      sealMinutes(o);
    }
    // Injured players with no substitute available keep a partial shift.
    for (final int id in injuredIds) {
      final MatchPlayerRow? row = rows[id];
      if (row != null && row.minutes > 80) row.minutes = 25 + _rng.nextInt(45);
    }

    // ------------------------------------------- ratings & points
    final int homeOutcome = homeGoals > awayGoals
        ? 3
        : homeGoals == awayGoals
        ? 1
        : 0;
    final int awayOutcome = awayGoals > homeGoals
        ? 3
        : homeGoals == awayGoals
        ? 1
        : 0;
    rows.forEach((int id, MatchPlayerRow row) {
      if (row.minutes == 0) return;
      final bool isHomePlayer =
          home.starters.any((Player p) => p.playerId == id) ||
          home.substitutes.any((Player p) => p.playerId == id);
      final int outcome = isHomePlayer ? homeOutcome : awayOutcome;
      final double noise = (_rng.nextDouble() - 0.5) * 8.0;
      row.rating =
          (44 +
                  outcome * 6 +
                  row.goals * 14 +
                  row.assists * 8 +
                  (row.redCards == 1 ? -16 : 0) -
                  row.yellowCards * 3 +
                  noise)
              .round()
              .clamp(20, 100);
      row.points = outcome + row.goals * 2;
    });
    // Keeper save credit.
    void keeperCredit(Player p, int saves) {
      if (Lineup.groupOf(p) != 1) return;
      final MatchPlayerRow? row = rows[p.playerId];
      if (row == null || row.minutes == 0) return;
      row.rating = (row.rating + saves * 3).clamp(20, 100);
      row.points += saves ~/ 3;
    }

    for (final Player p in home.starters) {
      keeperCredit(p, homeSaves);
    }
    for (final Player p in away.starters) {
      keeperCredit(p, awaySaves);
    }

    // MVP: highest rating with >= 30 minutes.
    MatchPlayerRow? best;
    for (final MatchPlayerRow row in rows.values) {
      if (row.minutes < 30) continue;
      if (best == null || row.rating > best.rating) best = row;
    }
    best?.mvp = 1;

    // ------------------------------------------- attendance & revenue
    final double appeal = (0.40 + 0.007 * input.homePower.clamp(0, 100)).clamp(
      0.30,
      0.98,
    );
    final int attGeneral = (input.capacityGeneral * appeal).round();
    final int attStand = (input.capacityStand * appeal).round();
    final int attTerrace = (input.capacityTerrace * appeal).round();
    final int attBoxes = (input.capacityBoxes * 0.95).round();
    final int revenue =
        attGeneral * _tierPrices[0] +
        attStand * _tierPrices[1] +
        attTerrace * _tierPrices[2] +
        attBoxes * _tierPrices[3];

    events.sort((MatchEvent a, MatchEvent b) {
      final int c = a.minute.compareTo(b.minute);
      return c != 0 ? c : a.type.compareTo(b.type);
    });

    // Possession estimate from the two midfields, with a small home edge.
    final double homeMid = Lineup.midfieldOn(home.starters);
    final double awayMid = Lineup.midfieldOn(away.starters);
    final int homePossession = ((homeMid + 3) / (homeMid + awayMid + 6) * 100)
        .round()
        .clamp(25, 75);

    return MatchResult(
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      events: recordEvents ? events : <MatchEvent>[],
      playerRows: rows.values
          .where((MatchPlayerRow r) => r.minutes > 0)
          .toList(),
      attendanceGeneral: attGeneral,
      attendanceStand: attStand,
      attendanceTerrace: attTerrace,
      attendanceBoxes: attBoxes,
      revenue: revenue,
      homeShots: homeShots,
      awayShots: awayShots,
      homeShotsOnTarget: homeShotsOnTarget,
      awayShotsOnTarget: awayShotsOnTarget,
      homeSaves: homeSaves,
      awaySaves: awaySaves,
      homePossession: homePossession,
      input: input,
    );
  }

  /// Runs a penalty shootout between two clubs. `detail` on each event is
  /// `scored`/`missed`; minutes stay at 120 so the viewer shows them after
  /// full time. Sudden death follows when the first five kicks each end level.
  MatchPenaltyShootout penaltyShootout(MatchInput input) {
    final Lineup home = Lineup.best(
      input.homeSquad,
      formation: input.homeFormation,
      preferredIds: input.homeLineupIds,
    );
    final Lineup away = Lineup.best(
      input.awaySquad,
      formation: input.awayFormation,
      preferredIds: input.awayLineupIds,
    );
    final List<Player> homeKickers = _shootoutKickers(home.starters);
    final List<Player> awayKickers = _shootoutKickers(away.starters);
    final List<MatchEvent> events = <MatchEvent>[];
    int homeScore = 0;
    int awayScore = 0;
    int round = 1;

    // Best of five first, then sudden death until somebody leads.
    while (true) {
      final bool suddenDeath = round > 5;
      for (final bool isHome in <bool>[true, false]) {
        final Player shooter = isHome
            ? homeKickers[(round - 1) % homeKickers.length]
            : awayKickers[(round - 1) % awayKickers.length];
        final bool scored = _rng.nextDouble() < 0.76;
        if (scored) {
          if (isHome) {
            homeScore++;
          } else {
            awayScore++;
          }
        }
        events.add(
          MatchEvent(
            minute: 120,
            type: MatchEvent.shootout,
            side: isHome ? 'home' : 'away',
            playerId: shooter.playerId,
            playerName: shooter.name,
            detail: '${scored ? 'scored' : 'missed'} $round',
          ),
        );
        // Best of five can end early once the result is mathematically safe.
        if (!suddenDeath) {
          final int kicksTaken = isHome ? round : round - 1;
          final int kicksLeft = 5 - kicksTaken;
          if (homeScore > awayScore + kicksLeft ||
              awayScore > homeScore + kicksLeft) {
            return MatchPenaltyShootout(
              homeScore: homeScore,
              awayScore: awayScore,
              events: events,
            );
          }
        }
      }
      if (suddenDeath && homeScore != awayScore) {
        return MatchPenaltyShootout(
          homeScore: homeScore,
          awayScore: awayScore,
          events: events,
        );
      }
      round++;
    }
  }

  /// Kickers by finishing skill, best penalty takers first.
  List<Player> _shootoutKickers(List<Player> starters) {
    final List<Player> outfield =
        starters.where((Player p) => p.positionId != 1).toList()
          ..sort((Player a, Player b) => b.power.compareTo(a.power));
    final List<Player> keeper = starters
        .where((Player p) => p.positionId == 1)
        .toList();
    return <Player>[...outfield, ...keeper];
  }

  static double tempsFactor(int temper) => 0.6 + 0.2 * temper;

  /// Probability that a shot turns into a goal, based on the attack/defence
  /// mismatch. Quality grows with the mismatch but is capped so even a huge
  /// favourite does not score on every attack.
  static double _conversion(double attack, double defense) {
    final double quality = (attack + 40) / (defense + 40);
    return (_conversionBase * pow(quality, 0.55).toDouble())
        .clamp(0.04, 0.32)
        .toDouble();
  }
}

/// A player currently on the pitch (substition bookkeeping).
class _OnPitch {
  _OnPitch(this.player, {this.enteredAt = 0});

  final Player player;
  final int enteredAt;

  bool enteredFromBenchAt({required int minute}) => enteredAt > 0;
}
