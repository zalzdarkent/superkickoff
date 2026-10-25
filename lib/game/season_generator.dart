import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';

/// Builds a new career season:
///  * season row + tournament links
///  * season_teams registration for every participating club
///  * double round-robin league fixtures with weekly dates
///  * first national-cup knockout round (mid-week dates, later rounds are
///    generated lazily by [scheduleCupRound] once the previous phase ends)
class SeasonGenerator {
  SeasonGenerator(this.db, {Random? random}) : _rng = random ?? Random();

  final Database db;
  final Random _rng;

  DateTime _startDate = DateTime(2025, 8, 9);

  Future<CareerPlan> generateCareer({
    required int countryId,
    required Tournament league,
    required Tournament? cup,
    List<Tournament> internationals = const <Tournament>[],
    List<Tournament> otherLeagues = const <Tournament>[],
    int startYear = 2025,
  }) async {
    _startDate = DateTime(startYear, 8, 9); // first Saturday of August-ish

    final List<Tournament> allDomesticLeagues = <Tournament>[
      league,
      ...otherLeagues.where((Tournament l) => l.tournamentId != league.tournamentId),
    ];

    final Season season = await _insertSeason(startYear);
    for (final Tournament tour in allDomesticLeagues) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });
    }
    if (cup != null) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': cup.tournamentId,
        'status': t.seasonTournamentActive,
      });
    }
    for (final Tournament tour in internationals) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });
    }

    // ------------------------------------------------ participants
    final Map<int, Team> allTeams = <int, Team>{};
    for (final Tournament lg in allDomesticLeagues) {
      List<Team> divTeams = await _teamsOf(countryId, lg.divisionId);
      final int maxDivTeams = lg.slots > 0 ? lg.slots : 24;
      if (divTeams.length > maxDivTeams) {
        divTeams = List<Team>.of(divTeams)
          ..sort((Team a, Team b) => b.power.compareTo(a.power));
        divTeams = divTeams.take(maxDivTeams).toList();
      }
      for (final Team tm in divTeams) {
        allTeams[tm.teamId] = tm;
      }
    }
    final List<Team> cupTeams = await _teamsOf(countryId, null);
    for (final Team tm in cupTeams) {
      allTeams[tm.teamId] = tm;
    }
    // Continental entrants: each country sends its top clubs by power.
    // Tiered cups (e.g. UCL/UEL/Conference or ACL Elite/Two/Challenge) exclude
    // clubs already invited to a higher tier. Super cups and world cups do not.
    final Map<int, List<int>> internationalEntrants = <int, List<int>>{};
    final Set<int> continentalInvites = <int>{};
    for (final Tournament tour in internationals) {
      final bool isSuperOrGlobal =
          tour.tournamentId == 54 ||
          tour.tournamentId == 56 ||
          tour.tournamentId == 163 ||
          tour.tournamentId == 1651;
      final List<Team> invited = await _internationalTeams(
        tour,
        exclude: isSuperOrGlobal ? const <int>{} : continentalInvites,
        beforeSeasonId: season.seasonId,
      );
      if (invited.length < 2) continue;
      final Map<int, Team> byId = <int, Team>{
        for (final Team tm in invited) tm.teamId: tm,
      };
      final List<int> entrants = seedByIdes(invited);
      internationalEntrants[tour.tournamentId] = entrants;
      if (!isSuperOrGlobal) {
        continentalInvites.addAll(entrants);
      }
      for (final int id in entrants) {
        allTeams[id] = byId[id]!;
      }
    }

    // ------------------------------------------------ registration
    // Coach per team comes from the team itself.
    for (final Team tm in allTeams.values) {
      await db.insert(t.seasonTeams, <String, Object?>{
        'team_id': tm.teamId,
        'season_id': season.seasonId,
        'coach_id': tm.coachId,
      });
    }

    // ------------------------------------------------ league fixtures
    final List<Map<String, Object?>> matchRows = <Map<String, Object?>>[];
    int userLeagueRounds = 0;
    for (final Tournament lg in allDomesticLeagues) {
      List<Team> divTeams = await _teamsOf(countryId, lg.divisionId);
      final int maxDivTeams = lg.slots > 0 ? lg.slots : 24;
      if (divTeams.length > maxDivTeams) {
        divTeams = List<Team>.of(divTeams)
          ..sort((Team a, Team b) => b.power.compareTo(a.power));
        divTeams = divTeams.take(maxDivTeams).toList();
      }
      final int teamCount = divTeams.length;
      final int r = teamCount >= 2 ? (teamCount - 1) * 2 : 0;
      if (lg.tournamentId == league.tournamentId) {
        userLeagueRounds = r;
      }
      if (teamCount >= 2) {
        final List<FixtureSlot> slots = doubleRoundRobin(
          divTeams.map((Team tm) => tm.teamId).toList(),
          _rng,
        );
        for (final FixtureSlot slot in slots) {
          matchRows.add(
            _matchRow(
              season.seasonId,
              lg.tournamentId,
              allTeams[slot.home]!,
              allTeams[slot.away]!,
              round: slot.round,
              phase: 1,
              leg: slot.leg,
              date: _iso(_leagueDate(slot.round)),
            ),
          );
        }
      }
    }

    // ------------------------------------------------ cup first round
    int cupPhases = 0;
    if (cup != null && cupTeams.length >= 4) {
      final List<int> surviving = seedByIdes(cupTeams);
      cupPhases = knockoutRounds(surviving.length);
      final DateTime cupDate = _cupDate(1, userLeagueRounds);
      await scheduleCupRound(
        season.seasonId,
        cup.tournamentId,
        surviving,
        phase: 1,
        date: cupDate,
        allTeams: allTeams,
      );
    }

    // ------------------------------------ continental group stage / round 1
    int internationalIndex = 0;
    int superCupIndex = 0;
    for (final MapEntry<int, List<int>> entry
        in internationalEntrants.entries) {
      final bool isSuperCup = entry.key == 54 || entry.key == 1651;
      final DateTime start = isSuperCup
          ? _startDate.subtract(Duration(days: 4 + (superCupIndex++ * 3)))
          : _internationalDate(internationalIndex++);
      if (entry.value.length >= 8) {
        await scheduleGroupStage(
          season.seasonId,
          entry.key,
          entry.value,
          start: start,
          allTeams: allTeams,
        );
      } else {
        await scheduleCupRound(
          season.seasonId,
          entry.key,
          entry.value,
          phase: 1,
          date: start,
          allTeams: allTeams,
        );
      }
    }

    await _insertMatches(matchRows);
    await resolveFixtureClashes(season.seasonId);
    await repairSelfMatches(season.seasonId);
    return CareerPlan(
      season: season,
      leagueTournamentId: league.tournamentId,
      cupTournamentId: cup?.tournamentId,
      leagueRounds: userLeagueRounds,
      cupRounds: cupPhases,
      teamCount: allTeams.length,
      matchCount: matchRows.length,
      internationalTournamentIds: internationalEntrants.keys.toList(),
    );
  }

  /// Adds continental cups to a season that was generated before the feature
  /// existed. Existing careers keep their domestic fixtures untouched.
  Future<int> addInternationalCups({
    required Season season,
    required List<Tournament> internationals,
    required Map<int, Team> teamCache,
  }) async {
    _startDate = DateTime(season.startYear, 8, 9);
    int added = 0;
    int superCupIndex = 0;
    // Clubs already playing a tiered continental cup must not be invited again.
    final List<Map<String, Object?>> playing = await db.rawQuery(
      '''
      SELECT DISTINCT home_team_id AS id FROM matches
      WHERE season_id = ? AND tournament_id IN (49, 51, 135, 99, 164, 1650, 52, 53, 50, 100)
      UNION
      SELECT DISTINCT away_team_id FROM matches
      WHERE season_id = ? AND tournament_id IN (49, 51, 135, 99, 164, 1650, 52, 53, 50, 100)
    ''',
      <Object?>[season.seasonId, season.seasonId],
    );
    final Set<int> continentalInvites = <int>{
      for (final Map<String, Object?> row in playing) row['id'] as int,
    };
    for (final Tournament tour in internationals) {
      final List<Map<String, Object?>> linked = await db.query(
        t.seasonTournaments,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[season.seasonId, tour.tournamentId],
        limit: 1,
      );
      if (linked.isNotEmpty) continue;
      final bool isSuperOrGlobal =
          tour.tournamentId == 54 ||
          tour.tournamentId == 56 ||
          tour.tournamentId == 163 ||
          tour.tournamentId == 1651;
      final List<Team> invited = await _internationalTeams(
        tour,
        exclude: isSuperOrGlobal ? const <int>{} : continentalInvites,
        beforeSeasonId: season.seasonId,
      );
      if (invited.length < 2) continue;
      final Map<int, Team> byId = <int, Team>{
        for (final Team tm in invited) tm.teamId: tm,
      };
      final List<int> entrants = seedByIdes(invited);
      if (!isSuperOrGlobal) {
        continentalInvites.addAll(entrants);
      }

      final List<Map<String, Object?>> registered = await db.query(
        t.seasonTeams,
        columns: <String>['team_id'],
        where: 'season_id = ?',
        whereArgs: <Object?>[season.seasonId],
      );
      final Set<int> registeredIds = <int>{
        for (final Map<String, Object?> row in registered)
          row['team_id'] as int,
      };
      for (final int id in entrants) {
        final Team team = byId[id]!;
        teamCache[id] = team;
        if (registeredIds.contains(id)) continue;
        await db.insert(t.seasonTeams, <String, Object?>{
          'team_id': id,
          'season_id': season.seasonId,
          'coach_id': team.coachId,
        });
      }
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });

      final List<Map<String, Object?>> dateRows = await db.rawQuery(
        '''
        SELECT MIN(date) AS next_date FROM matches
        WHERE season_id = ? AND status = ?
      ''',
        <Object?>[season.seasonId, t.matchScheduled],
      );
      final String? nextDate = dateRows.isEmpty
          ? null
          : dateRows.first['next_date'] as String?;
      final DateTime base = DateTime.tryParse(nextDate ?? '') ?? _startDate;
      final bool isSuperCup =
          tour.tournamentId == 54 || tour.tournamentId == 1651;
      final DateTime date = isSuperCup
          ? _startDate.subtract(Duration(days: 4 + (superCupIndex++ * 3)))
          : _nextThursday(base.add(Duration(days: 7 * (added * 6 + 1))));
      if (entrants.length >= 8) {
        await scheduleGroupStage(
          season.seasonId,
          tour.tournamentId,
          entrants,
          start: date,
          allTeams: teamCache,
        );
      } else {
        await scheduleCupRound(
          season.seasonId,
          tour.tournamentId,
          entrants,
          phase: 1,
          date: date,
          allTeams: teamCache,
        );
      }
      added++;
    }
    await resolveFixtureClashes(season.seasonId);
    await repairSelfMatches(season.seasonId);
    return added;
  }

  /// Adds domestic lower division leagues to an existing season if they weren't
  /// generated yet.
  Future<int> addDomesticLeagues({
    required Season season,
    required int countryId,
    required List<Tournament> leagues,
    required Map<int, Team> teamCache,
    String? currentDate,
  }) async {
    _startDate = DateTime(season.startYear, 8, 9);
    int added = 0;
    final List<Map<String, Object?>> matchRows = <Map<String, Object?>>[];

    for (final Tournament tour in leagues) {
      final List<Map<String, Object?>> linked = await db.query(
        t.seasonTournaments,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[season.seasonId, tour.tournamentId],
        limit: 1,
      );
      if (linked.isNotEmpty) continue;

      List<Team> divTeams = await _teamsOf(countryId, tour.divisionId);
      final int maxDivTeams = tour.slots > 0 ? tour.slots : 24;
      if (divTeams.length > maxDivTeams) {
        divTeams = List<Team>.of(divTeams)
          ..sort((Team a, Team b) => b.power.compareTo(a.power));
        divTeams = divTeams.take(maxDivTeams).toList();
      }
      if (divTeams.length < 2) continue;

      for (final Team tm in divTeams) {
        teamCache[tm.teamId] = tm;
      }

      final List<Map<String, Object?>> registered = await db.query(
        t.seasonTeams,
        columns: <String>['team_id'],
        where: 'season_id = ?',
        whereArgs: <Object?>[season.seasonId],
      );
      final Set<int> registeredIds = <int>{
        for (final Map<String, Object?> row in registered)
          row['team_id'] as int,
      };
      for (final Team tm in divTeams) {
        if (!registeredIds.contains(tm.teamId)) {
          await db.insert(t.seasonTeams, <String, Object?>{
            'team_id': tm.teamId,
            'season_id': season.seasonId,
            'coach_id': tm.coachId,
          });
        }
      }

      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });

      final List<FixtureSlot> slots = doubleRoundRobin(
        divTeams.map((Team tm) => tm.teamId).toList(),
        _rng,
      );
      for (final FixtureSlot slot in slots) {
        matchRows.add(
          _matchRow(
            season.seasonId,
            tour.tournamentId,
            teamCache[slot.home]!,
            teamCache[slot.away]!,
            round: slot.round,
            phase: 1,
            leg: slot.leg,
            date: _iso(_leagueDate(slot.round)),
          ),
        );
      }
      added++;
    }

    if (matchRows.isNotEmpty) {
      await _insertMatches(matchRows);
      await repairSelfMatches(season.seasonId);

      // If season is underway, simulate past scheduled matches prior to currentDate
      if (currentDate != null) {
        final List<Map<String, Object?>> pastMatches = await db.query(
          t.matches,
          where: 'season_id = ? AND date < ? AND status = ?',
          whereArgs: <Object?>[season.seasonId, currentDate, t.matchScheduled],
        );
        if (pastMatches.isNotEmpty) {
          final Batch batch = db.batch();
          for (final Map<String, Object?> row in pastMatches) {
            final int matchId = row['match_id'] as int;
            final int homeId = row['home_team_id'] as int;
            final int awayId = row['away_team_id'] as int;
            final Team? home = teamCache[homeId];
            final Team? away = teamCache[awayId];
            if (home != null && away != null) {
              final double homeAdv = 1.1;
              final double homeRoll = _rng.nextDouble() * (home.power * homeAdv);
              final double awayRoll = _rng.nextDouble() * away.power;
              final int homeGoals = homeRoll > awayRoll + 15
                  ? 2 + _rng.nextInt(3)
                  : (homeRoll > awayRoll ? 1 + _rng.nextInt(2) : _rng.nextInt(2));
              final int awayGoals = awayRoll > homeRoll + 15
                  ? 2 + _rng.nextInt(3)
                  : (awayRoll > homeRoll ? 1 + _rng.nextInt(2) : _rng.nextInt(2));
              final int? winnerId = homeGoals > awayGoals
                  ? homeId
                  : (awayGoals > homeGoals ? awayId : null);
              batch.update(
                t.matches,
                <String, Object?>{
                  'status': t.matchFinished,
                  'home_goals': homeGoals,
                  'away_goals': awayGoals,
                  'winner_id': winnerId,
                },
                where: 'match_id = ?',
                whereArgs: <Object?>[matchId],
              );
            }
          }
          await batch.commit(noResult: true);
        }
      }
    }
    return added;
  }

  DateTime _nextThursday(DateTime from) {
    DateTime d = from;
    while (d.weekday != DateTime.thursday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  /// Schedules 3 pre-season friendly matches for [userTeamId] before the league season kicks off.
  Future<void> schedulePreSeasonFriendlies({
    required int seasonId,
    required int userTeamId,
    required Map<int, Team> allTeams,
  }) async {
    final Team? userTeam = allTeams[userTeamId];
    if (userTeam == null) return;

    final List<Team> candidates = allTeams.values
        .where((Team t) => t.teamId != userTeamId)
        .toList();
    if (candidates.length < 3) return;
    candidates.shuffle(_rng);

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    final List<DateTime> dates = <DateTime>[
      _startDate.subtract(const Duration(days: 17)),
      _startDate.subtract(const Duration(days: 10)),
      _startDate.subtract(const Duration(days: 3)),
    ];

    for (int i = 0; i < 3; i++) {
      final Team opp = candidates[i];
      final bool home = i % 2 == 0;
      rows.add(
        _matchRow(
          seasonId,
          9999,
          home ? userTeam : opp,
          home ? opp : userTeam,
          round: i + 1,
          phase: 0,
          leg: 1,
          date: _iso(dates[i]),
        ),
      );
    }
    await _insertMatches(rows);
  }

  /// Builds a group stage: clubs are spread snake-style over groups of four,
  /// then play a double round robin. The top two of every group advance to
  /// the knockout rounds, which [generateCareer] leaves for later.
  Future<int> scheduleGroupStage(
    int seasonId,
    int tournamentId,
    List<int> entrants, {
    required DateTime start,
    required Map<int, Team> allTeams,
  }) async {
    final List<int> sorted = entrants.toSet().toList()
      ..sort(
        (int a, int b) =>
            (allTeams[b]?.power ?? 0).compareTo(allTeams[a]?.power ?? 0),
      );
    final int groupCount = sorted.length ~/ 4;
    if (groupCount < 1) return 0;
    final List<List<int>> groups = List<List<int>>.generate(
      groupCount,
      (_) => <int>[],
    );
    for (int i = 0; i < sorted.length; i++) {
      final int round = i ~/ groupCount;
      final int slot = i % groupCount;
      final int index = round.isEven ? slot : groupCount - 1 - slot;
      groups[index].add(sorted[i]);
    }

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (int g = 0; g < groups.length; g++) {
      final List<FixtureSlot> slots = doubleRoundRobin(groups[g], _rng);
      for (final FixtureSlot slot in slots) {
        final Team? home = allTeams[slot.home];
        final Team? away = allTeams[slot.away];
        if (home == null || away == null) continue;
        rows.add(
          _matchRow(
            seasonId,
            tournamentId,
            home,
            away,
            round: slot.round,
            phase: 0,
            leg: slot.leg,
            date: _iso(start.add(Duration(days: 7 * (slot.round - 1)))),
            groupId: g + 1,
          ),
        );
      }
    }
    await _insertMatches(rows);
    return groups.length;
  }

  /// Schedules the NEXT knockout round once a cup phase fully finished.
  /// [survivors] are the winning team ids (byes included). When [pairs] is
  /// provided, explicit match pairings are scheduled instead of power-seeding.
  /// Returns the number of matches scheduled.
  Future<int> scheduleCupRound(
    int seasonId,
    int cupTournamentId,
    List<int> survivors, {
    required int phase,
    required DateTime date,
    required Map<int, Team> allTeams,
    List<(int, int)>? pairs,
  }) async {
    final List<Map<String, Object?>> tourRows = await db.query(
      t.tournaments,
      columns: <String>['rounds'],
      where: 'tournament_id = ?',
      whereArgs: <Object?>[cupTournamentId],
      limit: 1,
    );
    final int roundsSetting = tourRows.isEmpty
        ? 1
        : ((tourRows.first['rounds'] as int?) ?? 1);
    final int tieCount = pairs != null ? pairs.length : (survivors.length ~/ 2);
    // Knockout rounds before the final are 2-legged if the tournament setting is rounds == 2.
    final bool twoLegged = roundsSetting == 2 && tieCount > 1;

    final List<(int, int)> matchPairs = pairs ?? <(int, int)>[];
    if (pairs == null) {
      final List<int> ids = List<int>.of(survivors)
        ..sort(
          (int a, int b) =>
              (allTeams[b]?.power ?? 0).compareTo(allTeams[a]?.power ?? 0),
        );
      while (ids.length > 1) {
        matchPairs.add((ids.removeAt(0), ids.removeLast()));
      }
    }

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final (int a, int b) in matchPairs) {
      if (a == b) continue;
      final Team? homeTeam = allTeams[a];
      final Team? awayTeam = allTeams[b];
      if (homeTeam == null || awayTeam == null) continue;
      rows.add(
        _matchRow(
          seasonId,
          cupTournamentId,
          homeTeam,
          awayTeam,
          round: phase,
          phase: phase,
          leg: 1,
          date: _iso(date),
        ),
      );
      if (twoLegged) {
        // Return leg (Leg 2) played ~7 days later with reversed venues.
        rows.add(
          _matchRow(
            seasonId,
            cupTournamentId,
            awayTeam,
            homeTeam,
            round: phase,
            phase: phase,
            leg: 2,
            date: _iso(date.add(const Duration(days: 7))),
          ),
        );
      }
    }
    await _insertMatches(rows);
    return rows.length;
  }

  // ---------------------------------------------------------------- helpers

  Future<Season> _insertSeason(int startYear) async {
    final Map<String, Object?> values = <String, Object?>{
      'name': 'Season $startYear/${(startYear + 1) % 100}',
      'start_year': startYear,
      'end_year': startYear + 1,
    };
    final int id = await db.insert(t.seasons, values);
    final rows = await db.query(
      t.seasons,
      where: 'season_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return Season.fromMap(rows.first);
  }

  /// Clubs invited to a continental competition, honouring each country's
  /// slot count. Only top-division clubs qualify and [exclude] keeps a club
  /// out of a second competition in the same season.
  Future<List<Team>> _internationalTeams(
    Tournament tour, {
    Set<int> exclude = const <int>{},
    int? beforeSeasonId,
  }) async {
    if (tour.tournamentId == 56) {
      return _intercontinentalTeams(beforeSeasonId: beforeSeasonId);
    }
    final _ChampionsFeed? feed = _championsFeeds[tour.tournamentId];
    if (feed != null) return _championsOf(tour, feed, beforeSeasonId);
    final rows = await db.query(
      t.internationalSlots,
      where: 'tournament_id = ?',
      whereArgs: <Object?>[tour.tournamentId],
    );
    final List<Team> teams = <Team>[];
    final Set<int> addedIds = <int>{};
    for (final Map<String, Object?> row in rows) {
      final int countryId = row['country_id'] as int;
      final int slots = (row['slots'] as int?) ?? 0;
      if (slots <= 0) continue;
      final List<Team> clubs = await _continentalQualifiers(
        countryId,
        beforeSeasonId: beforeSeasonId,
      );
      final List<Team> picked = clubs
          .where(
            (Team tm) =>
                !exclude.contains(tm.teamId) && addedIds.add(tm.teamId),
          )
          .take(slots)
          .toList();
      teams.addAll(picked);
    }
    return teams;
  }

  /// Super cups and world cups are contested by continental champions.
  static const Map<int, _ChampionsFeed> _championsFeeds = <int, _ChampionsFeed>{
    54: _ChampionsFeed(<int>[49, 51], 2), // UEFA Super Cup
    1651: _ChampionsFeed(<int>[99, 164], 2), // AFC Super Cup
    163: _ChampionsFeed(<int>[49, 52, 99, 50, 100, 51, 53, 164, 135, 1650], 16),
  };

  static const List<_IntercontinentalRegion> _intercontinentalRegions =
      <_IntercontinentalRegion>[
        _IntercontinentalRegion(49, 3), // UEFA
        _IntercontinentalRegion(52, 2), // CONMEBOL
        _IntercontinentalRegion(99, 5), // AFC
        _IntercontinentalRegion(100, 4), // CAF
        _IntercontinentalRegion(50, 1), // CONCACAF
        _IntercontinentalRegion(null, 6), // OFC
      ];

  Future<List<Team>> _intercontinentalTeams({int? beforeSeasonId}) async {
    final List<Team> teams = <Team>[];
    final Set<int> selectedIds = <int>{};
    for (final _IntercontinentalRegion region in _intercontinentalRegions) {
      Team? selected;
      if (region.tournamentId != null && beforeSeasonId != null) {
        final (int, int)? finalTeams = await _lastFinal(
          region.tournamentId!,
          beforeSeasonId,
        );
        if (finalTeams != null) {
          final List<Map<String, Object?>> rows = await db.query(
            t.teams,
            where: 'team_id = ?',
            whereArgs: <Object?>[finalTeams.$1],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final Team champion = Team.fromMap(rows.first);
            if (selectedIds.add(champion.teamId)) selected = champion;
          }
        }
      }
      if (selected == null) {
        final List<Map<String, Object?>> rows = await db.rawQuery(
          '''
          SELECT tm.* FROM ${t.teams} tm
          JOIN ${t.countries} c ON c.country_id = tm.country_id
          WHERE tm.division = 1 AND c.confederation = ?
          ORDER BY tm.power DESC
          LIMIT 20
          ''',
          <Object?>[region.confederation],
        );
        for (final Map<String, Object?> row in rows) {
          final Team candidate = Team.fromMap(row);
          if (selectedIds.add(candidate.teamId)) {
            selected = candidate;
            break;
          }
        }
      }
      if (selected != null) teams.add(selected);
    }
    return teams;
  }

  /// Champions of the feeder cups from the latest finished season, then
  /// runners-up in the same order, up to the field size. Gaps (first season,
  /// unfinished cups) are filled with the strongest clubs of the countries
  /// that hold slots, by power - never at random.
  Future<List<Team>> _championsOf(
    Tournament tour,
    _ChampionsFeed feed,
    int? beforeSeasonId,
  ) async {
    final List<int> champions = <int>[];
    final List<int> runnersUp = <int>[];
    if (beforeSeasonId != null) {
      for (final int cupId in feed.cups) {
        final (int, int)? finalists = await _lastFinal(cupId, beforeSeasonId);
        if (finalists == null) continue;
        champions.add(finalists.$1);
        runnersUp.add(finalists.$2);
      }
    }
    final List<int> ids = <int>[];
    for (final int id in <int>[...champions, ...runnersUp]) {
      if (ids.length < feed.size && !ids.contains(id)) ids.add(id);
    }
    final List<Team> teams = <Team>[];
    for (final int id in ids) {
      final List<Map<String, Object?>> rows = await db.query(
        t.teams,
        where: 'team_id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isNotEmpty) teams.add(Team.fromMap(rows.first));
    }
    if (teams.length >= feed.size) return teams;

    final List<Map<String, Object?>> slotRows = tour.tournamentId == 56
        ? await db.rawQuery('''
        SELECT DISTINCT country_id, 1 AS slots
        FROM ${t.internationalSlots}
        WHERE tournament_id IN (${feed.cups.join(',')})
        ''')
        : await db.query(
            t.internationalSlots,
            where: 'tournament_id = ?',
            whereArgs: <Object?>[tour.tournamentId],
          );
    final List<Team> pool = <Team>[];
    for (final Map<String, Object?> row in slotRows) {
      final List<Map<String, Object?>> clubs = await db.query(
        t.teams,
        where: 'country_id = ? AND division = 1',
        whereArgs: <Object?>[row['country_id']],
        orderBy: 'power DESC',
        limit: (row['slots'] as int?) ?? 0,
      );
      pool.addAll(clubs.map(Team.fromMap));
    }
    pool.sort((Team a, Team b) => b.power.compareTo(a.power));
    for (final Team club in pool) {
      if (teams.length >= feed.size) break;
      if (teams.every((Team tm) => tm.teamId != club.teamId)) teams.add(club);
    }
    return teams;
  }

  /// (champion, runner-up) of the latest fully played edition of a cup before
  /// [beforeSeasonId], or null when none has finished.
  Future<(int, int)?> _lastFinal(int tournamentId, int beforeSeasonId) async {
    final List<Map<String, Object?>> seasons = await db.rawQuery(
      '''
      SELECT MAX(season_id) AS season_id FROM matches
      WHERE tournament_id = ? AND season_id < ?
    ''',
      <Object?>[tournamentId, beforeSeasonId],
    );
    final int? seasonId = seasons.isEmpty
        ? null
        : seasons.first['season_id'] as int?;
    if (seasonId == null) return null;
    final int open =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM matches WHERE season_id = ? '
            'AND tournament_id = ? AND status != ?',
            <Object?>[seasonId, tournamentId, t.matchFinished],
          ),
        ) ??
        0;
    if (open > 0) return null;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT home_team_id, away_team_id, winner_id FROM matches
      WHERE season_id = ? AND tournament_id = ?
        AND phase = (SELECT MAX(phase) FROM matches
                     WHERE season_id = ? AND tournament_id = ?)
        AND winner_id IS NOT NULL AND winner_id != 0
      LIMIT 1
    ''',
      <Object?>[seasonId, tournamentId, seasonId, tournamentId],
    );
    if (rows.isEmpty) return null;
    final int winner = rows.first['winner_id'] as int;
    final int home = rows.first['home_team_id'] as int;
    final int away = rows.first['away_team_id'] as int;
    return (winner, winner == home ? away : home);
  }

  /// Qualification follows the latest completed domestic table when one is
  /// available; a new save falls back to club strength.
  Future<List<Team>> _continentalQualifiers(
    int countryId, {
    int? beforeSeasonId,
  }) async {
    final List<Map<String, Object?>> clubRows = await db.query(
      t.teams,
      where: 'country_id = ? AND division = 1',
      whereArgs: <Object?>[countryId],
      orderBy: 'power DESC',
    );
    final List<Team> clubs = clubRows.map(Team.fromMap).toList();
    if (beforeSeasonId == null) return _fallbackQualifiers(clubs);
    final List<Map<String, Object?>> seasonRows = await db.rawQuery(
      '''
      SELECT st.season_id, tu.tournament_id
      FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tu.organization = ? AND tu.division_id = 1
        AND tc.country_id = ? AND st.season_id < ?
      ORDER BY st.season_id DESC
      LIMIT 1
    ''',
      <Object?>[t.orgLeague, countryId, beforeSeasonId],
    );
    if (seasonRows.isEmpty || seasonRows.first['season_id'] == null) {
      return _fallbackQualifiers(clubs);
    }
    final int seasonId = seasonRows.first['season_id'] as int;
    final int tournamentId = seasonRows.first['tournament_id'] as int;
    final List<Map<String, Object?>> results = await db.rawQuery(
      '''
      SELECT team_id, SUM(points) AS points,
             SUM(goals_for) - SUM(goals_against) AS goal_difference,
             SUM(goals_for) AS goals_for
      FROM (
        SELECT home_team_id AS team_id,
               CASE WHEN home_goals > away_goals THEN 3
                    WHEN home_goals = away_goals THEN 1 ELSE 0 END AS points,
               home_goals AS goals_for, away_goals AS goals_against
        FROM matches WHERE season_id = ? AND tournament_id = ? AND status = ?
        UNION ALL
        SELECT away_team_id AS team_id,
               CASE WHEN away_goals > home_goals THEN 3
                    WHEN away_goals = home_goals THEN 1 ELSE 0 END AS points,
               away_goals AS goals_for, home_goals AS goals_against
        FROM matches WHERE season_id = ? AND tournament_id = ? AND status = ?
      ) GROUP BY team_id
      ORDER BY points DESC, goal_difference DESC, goals_for DESC
    ''',
      <Object?>[
        seasonId,
        tournamentId,
        t.matchFinished,
        seasonId,
        tournamentId,
        t.matchFinished,
      ],
    );
    if (results.isEmpty) return _fallbackQualifiers(clubs);
    final Map<int, Team> byId = <int, Team>{
      for (final Team club in clubs) club.teamId: club,
    };
    final List<Team> ordered = <Team>[
      for (final Map<String, Object?> row in results)
        if (byId.remove(row['team_id']) case final Team club) club,
    ];
    ordered.addAll(byId.values);
    return ordered;
  }

  /// Countries outside the simulated domestic world have no table to qualify
  /// from. Rotate their leading clubs instead of selecting the same power list
  /// every season.
  List<Team> _fallbackQualifiers(List<Team> clubs) {
    final List<Team> leading = clubs.take(min(8, clubs.length)).toList()
      ..shuffle(_rng);
    return <Team>[...leading, ...clubs.skip(leading.length)];
  }

  Future<List<Team>> _teamsOf(int countryId, int? divisionId) async {
    final String where = divisionId == null
        ? 'country_id = ?'
        : 'country_id = ? AND division = ?';
    final List<Object?> args = divisionId == null
        ? <Object?>[countryId]
        : <Object?>[countryId, divisionId];
    final rows = await db.query(t.teams, where: where, whereArgs: args);
    return rows.map(Team.fromMap).toList();
  }

  Map<String, Object?> _matchRow(
    int seasonId,
    int tournamentId,
    Team home,
    Team away, {
    required int round,
    required int phase,
    required int leg,
    required String date,
    int? groupId,
  }) {
    return <String, Object?>{
      'tournament_id': tournamentId,
      'season_id': seasonId,
      'home_team_id': home.teamId,
      'away_team_id': away.teamId,
      'stadium_id': home.stadiumId,
      'round': round,
      'phase': phase,
      'group_id': groupId,
      'status': t.matchScheduled,
      'leg': leg,
      'date': date,
      'home_goals': null,
      'away_goals': null,
      'winner_id': null,
    };
  }

  Future<void> _insertMatches(List<Map<String, Object?>> rows) async {
    await db.transaction((Transaction txn) async {
      for (final Map<String, Object?> row in rows) {
        await txn.insert(t.matches, row);
      }
    });
  }

  DateTime _leagueDate(int round) =>
      _startDate.add(Duration(days: 7 * (round - 1)));

  /// Cup is on Wednesdays, interleaved: phase 1 mid-week before half-time.
  DateTime _cupDate(int phase, int leagueRounds) {
    final int spacing = max(2, leagueRounds ~/ 8);
    final int weekOffset = 2 + (phase - 1) * spacing;
    return _startDate.add(Duration(days: 7 * weekOffset - 3));
  }

  /// Continental rounds get their own mid-week slots (Tuesdays or Thursdays) so
  /// they never land on domestic cup dates (Wednesdays) or league matchdays (Saturdays).
  DateTime _internationalDate(int index) {
    final int dayOffset = index.isEven ? -4 : -2;
    final int weekOffset = 3 + (index ~/ 2) * 6;
    return _startDate.add(Duration(days: 7 * weekOffset + dayOffset));
  }

  /// Sorts teams by power (seeding) and returns their ids.
  /// Seeds the cup by club power and trims the field to the largest power of
  /// two that fits, which keeps every knockout round evenly paired.
  List<int> seedByIdes(List<Team> teams) {
    final Map<int, Team> unique = <int, Team>{
      for (final Team tm in teams) tm.teamId: tm,
    };
    final List<Team> sorted = unique.values.toList()
      ..sort((Team a, Team b) => b.power.compareTo(a.power));
    int bracket = 1;
    while (bracket * 2 <= sorted.length) {
      bracket *= 2;
    }
    return sorted.take(bracket).map((Team tm) => tm.teamId).toList();
  }

  /// How many knockout rounds until one winner remains: n -> ceil(n/2).
  static int knockoutRounds(int teamCount) {
    int rounds = 0;
    int size = teamCount;
    while (size > 1) {
      size = (size + 1) ~/ 2;
      rounds++;
    }
    return rounds;
  }

  /// Fixes any corrupted matches where a club was scheduled against itself.
  Future<void> repairSelfMatches(int seasonId) async {
    final List<Map<String, Object?>> selfMatches = await db.query(
      t.matches,
      where: 'season_id = ? AND home_team_id = away_team_id',
      whereArgs: <Object?>[seasonId],
    );
    if (selfMatches.isEmpty) return;

    for (final Map<String, Object?> m in selfMatches) {
      final int matchId = m['match_id'] as int;
      final int tournamentId = m['tournament_id'] as int;
      final int phase = (m['phase'] as int?) ?? 1;
      final int teamId = m['home_team_id'] as int;

      // Find other clubs in this tournament phase that are already playing:
      final List<Map<String, Object?>> playingRows = await db.rawQuery(
        '''
        SELECT home_team_id AS id FROM matches WHERE season_id = ? AND tournament_id = ? AND phase = ? AND match_id != ?
        UNION
        SELECT away_team_id AS id FROM matches WHERE season_id = ? AND tournament_id = ? AND phase = ? AND match_id != ?
        ''',
        <Object?>[
          seasonId,
          tournamentId,
          phase,
          matchId,
          seasonId,
          tournamentId,
          phase,
          matchId,
        ],
      );
      final Set<int> busyIds = <int>{
        for (final Map<String, Object?> r in playingRows) r['id'] as int,
      };
      busyIds.add(teamId);

      final String notInClause = busyIds.isEmpty ? '0' : busyIds.join(',');

      // Find an available team registered in this season to serve as opponent:
      final List<Map<String, Object?>> candidateRows = await db.rawQuery(
        '''
        SELECT tm.team_id FROM season_teams st
        JOIN teams tm ON tm.team_id = st.team_id
        WHERE st.season_id = ? AND tm.team_id NOT IN ($notInClause)
        ORDER BY tm.power DESC
        LIMIT 1
        ''',
        <Object?>[seasonId],
      );

      if (candidateRows.isNotEmpty) {
        final int oppId = candidateRows.first['team_id'] as int;
        await db.update(
          t.matches,
          <String, Object?>{'away_team_id': oppId},
          where: 'match_id = ?',
          whereArgs: <Object?>[matchId],
        );
      } else {
        await db.delete(
          t.matches,
          where: 'match_id = ?',
          whereArgs: <Object?>[matchId],
        );
      }
    }
  }

  /// Resolves any scheduling clash where a team has multiple matches on the
  /// same date, shifting the later match to the nearest available mid-week date
  /// (Tuesdays, Wednesdays, or Thursdays) where neither club has a fixture.
  Future<int> resolveFixtureClashes(int seasonId) async {
    final List<Map<String, Object?>> matches = await db.rawQuery(
      '''
      SELECT match_id, tournament_id, home_team_id, away_team_id, date
      FROM matches
      WHERE season_id = ? AND date IS NOT NULL AND status = ?
      ORDER BY date ASC, match_id ASC
    ''',
      <Object?>[seasonId, t.matchScheduled],
    );

    final Map<int, Set<String>> teamDates = <int, Set<String>>{};
    final List<Map<String, Object?>> played = await db.rawQuery(
      '''
      SELECT home_team_id, away_team_id, date FROM matches
      WHERE season_id = ? AND date IS NOT NULL AND status = ?
    ''',
      <Object?>[seasonId, t.matchFinished],
    );
    for (final Map<String, Object?> r in played) {
      final String d = r['date'] as String;
      final int h = r['home_team_id'] as int;
      final int a = r['away_team_id'] as int;
      teamDates.putIfAbsent(h, () => <String>{}).add(d);
      teamDates.putIfAbsent(a, () => <String>{}).add(d);
    }

    int moved = 0;
    for (final Map<String, Object?> m in matches) {
      final int matchId = m['match_id'] as int;
      final int home = m['home_team_id'] as int;
      final int away = m['away_team_id'] as int;
      final String originalDate = m['date'] as String;

      final bool homeClash = teamDates[home]?.contains(originalDate) ?? false;
      final bool awayClash = teamDates[away]?.contains(originalDate) ?? false;

      if (!homeClash && !awayClash) {
        teamDates.putIfAbsent(home, () => <String>{}).add(originalDate);
        teamDates.putIfAbsent(away, () => <String>{}).add(originalDate);
        continue;
      }

      // Conflict found! Find the earliest mid-week date where neither team has a match.
      DateTime candidate =
          DateTime.tryParse(originalDate) ?? DateTime(2025, 8, 9);
      while (true) {
        candidate = candidate.add(const Duration(days: 1));
        final int wd = candidate.weekday;
        if (wd == DateTime.tuesday ||
            wd == DateTime.wednesday ||
            wd == DateTime.thursday) {
          final String iso = _iso(candidate);
          final bool hFree = !(teamDates[home]?.contains(iso) ?? false);
          final bool aFree = !(teamDates[away]?.contains(iso) ?? false);
          if (hFree && aFree) {
            await db.update(
              t.matches,
              <String, Object?>{'date': iso},
              where: 'match_id = ?',
              whereArgs: <Object?>[matchId],
            );
            teamDates.putIfAbsent(home, () => <String>{}).add(iso);
            teamDates.putIfAbsent(away, () => <String>{}).add(iso);
            moved++;
            break;
          }
        }
      }
    }
    return moved;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Outcome of a full career generation.
class CareerPlan {
  CareerPlan({
    required this.season,
    required this.leagueTournamentId,
    required this.cupTournamentId,
    required this.leagueRounds,
    required this.cupRounds,
    required this.teamCount,
    required this.matchCount,
    this.internationalTournamentIds = const <int>[],
  });

  final Season season;
  final int leagueTournamentId;
  final int? cupTournamentId;
  final int leagueRounds;
  final int cupRounds;
  final int teamCount;
  final int matchCount;
  final List<int> internationalTournamentIds;
}

/// One direction of a round-robin match: home/away pair + round + leg.
class FixtureSlot {
  FixtureSlot(this.round, this.leg, this.home, this.away);

  final int round;
  final int leg;
  final int home;
  final int away;
}

/// Classic circle-method double round robin (n-1 rounds, mirrored legs).
/// Handles odd team counts with a bye placeholder (-1).
List<FixtureSlot> doubleRoundRobin(List<int> teamIds, [Random? random]) {
  final List<int> ids = List<int>.of(teamIds);
  if (ids.length < 2) return <FixtureSlot>[];
  ids.shuffle(random);
  if (ids.length.isOdd) ids.add(-1);

  final int half = ids.length - 1;
  final List<FixtureSlot> legs = <FixtureSlot>[];

  for (int round = 1; round <= half; round++) {
    for (int i = 0; i < ids.length ~/ 2; i++) {
      final int a = ids[i];
      final int b = ids[ids.length - 1 - i];
      if (a == -1 || b == -1) continue;
      // Alternate fixture orientation so home/away split evenly.
      final bool swap = (round + i) % 2 == 0;
      final int home = swap ? b : a;
      final int away = swap ? a : b;
      legs.add(FixtureSlot(round, 1, home, away));
    }
    // Rotate all but the first.
    final int last = ids.removeLast();
    ids.insert(1, last);
  }

  // Mirrored second half.
  final List<FixtureSlot> all = <FixtureSlot>[...legs];
  for (final FixtureSlot slot in legs) {
    all.add(FixtureSlot(slot.round + half, 2, slot.away, slot.home));
  }
  return all;
}

/// Feeder cups (priority order) and field size of a champions-only cup.
class _ChampionsFeed {
  const _ChampionsFeed(this.cups, this.size);

  final List<int> cups;
  final int size;
}

class _IntercontinentalRegion {
  const _IntercontinentalRegion(this.tournamentId, this.confederation);

  final int? tournamentId;
  final int confederation;
}
