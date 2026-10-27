import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import 'national_team_service.dart';

/// Group table row for international tournaments.
class InternationalStandingRow {
  const InternationalStandingRow({
    required this.countryId,
    required this.countryName,
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.points = 0,
    this.groupId,
  });

  final int countryId;
  final String countryName;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int goalsFor;
  final int goalsAgainst;
  final int points;
  final int? groupId;

  int get goalDifference => goalsFor - goalsAgainst;

  InternationalStandingRow copyWith({
    int? played,
    int? won,
    int? drawn,
    int? lost,
    int? goalsFor,
    int? goalsAgainst,
    int? points,
  }) =>
      InternationalStandingRow(
        countryId: countryId,
        countryName: countryName,
        played: played ?? this.played,
        won: won ?? this.won,
        drawn: drawn ?? this.drawn,
        lost: lost ?? this.lost,
        goalsFor: goalsFor ?? this.goalsFor,
        goalsAgainst: goalsAgainst ?? this.goalsAgainst,
        points: points ?? this.points,
        groupId: groupId,
      );
}

typedef InternationalStanding = InternationalStandingRow;

/// Service that handles international competition generation, formats,
/// standings calculation, and tournament progression.
class InternationalTournamentService {
  InternationalTournamentService(this.db, {Random? random})
      : _rng = random ?? Random(),
        _nationalService = NationalTeamService(db);

  final Database db;
  final Random _rng;
  final NationalTeamService _nationalService;

  // ------------------------------------------------ Standings & Tie-breakers

  /// Computes standings for [tournamentId] and [seasonId], optionally filtered by [groupId].
  Future<List<InternationalStandingRow>> getStandings({
    required int tournamentId,
    required int seasonId,
    int? groupId,
  }) async {
    final List<Map<String, Object?>> matches = await db.query(
      t.countryMatches,
      where: 'tournament_id = ? AND season_id = ? AND status = ? ${groupId != null ? 'AND group_id = $groupId' : ''}',
      whereArgs: <Object?>[tournamentId, seasonId, t.matchFinished],
    );

    final Set<int> countryIds = <int>{};
    for (final Map<String, Object?> m in matches) {
      countryIds.add((m['home_country_id'] as int?) ?? 0);
      countryIds.add((m['away_country_id'] as int?) ?? 0);
    }

    // Also include countries that have scheduled matches in this group
    final List<Map<String, Object?>> scheduled = await db.query(
      t.countryMatches,
      where: 'tournament_id = ? AND season_id = ? ${groupId != null ? 'AND group_id = $groupId' : ''}',
      whereArgs: <Object?>[tournamentId, seasonId],
    );
    for (final Map<String, Object?> m in scheduled) {
      countryIds.add((m['home_country_id'] as int?) ?? 0);
      countryIds.add((m['away_country_id'] as int?) ?? 0);
    }
    countryIds.remove(0);

    final Map<int, InternationalStandingRow> rows = <int, InternationalStandingRow>{};
    for (final int cId in countryIds) {
      final Country? c = await _nationalService.getNationalTeam(cId);
      rows[cId] = InternationalStandingRow(
        countryId: cId,
        countryName: c?.name ?? 'Country $cId',
        groupId: groupId,
      );
    }

    for (final Map<String, Object?> m in matches) {
      final int home = (m['home_country_id'] as int?) ?? 0;
      final int away = (m['away_country_id'] as int?) ?? 0;
      final int hg = (m['home_goals'] as int?) ?? 0;
      final int ag = (m['away_goals'] as int?) ?? 0;

      if (!rows.containsKey(home) || !rows.containsKey(away)) continue;

      final InternationalStandingRow rHome = rows[home]!;
      final InternationalStandingRow rAway = rows[away]!;

      if (hg > ag) {
        rows[home] = rHome.copyWith(
          played: rHome.played + 1,
          won: rHome.won + 1,
          goalsFor: rHome.goalsFor + hg,
          goalsAgainst: rHome.goalsAgainst + ag,
          points: rHome.points + 3,
        );
        rows[away] = rAway.copyWith(
          played: rAway.played + 1,
          lost: rAway.lost + 1,
          goalsFor: rAway.goalsFor + ag,
          goalsAgainst: rAway.goalsAgainst + hg,
        );
      } else if (hg < ag) {
        rows[home] = rHome.copyWith(
          played: rHome.played + 1,
          lost: rHome.lost + 1,
          goalsFor: rHome.goalsFor + hg,
          goalsAgainst: rHome.goalsAgainst + ag,
        );
        rows[away] = rAway.copyWith(
          played: rAway.played + 1,
          won: rAway.won + 1,
          goalsFor: rAway.goalsFor + ag,
          goalsAgainst: rAway.goalsAgainst + hg,
          points: rAway.points + 3,
        );
      } else {
        rows[home] = rHome.copyWith(
          played: rHome.played + 1,
          drawn: rHome.drawn + 1,
          goalsFor: rHome.goalsFor + hg,
          goalsAgainst: rHome.goalsAgainst + ag,
          points: rHome.points + 1,
        );
        rows[away] = rAway.copyWith(
          played: rAway.played + 1,
          drawn: rAway.drawn + 1,
          goalsFor: rAway.goalsFor + ag,
          goalsAgainst: rAway.goalsAgainst + hg,
          points: rAway.points + 1,
        );
      }
    }

    final List<InternationalStandingRow> sorted = rows.values.toList();
    sorted.sort((a, b) {
      if (b.points != a.points) return b.points.compareTo(a.points);
      if (b.goalDifference != a.goalDifference) {
        return b.goalDifference.compareTo(a.goalDifference);
      }
      if (b.goalsFor != a.goalsFor) return b.goalsFor.compareTo(a.goalsFor);
      return a.countryName.compareTo(b.countryName);
    });

    return sorted;
  }

  /// Extracts the best third-place teams across multiple groups (e.g. EURO or Asian Cup).
  Future<List<InternationalStandingRow>> getBestThirdPlacedTeams({
    required int tournamentId,
    required int seasonId,
    required int groupCount,
    required int advanceCount,
  }) async {
    final List<InternationalStandingRow> thirds = <InternationalStandingRow>[];
    for (int g = 1; g <= groupCount; g++) {
      final List<InternationalStandingRow> groupStandings = await getStandings(
        tournamentId: tournamentId,
        seasonId: seasonId,
        groupId: g,
      );
      if (groupStandings.length >= 3) {
        thirds.add(groupStandings[2]);
      }
    }

    thirds.sort((a, b) {
      if (b.points != a.points) return b.points.compareTo(a.points);
      if (b.goalDifference != a.goalDifference) {
        return b.goalDifference.compareTo(a.goalDifference);
      }
      if (b.goalsFor != a.goalsFor) return b.goalsFor.compareTo(a.goalsFor);
      return a.countryName.compareTo(b.countryName);
    });

    return thirds.take(advanceCount).toList();
  }

  // ------------------------------------------------ Tournament Scheduling

  /// Schedules group stage fixtures for [participatingCountryIds].
  ///
  /// Divides teams into groups of [groupSize], then schedules single or double round-robin matches.
  Future<List<CountryMatch>> scheduleGroupStage({
    required int tournamentId,
    required int seasonId,
    required List<int> participatingCountryIds,
    List<String>? matchDates,
    String? startDate,
    int groupSize = 4,
    int? groupCount,
    bool doubleRoundRobin = false,
    String? windowId,
  }) async {
    final List<CountryMatch> fixtures = <CountryMatch>[];
    final int count = groupCount ?? (participatingCountryIds.length / groupSize).ceil();
    final List<String> dates = matchDates ?? (startDate != null
        ? List<String>.generate(
            6,
            (int i) => DateTime.parse(startDate).add(Duration(days: i * 3)).toIso8601String().substring(0, 10),
          )
        : <String>['2026-06-01']);

    int dateIdx = 0;
    for (int g = 1; g <= count; g++) {
      final int startIdx = (g - 1) * groupSize;
      final List<int> groupTeams = participatingCountryIds
          .skip(startIdx)
          .take(groupSize)
          .toList();

      if (groupTeams.length < 2) continue;

      // Generate round robin pairs
      final List<(int, int)> pairs = <(int, int)>[];
      for (int i = 0; i < groupTeams.length; i++) {
        for (int j = i + 1; j < groupTeams.length; j++) {
          pairs.add((groupTeams[i], groupTeams[j]));
          if (doubleRoundRobin) {
            pairs.add((groupTeams[j], groupTeams[i]));
          }
        }
      }

      for (int p = 0; p < pairs.length; p++) {
        final (int, int) pair = pairs[p];
        final String matchDate = dates.isNotEmpty
            ? dates[(dateIdx + p) % dates.length]
            : '2026-06-15';

        final Map<String, Object?> row = <String, Object?>{
          'tournament_id': tournamentId,
          'season_id': seasonId,
          'home_country_id': pair.$1,
          'away_country_id': pair.$2,
          'phase': 0, // 0 = group stage
          'round': p + 1,
          'leg': 1,
          'status': t.matchScheduled,
          'date': matchDate,
          'group_id': g,
          'window_id': windowId,
        };

        final int matchId = await db.insert(
          t.countryMatches,
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        fixtures.add(CountryMatch.fromMap(<String, Object?>{...row, 'match_id': matchId}));
      }
      dateIdx += 2;
    }

    return fixtures;
  }

  /// Schedules knockout bracket round for qualified teams.
  ///
  /// Phase: 1 = R16/R32, 2 = QF, 3 = SF, 4 = Final.
  Future<List<CountryMatch>> scheduleKnockoutRound({
    required int tournamentId,
    required int seasonId,
    required int phase,
    List<int>? qualifiedCountryIds,
    List<int>? participatingCountryIds,
    required String matchDate,
    bool twoLegged = false,
    String? leg2Date,
    String? windowId,
  }) async {
    final List<int> teams = qualifiedCountryIds ?? participatingCountryIds ?? const <int>[];
    final List<CountryMatch> created = <CountryMatch>[];
    if (teams.length < 2) return created;

    for (int i = 0; i < teams.length - 1; i += 2) {
      final int home = teams[i];
      final int away = teams[i + 1];
      final int roundNumber = (i ~/ 2) + 1;

      // Leg 1
      final Map<String, Object?> row1 = <String, Object?>{
        'tournament_id': tournamentId,
        'season_id': seasonId,
        'home_country_id': home,
        'away_country_id': away,
        'phase': phase,
        'round': roundNumber,
        'leg': 1,
        'status': t.matchScheduled,
        'date': matchDate,
        'window_id': windowId,
      };

      final int id1 = await db.insert(t.countryMatches, row1);
      created.add(CountryMatch.fromMap(<String, Object?>{...row1, 'match_id': id1}));

      if (twoLegged && leg2Date != null) {
        // Leg 2
        final Map<String, Object?> row2 = <String, Object?>{
          'tournament_id': tournamentId,
          'season_id': seasonId,
          'home_country_id': away,
          'away_country_id': home,
          'phase': phase,
          'round': roundNumber,
          'leg': 2,
          'status': t.matchScheduled,
          'date': leg2Date,
          'window_id': windowId,
        };

        final int id2 = await db.insert(t.countryMatches, row2);
        created.add(CountryMatch.fromMap(<String, Object?>{...row2, 'match_id': id2}));
      }
    }

    return created;
  }

  /// Advances winners from a completed knockout round to schedule the next round.
  Future<List<CountryMatch>> advanceKnockoutProgression({
    required int tournamentId,
    required int seasonId,
    required int currentPhase,
    required String nextRoundDate,
    bool nextRoundTwoLegged = false,
    String? nextRoundLeg2Date,
    String? windowId,
  }) async {
    // 1. Fetch matches of current phase
    final List<Map<String, Object?>> matches = await db.query(
      t.countryMatches,
      where: 'tournament_id = ? AND season_id = ? AND phase = ?',
      whereArgs: <Object?>[tournamentId, seasonId, currentPhase],
      orderBy: 'round ASC, leg ASC',
    );

    if (matches.isEmpty) return <CountryMatch>[];
    // Check all matches are finished
    final bool allDone = matches.every(
      (m) => (m['status'] as int?) == t.matchFinished,
    );
    if (!allDone) return <CountryMatch>[];

    // Determine winners per tie/round
    final Map<int, List<Map<String, Object?>>> byRound = <int, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> m in matches) {
      final int r = (m['round'] as int?) ?? 1;
      byRound.putIfAbsent(r, () => <Map<String, Object?>>[]).add(m);
    }

    final List<int> winners = <int>[];
    for (final int r in byRound.keys.toList()..sort()) {
      final List<Map<String, Object?>> ties = byRound[r]!;
      if (ties.length == 1) {
        final Map<String, Object?> m = ties.first;
        final int w = (m['winner_id'] as int?) ?? 0;
        if (w > 0) {
          winners.add(w);
        } else {
          final int h = m['home_country_id'] as int;
          final int a = m['away_country_id'] as int;
          final int hg = (m['home_goals'] as int?) ?? 0;
          final int ag = (m['away_goals'] as int?) ?? 0;
          winners.add(hg >= ag ? h : a);
        }
      } else if (ties.length >= 2) {
        // Two-legged tie
        final Map<String, Object?> leg1 = ties.firstWhere(
          (m) => ((m['leg'] as int?) ?? 1) == 1,
          orElse: () => ties[0],
        );
        final Map<String, Object?> leg2 = ties.firstWhere(
          (m) => ((m['leg'] as int?) ?? 1) == 2,
          orElse: () => ties[1],
        );
        final int teamA = leg1['home_country_id'] as int;
        final int teamB = leg1['away_country_id'] as int;

        final int aggA = ((leg1['home_goals'] as int?) ?? 0) + ((leg2['away_goals'] as int?) ?? 0);
        final int aggB = ((leg1['away_goals'] as int?) ?? 0) + ((leg2['home_goals'] as int?) ?? 0);

        if (aggA > aggB) {
          winners.add(teamA);
        } else if (aggB > aggA) {
          winners.add(teamB);
        } else {
          // Penalties in leg 2
          final int penH = (leg2['penalty_home_goals'] as int?) ?? 0;
          final int penA = (leg2['penalty_away_goals'] as int?) ?? 0;
          winners.add(penH >= penA ? teamB : teamA);
        }
      }
    }

    if (winners.length < 2) return <CountryMatch>[];

    // Check if next phase already scheduled
    final int nextPhase = currentPhase + 1;
    final List<Map<String, Object?>> nextExists = await db.query(
      t.countryMatches,
      where: 'tournament_id = ? AND season_id = ? AND phase = ?',
      whereArgs: <Object?>[tournamentId, seasonId, nextPhase],
      limit: 1,
    );
    if (nextExists.isNotEmpty) return <CountryMatch>[];

    return scheduleKnockoutRound(
      tournamentId: tournamentId,
      seasonId: seasonId,
      phase: nextPhase,
      qualifiedCountryIds: winners,
      matchDate: nextRoundDate,
      twoLegged: nextRoundTwoLegged,
      leg2Date: nextRoundLeg2Date,
      windowId: windowId,
    );
  }

  // ------------------------------------------------ International Friendlies

  /// Generates sensible international friendlies inside an international window.
  Future<List<CountryMatch>> scheduleFriendliesForWindow({
    required int seasonId,
    required InternationalWindow window,
    List<int>? participatingCountryIds,
    int matchesPerTeam = 2,
  }) async {
    final List<CountryMatch> friendlies = <CountryMatch>[];

    // 1. Fetch eligible countries
    List<Country> countries = [];
    if (participatingCountryIds != null && participatingCountryIds.isNotEmpty) {
      for (final int cId in participatingCountryIds) {
        final Country? c = await _nationalService.getNationalTeam(cId);
        if (c != null) countries.add(c);
      }
    } else {
      countries = await _nationalService.getNationalTeams();
      // Select active top countries across confederations
      countries = countries.take(32).toList();
    }

    if (countries.length < 2) return friendlies;

    // 2. Sort by power for balanced matchmaking
    countries.sort((a, b) => b.power.compareTo(a.power));

    final DateTime? start = DateTime.tryParse(window.startDate);
    final DateTime? end = DateTime.tryParse(window.endDate);
    final String date1 = start != null
        ? start.add(const Duration(days: 2)).toIso8601String().substring(0, 10)
        : window.startDate;
    final String date2 = end != null
        ? end.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10)
        : window.endDate;

    final List<String> dates = matchesPerTeam >= 2 ? <String>[date1, date2] : <String>[date1];

    for (int d = 0; d < dates.length; d++) {
      final String matchDate = dates[d];
      final List<Country> pool = List<Country>.of(countries);
      // Alternate pairing on matchday 2 so teams don't play the same opponent
      if (d > 0) {
        pool.shuffle(_rng);
      }

      for (int i = 0; i < pool.length - 1; i += 2) {
        final Country home = pool[i];
        final Country away = pool[i + 1];

        final Map<String, Object?> row = <String, Object?>{
          'tournament_id': t.tournamentFriendlies,
          'season_id': seasonId,
          'home_country_id': home.countryId,
          'away_country_id': away.countryId,
          'phase': 0,
          'round': d + 1,
          'leg': 1,
          'status': t.matchScheduled,
          'date': matchDate,
          'window_id': window.windowId,
        };

        final int id = await db.insert(
          t.countryMatches,
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        friendlies.add(CountryMatch.fromMap(<String, Object?>{...row, 'match_id': id}));
      }
    }

    return friendlies;
  }

  // ------------------------------------------------ Specific Competitions

  /// Schedules the ASEAN Championship (AFF Championship) - Tournament ID 902.
  /// 10 ASEAN countries in 2 groups of 5, single round robin, top 2 advance to SF and Final.
  Future<List<CountryMatch>> scheduleAseanChampionship({
    required int seasonId,
    required InternationalWindow window,
  }) async {
    // 10 ASEAN nations
    const List<int> aseanIds = <int>[
      94,  // Indonesia
      223, // Thailand
      243, // Vietnam
      146, // Malaysia
      210, // Singapore
      68,  // Philippines
      26,  // Myanmar
      36,  // Cambodia
      133, // Laos
      31,  // Brunei
    ];

    final DateTime? start = DateTime.tryParse(window.startDate);
    final List<String> dates = <String>[];
    if (start != null) {
      for (int i = 0; i < 5; i++) {
        final DateTime d = start.add(Duration(days: i * 3));
        dates.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      }
    } else {
      dates.addAll(<String>[window.startDate, window.endDate]);
    }

    return scheduleGroupStage(
      tournamentId: t.tournamentAseanChampionship,
      seasonId: seasonId,
      participatingCountryIds: aseanIds,
      matchDates: dates,
      groupSize: 5,
      doubleRoundRobin: false,
      windowId: window.windowId,
    );
  }

  /// Schedules the FIFA ASEAN Cup - Tournament ID 903.
  /// 14 teams in two divisions / groups (distinct competition!).
  Future<List<CountryMatch>> scheduleFifaAseanCup({
    required int seasonId,
    required InternationalWindow window,
  }) async {
    // 14 sides: 10 ASEAN members + 4 guest/regional teams
    const List<int> teams14 = <int>[
      94, 223, 243, 146, 210, 68, 26, 36, 133, 31,
      14,  // Australia (guest)
      93,  // India (guest)
      228, // Timor Leste
      41,  // China (guest)
    ];

    final DateTime? start = DateTime.tryParse(window.startDate);
    final List<String> dates = <String>[];
    if (start != null) {
      for (int i = 0; i < 5; i++) {
        final DateTime d = start.add(Duration(days: i * 4));
        dates.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      }
    } else {
      dates.addAll(<String>[window.startDate, window.endDate]);
    }

    return scheduleGroupStage(
      tournamentId: t.tournamentFifaAseanCup,
      seasonId: seasonId,
      participatingCountryIds: teams14,
      matchDates: dates,
      groupSize: 7, // 2 groups of 7
      doubleRoundRobin: false,
      windowId: window.windowId,
    );
  }

  /// Computes UEFA Nations League Promotion and Relegation.
  ///
  /// Group winners in lower leagues promote up; group losers in upper leagues relegate down.
  Future<Map<String, List<int>>> processNationsLeaguePromotionRelegation({
    required int seasonId,
    required Map<String, List<int>> leagues, // 'A', 'B', 'C', 'D' -> countryIds
  }) async {
    final Map<String, List<int>> result = <String, List<int>>{
      'promoted': <int>[],
      'relegated': <int>[],
      'finalFour': <int>[],
    };

    // League A group winners advance to Final Four
    final List<InternationalStandingRow> leagueA = await getStandings(
      tournamentId: t.tournamentNationsLeague,
      seasonId: seasonId,
      groupId: 1,
    );
    if (leagueA.isNotEmpty) {
      result['finalFour']!.add(leagueA.first.countryId);
      result['relegated']!.add(leagueA.last.countryId);
    }

    final List<InternationalStandingRow> leagueB = await getStandings(
      tournamentId: t.tournamentNationsLeague,
      seasonId: seasonId,
      groupId: 2,
    );
    if (leagueB.isNotEmpty) {
      result['promoted']!.add(leagueB.first.countryId);
      result['relegated']!.add(leagueB.last.countryId);
    }

    return result;
  }

  Future<List<CountryMatch>> advanceKnockoutRound({
    required int seasonId,
    required int tournamentId,
    required int currentPhase,
    required String nextMatchDate,
    bool twoLegged = false,
    String? leg2Date,
    String? windowId,
  }) => advanceKnockoutProgression(
    tournamentId: tournamentId,
    seasonId: seasonId,
    currentPhase: currentPhase,
    nextRoundDate: nextMatchDate,
    nextRoundTwoLegged: twoLegged,
    nextRoundLeg2Date: leg2Date,
    windowId: windowId,
  );

  NationsLeagueMovement calculateNationsLeaguePromotionsRelegations(
    Map<int, List<InternationalStanding>> divisions,
  ) {
    final Map<int, List<int>> promotions = <int, List<int>>{};
    final Map<int, List<int>> relegations = <int, List<int>>{};

    for (final int div in divisions.keys) {
      final List<InternationalStanding> list = divisions[div]!;
      if (list.isEmpty) continue;
      if (div > 1) {
        promotions.putIfAbsent(div, () => <int>[]).add(list.first.countryId);
      }
      relegations.putIfAbsent(div, () => <int>[]).add(list.last.countryId);
    }
    return NationsLeagueMovement(promotions: promotions, relegations: relegations);
  }

  Future<void> postponeCountryMatch({
    required int matchId,
    required String newDate,
    String? reason,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.countryMatches,
      where: 'match_id = ?',
      whereArgs: <Object?>[matchId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final String originalDate = (rows.first['original_date'] as String?) ??
        (rows.first['date'] as String? ?? '');
    await db.update(
      t.countryMatches,
      <String, Object?>{
        'date': newDate,
        'original_date': originalDate,
        'reschedule_reason': reason ?? 'Postponed',
      },
      where: 'match_id = ?',
      whereArgs: <Object?>[matchId],
    );
  }

  /// Returns all country matches for [tournamentId] in [seasonId].
  Future<List<CountryMatch>> matchesForTournament({
    required int seasonId,
    required int tournamentId,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.countryMatches,
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: <Object?>[seasonId, tournamentId],
      orderBy: 'date ASC, match_id ASC',
    );
    return rows.map(CountryMatch.fromMap).toList();
  }
}

class NationsLeagueMovement {
  const NationsLeagueMovement({
    required this.promotions,
    required this.relegations,
  });
  final Map<int, List<int>> promotions;
  final Map<int, List<int>> relegations;
}
