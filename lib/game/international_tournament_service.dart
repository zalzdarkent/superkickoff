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

    // Map each country to its respective group_id in this tournament
    final Map<int, int?> countryGroupMap = <int, int?>{};
    for (final Map<String, Object?> m in matches) {
      final int home = (m['home_country_id'] as int?) ?? 0;
      final int away = (m['away_country_id'] as int?) ?? 0;
      final int? gid = (m['group_id'] as int?) ?? groupId;
      if (home > 0) countryGroupMap[home] = gid;
      if (away > 0) countryGroupMap[away] = gid;
    }

    // Also include countries that have scheduled matches in this tournament/group
    final List<Map<String, Object?>> scheduled = await db.query(
      t.countryMatches,
      where: 'tournament_id = ? AND season_id = ? ${groupId != null ? 'AND group_id = $groupId' : ''}',
      whereArgs: <Object?>[tournamentId, seasonId],
    );
    for (final Map<String, Object?> m in scheduled) {
      final int home = (m['home_country_id'] as int?) ?? 0;
      final int away = (m['away_country_id'] as int?) ?? 0;
      final int? gid = (m['group_id'] as int?) ?? groupId;
      if (home > 0) countryGroupMap[home] = gid;
      if (away > 0) countryGroupMap[away] = gid;
    }

    final Map<int, InternationalStandingRow> rows = <int, InternationalStandingRow>{};
    for (final MapEntry<int, int?> entry in countryGroupMap.entries) {
      final int cId = entry.key;
      final Country? c = await _nationalService.getNationalTeam(cId);
      rows[cId] = InternationalStandingRow(
        countryId: cId,
        countryName: c?.name ?? 'Country $cId',
        groupId: entry.value ?? groupId,
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
    int startGroupId = 1,
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
      final int actualGroupId = startGroupId + g - 1;
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
          'group_id': actualGroupId,
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
    int? userCountryId,
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
      final List<Country> topList = countries.take(32).toList();
      if (userCountryId != null && !topList.any((c) => c.countryId == userCountryId)) {
        final Country? userC = await _nationalService.getNationalTeam(userCountryId);
        if (userC != null) {
          if (topList.length >= 32) topList.removeLast();
          topList.add(userC);
        }
      }
      countries = topList;
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

    final List<Map<String, Object?>> pendingRows = <Map<String, Object?>>[];
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

        pendingRows.add(<String, Object?>{
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
        });
      }
    }

    if (pendingRows.isNotEmpty) {
      await db.transaction((Transaction txn) async {
        final Batch batch = txn.batch();
        for (final Map<String, Object?> row in pendingRows) {
          batch.insert(
            t.countryMatches,
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        final List<Object?> results = await batch.commit();
        for (int i = 0; i < pendingRows.length; i++) {
          final int id = (results[i] as int?) ?? 0;
          friendlies.add(
            CountryMatch.fromMap(<String, Object?>{
              ...pendingRows[i],
              'match_id': id,
            }),
          );
        }
      });
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

  // ------------------------------------------------ Major Tournaments & Qualifiers

  /// Schedules continental qualifiers (AFC, UEFA, CONMEBOL, CAF, CONCACAF) for World Cup or Continental Cups.
  Future<List<CountryMatch>> scheduleQualifiers({
    required int seasonId,
    required int tournamentId,
    required InternationalWindow window1,
    required InternationalWindow window2,
    int? userCountryId,
  }) async {
    final List<CountryMatch> allFixtures = <CountryMatch>[];
    final List<Country> allNations = await _nationalService.getNationalTeams();
    if (allNations.isEmpty) return allFixtures;

    // Dates from window 1 (e.g. October) and window 2 (e.g. March)
    final DateTime? w1Start = DateTime.tryParse(window1.startDate);
    final DateTime? w1End = DateTime.tryParse(window1.endDate);
    final DateTime? w2Start = DateTime.tryParse(window2.startDate);
    final DateTime? w2End = DateTime.tryParse(window2.endDate);

    final String d1 = w1Start != null ? w1Start.add(const Duration(days: 2)).toIso8601String().substring(0, 10) : window1.startDate;
    final String d2 = w1End != null ? w1End.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10) : window1.endDate;
    final String d3 = w2Start != null ? w2Start.add(const Duration(days: 2)).toIso8601String().substring(0, 10) : window2.startDate;
    final String d4 = w2End != null ? w2End.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10) : window2.endDate;
    final List<String> qualDates = <String>[d1, d2, d3, d4];

    // Partition countries by confederation:
    // 5: AFC (Asia), 3: UEFA (Europe), 2: CONMEBOL, 4: CAF (Africa), 1: CONCACAF
    final Map<int, List<Country>> confMap = <int, List<Country>>{};
    for (final Country c in allNations) {
      confMap.putIfAbsent(c.confederation, () => <Country>[]).add(c);
    }

    int currentGroupId = 1;
    for (final int conf in const <int>[5, 3, 2, 4, 1]) {
      final List<Country> confCountries = confMap[conf] ?? <Country>[];
      if (confCountries.length < 4) continue;

      // Take top 16 nations per conf (and ensure user country is included if in this conf)
      confCountries.sort((Country a, Country b) => b.power.compareTo(a.power));
      final List<Country> pool = confCountries.take(16).toList();
      if (userCountryId != null && confCountries.any((Country c) => c.countryId == userCountryId)) {
        if (!pool.any((Country c) => c.countryId == userCountryId)) {
          final Country userC = confCountries.firstWhere((Country c) => c.countryId == userCountryId);
          if (pool.isNotEmpty) pool.removeLast();
          pool.add(userC);
        }
      }

      // Schedule into groups of 4 (4 matchdays)
      final List<int> pIds = pool.map((Country c) => c.countryId).toList();
      final List<CountryMatch> fixtures = await scheduleGroupStage(
        tournamentId: tournamentId,
        seasonId: seasonId,
        participatingCountryIds: pIds,
        matchDates: qualDates,
        groupSize: 4,
        groupCount: (pIds.length / 4).floor(),
        doubleRoundRobin: false,
        windowId: window1.windowId,
        startGroupId: currentGroupId,
      );
      allFixtures.addAll(fixtures);
      currentGroupId += (pIds.length / 4).floor();
    }

    return allFixtures;
  }

  /// Schedules FIFA World Cup Final Tournament (48 teams in 12 groups of 4, followed by Round of 32 -> Final).
  Future<List<CountryMatch>> scheduleWorldCupTournament({
    required int seasonId,
    required InternationalWindow summerWindow,
    int? userCountryId,
  }) async {
    final List<Country> allNations = await _nationalService.getNationalTeams();
    allNations.sort((Country a, Country b) => b.power.compareTo(a.power));

    // Top 48 nations worldwide
    final List<Country> participants = allNations.take(48).toList();
    if (userCountryId != null && !participants.any((Country c) => c.countryId == userCountryId)) {
      final Country? userC = await _nationalService.getNationalTeam(userCountryId);
      if (userC != null) {
        if (participants.isNotEmpty) participants.removeLast();
        participants.add(userC);
      }
    }

    // Dates during Summer Window (June 11 - July 19)
    final DateTime start = DateTime.tryParse(summerWindow.startDate) ?? DateTime(2026, 6, 11);
    final List<String> groupDates = <String>[
      start.add(const Duration(days: 2)).toIso8601String().substring(0, 10),
      start.add(const Duration(days: 6)).toIso8601String().substring(0, 10),
      start.add(const Duration(days: 10)).toIso8601String().substring(0, 10),
    ];

    final List<int> pIds = participants.map((Country c) => c.countryId).toList();
    return scheduleGroupStage(
      tournamentId: t.tournamentWorldCup,
      seasonId: seasonId,
      participatingCountryIds: pIds,
      matchDates: groupDates,
      groupSize: 4,
      groupCount: 12, // 12 groups (A - L)
      doubleRoundRobin: false,
      windowId: summerWindow.windowId,
      startGroupId: 1,
    );
  }

  /// Schedules Continental Championship (e.g. AFC Asian Cup or UEFA EURO - 24 teams in 6 groups of 4).
  Future<List<CountryMatch>> scheduleContinentalChampionship({
    required int tournamentId,
    required int seasonId,
    required InternationalWindow summerWindow,
    required int confederation,
    int? userCountryId,
  }) async {
    final List<Country> confNations = await _nationalService.getNationalTeams(confederation: confederation);
    confNations.sort((Country a, Country b) => b.power.compareTo(a.power));

    final List<Country> participants = confNations.take(24).toList();
    if (userCountryId != null && confNations.any((Country c) => c.countryId == userCountryId)) {
      if (!participants.any((Country c) => c.countryId == userCountryId)) {
        final Country userC = confNations.firstWhere((Country c) => c.countryId == userCountryId);
        if (participants.isNotEmpty) participants.removeLast();
        participants.add(userC);
      }
    }

    if (participants.length < 8) return <CountryMatch>[];

    final DateTime start = DateTime.tryParse(summerWindow.startDate) ?? DateTime(2027, 6, 11);
    final List<String> groupDates = <String>[
      start.add(const Duration(days: 2)).toIso8601String().substring(0, 10),
      start.add(const Duration(days: 6)).toIso8601String().substring(0, 10),
      start.add(const Duration(days: 10)).toIso8601String().substring(0, 10),
    ];

    final List<int> pIds = participants.map((Country c) => c.countryId).toList();
    final int groupCount = (pIds.length / 4).floor();

    return scheduleGroupStage(
      tournamentId: tournamentId,
      seasonId: seasonId,
      participatingCountryIds: pIds,
      matchDates: groupDates,
      groupSize: 4,
      groupCount: groupCount,
      doubleRoundRobin: false,
      windowId: summerWindow.windowId,
      startGroupId: 1,
    );
  }

  /// Automatically progresses completed group stage to knockout stage,
  /// or progresses completed knockout rounds to the next round (R32 -> R16 -> QF -> SF -> Final).
  Future<void> checkAndAdvanceInternationalKnockouts({
    required int seasonId,
    required String currentDate,
  }) async {
    // Check all active international tournaments in this season
    const List<int> majorTournaments = <int>[
      t.tournamentWorldCup,
      t.tournamentAsianCup,
      t.tournamentEuro,
      t.tournamentAseanChampionship,
      t.tournamentFifaAseanCup,
    ];

    for (final int tId in majorTournaments) {
      final List<CountryMatch> allMatches = await matchesForTournament(
        seasonId: seasonId,
        tournamentId: tId,
      );
      if (allMatches.isEmpty) continue;

      // 1. Check if group stage (phase 0) is fully completed
      final List<CountryMatch> groupMatches = allMatches.where((CountryMatch m) => m.phase == 0).toList();
      final bool groupComplete = groupMatches.isNotEmpty && groupMatches.every((CountryMatch m) => m.status == t.matchFinished);

      // Check if knockout phase 1 (Round 1) exists
      final bool hasPhase1 = allMatches.any((CountryMatch m) => m.phase == 1);

      if (groupComplete && !hasPhase1) {
        // Advance from group stage to Phase 1 knockout!
        final Set<int> groupIds = groupMatches.map((CountryMatch m) => m.groupId ?? 1).toSet();
        final List<int> qualified = <int>[];

        for (final int gid in groupIds.toList()..sort()) {
          final List<InternationalStandingRow> standings = await getStandings(
            tournamentId: tId,
            seasonId: seasonId,
            groupId: gid,
          );
          if (standings.isNotEmpty) qualified.add(standings.first.countryId);
          if (standings.length >= 2) qualified.add(standings[1].countryId);
        }

        // For World Cup (12 groups), top 2 (24) + top 8 best thirds = 32 teams
        if (tId == t.tournamentWorldCup && groupIds.length == 12) {
          final List<InternationalStandingRow> bestThirds = await getBestThirdPlacedTeams(
            tournamentId: tId,
            seasonId: seasonId,
            groupCount: 12,
            advanceCount: 8,
          );
          for (final InternationalStandingRow row in bestThirds) {
            if (!qualified.contains(row.countryId)) {
              qualified.add(row.countryId);
            }
          }
        } else if ((tId == t.tournamentAsianCup || tId == t.tournamentEuro) && groupIds.length == 6) {
          // 6 groups, top 2 (12) + top 4 best thirds = 16 teams
          final List<InternationalStandingRow> bestThirds = await getBestThirdPlacedTeams(
            tournamentId: tId,
            seasonId: seasonId,
            groupCount: 6,
            advanceCount: 4,
          );
          for (final InternationalStandingRow row in bestThirds) {
            if (!qualified.contains(row.countryId)) {
              qualified.add(row.countryId);
            }
          }
        }

        if (qualified.length >= 2) {
          // Schedule Round 1 of knockouts 4 days after group stage finishes
          final DateTime cur = DateTime.tryParse(currentDate) ?? DateTime.now();
          final String nextRoundDate = cur.add(const Duration(days: 3)).toIso8601String().substring(0, 10);
          await scheduleKnockoutRound(
            tournamentId: tId,
            seasonId: seasonId,
            phase: 1,
            qualifiedCountryIds: qualified,
            matchDate: nextRoundDate,
          );
        }
      } else if (hasPhase1) {
        // 2. Check if latest knockout phase is complete, then advance to next phase
        final int maxPhase = allMatches.map((CountryMatch m) => m.phase).reduce(max);
        final List<CountryMatch> latestPhaseMatches = allMatches.where((CountryMatch m) => m.phase == maxPhase).toList();
        final bool latestDone = latestPhaseMatches.isNotEmpty &&
            latestPhaseMatches.every((CountryMatch m) => m.status == t.matchFinished);

        if (latestDone && latestPhaseMatches.length > 1) {
          final DateTime cur = DateTime.tryParse(currentDate) ?? DateTime.now();
          final String nextRoundDate = cur.add(const Duration(days: 4)).toIso8601String().substring(0, 10);
          await advanceKnockoutProgression(
            tournamentId: tId,
            seasonId: seasonId,
            currentPhase: maxPhase,
            nextRoundDate: nextRoundDate,
          );
        }
      }
    }
  }

  /// Fetches player statistics for a specific international match from `match_players_countries`.
  Future<List<Map<String, Object?>>> matchPlayersForCountryMatch(int matchId) async {
    return db.rawQuery(
      '''
      SELECT mpc.player_id,
             p.name AS player_name,
             pos.abbreviation AS position_abbr,
             mpc.country_id,
             mpc.starter,
             mpc.minutes,
             mpc.rating,
             mpc.mvp,
             mpc.goals,
             mpc.assists,
             mpc.yellow_cards,
             mpc.red_cards
      FROM ${t.matchPlayersCountries} mpc
      JOIN ${t.players} p ON p.player_id = mpc.player_id
      LEFT JOIN positions pos ON pos.position_id = p.position_id
      WHERE mpc.match_id = ?
      ORDER BY mpc.country_id ASC, mpc.starter DESC, mpc.minutes DESC, mpc.rating DESC
      ''',
      <Object?>[matchId],
    );
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
