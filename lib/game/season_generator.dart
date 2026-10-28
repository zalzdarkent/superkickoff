import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import 'competition_config.dart';
import 'fixture_calendar.dart';
import 'fixture_scheduler.dart';
import 'international_calendar.dart';
import 'international_tournament_service.dart';

export 'fixture_scheduler.dart' show FixtureSlot;

/// Builds a new career season:
///  * season row + tournament links
///  * season_teams registration for every participating club
///  * mathematically correct league fixtures with balanced home/away rhythm
///  * competition-specific group stages, league phases and knockout brackets
///  * a single global calendar that resolves clashes and rest periods
class SeasonGenerator {
  SeasonGenerator(this.db, {Random? random})
    : _rng = random ?? Random(),
      _calendar = FixtureSchedulingService(db);

  final Database db;
  final Random _rng;
  final FixtureSchedulingService _calendar;

  DateTime _startDate = DateTime(2025, 8, 9);
  int? _userTeamId;
  final Map<String, List<Team>> _qualifiersCache = <String, List<Team>>{};

  Future<CareerPlan> generateCareer({
    required int countryId,
    required Tournament league,
    required Tournament? cup,
    List<Tournament> internationals = const <Tournament>[],
    List<Tournament> otherLeagues = const <Tournament>[],
    int startYear = 2025,
    int? userTeamId,
  }) async {
    _startDate = DateTime(startYear, 8, 9); // first Saturday of August-ish
    _userTeamId = userTeamId;
    _qualifiersCache.clear();

    final List<Tournament> allDomesticLeagues = <Tournament>[
      league,
      ...otherLeagues.where(
        (Tournament l) => l.tournamentId != league.tournamentId,
      ),
    ];

    final Season season = await _insertSeason(startYear);
    final InternationalCalendarService intlCalendar =
        InternationalCalendarService(db);
    final List<InternationalWindow> windows = await intlCalendar
        .generateWindowsForSeason(season.seasonId, startYear);
    final InternationalTournamentService intlTournaments =
        InternationalTournamentService(db);
    for (final InternationalWindow win in windows) {
      if (win.windowType == InternationalWindowType.fifaWindow) {
        await intlTournaments.scheduleFriendliesForWindow(
          seasonId: season.seasonId,
          window: win,
        );
      }
    }
    await Future<void>.delayed(Duration.zero);

    for (final Tournament tour in allDomesticLeagues) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });
      await _persistConfig(tour, startYear);
    }
    if (cup != null) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': cup.tournamentId,
        'status': t.seasonTournamentActive,
      });
      await _persistConfig(cup, startYear);
    }
    for (final Tournament tour in internationals) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });
      await _persistConfig(tour, startYear);
    }

    // ------------------------------------------------ participants
    final Map<int, Team> allTeams = <int, Team>{};
    final Map<int, List<Team>> domesticTeamsByTournament = <int, List<Team>>{};
    for (final Tournament lg in allDomesticLeagues) {
      List<Team> divTeams = await _teamsOf(countryId, lg.divisionId);
      final int maxDivTeams = lg.slots > 0 ? lg.slots : 24;
      if (divTeams.length > maxDivTeams) {
        divTeams = List<Team>.of(divTeams)
          ..sort((Team a, Team b) => b.power.compareTo(a.power));
        divTeams = divTeams.take(maxDivTeams).toList();
      }
      domesticTeamsByTournament[lg.tournamentId] = divTeams;
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
      final CompetitionConfig tourConfig = await _configForTournament(
        tour.tournamentId,
        seasonStartYear: startYear,
      );
      // A league phase or group stage uses every qualified club; trimming to a power of two
      // would silently drop clubs from the table or groups. Knockout-only competitions
      // still pick a bracket-sized field.
      final List<int> entrants =
          (tourConfig.format == CompetitionFormat.leaguePhase ||
              tourConfig.format == CompetitionFormat.groupStage)
          ? _seedIdsByPower(invited)
          : seedByIdes(invited);
      internationalEntrants[tour.tournamentId] = entrants;
      if (!isSuperOrGlobal) {
        continentalInvites.addAll(entrants);
      }
      for (final int id in entrants) {
        allTeams[id] = byId[id]!;
      }
    }
    await Future<void>.delayed(Duration.zero);

    // ------------------------------------------------ registration
    // Coach per team comes from the team itself.
    await db.transaction((Transaction txn) async {
      final Batch batch = txn.batch();
      for (final Team tm in allTeams.values) {
        batch.insert(t.seasonTeams, <String, Object?>{
          'team_id': tm.teamId,
          'season_id': season.seasonId,
          'coach_id': tm.coachId,
        });
      }
      await batch.commit(noResult: true);
    });

    // ------------------------------------------------ league fixtures
    final List<Map<String, Object?>> matchRows = <Map<String, Object?>>[];
    int userLeagueRounds = 0;
    for (final Tournament lg in allDomesticLeagues) {
      final List<Team> divTeams =
          domesticTeamsByTournament[lg.tournamentId] ?? const <Team>[];
      final int teamCount = divTeams.length;
      final CompetitionConfig config = await _configForTournament(
        lg.tournamentId,
        seasonStartYear: startYear,
      );
      final bool doubleRound = config.doubleRoundRobin;
      final int roundsPerLeg = teamCount.isEven ? teamCount - 1 : teamCount;
      final int r = teamCount >= 2 ? roundsPerLeg * (doubleRound ? 2 : 1) : 0;
      if (lg.tournamentId == league.tournamentId) {
        userLeagueRounds = r;
      }
      if (teamCount >= 2) {
        final List<FixtureSlot> slots = RoundRobinScheduler.schedule(
          divTeams.map((Team tm) => tm.teamId).toList(),
          doubleRound: doubleRound,
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
              date: _iso(_roundDate(_startDate, slot.round, config)),
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);
      }
    }

    // ------------------------------------------------ cup first round
    int cupPhases = 0;
    if (cup != null && cupTeams.length >= 4) {
      final CompetitionConfig cupConfig = await _configForTournament(
        cup.tournamentId,
        seasonStartYear: startYear,
      );
      final List<int> seeded = _seedIdsByPower(cupTeams);
      final KnockoutPlan plan = KnockoutScheduler.planOpeningRound(
        seeded,
        useByes: cupConfig.useByes,
        trimToPowerOfTwo: cupConfig.trimToPowerOfTwo,
        fieldSize: cupConfig.fieldSize,
      );
      cupPhases = plan.roundsToFinal;
      final DateTime cupDate = _cupDate(1, userLeagueRounds);
      await scheduleCupRound(
        season.seasonId,
        cup.tournamentId,
        seeded,
        phase: 1,
        date: cupDate,
        allTeams: allTeams,
        pairs: plan.pairs,
        byes: plan.byes,
      );
    }

    // ----------------------- continental league phase / group stage / round 1
    int internationalIndex = 0;
    int superCupIndex = 0;
    for (final MapEntry<int, List<int>> entry
        in internationalEntrants.entries) {
      final bool isSuperCup = entry.key == 54 || entry.key == 1651;
      final DateTime start = isSuperCup
          ? _startDate.subtract(Duration(days: 4 + (superCupIndex++ * 3)))
          : _internationalDate(internationalIndex++);
      await _scheduleContinentalOpening(
        seasonId: season.seasonId,
        tournamentId: entry.key,
        entrants: entry.value,
        start: start,
        allTeams: allTeams,
        seasonStartYear: startYear,
      );
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
      internationalWindows: windows,
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
      await _persistConfig(tour, season.startYear);
      final CompetitionConfig tourConfig = await _configForTournament(
        tour.tournamentId,
        seasonStartYear: season.startYear,
      );
      final List<int> entrants =
          (tourConfig.format == CompetitionFormat.leaguePhase ||
              tourConfig.format == CompetitionFormat.groupStage)
          ? _seedIdsByPower(invited)
          : seedByIdes(invited);
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
      await _scheduleContinentalOpening(
        seasonId: season.seasonId,
        tournamentId: tour.tournamentId,
        entrants: entrants,
        start: date,
        allTeams: teamCache,
        seasonStartYear: season.startYear,
      );
      added++;
    }
    if (added > 0) {
      await resolveFixtureClashes(season.seasonId);
      await repairSelfMatches(season.seasonId);
    }
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

      await _persistConfig(tour, season.startYear);
      final CompetitionConfig config = await _configForTournament(
        tour.tournamentId,
        seasonStartYear: season.startYear,
      );
      final List<FixtureSlot> slots = RoundRobinScheduler.schedule(
        divTeams.map((Team tm) => tm.teamId).toList(),
        doubleRound: config.doubleRoundRobin,
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
            date: _iso(_roundDate(_startDate, slot.round, config)),
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
              final double homeRoll =
                  _rng.nextDouble() * (home.power * homeAdv);
              final double awayRoll = _rng.nextDouble() * away.power;
              final int homeGoals = homeRoll > awayRoll + 15
                  ? 2 + _rng.nextInt(3)
                  : (homeRoll > awayRoll
                        ? 1 + _rng.nextInt(2)
                        : _rng.nextInt(2));
              final int awayGoals = awayRoll > homeRoll + 15
                  ? 2 + _rng.nextInt(3)
                  : (awayRoll > homeRoll
                        ? 1 + _rng.nextInt(2)
                        : _rng.nextInt(2));
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

  /// Builds a group stage: clubs are spread snake-style over balanced groups
  /// capped at the configured size, then play a single or double round robin.
  /// The top two of every group advance to the knockout rounds, which
  /// [generateCareer] leaves for later.
  Future<int> scheduleGroupStage(
    int seasonId,
    int tournamentId,
    List<int> entrants, {
    required DateTime start,
    required Map<int, Team> allTeams,
    CompetitionConfig? config,
  }) async {
    final CompetitionConfig cfg =
        config ?? await configForSeason(tournamentId, seasonId);
    final int groupSize = max(2, cfg.groupSize);
    final List<int> sorted = _seedIdsByPower(<Team>[
      for (final int id in entrants)
        if (allTeams[id] != null) allTeams[id]!,
    ]);
    final int naturalGroups = (sorted.length + groupSize - 1) ~/ groupSize;
    final int groupCount = cfg.groupCount > 0
        ? min(cfg.groupCount, naturalGroups)
        : naturalGroups;
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
      final List<FixtureSlot> slots = RoundRobinScheduler.schedule(
        groups[g],
        doubleRound: cfg.groupDoubleRoundRobin,
      );
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
            date: _iso(_roundDate(start, slot.round, cfg)),
            groupId: g + 1,
          ),
        );
      }
    }
    await _insertMatches(rows);
    return groups.length;
  }

  /// Builds a UEFA-style league phase: every club plays a fixed number of
  /// distinct opponents with an exact home/away split. Matches use `phase = 0`
  /// so they are treated as a table stage, never as a knockout tie.
  Future<int> scheduleLeaguePhase(
    int seasonId,
    int tournamentId,
    List<int> entrants, {
    required DateTime start,
    required Map<int, Team> allTeams,
    CompetitionConfig? config,
  }) async {
    final CompetitionConfig cfg =
        config ?? await configForSeason(tournamentId, seasonId);
    final List<int> seeded = _seedIdsByPower(<Team>[
      for (final int id in entrants)
        if (allTeams[id] != null) allTeams[id]!,
    ]);
    if (seeded.length < 2) return 0;
    final Map<int, int> associationOf = <int, int>{
      for (final int id in seeded) id: allTeams[id]?.countryId ?? 0,
    };
    final LeaguePhaseSchedule plan = LeaguePhaseScheduler.generate(
      seeded,
      opponents: cfg.leaguePhaseOpponents,
      homeMatches: cfg.leaguePhaseHomeMatches,
      associationOf: associationOf,
    );
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final FixtureSlot slot in plan.fixtures) {
      final Team? home = allTeams[slot.home];
      final Team? away = allTeams[slot.away];
      if (home == null || away == null || slot.home == slot.away) continue;
      rows.add(
        _matchRow(
          seasonId,
          tournamentId,
          home,
          away,
          round: slot.round,
          phase: 0,
          leg: 1,
          date: _iso(_roundDate(start, slot.round, cfg)),
        ),
      );
    }
    await _insertMatches(rows);
    return rows.length;
  }

  /// Chooses the correct opening structure for a continental or special
  /// competition from its [CompetitionConfig].
  Future<void> _scheduleContinentalOpening({
    required int seasonId,
    required int tournamentId,
    required List<int> entrants,
    required DateTime start,
    required Map<int, Team> allTeams,
    required int seasonStartYear,
  }) async {
    final CompetitionConfig config = await configForSeason(
      tournamentId,
      seasonId,
      seasonStartYear: seasonStartYear,
    );
    if (config.format == CompetitionFormat.leaguePhase) {
      await scheduleLeaguePhase(
        seasonId,
        tournamentId,
        entrants,
        start: start,
        allTeams: allTeams,
        config: config,
      );
      return;
    }
    if (config.format == CompetitionFormat.groupStage &&
        entrants.length >= config.groupSize * 2) {
      await scheduleGroupStage(
        seasonId,
        tournamentId,
        entrants,
        start: start,
        allTeams: allTeams,
        config: config,
      );
      return;
    }
    final List<int> seeded = _seedIdsByPower(<Team>[
      for (final int id in entrants)
        if (allTeams[id] != null) allTeams[id]!,
    ]);
    final KnockoutPlan plan = KnockoutScheduler.planOpeningRound(
      seeded,
      useByes: config.useByes,
      trimToPowerOfTwo: config.trimToPowerOfTwo,
      fieldSize: config.fieldSize,
    );
    await scheduleCupRound(
      seasonId,
      tournamentId,
      seeded,
      phase: 1,
      date: start,
      allTeams: allTeams,
      pairs: plan.pairs,
      byes: plan.byes,
    );
  }

  /// Resolves a tournament row to its central competition configuration.
  Future<CompetitionConfig> _configForTournament(
    int tournamentId, {
    int? seasonStartYear,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.tournaments,
      where: 'tournament_id = ?',
      whereArgs: <Object?>[tournamentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return CompetitionConfig(
        tournamentId: tournamentId,
        name: 'Tournament $tournamentId',
        type: CompetitionType.international,
        format: CompetitionFormat.knockout,
        seasonStartYear: seasonStartYear,
      );
    }
    return _calendar.resolveConfig(
      Tournament.fromMap(rows.first),
      seasonStartYear: seasonStartYear,
    );
  }

  Future<CompetitionConfig> configForSeason(
    int tournamentId,
    int seasonId, {
    int? seasonStartYear,
  }) async {
    int? startYear = seasonStartYear;
    if (startYear == null) {
      final List<Map<String, Object?>> rows = await db.query(
        t.seasons,
        columns: <String>['start_year'],
        where: 'season_id = ?',
        whereArgs: <Object?>[seasonId],
        limit: 1,
      );
      startYear = rows.isEmpty ? null : rows.first['start_year'] as int?;
    }
    return _configForTournament(tournamentId, seasonStartYear: startYear);
  }

  Future<void> _persistConfig(Tournament tour, int startYear) async {
    final CompetitionConfig? existing = await _calendar.loadConfig(
      tour.tournamentId,
      seasonStartYear: startYear,
    );
    if (existing != null) return;
    await _calendar.persistConfig(
      CompetitionConfig.forTournament(tour, seasonStartYear: startYear),
    );
  }

  /// Schedules the NEXT knockout round once a cup phase fully finished.
  /// [survivors] are the winning team ids (byes included). When [pairs] is
  /// provided, explicit match pairings are scheduled instead of power-seeding.
  /// [byes] are clubs that advance directly to the following phase.
  /// Returns the number of matches scheduled.
  Future<int> scheduleCupRound(
    int seasonId,
    int cupTournamentId,
    List<int> survivors, {
    required int phase,
    required DateTime date,
    required Map<int, Team> allTeams,
    List<(int, int)>? pairs,
    List<int> byes = const <int>[],
  }) async {
    final CompetitionConfig config = await configForSeason(
      cupTournamentId,
      seasonId,
    );
    final List<int> seeded = _seedIdsByPower(<Team>[
      for (final int id in survivors)
        if (allTeams[id] != null) allTeams[id]!,
    ]);

    List<(int, int)> matchPairs;
    List<int> advancingByes = List<int>.of(byes);
    if (pairs != null) {
      matchPairs = pairs;
    } else {
      final KnockoutPlan plan = KnockoutScheduler.pairNextRound(seeded);
      matchPairs = plan.pairs;
      advancingByes.addAll(plan.byes);
    }

    final Set<int> paired = <int>{
      for (final (int a, int b) in matchPairs) ...<int>[a, b],
    };
    advancingByes = <int>[
      for (final int id in advancingByes.toSet())
        if (!paired.contains(id)) id,
    ];

    final bool isFinal =
        matchPairs.length == 1 && advancingByes.isEmpty && seeded.length == 2;
    final int legs = (isFinal && config.finalSingleMatch)
        ? 1
        : config.knockoutLegs;

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final (int a, int b) in matchPairs) {
      if (a == b) continue;
      final Team? homeTeam = allTeams[a];
      final Team? awayTeam = allTeams[b];
      if (homeTeam == null || awayTeam == null) continue;
      final bool neutral = isFinal && config.neutralFinal;
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
          neutralVenue: neutral,
          extraTime: config.extraTime,
          awayGoalsRule: config.awayGoals,
        ),
      );
      if (legs == 2) {
        // Return leg played ~7 days later with reversed venues.
        rows.add(
          _matchRow(
            seasonId,
            cupTournamentId,
            awayTeam,
            homeTeam,
            round: phase,
            phase: phase,
            leg: 2,
            date: _iso(date.add(Duration(days: config.matchdayIntervalDays))),
            neutralVenue: false,
            extraTime: config.extraTime,
            awayGoalsRule: config.awayGoals,
          ),
        );
      }
    }
    await _recordByes(seasonId, cupTournamentId, phase, advancingByes);
    await _insertMatches(rows);
    return rows.length;
  }

  /// Clubs that received a bye in [phase] and therefore advance without
  /// playing. Used by the knockout progression code.
  Future<List<int>> byesForPhase(
    int seasonId,
    int tournamentId,
    int phase,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        'knockout_byes',
        columns: <String>['team_id'],
        where: 'season_id = ? AND tournament_id = ? AND phase = ?',
        whereArgs: <Object?>[seasonId, tournamentId, phase],
      );
      return <int>[
        for (final Map<String, Object?> row in rows) row['team_id'] as int,
      ];
    } catch (_) {
      return <int>[];
    }
  }

  Future<void> _recordByes(
    int seasonId,
    int tournamentId,
    int phase,
    List<int> byes,
  ) async {
    if (byes.isEmpty) return;
    for (final int teamId in byes) {
      try {
        await db.insert('knockout_byes', <String, Object?>{
          'season_id': seasonId,
          'tournament_id': tournamentId,
          'phase': phase,
          'team_id': teamId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } catch (_) {
        // Older saves may not have the byes table yet.
      }
    }
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
          if (_userTeamId != null && candidate.teamId == _userTeamId) {
            // User team must only enter if they actually won the feeder tournament.
            continue;
          }
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

    final List<Map<String, Object?>> slotRows =
        (tour.tournamentId == 56 ||
            _championsFeeds.containsKey(tour.tournamentId))
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
      if (_userTeamId != null && club.teamId == _userTeamId) {
        // User team must only enter if they earned qualification via feeder cups.
        continue;
      }
      if (teams.every((Team tm) => tm.teamId != club.teamId)) teams.add(club);
    }
    return teams;
  }

  /// Exposes the final result of a tournament before [beforeSeasonId].
  Future<(int, int)?> lastFinal(int tournamentId, int beforeSeasonId) =>
      _lastFinal(tournamentId, beforeSeasonId);

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
    final String cacheKey = '$countryId:${beforeSeasonId ?? -1}';
    final List<Team>? cached = _qualifiersCache[cacheKey];
    if (cached != null) return cached;

    final List<Map<String, Object?>> clubRows = await db.query(
      t.teams,
      where: 'country_id = ? AND division = 1',
      whereArgs: <Object?>[countryId],
      orderBy: 'power DESC',
    );
    final List<Team> clubs = clubRows.map(Team.fromMap).toList();
    if (beforeSeasonId == null) {
      final List<Team> fallback = _fallbackQualifiers(clubs);
      _qualifiersCache[cacheKey] = fallback;
      return fallback;
    }
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
      final List<Team> fallback = _fallbackQualifiers(clubs);
      _qualifiersCache[cacheKey] = fallback;
      return fallback;
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
    if (results.isEmpty) {
      final List<Team> fallback = _fallbackQualifiers(clubs);
      _qualifiersCache[cacheKey] = fallback;
      return fallback;
    }
    final Map<int, Team> byId = <int, Team>{
      for (final Team club in clubs) club.teamId: club,
    };
    final List<Team> ordered = <Team>[
      for (final Map<String, Object?> row in results)
        if (byId.remove(row['team_id']) case final Team club) club,
    ];
    ordered.addAll(byId.values);
    _qualifiersCache[cacheKey] = ordered;
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
    bool neutralVenue = false,
    bool extraTime = false,
    bool awayGoalsRule = false,
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
      'kickoff_time': null,
      'original_date': null,
      'reschedule_reason': null,
      'neutral_venue': neutralVenue ? 1 : 0,
      'extra_time': extraTime ? 1 : 0,
      'away_goals_rule': awayGoalsRule ? 1 : 0,
    };
  }

  Future<void> _insertMatches(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    await db.transaction((Transaction txn) async {
      final Batch batch = txn.batch();
      for (final Map<String, Object?> row in rows) {
        batch.insert(t.matches, row);
      }
      await batch.commit(noResult: true);
    });
  }

  DateTime _roundDate(DateTime start, int round, CompetitionConfig config) {
    final DateTime preferred = start.add(
      Duration(days: config.matchdayIntervalDays * (round - 1)),
    );
    if (config.allowedWeekdays.isEmpty) return preferred;
    for (int offset = 0; offset < 7; offset++) {
      final DateTime candidate = preferred.add(Duration(days: offset));
      if (config.allowedWeekdays.contains(candidate.weekday)) return candidate;
    }
    throw StateError(
      'Competition ${config.tournamentId} has no valid allowed weekdays.',
    );
  }

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
    final List<int> sorted = _seedIdsByPower(teams);
    int bracket = 1;
    while (bracket * 2 <= sorted.length) {
      bracket *= 2;
    }
    return sorted.take(bracket).toList();
  }

  /// Unique club ids ordered by descending power (deterministic seeding).
  List<int> _seedIdsByPower(List<Team> teams) {
    final Map<int, Team> unique = <int, Team>{
      for (final Team tm in teams) tm.teamId: tm,
    };
    final List<Team> sorted = unique.values.toList()
      ..sort((Team a, Team b) {
        final int byPower = b.power.compareTo(a.power);
        if (byPower != 0) return byPower;
        return a.teamId.compareTo(b.teamId);
      });
    return sorted.map((Team tm) => tm.teamId).toList();
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

  /// Resolves scheduling clashes through the unified calendar service.
  /// Completed fixtures are fixed; every other fixture is checked for
  /// same-day conflicts and the configured rest period, then moved to the
  /// nearest valid date with an audit trail.
  Future<int> resolveFixtureClashes(int seasonId) =>
      _calendar.resolveSeasonConflicts(seasonId);

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
    this.internationalWindows = const <InternationalWindow>[],
  });

  final Season season;
  final int leagueTournamentId;
  final int? cupTournamentId;
  final int leagueRounds;
  final int cupRounds;
  final int teamCount;
  final int matchCount;
  final List<int> internationalTournamentIds;
  final List<InternationalWindow> internationalWindows;
}

/// Backwards-compatible wrapper around [RoundRobinScheduler]. Kept because
/// existing callers (and tests) import this helper from the season generator.
List<FixtureSlot> doubleRoundRobin(List<int> teamIds, [Random? random]) =>
    RoundRobinScheduler.schedule(teamIds, doubleRound: true, random: random);

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
