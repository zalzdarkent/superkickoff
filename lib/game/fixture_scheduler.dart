import 'dart:math';

/// One fixture produced by a scheduler. Kept in the game layer so fixture
/// generation can be tested without a database.
class FixtureSlot {
  FixtureSlot(this.round, this.leg, this.home, this.away, {this.groupId});

  final int round;
  final int leg;
  final int home;
  final int away;
  final int? groupId;

  @override
  String toString() =>
      'FixtureSlot(round: $round, leg: $leg, $home v $away'
      '${groupId == null ? '' : ', group: $groupId'})';
}

class _Pair {
  _Pair(this.first, this.second);

  final int first;
  final int second;
}

/// Circle-method round-robin with deterministic home-away optimisation.
///
/// The first half of a double round-robin is mirrored, so every club ends with
/// exactly `N - 1` home and `N - 1` away matches. The optimiser only changes
/// the orientation of first-half fixtures (which club is at home); it never
/// changes the pairings, so mathematical correctness is preserved.
class RoundRobinScheduler {
  const RoundRobinScheduler._();

  static List<FixtureSlot> schedule(
    List<int> teamIds, {
    bool doubleRound = true,
    Random? random,
    bool optimizeHomeAway = true,
  }) {
    final List<int> ids = _unique(teamIds);
    if (ids.length < 2) return <FixtureSlot>[];
    if (random != null) ids.shuffle(random);

    final List<List<_Pair>> pairings = _circleRounds(ids);
    final int halfRounds = pairings.length;

    // Formula that gives an alternating home-away pattern for an even field:
    // in even rounds the second club is at home, in odd rounds the first club.
    final List<List<bool>> firstHome = List<List<bool>>.generate(
      halfRounds,
      (int r) => List<bool>.filled(pairings[r].length, r.isOdd),
    );

    if (optimizeHomeAway) {
      _optimiseOrientations(
        pairings,
        firstHome,
        ids,
        doubleRound: doubleRound,
        random: random,
      );
    }

    final List<FixtureSlot> slots = <FixtureSlot>[];
    for (int r = 0; r < halfRounds; r++) {
      for (int i = 0; i < pairings[r].length; i++) {
        final _Pair pair = pairings[r][i];
        final bool homeFirst = firstHome[r][i];
        slots.add(
          FixtureSlot(
            r + 1,
            1,
            homeFirst ? pair.first : pair.second,
            homeFirst ? pair.second : pair.first,
          ),
        );
      }
    }
    if (!doubleRound) return slots;

    for (int r = 0; r < halfRounds; r++) {
      for (int i = 0; i < pairings[r].length; i++) {
        final _Pair pair = pairings[r][i];
        final bool homeFirst = firstHome[r][i];
        // Reverse the venue for the return fixture.
        slots.add(
          FixtureSlot(
            r + halfRounds + 1,
            2,
            homeFirst ? pair.second : pair.first,
            homeFirst ? pair.first : pair.second,
          ),
        );
      }
    }
    return slots;
  }

  /// Classic circle method. `-1` is the bye placeholder for odd fields.
  static List<List<_Pair>> _circleRounds(List<int> teamIds) {
    final List<int> ring = List<int>.of(teamIds);
    if (ring.length.isOdd) ring.add(-1);
    final int n = ring.length;
    final List<List<_Pair>> rounds = <List<_Pair>>[];
    for (int r = 0; r < n - 1; r++) {
      final List<_Pair> pairs = <_Pair>[];
      for (int i = 0; i < n ~/ 2; i++) {
        final int a = ring[i];
        final int b = ring[n - 1 - i];
        if (a == -1 || b == -1) continue;
        pairs.add(_Pair(a, b));
      }
      rounds.add(pairs);
      ring.insert(1, ring.removeLast());
    }
    return rounds;
  }

  static void _optimiseOrientations(
    List<List<_Pair>> pairings,
    List<List<bool>> firstHome,
    List<int> ids, {
    required bool doubleRound,
    Random? random,
  }) {
    int score = _score(pairings, firstHome, ids, doubleRound: doubleRound);
    if (score == 0) return;

    int seed = 0x5EED;
    for (final int id in ids) {
      seed = (seed * 31 + id) & 0x7fffffff;
    }
    if (random != null) seed ^= random.nextInt(0x7fffffff);

    // A few deterministic restarts are enough for realistic league sizes while
    // keeping an odd-sized league generation comfortably under a second.
    final int rounds = pairings.length;
    final int variables = pairings.fold<int>(
      0,
      (int sum, List<_Pair> pairs) => sum + pairs.length,
    );
    final int iterations = (26000 + variables * 400).clamp(26000, 90000);

    for (int restart = 0; restart < 4 && score > 0; restart++) {
      final Random rng = Random(seed + restart * 7919);
      final List<List<bool>> current = List<List<bool>>.generate(
        rounds,
        (int r) => List<bool>.of(firstHome[r]),
      );
      int currentScore = score;
      int bestScore = currentScore;
      List<List<bool>> best = List<List<bool>>.generate(
        rounds,
        (int r) => List<bool>.of(current[r]),
      );
      double temperature = 3.0;
      for (int it = 0; it < iterations; it++) {
        final int r = rng.nextInt(rounds);
        if (pairings[r].isEmpty) continue;
        final int i = rng.nextInt(pairings[r].length);
        current[r][i] = !current[r][i];
        final int candidate = _score(
          pairings,
          current,
          ids,
          doubleRound: doubleRound,
        );
        final int delta = candidate - currentScore;
        if (delta <= 0 ||
            rng.nextDouble() < exp(-delta / max(0.05, temperature))) {
          currentScore = candidate;
          if (candidate < bestScore) {
            bestScore = candidate;
            for (int rr = 0; rr < rounds; rr++) {
              best[rr] = List<bool>.of(current[rr]);
            }
            if (bestScore == 0) break;
          }
        } else {
          current[r][i] = !current[r][i];
        }
        temperature = max(0.02, temperature * 0.99995);
      }
      if (bestScore < score) {
        for (int rr = 0; rr < rounds; rr++) {
          firstHome[rr] = List<bool>.of(best[rr]);
        }
        score = bestScore;
      }
      seed = seed * 1103515245 + 12345;
    }
  }

  /// Lower is better. Hard requirements (run length, totals) dominate the
  /// soft five-match balance preferences.
  static int _score(
    List<List<_Pair>> pairings,
    List<List<bool>> firstHome,
    List<int> ids, {
    required bool doubleRound,
  }) {
    final Map<int, List<int>> sequences = <int, List<int>>{
      for (final int id in ids) id: <int>[],
    };
    for (int r = 0; r < pairings.length; r++) {
      for (int i = 0; i < pairings[r].length; i++) {
        final _Pair pair = pairings[r][i];
        if (firstHome[r][i]) {
          sequences[pair.first]!.add(1);
          sequences[pair.second]!.add(-1);
        } else {
          sequences[pair.first]!.add(-1);
          sequences[pair.second]!.add(1);
        }
      }
    }

    int score = 0;
    for (final int id in ids) {
      final List<int> first = sequences[id]!;
      final List<int> full = doubleRound
          ? <int>[...first, ...first.map((int v) => -v)]
          : first;

      int run = 1;
      for (int i = 1; i < full.length; i++) {
        if (full[i] == full[i - 1]) {
          run++;
        } else {
          if (run > 2) score += (run - 2) * (run - 2) * 100;
          run = 1;
        }
      }
      if (run > 2) score += (run - 2) * (run - 2) * 100;

      for (int i = 0; i + 4 < full.length; i++) {
        final int window = full[i] +
            full[i + 1] +
            full[i + 2] +
            full[i + 3] +
            full[i + 4];
        final int excess = window.abs() - 1;
        if (excess > 0) score += excess * excess * 4;
      }

      if (!doubleRound) {
        final int homes = first.where((int v) => v > 0).length;
        final int aways = first.where((int v) => v < 0).length;
        final int imbalance = (homes - aways).abs();
        if (imbalance > 1) score += (imbalance - 1) * (imbalance - 1) * 50;
      }
    }
    return score;
  }

  static List<int> _unique(List<int> ids) {
    final List<int> result = <int>[];
    final Set<int> seen = <int>{};
    for (final int id in ids) {
      if (seen.add(id)) result.add(id);
    }
    return result;
  }
}

class LeaguePhaseSchedule {
  LeaguePhaseSchedule(this.fixtures, this.opponentRounds);

  final List<FixtureSlot> fixtures;

  /// Number of matchdays in the league phase (one fixture per club per round).
  final int opponentRounds;
}

/// Generates a UEFA-style league phase: every club plays a fixed number of
/// distinct opponents, with an exact home/away split, and no club appears twice
/// on the same matchday.
class LeaguePhaseScheduler {
  const LeaguePhaseScheduler._();

  static LeaguePhaseSchedule generate(
    List<int> teamIds, {
    required int opponents,
    int? homeMatches,
    Map<int, int>? associationOf,
  }) {
    final List<int> ids = teamIds.toSet().toList();
    if (ids.length < 2 || opponents <= 0) {
      return LeaguePhaseSchedule(<FixtureSlot>[], 0);
    }
    final int n = ids.length;
    final int playableOpponents = min(opponents, n - 1);
    final int targetHome = homeMatches ?? playableOpponents ~/ 2;
    final int targetAway = playableOpponents - targetHome;

    final List<List<_Pair>> allRounds = RoundRobinScheduler._circleRounds(ids);
    // Try every cyclic offset and pick the set of matchdays with the fewest
    // same-association pairings. This is a best-effort association restriction;
    // the game data does not contain a full country-clash rulebook.
    int bestOffset = 0;
    int bestConflicts = 1 << 30;
    for (int offset = 0; offset < allRounds.length; offset++) {
      final List<List<_Pair>> selected = <List<_Pair>>[];
      for (int i = 0; i < playableOpponents; i++) {
        selected.add(allRounds[(offset + i) % allRounds.length]);
      }
      final int conflicts = _associationConflicts(selected, associationOf);
      if (conflicts < bestConflicts) {
        bestConflicts = conflicts;
        bestOffset = offset;
      }
    }

    final List<List<_Pair>> selected = <List<_Pair>>[
      for (int i = 0; i < playableOpponents; i++)
        allRounds[(bestOffset + i) % allRounds.length],
    ];

    final Map<String, bool> homeFirst = _orientLeaguePhase(
      selected,
      ids,
      targetHome: targetHome,
      targetAway: targetAway,
    );

    final List<FixtureSlot> fixtures = <FixtureSlot>[];
    for (int r = 0; r < selected.length; r++) {
      for (final _Pair pair in selected[r]) {
        // The orientation map stores whether the lower-numbered club is at
        // home. Translate it to this pair's actual order.
        final bool lowerHome =
            homeFirst[_edgeKey(pair.first, pair.second)] ?? true;
        final bool firstIsHome = pair.first < pair.second
            ? lowerHome
            : !lowerHome;
        fixtures.add(
          FixtureSlot(
            r + 1,
            1,
            firstIsHome ? pair.first : pair.second,
            firstIsHome ? pair.second : pair.first,
          ),
        );
      }
    }
    return LeaguePhaseSchedule(fixtures, selected.length);
  }

  static int _associationConflicts(
    List<List<_Pair>> rounds,
    Map<int, int>? associationOf,
  ) {
    if (associationOf == null) return 0;
    int conflicts = 0;
    for (final List<_Pair> round in rounds) {
      for (final _Pair pair in round) {
        final int? a = associationOf[pair.first];
        final int? b = associationOf[pair.second];
        if (a != null && b != null && a == b) conflicts++;
      }
    }
    return conflicts;
  }

  static String _edgeKey(int a, int b) => a < b ? '$a-$b' : '$b-$a';

  /// Orient the selected edges so every club receives its exact home count.
  /// The graph is even-regular (each club plays the same number of matches in
  /// the selected matchdays), so an Eulerian orientation always exists when
  /// home and away targets are equal.
  static Map<String, bool> _orientLeaguePhase(
    List<List<_Pair>> rounds,
    List<int> ids, {
    required int targetHome,
    required int targetAway,
  }) {
    final List<_Edge> edges = <_Edge>[];
    final Map<int, List<int>> adjacency = <int, List<int>>{
      for (final int id in ids) id: <int>[],
    };
    for (final List<_Pair> round in rounds) {
      for (final _Pair pair in round) {
        final int index = edges.length;
        edges.add(_Edge(pair.first, pair.second));
        adjacency[pair.first]!.add(index);
        adjacency[pair.second]!.add(index);
      }
    }

    final Map<String, bool> orientation = <String, bool>{};
    final List<bool> used = List<bool>.filled(edges.length, false);

    // Hierholzer: walk every edge exactly once and orient it in the direction
    // of travel. Because the graph is even-regular, each component has an
    // Eulerian circuit and every vertex ends with in-degree == out-degree.
    for (final int start in ids) {
      if (adjacency[start]!.every((int e) => used[e])) continue;
      final List<int> vertexStack = <int>[start];
      final List<(int, int)> traversed = <(int, int)>[];
      while (vertexStack.isNotEmpty) {
        final int v = vertexStack.last;
        int? nextEdge;
        for (final int edgeIndex in adjacency[v]!) {
          if (!used[edgeIndex]) {
            nextEdge = edgeIndex;
            break;
          }
        }
        if (nextEdge == null) {
          vertexStack.removeLast();
          continue;
        }
        used[nextEdge] = true;
        traversed.add((nextEdge, v));
        vertexStack.add(edges[nextEdge].other(v));
      }
      for (final (int edgeIndex, int from) in traversed) {
        final _Edge edge = edges[edgeIndex];
        final int low = edge.a < edge.b ? edge.a : edge.b;
        // True means the lower-numbered club hosts this fixture.
        orientation[_edgeKey(edge.a, edge.b)] = from == low;
      }
    }

    // Defensive fallback for unusual graphs: greedily balance home counts.
    final Map<int, int> homes = <int, int>{for (final int id in ids) id: 0};
    for (final MapEntry<String, bool> entry in orientation.entries) {
      final List<String> parts = entry.key.split('-');
      final int a = int.parse(parts[0]);
      final int b = int.parse(parts[1]);
      homes[entry.value ? a : b] = (homes[entry.value ? a : b] ?? 0) + 1;
    }
    bool balanced = orientation.length == edges.length;
    for (final int id in ids) {
      if ((homes[id] ?? 0) != targetHome) {
        balanced = false;
        break;
      }
    }
    if (balanced) return orientation;

    // Hill-climb flips until the home totals match.
    final List<String> keys = orientation.keys.toList();
    int score = _orientationScore(homes, ids, targetHome, targetAway);
    for (int it = 0; it < 40000 && score > 0; it++) {
      final String key = keys[it % keys.length];
      final List<String> parts = key.split('-');
      final int a = int.parse(parts[0]);
      final int b = int.parse(parts[1]);
      final bool old = orientation[key]!;
      final int oldHome = old ? a : b;
      final int newHome = old ? b : a;
      homes[oldHome] = (homes[oldHome] ?? 0) - 1;
      homes[newHome] = (homes[newHome] ?? 0) + 1;
      orientation[key] = !old;
      final int candidate = _orientationScore(
        homes,
        ids,
        targetHome,
        targetAway,
      );
      if (candidate <= score) {
        score = candidate;
      } else {
        homes[newHome] = (homes[newHome] ?? 0) - 1;
        homes[oldHome] = (homes[oldHome] ?? 0) + 1;
        orientation[key] = old;
      }
    }
    return orientation;
  }

  static int _orientationScore(
    Map<int, int> homes,
    List<int> ids,
    int targetHome,
    int targetAway,
  ) {
    int score = 0;
    for (final int id in ids) {
      final int value = homes[id] ?? 0;
      final int delta = value - targetHome;
      score += delta * delta;
    }
    return score;
  }
}

class _Edge {
  _Edge(this.a, this.b);

  final int a;
  final int b;

  int other(int v) => v == a ? b : a;
  bool connects(int x, int y) => (a == x && b == y) || (a == y && b == x);
}

class KnockoutPlan {
  KnockoutPlan({
    required this.bracketSize,
    required this.pairs,
    required this.byes,
  });

  final int bracketSize;
  final List<(int, int)> pairs;
  final List<int> byes;

  int get roundsToFinal => bracketSize <= 1 ? 0 : bracketSize.bitLength - 1;
  bool get isEmpty => pairs.isEmpty && byes.isEmpty;
}

/// Deterministic knockout bracket helpers. Byes are first-class: a club that
/// receives one is returned in [KnockoutPlan.byes] and must be carried into the
/// next round by the caller (the database layer stores it).
class KnockoutScheduler {
  const KnockoutScheduler._();

  static KnockoutPlan planOpeningRound(
    List<int> entrants, {
    bool useByes = true,
    bool trimToPowerOfTwo = false,
    int? fieldSize,
  }) {
    final List<int> ids = entrants.toSet().toList();
    if (ids.isEmpty) {
      return KnockoutPlan(bracketSize: 0, pairs: <(int, int)>[], byes: <int>[]);
    }
    if (trimToPowerOfTwo) {
      final int limit = min(ids.length, fieldSize ?? ids.length);
      final int bracket = _largestPowerOfTwo(limit);
      final List<int> field = ids.take(bracket).toList();
      return KnockoutPlan(
        bracketSize: bracket,
        pairs: _pairSeeded(field),
        byes: <int>[],
      );
    }
    if (!useByes) {
      final int bracket = _largestPowerOfTwo(ids.length);
      final List<int> field = ids.take(bracket).toList();
      return KnockoutPlan(
        bracketSize: bracket,
        pairs: _pairSeeded(field),
        byes: <int>[],
      );
    }

    final int bracket = _nextPowerOfTwo(ids.length);
    final int byeCount = bracket - ids.length;
    final List<int> byes = ids.take(byeCount).toList();
    final List<int> playing = ids.skip(byeCount).toList();
    return KnockoutPlan(
      bracketSize: bracket,
      pairs: _pairSeeded(playing),
      byes: byes,
    );
  }

  /// Pairs survivors of the previous round. Survivors must be in bracket order;
  /// adjacent winners meet, and an odd survivor receives a bye.
  static KnockoutPlan pairNextRound(List<int> survivors) {
    final List<int> ids = survivors.toSet().toList();
    if (ids.length <= 1) {
      return KnockoutPlan(bracketSize: ids.length, pairs: <(int, int)>[], byes: ids);
    }
    final List<int> byes = ids.length.isOdd ? <int>[ids.last] : <int>[];
    final List<int> playing = ids.length.isOdd
        ? ids.sublist(0, ids.length - 1)
        : ids;
    return KnockoutPlan(
      bracketSize: _nextPowerOfTwo(ids.length),
      pairs: _pairSeeded(playing),
      byes: byes,
    );
  }

  static List<(int, int)> _pairSeeded(List<int> ids) {
    final List<(int, int)> pairs = <(int, int)>[];
    for (int i = 0; i < ids.length ~/ 2; i++) {
      pairs.add((ids[i], ids[ids.length - 1 - i]));
    }
    return pairs;
  }

  static int _nextPowerOfTwo(int value) {
    int result = 1;
    while (result < value) {
      result <<= 1;
    }
    return result;
  }

  static int _largestPowerOfTwo(int value) {
    int result = 1;
    while (result * 2 <= value) {
      result <<= 1;
    }
    return result;
  }

  static bool isPowerOfTwo(int value) =>
      value > 0 && (value & (value - 1)) == 0;
}
