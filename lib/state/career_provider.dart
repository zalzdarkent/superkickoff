import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/format.dart' as fmt;
import '../data/db/app_database.dart';
import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import '../data/repositories/match_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/news_repository.dart';
import '../data/repositories/prize_repository.dart';
import '../data/repositories/reference_repository.dart';
import '../data/repositories/scouting_repository.dart';
import '../data/repositories/season_repository.dart';
import '../data/repositories/squad_repository.dart';
import '../data/repositories/sponsorship_repository.dart';
import '../data/repositories/transfer_repository.dart';
import '../game/career_service.dart';
import '../game/formation.dart';
import '../game/match_engine.dart';
import '../game/news_engine.dart';
import '../game/season_generator.dart';
import '../game/training.dart';

/// Presentation-facing career state. One instance lives above the app and
/// notifies widgets whenever the career world changes.
class CareerProvider extends ChangeNotifier {
  CareerProvider();

  late Database _db;
  late ReferenceRepository _refs;
  late SeasonRepository _seasons;
  late SquadRepository _squads;
  late MatchRepository _matchRepo;
  late MessageRepository _messages;
  late NewsRepository _news;
  late NewsEngine _newsEngine;
  late TransferRepository _transfers;
  late PrizeRepository _prizes;
  late SponsorshipRepository _sponsorships;
  late ScoutingRepository _scouting;
  late CareerService _service;
  late MatchEngine _engine;
  final Random _rng = Random();

  bool initialized = false;
  bool hasCareer = false;
  bool busy = false;
  String busyStatus = '';

  Season? season;
  Tournament? league;
  Tournament? cup;

  /// Every knockout competition of the season: domestic cup plus continental
  /// cups such as the Champions League or AFC Champions League.
  List<Tournament> cups = <Tournament>[];
  int userTeamId = 0;
  Team? userTeam;
  ManagerProfile? managerProfile;
  Map<int, Team> teamCache = <int, Team>{};

  List<FixtureMatch> upcoming = <FixtureMatch>[];
  String? nextDate;
  List<FixtureMatch> matchesToday = <FixtureMatch>[];

  /// The matchday that just finished, kept after the world advances so the
  /// results screen can show every game played on that date.
  List<FixtureMatch> lastMatchday = <FixtureMatch>[];
  Map<int, Team> lastMatchdayTeams = <int, Team>{};

  /// Aggregate (home, away) of finished leg-2 cup ties in [lastMatchday].
  Map<int, (int, int)> lastMatchdayAggregates = <int, (int, int)>{};
  List<StandingRow> standings = <StandingRow>[];

  /// Group tables of continental cups, keyed by tournament id.
  Map<int, List<GroupTable>> cupGroups = <int, List<GroupTable>>{};
  List<LeaderRow> topScorers = <LeaderRow>[];
  List<LeaderRow> topAssists = <LeaderRow>[];
  List<LeaderRow> topCleanSheets = <LeaderRow>[];
  List<LeaderRow> topRated = <LeaderRow>[];

  /// User club leaderboards and the tactic chosen for the next match.
  List<LeaderRow> clubTopScorers = <LeaderRow>[];
  List<LeaderRow> clubTopAssists = <LeaderRow>[];
  List<LeaderRow> clubTopRated = <LeaderRow>[];
  Formation formation = Formation.f442;

  /// Saved XI for the formation pitch: slot index -> player id.
  Map<int, int> lineup = <int, int>{};
  List<Message> inbox = <Message>[];
  int unreadCount = 0;
  int week = 0;

  // Live match session (filled while watching a match).
  LiveMatchSession? liveSession;

  // ------------------------------------------------------------ bootstrap

  Future<void> init([Database? database]) async {
    _db = database ?? await AppDatabase.open();
    _refs = ReferenceRepository(_db);
    _seasons = SeasonRepository(_db);
    _squads = SquadRepository(_db);
    _matchRepo = MatchRepository(_db);
    _messages = MessageRepository(_db);
    _news = NewsRepository(_db);
    _newsEngine = NewsEngine(_db, _news);
    _transfers = TransferRepository(_db);
    _prizes = PrizeRepository(_db);
    _sponsorships = SponsorshipRepository(_db);
    _scouting = ScoutingRepository(_db);
    _engine = MatchEngine();
    _service = CareerService(
      _db,
      refs: _refs,
      seasons: _seasons,
      squads: _squads,
      matches: _matchRepo,
      messages: _messages,
      prizes: _prizes,
      transfers: _transfers,
      sponsorships: _sponsorships,
      scouting: _scouting,
      engine: _engine,
      generator: SeasonGenerator(_db, random: _rng),
      random: _rng,
    );
    initialized = true;
    await _loadCareerState();
  }

  Future<void> _loadCareerState() async {
    hasCareer = await _seasons.hasCareer();
    managerProfile = await _loadManagerProfile();
    if (!hasCareer) {
      notifyListeners();
      return;
    }
    season = await _seasons.currentSeason();
    await _deriveCareerContext();
    await refreshWorld();
  }

  Future<ManagerProfile?> _loadManagerProfile() async {
    final List<Map<String, Object?>> rows = await _db.query(
      t.managerProfile,
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ManagerProfile(
      name: rows.first['name'] as String? ?? 'Manager',
      countryId: rows.first['country_id'] as int? ?? 0,
    );
  }

  /// Recomputes userTeam/league/cup/inbox from the persisted DB state.
  Future<void> _deriveCareerContext() async {
    final int? storedTeamId = await _latestCareerTeam();
    if (storedTeamId == null) {
      hasCareer = false;
      return;
    }
    userTeamId = storedTeamId;
    userTeam = await _refs.teamById(userTeamId);
    if (userTeam == null) {
      hasCareer = false;
      return;
    }
    league = await _leagueFor(userTeam!);
    await _loadCups(season!.seasonId);
    // Cache every team that participates this season.
    final rows = await _db.rawQuery(
      '''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[season!.seasonId],
    );
    teamCache = <int, Team>{
      for (final Map<String, Object?> row in rows)
        row['team_id'] as int: Team.fromMap(row),
    };
    await _ensureInternationalCups();
  }

  /// Older saves lack some continental competitions (or all of them). Add the
  /// missing ones when a save is loaded; already-linked ones are skipped.
  Future<void> _ensureInternationalCups() async {
    final Season? current = season;
    final Team? team = userTeam;
    if (current == null || team == null) return;
    final List<Tournament> internationals = await _refs.internationalCups(
      team.countryId,
    );
    final Set<int> have = <int>{for (final Tournament c in cups) c.tournamentId};
    if (internationals.every((Tournament c) => have.contains(c.tournamentId))) {
      return;
    }
    final int added = await SeasonGenerator(_db, random: _rng)
        .addInternationalCups(
          season: current,
          internationals: internationals,
          teamCache: teamCache,
        );
    if (added > 0) await _loadCups(current.seasonId);
  }

  Future<void> _loadCups(int seasonId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT tu.* FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      WHERE st.season_id = ? AND tu.organization IN (?, ?)
      ORDER BY tu.tournament_id ASC
    ''',
      <Object?>[seasonId, t.orgNationalCup, t.orgInternational],
    );
    cups = rows.map(Tournament.fromMap).toList();
    cup = null;
    for (final Tournament tour in cups) {
      if (tour.isNationalCup) {
        cup = tour;
        break;
      }
    }
  }

  /// The career row stores the managed club per season (career_history).
  Future<int?> _latestCareerTeam() async {
    final rows = await _db.query(
      t.careerHistory,
      orderBy: 'season_id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['team_id'] as int?;
  }

  Future<Tournament?> _leagueFor(Team team) async {
    final rows = await _db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tu.organization = ? AND tc.country_id = ? AND tu.division_id = ?
      LIMIT 1
    ''',
      <Object?>[t.orgLeague, team.countryId, team.division],
    );
    return rows.isEmpty ? null : Tournament.fromMap(rows.first);
  }

  // -------------------------------------------------------------- setup flow

  Future<List<Map<String, Object?>>> playableCountries() =>
      _refs.playableCountries();

  Future<List<Map<String, Object?>>> allCountries() => _refs.allCountries();

  Future<Tournament?> tournamentById(int id) => _refs.tournamentById(id);

  Future<List<Map<String, Object?>>> leaguesForCountry(int countryId) =>
      _refs.leaguesForCountry(countryId);

  Future<List<Map<String, Object?>>> teamsForLeague(
    int countryId,
    int divisionId,
  ) async {
    final Map<String, Object?>? cupRow = await _refs.nationalCup(countryId);
    cup = cupRow == null ? null : Tournament.fromMap(cupRow);
    return _refs
        .teamsForDivision(countryId, divisionId)
        .then(
          (List<Team> list) => list
              .map(
                (Team tm) => <String, Object?>{
                  'team_id': tm.teamId,
                  'name': tm.name,
                  'power': tm.power,
                  'value': tm.value,
                  'budget': tm.budget,
                  'division': tm.division,
                },
              )
              .toList(),
        );
  }

  /// Generates the whole season for a brand new career.
  Future<void> startCareer({
    required String managerName,
    required int nationalityId,
    required int countryId,
    required Tournament leagueTournament,
    required int teamId,
    required void Function(String) onProgress,
  }) async {
    busy = true;
    onProgress('Registering teams...');
    await _db.insert(t.managerProfile, <String, Object?>{
      'id': 1,
      'name': managerName.trim(),
      'country_id': nationalityId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    managerProfile = ManagerProfile(
      name: managerName.trim(),
      countryId: nationalityId,
    );
    final Map<String, Object?>? cupRow = await _refs.nationalCup(countryId);
    final Tournament? cupTournament = cupRow == null
        ? null
        : Tournament.fromMap(cupRow);
    final String label = 'Generating fixtures...';
    onProgress(label);
    await _serviceCareerGeneration(
      countryId,
      leagueTournament,
      cupTournament,
      teamId,
      onProgress,
    );
    busy = false;
    notifyListeners();
  }

  Future<void> _serviceCareerGeneration(
    int countryId,
    Tournament leagueTournament,
    Tournament? cupTournament,
    int teamId,
    void Function(String) onProgress,
  ) async {
    final CareerPlan plan = await SeasonGenerator(_db, random: _rng)
        .generateCareer(
          countryId: countryId,
          league: leagueTournament,
          cup: cupTournament,
          internationals: await _refs.internationalCups(countryId),
        );
    onProgress('Saving career...');
    // Persist the manager pick for continuation across restarts.
    await _db.insert(t.careerHistory, <String, Object?>{
      'team_id': teamId,
      'season_id': plan.season.seasonId,
      'country_id': countryId,
    });
    season = plan.season;
    userTeamId = teamId;
    userTeam = await _refs.teamById(teamId);
    league = leagueTournament;
    cup = cupTournament;
    await _loadCups(plan.season.seasonId);
    final rows = await _db.rawQuery(
      '''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[plan.season.seasonId],
    );
    teamCache = <int, Team>{
      for (final Map<String, Object?> row in rows)
        row['team_id'] as int: Team.fromMap(row),
    };
    // Schedule 3 pre-season friendly matches for user team!
    await SeasonGenerator(_db, random: _rng).schedulePreSeasonFriendlies(
      seasonId: plan.season.seasonId,
      userTeamId: teamId,
      allTeams: teamCache,
    );
    hasCareer = true;
    await AppDatabase.beginSession();
    await refreshWorld();
  }

  // ------------------------------------------------------------- world state

  Future<void> refreshWorld() async {
    if (season == null || userTeamId == 0) {
      notifyListeners();
      return;
    }
    await _service.repairSelfMatches(season!.seasonId);
    await _service.resolveFixtureClashes(season!.seasonId);
    upcoming = await _service.upcomingMatches(season!.seasonId);
    nextDate = await _service.nextMatchDate(season!.seasonId);
    matchesToday = nextDate == null
        ? <FixtureMatch>[]
        : await _service.matchesOnDate(season!.seasonId, nextDate!);
    formation = Formation.parse(await _squads.formationForTeam(userTeamId));
    lineup = await _squads.lineupForTeam(userTeamId);
    await _ensureLineup();
    await _ensurePreviewNews();
    if (league != null) {
      final int seasonId = season!.seasonId;
      final int tournamentId = league!.tournamentId;
      standings = await _seasons.standings(seasonId, tournamentId);
      final Map<int, List<GroupTable>> groups = <int, List<GroupTable>>{};
      for (final Tournament tour in cups) {
        if (!tour.isInternational) continue;
        final List<GroupTable> tables = await _seasons.groupTables(
          seasonId,
          tour.tournamentId,
        );
        if (tables.isNotEmpty) groups[tour.tournamentId] = tables;
      }
      cupGroups = groups;
      topScorers = await _seasons.topScorers(seasonId, tournamentId);
      topAssists = await _seasons.topAssists(seasonId, tournamentId);
      topCleanSheets = await _seasons.topCleanSheets(seasonId, tournamentId);
      topRated = await _seasons.topRated(seasonId, tournamentId);
      clubTopScorers = await _seasons.topScorers(
        seasonId,
        tournamentId,
        teamId: userTeamId,
        limit: 5,
      );
      clubTopAssists = await _seasons.topAssists(
        seasonId,
        tournamentId,
        teamId: userTeamId,
        limit: 5,
      );
      clubTopRated = await _seasons.topRated(
        seasonId,
        tournamentId,
        teamId: userTeamId,
        limit: 5,
      );
    }
    inbox = await _messages.latest(teamId: userTeamId);
    unreadCount = inbox.where((Message m) => !m.isRead).length;
    userTeam = await _refs.teamById(userTeamId);
    final Team? refreshed = userTeam;
    if (refreshed != null) {
      teamCache[refreshed.teamId] = refreshed;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- match days

  /// The user's match on the next date, if any.
  FixtureMatch? get nextUserMatch {
    for (final FixtureMatch m in matchesToday) {
      if (m.homeTeamId == userTeamId || m.awayTeamId == userTeamId) return m;
    }
    return null;
  }

  String competitionLabel(FixtureMatch match) {
    if (match.tournamentId == 9999) return 'Friendly';
    if (match.tournamentId == league?.tournamentId) {
      return league?.name ?? 'League';
    }
    for (final Tournament tournament in cups) {
      if (tournament.tournamentId == match.tournamentId) {
        return tournament.name;
      }
    }
    return 'Cup';
  }

  /// Plays the user's live match with full event recording plus the rest of
  /// the matchday, then housekeeping.
  Future<void> startLiveMatch() async {
    final FixtureMatch? mine = nextUserMatch;
    if (mine == null || season == null) return;
    final MatchResult result = await _service.simulateMatch(
      mine,
      recordEvents: true,
    );

    final bool isLeague = mine.tournamentId == league?.tournamentId;
    bool isCupFinal = false;
    bool isLeagueDecider = false;
    String? trophyName;
    bool leagueTitleWon = false;

    if (!isLeague && mine.tournamentId != 9999) {
      if (mine.groupId == null) {
        final int tiesInPhase =
            Sqflite.firstIntValue(
              await _db.rawQuery(
                'SELECT COUNT(*) FROM matches WHERE season_id = ? AND tournament_id = ? AND phase = ? AND group_id IS NULL',
                <Object?>[season!.seasonId, mine.tournamentId, mine.phase],
              ),
            ) ??
            0;
        if (tiesInPhase == 1) {
          isCupFinal = true;
          trophyName = competitionLabel(mine);
        }
      }
    } else if (isLeague && league != null) {
      final int maxRound =
          Sqflite.firstIntValue(
            await _db.rawQuery(
              'SELECT MAX(round) FROM matches WHERE season_id = ? AND tournament_id = ?',
              <Object?>[season!.seasonId, league!.tournamentId],
            ),
          ) ??
          0;
      final int userRank = standings.indexWhere(
        (StandingRow r) => r.teamId == userTeamId,
      );

      // A title decider only exists if the title has NOT already been won before this match.
      bool leagueAlreadyDecided = false;
      if (standings.isNotEmpty) {
        final StandingRow prevFirst = standings.first;
        final StandingRow? prevSecond =
            standings.length > 1 ? standings[1] : null;
        final int secondPlayed = prevSecond?.played ?? prevFirst.played;
        final int remainingForSecond = maxRound - secondPlayed;
        final int maxSecondBefore =
            (prevSecond?.points ?? 0) + (remainingForSecond * 3);
        if (prevFirst.points > maxSecondBefore ||
            (maxRound > 0 && prevFirst.played >= maxRound)) {
          leagueAlreadyDecided = true;
        }
      }

      if (!leagueAlreadyDecided && userRank >= 0 && userRank <= 1) {
        final StandingRow currentFirst = standings.first;
        final StandingRow? currentSecond =
            standings.length > 1 ? standings[1] : null;
        final int remainingBefore = maxRound - currentFirst.played;
        final int maxSecondPossible =
            (currentSecond?.points ?? 0) + (remainingBefore * 3);

        final bool canClinch = userRank == 0 &&
            (currentFirst.points + 3 > maxSecondPossible ||
                (maxRound > 0 && mine.round >= maxRound - 2));
        final bool finalRounds = maxRound > 0 && mine.round >= maxRound - 1;

        if (canClinch || finalRounds) {
          isLeagueDecider = true;
          trophyName = league!.name;
        }

        final List<StandingRow> updated = await _seasons.standings(
          season!.seasonId,
          league!.tournamentId,
        );
        if (updated.isNotEmpty && updated.first.teamId == userTeamId) {
          final StandingRow first = updated.first;
          final StandingRow? second = updated.length > 1 ? updated[1] : null;
          final int remainingRounds = maxRound - first.played;
          final int maxSecondPoints =
              (second?.points ?? 0) + (remainingRounds * 3);
          if (first.points > maxSecondPoints ||
              (maxRound > 0 && first.played >= maxRound)) {
            isLeagueDecider = true;
            leagueTitleWon = true;
            trophyName = league!.name;
          }
        }
      }
    }

    FixtureMatch? leg1Match;
    bool hasLeg2 = false;
    // League rounds also use leg 2 (mirror fixtures); only cup ties aggregate.
    if (mine.groupId == null && !isLeague && mine.tournamentId != 9999) {
      if (mine.leg == 2) {
        final List<Map<String, Object?>> leg1Rows = await _db.query(
          t.matches,
          where:
              'season_id = ? AND tournament_id = ? AND phase = ? AND leg = 1 '
              'AND home_team_id = ? AND away_team_id = ?',
          whereArgs: <Object?>[
            season!.seasonId,
            mine.tournamentId,
            mine.phase,
            mine.awayTeamId,
            mine.homeTeamId,
          ],
          limit: 1,
        );
        if (leg1Rows.isNotEmpty) {
          leg1Match = FixtureMatch.fromMap(leg1Rows.first);
        }
      } else if (mine.leg == 1) {
        final int leg2Count =
            Sqflite.firstIntValue(
              await _db.rawQuery(
                '''
          SELECT COUNT(*) FROM matches
          WHERE season_id = ? AND tournament_id = ? AND phase = ? AND leg = 2
            AND home_team_id = ? AND away_team_id = ?
          ''',
                <Object?>[
                  season!.seasonId,
                  mine.tournamentId,
                  mine.phase,
                  mine.awayTeamId,
                  mine.homeTeamId,
                ],
              ),
            ) ??
            0;
        hasLeg2 = leg2Count > 0;
      }
    }

    liveSession = LiveMatchSession(
      match: mine,
      result: result,
      homeTeam: teamCache[mine.homeTeamId]!,
      awayTeam: teamCache[mine.awayTeamId]!,
      isCupFinal: isCupFinal,
      isLeagueDecider: isLeagueDecider,
      trophyName: trophyName,
      leagueTitleWon: leagueTitleWon,
      leg1Match: leg1Match,
      hasLeg2: hasLeg2,
    );
    notifyListeners();
  }

  /// Only quick-simulates the rest of the current matchday (no user match).
  Future<void> playAiMatchday() async {
    if (season == null || nextDate == null) return;
    final int seasonId = season!.seasonId;
    final String date = nextDate!;
    await _service.simulateMatchday(
      seasonId: seasonId,
      date: date,
      skipMatchId: nextUserMatch?.matchId,
    );
    await _rememberMatchday(seasonId, date);
    await _tickAfterMatchday();
  }

  /// Completes a live match: quick-sims the remaining matchday and closes
  /// the live session.
  Future<void> finishLiveMatch() async {
    final FixtureMatch? mine = nextUserMatch;
    final int? seasonId = season?.seasonId;
    final String? date = nextDate;
    if (seasonId != null && date != null) {
      await _service.simulateMatchday(
        seasonId: seasonId,
        date: date,
        skipMatchId: mine?.matchId,
      );
      await _rememberMatchday(seasonId, date);
    }
    liveSession = null;
    await _tickAfterMatchday();
  }

  /// Stories for the world, the user's region and the user's league.
  Future<List<NewsItem>> newsFeed(String scope) => _news.feed(scope);

  /// Writes the stories for [date]; safe to call twice for the same day.
  Future<void> _writeNews(int seasonId, String date) async {
    final Tournament? lg = league;
    if (lg == null) return;
    try {
      await _newsEngine.onMatchday(
        seasonId: seasonId,
        date: date.length >= 10 ? date.substring(0, 10) : date,
        userLeagueId: lg.tournamentId,
        userRegion: await _refs.leagueRegion(lg.tournamentId),
      );
    } catch (e, st) {
      debugPrint('news generation failed: $e\n$st');
    }
  }

  /// Season-opening stories, written once per season.
  Future<void> _ensurePreviewNews() async {
    final Tournament? lg = league;
    final Season? current = season;
    if (lg == null || current == null) return;
    if (await _news.hasRef('pre:league:${current.seasonId}')) return;
    try {
      final List<Map<String, Object?>> first = await _db.rawQuery(
        'SELECT MIN(date) AS d FROM matches WHERE season_id = ?',
        <Object?>[current.seasonId],
      );
      final String date = ((first.first['d'] as String?) ?? '').length >= 10
          ? (first.first['d'] as String).substring(0, 10)
          : '${current.startYear}-08-01';
      await _newsEngine.preview(
        seasonId: current.seasonId,
        date: date,
        userLeagueId: lg.tournamentId,
        userRegion: await _refs.leagueRegion(lg.tournamentId),
      );
    } catch (e, st) {
      debugPrint('news preview failed: $e\n$st');
    }
  }

  Future<void> _rememberMatchday(int seasonId, String date) async {
    await _writeNews(seasonId, date);
    final List<FixtureMatch> played = await _service.matchesOnDate(
      seasonId,
      date,
      scheduledOnly: false,
    );
    lastMatchday = played.where((FixtureMatch m) => m.isPlayed).toList();
    lastMatchdayTeams = Map<int, Team>.of(teamCache);
    lastMatchdayAggregates = <int, (int, int)>{};
    for (final FixtureMatch m in lastMatchday) {
      // League rounds also use leg 2 (mirror fixtures); only cup ties aggregate.
      if (m.leg != 2 || m.groupId != null || !cups.any((Tournament c) => c.tournamentId == m.tournamentId)) {
        continue;
      }
      final List<Map<String, Object?>> rows = await _db.query(
        t.matches,
        where: 'season_id = ? AND tournament_id = ? AND phase = ? AND leg = 1 '
            'AND home_team_id = ? AND away_team_id = ? AND status = ?',
        whereArgs: <Object?>[
          seasonId,
          m.tournamentId,
          m.phase,
          m.awayTeamId,
          m.homeTeamId,
          t.matchFinished,
        ],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final FixtureMatch leg1 = FixtureMatch.fromMap(rows.first);
      lastMatchdayAggregates[m.matchId] = (
        (m.homeGoals ?? 0) + (leg1.awayGoals ?? 0),
        (m.awayGoals ?? 0) + (leg1.homeGoals ?? 0),
      );
    }
  }

  Future<void> _tickAfterMatchday() async {
    if (season == null) return;
    // Cup rounds might be ready to be drawn (domestic and continental).
    for (final Tournament tournament in cups) {
      await _service.maybeScheduleNextCupRound(
        seasonId: season!.seasonId,
        cupTournamentId: tournament.tournamentId,
        teamCache: teamCache,
      );
    }
    week++;
    await _service.weeklyHousekeeping(
      seasonId: season!.seasonId,
      userTeamId: userTeamId,
    );
    await refreshWorld();
    // End of season?
    if (await _service.seasonComplete(season!.seasonId)) {
      busy = true;
      busyStatus = 'Season finished!';
      notifyListeners();
      final Season next = await _service.completeSeason(
        userTeamId: userTeamId,
        onProgress: (String s) {
          busyStatus = s;
          notifyListeners();
        },
      );
      season = next;
      await _deriveCareerContext();
      busy = false;
      await refreshWorld();
    }
  }

  /// Starts a resumable session from the title screen.
  Future<void> continueCareer() => AppDatabase.beginSession();

  /// Leaves through the explicit save prompt. A discarded session is restored
  /// to the snapshot taken when it was opened.
  Future<void> leaveCareer({required bool save}) async {
    await AppDatabase.finishSession(save: save);
    initialized = false;
    hasCareer = false;
    userTeamId = 0;
    userTeam = null;
    managerProfile = null;
    season = null;
    await init();
  }

  /// Replaces the local save with the immutable bundled database.
  Future<void> newCareer() async {
    await AppDatabase.reset();
    initialized = false;
    hasCareer = false;
    userTeamId = 0;
    userTeam = null;
    managerProfile = null;
    season = null;
    await init();
  }

  Future<List<FixtureMatch>> seasonFixtures() => season == null
      ? Future<List<FixtureMatch>>.value(<FixtureMatch>[])
      : _seasons.fixturesForSeason(season!.seasonId);

  // ---------------------------------------------------------------- squad

  Future<List<Player>> squadForUser() => _squads.squadForTeam(userTeamId);

  Future<List<SquadStatRow>> squadStatistics() {
    final int? seasonId = season?.seasonId;
    if (seasonId == null) {
      return Future<List<SquadStatRow>>.value(<SquadStatRow>[]);
    }
    return _squads.squadSeasonStats(userTeamId, seasonId);
  }

  Future<Map<int, int>> suspensionsForUser() =>
      _squads.suspensionsForTeam(userTeamId);

  /// Extends a squad player's contract; returns an error message on failure.
  Future<String?> renewContract(int playerId) async {
    if (season == null) return 'No season loaded.';
    final String? error = await _squads.renewContract(
      playerId: playerId,
      teamId: userTeamId,
      currentYear: season!.endYear,
    );
    if (error == null) await refreshWorld();
    return error;
  }

  Future<YouthAcademyState> youthAcademyState() =>
      _squads.youthAcademyState(userTeamId);

  Future<String?> upgradeYouthAcademy() async {
    final String? error = await _squads.upgradeYouthAcademy(userTeamId);
    if (error == null) await refreshWorld();
    return error;
  }

  Future<TrainingState> trainingState() => _squads.trainingStatus(
    teamId: userTeamId,
    seasonId: season?.seasonId ?? 0,
  );

  Future<TrainingOutcome> runTraining(TrainingFocus focus) async {
    if (season == null) {
      return const TrainingOutcome(error: 'No season loaded.');
    }
    final TrainingOutcome outcome = await _squads.runTraining(
      teamId: userTeamId,
      seasonId: season!.seasonId,
      focus: focus,
    );
    if (outcome.ok) await refreshWorld();
    return outcome;
  }

  Future<PlayerDetail?> playerDetail(int playerId) =>
      _squads.playerDetail(playerId, seasonId: season?.seasonId);

  Future<ClubOverview?> clubOverview() async {
    final ManagerProfile? profile = managerProfile;
    final Country? country = profile == null
        ? null
        : await _refs.countryById(profile.countryId);
    return _squads.clubOverview(
      userTeamId,
      managerName: profile?.name,
      managerCountry: country?.name,
    );
  }

  Future<List<ClubTrophy>> clubTrophies() => _seasons.clubTrophies(userTeamId);

  /// Archived-season browsing used by the Table tab history screen.
  Future<List<Season>> allSeasons() => _seasons.allSeasons();

  Future<List<Tournament>> competitionsForSeason(int seasonId) =>
      _seasons.tournamentsForSeason(seasonId);

  Future<List<StandingRow>> standingsForSeason(
    int seasonId,
    int tournamentId,
  ) => _seasons.standings(seasonId, tournamentId);

  Future<List<GroupTable>> groupsForSeason(int seasonId, int tournamentId) =>
      _seasons.groupTables(seasonId, tournamentId);

  Future<CompetitionStats> competitionStats(int tournamentId) async {
    final int? seasonId = season?.seasonId;
    if (seasonId == null) {
      return const CompetitionStats(
        standings: <StandingRow>[],
        groups: <GroupTable>[],
        scorers: <LeaderRow>[],
        assists: <LeaderRow>[],
        cleanSheets: <LeaderRow>[],
        rated: <LeaderRow>[],
      );
    }
    return CompetitionStats(
      standings: await _seasons.standings(seasonId, tournamentId),
      groups: await _seasons.groupTables(seasonId, tournamentId),
      scorers: await _seasons.topScorers(seasonId, tournamentId),
      assists: await _seasons.topAssists(seasonId, tournamentId),
      cleanSheets: await _seasons.topCleanSheets(seasonId, tournamentId),
      rated: await _seasons.topRated(seasonId, tournamentId),
      region: await _refs.leagueRegion(tournamentId),
    );
  }

  Future<ClubHistory> clubHistory() async {
    final List<CareerSeason> seasons = await _seasons.careerHistory(userTeamId);
    final List<PlayerAward> awards = await _seasons.clubAwards(userTeamId);
    return ClubHistory(seasons: seasons, awards: awards);
  }

  /// Expands the stadium one step and refreshes the career world on success.
  Future<String?> expandStadium() async {
    final String? error = await _squads.expandStadium(userTeamId);
    if (error == null) await refreshWorld();
    return error;
  }

  Future<List<TransferRecord>> transferHistory() =>
      _squads.transferHistory(userTeamId);

  /// True after the manager pressed Clear, so the XI is not refilled behind
  /// their back until they pick a formation or press Auto.
  bool _lineupCleared = false;

  /// Saves the tactic used for the next match and re-picks the best XI for the
  /// new shape, since slot groups change.
  Future<void> setFormation(Formation f) async {
    formation = f;
    await _squads.setFormation(userTeamId, f.name);
    await autoFillLineup();
  }

  /// Fills every pitch slot with the best available player for the current
  /// formation (same picker the match engine uses).
  Future<void> autoFillLineup() async {
    _lineupCleared = false;
    final List<Player> squad = await squadForUser();
    final Lineup xi = Lineup.best(squad, formation: formation);
    lineup = <int, int>{
      for (int i = 0; i < xi.starters.length; i++) i: xi.starters[i].playerId,
    };
    await _squads.saveLineup(userTeamId, lineup);
    notifyListeners();
  }

  /// Keeps the XI populated: fills it when empty or when it names players who
  /// have left the club.
  Future<void> _ensureLineup() async {
    if (userTeamId == 0 || _lineupCleared) return;
    if (lineup.isNotEmpty) {
      final Set<int> ids = (await squadForUser())
          .map((Player p) => p.playerId)
          .toSet();
      if (lineup.values.every(ids.contains)) return;
    }
    await autoFillLineup();
  }

  /// Places [playerId] in [slot]. A player already in another slot swaps with
  /// the occupant, so the XI always stays consistent.
  Future<void> assignLineupSlot(int slot, int playerId) async {
    int? oldSlot;
    for (final MapEntry<int, int> entry in lineup.entries) {
      if (entry.value == playerId) {
        oldSlot = entry.key;
        break;
      }
    }
    final int? displaced = lineup[slot];
    lineup.removeWhere((int key, int value) => value == playerId);
    lineup[slot] = playerId;
    if (displaced != null && oldSlot != null && oldSlot != slot) {
      lineup[oldSlot] = displaced;
    }
    await _squads.saveLineup(userTeamId, lineup);
    notifyListeners();
  }

  Future<void> clearLineupSlot(int slot) async {
    if (lineup.remove(slot) == null) return;
    await _squads.saveLineup(userTeamId, lineup);
    notifyListeners();
  }

  Future<void> clearLineup() async {
    if (lineup.isEmpty) return;
    _lineupCleared = true;
    lineup = <int, int>{};
    await _squads.clearLineup(userTeamId);
    notifyListeners();
  }

  Future<void> toggleSquadStatus(Player p) async {
    final int newStatus = p.squadStatus == t.squadFirstTeam
        ? t.squadReserve
        : t.squadFirstTeam;
    await _squads.setSquadStatus(p.playerId, newStatus);
    await refreshWorld();
  }

  Future<void> makeCaptain(Player p) async {
    await _squads.setCaptain(userTeamId, p.playerId);
    await refreshWorld();
  }

  Future<void> toggleListedForSale(Player p) async {
    final int newMarket = p.marketStatus == t.marketForSale
        ? t.marketActive
        : t.marketForSale;
    await _squads.setMarketStatus(p.playerId, newMarket);
    if (newMarket == t.marketForSale) {
      if (p.squadStatus == t.squadLoanListed) {
        await _squads.setSquadStatus(p.playerId, t.squadReserve);
      }
      await _service.requestSaleOffer(userTeamId: userTeamId, player: p);
    }
    await refreshWorld();
  }

  Future<void> toggleListedForLoan(Player p) async {
    final int newStatus = p.squadStatus == t.squadLoanListed
        ? t.squadReserve
        : t.squadLoanListed;
    await _squads.setSquadStatus(p.playerId, newStatus);
    if (newStatus == t.squadLoanListed) {
      if (p.marketStatus == t.marketForSale) {
        await _squads.setMarketStatus(p.playerId, t.marketActive);
      }
      await _service.requestLoanOffer(userTeamId: userTeamId, player: p);
    }
    await refreshWorld();
  }

  Future<List<Map<String, Object?>>> marketPlayers({
    String? search,
    int? positionType,
    int? minAge,
    int? maxAge,
    int? minPrice,
    int? maxPrice,
  }) => _squads.marketPlayers(
    search: search,
    positionType: positionType,
    minAge: minAge,
    maxAge: maxAge,
    minPrice: minPrice,
    maxPrice: maxPrice,
    excludeTeamId: userTeamId,
  );

  Future<List<Map<String, Object?>>> allMarketPlayers({
    String? search,
    int? positionType,
    int? minAge,
    int? maxAge,
    int? minPrice,
    int? maxPrice,
  }) => _squads.allMarketPlayers(
    search: search,
    positionType: positionType,
    minAge: minAge,
    maxAge: maxAge,
    minPrice: minPrice,
    maxPrice: maxPrice,
    excludeTeamId: userTeamId,
  );

  Future<String?> makeTransferOffer(
    Map<String, Object?> row,
    int offerAmount,
  ) async {
    final int clubId = (row['club_team_id'] as int?) ?? 0;
    if (clubId == 0) return 'Player is a free agent';
    if (clubId == userTeamId) return 'Player already in your squad';
    
    final Team? buyer = userTeam;
    if (buyer == null) return 'Unknown team';
    if (buyer.budget < offerAmount) return 'Not enough budget';

    final int playerId = row['player_id'] as int;
    final int playerValue = (row['value'] as int?) ?? 0;

    // Create transfer offer
    final int offerId = await _transfers.createOffer(
      playerId: playerId,
      fromTeamId: clubId,
      toTeamId: userTeamId,
      offerAmount: offerAmount,
      playerValue: playerValue,
    );

    // Send notification to user about offer submission
    await _messages.insert(
      title: 'Transfer offer sent',
      body: 'Your offer of ${fmt.money(offerAmount)} for ${row['name']} '
            'has been sent to ${row['club_name']}. Awaiting response...',
      teamId: userTeamId,
      sender: 'Transfer Desk',
      transferOfferId: offerId,
    );

    await refreshWorld();

    // shortcut: instant club response, defer this until the next game week when timing matters.
    await _processClubDecision(offerId);
    
    return null;
  }

  /// Process club's decision on transfer offer.
  Future<void> _processClubDecision(int offerId) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null) return;

    // Simple AI: accept if offer >= 95% of value, reject if < 80%, counter otherwise
    final double offerPercent = offer.offerAmount / offer.playerValue;
    
    if (offerPercent >= 0.95) {
      // Accepted - move to contract negotiation
      final int msgId = await _messages.insert(
        title: 'Transfer offer accepted!',
        body: '${offer.fromTeamName} accepted your offer of ${fmt.money(offer.offerAmount)} '
              'for ${offer.playerName}. Now negotiate contract terms.',
        teamId: userTeamId,
        sender: offer.fromTeamName,
        transferOfferId: offerId,
      );
      await _transfers.updateOfferStatus(
        offerId,
        t.offerAccepted,
        messageId: msgId,
      );
    } else if (offerPercent < 0.80) {
      // Rejected
      final int msgId = await _messages.insert(
        title: 'Transfer offer rejected',
        body: '${offer.fromTeamName} rejected your offer of ${fmt.money(offer.offerAmount)} '
              'for ${offer.playerName}. They want at least ${fmt.money(offer.playerValue)}.',
        teamId: userTeamId,
        sender: offer.fromTeamName,
        transferOfferId: offerId,
      );
      await _transfers.updateOfferStatus(
        offerId,
        t.offerRejected,
        messageId: msgId,
      );
    } else {
      // Counter offer
      final int counterAmount = (offer.playerValue * 0.95).round();
      final int msgId = await _messages.insert(
        title: 'Counter offer received',
        body: '${offer.fromTeamName} countered your offer for ${offer.playerName}. '
              'They want ${fmt.money(counterAmount)} instead of ${fmt.money(offer.offerAmount)}.',
        teamId: userTeamId,
        sender: offer.fromTeamName,
        transferOfferId: offerId,
      );
      await _transfers.updateOfferStatus(
        offerId,
        t.offerCountered,
        counterAmount: counterAmount,
        messageId: msgId,
      );
    }
    await refreshWorld();
  }

  /// Accept counter offer and move to contract negotiation.
  Future<String?> acceptCounterOffer(int offerId) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null) return 'Offer not found';
    if (offer.counterAmount == null) return 'No counter offer available';
    
    final Team? buyer = userTeam;
    if (buyer == null) return 'Unknown team';
    if (buyer.budget < offer.counterAmount!) return 'Not enough budget';

    final int msgId = await _messages.insert(
      title: 'Counter offer accepted',
      body: 'You accepted ${offer.fromTeamName}\'s counter offer of '
            '${fmt.money(offer.counterAmount!)} for ${offer.playerName}. '
            'Now negotiate contract terms.',
      teamId: userTeamId,
      sender: 'Transfer Desk',
      transferOfferId: offerId,
    );
    await _transfers.updateOfferStatus(
      offerId,
      t.offerAccepted,
      offerAmount: offer.counterAmount,
      messageId: msgId,
    );
    await refreshWorld();
    return null;
  }

  /// Accepts an AI club's offer for one of the manager's listed players.
  Future<String?> acceptSaleOffer(int offerId) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null || offer.fromTeamId != userTeamId) {
      return 'Sale offer not found';
    }
    if (offer.status != t.offerPending) return 'This offer is no longer active';

    await _transfers.updateOfferStatus(offerId, t.offerPlayerAccepted);
    final String? error = await _transfers.completeTransfer(offerId);
    if (error != null) {
      await _transfers.updateOfferStatus(offerId, t.offerPending);
      return error;
    }
    await _messages.insert(
      title: 'Player sold',
      body: '${offer.playerName} joined ${offer.toTeamName} for '
          '${fmt.money(offer.offerAmount)}.',
      teamId: userTeamId,
      sender: 'Transfer Desk',
      transferOfferId: offerId,
    );
    await refreshWorld();
    return null;
  }

  /// Responds to an AI club with a new fee for a listed player.
  Future<String?> counterSaleOffer(int offerId, int amount) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null || offer.fromTeamId != userTeamId) {
      return 'Sale offer not found';
    }
    if (offer.status != t.offerPending || amount <= 0) {
      return 'This offer is no longer active';
    }
    final Team? buyer = await _refs.teamById(offer.toTeamId);
    if (buyer == null || buyer.budget < amount) {
      return 'The buying club cannot afford that fee';
    }

    if (amount <= (offer.playerValue * 1.1).round()) {
      await _transfers.updateOfferStatus(
        offerId,
        t.offerPending,
        offerAmount: amount,
      );
      await _messages.insert(
        title: 'Counter offer accepted',
        body: '${offer.toTeamName} accepted ${fmt.money(amount)} for '
            '${offer.playerName}. Open this message to complete the sale.',
        teamId: userTeamId,
        sender: offer.toTeamName,
        transferOfferId: offerId,
      );
    } else {
      await _transfers.updateOfferStatus(offerId, t.offerRejected);
      await _messages.insert(
        title: 'Counter offer rejected',
        body: '${offer.toTeamName} rejected ${fmt.money(amount)} for '
            '${offer.playerName}.',
        teamId: userTeamId,
        sender: offer.toTeamName,
        transferOfferId: offerId,
      );
    }
    await refreshWorld();
    return null;
  }

  Future<void> rejectSaleOffer(int offerId) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null || offer.fromTeamId != userTeamId) return;
    await _transfers.updateOfferStatus(offerId, t.offerRejected);
    await _messages.insert(
      title: 'Transfer offer rejected',
      body: 'You rejected ${offer.toTeamName}\'s offer for ${offer.playerName}.',
      teamId: userTeamId,
      sender: 'Transfer Desk',
      transferOfferId: offerId,
    );
    await refreshWorld();
  }

  /// Accepts an AI club's loan offer for one of the manager's players.
  Future<String?> acceptLoanOffer(int offerId) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null || offer.fromTeamId != userTeamId) {
      return 'Loan offer not found';
    }
    if (offer.status != t.offerPending) return 'This offer is no longer active';

    final String? error = await _transfers.completeLoan(offerId);
    if (error != null) return error;

    await _messages.insert(
      title: 'Loan deal completed',
      body: '${offer.playerName} joined ${offer.toTeamName} on loan for '
          '${offer.loanSeasons == 1 ? '1 season' : '2 seasons'}. '
          'Your club received a loan fee of ${fmt.money(offer.offerAmount)}.',
      teamId: userTeamId,
      sender: 'Transfer Desk',
      transferOfferId: offerId,
    );
    await refreshWorld();
    return null;
  }

  Future<List<YouthProspect>> pendingProspects() =>
      _squads.pendingProspects(userTeamId);

  Future<Player?> signYouthProspect(int prospectId) async {
    final Player? player = await _squads.signProspect(prospectId);
    if (player != null) await refreshWorld();
    return player;
  }

  /// Propose contract terms to player.
  Future<String?> proposeContract({
    required int offerId,
    required int salary,
    required int durationYears,
  }) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null) return 'Offer not found';
    if (offer.status != t.offerAccepted) return 'Offer not yet accepted by club';

    await _transfers.updateContractProposal(
      offerId,
      salary: salary,
      durationYears: durationYears,
    );

    // Send notification about contract proposal
    await _messages.insert(
      title: 'Contract proposed to ${offer.playerName}',
      body: 'Salary: ${fmt.money(salary)}/season, Duration: $durationYears years. '
            'Awaiting player response...',
      teamId: userTeamId,
      sender: 'Transfer Desk',
      transferOfferId: offerId,
    );

    await refreshWorld();

    // shortcut: instant player response, defer this until the next game week when timing matters.
    await _processPlayerDecision(offerId);
    
    return null;
  }

  /// Process player's decision on contract offer.
  Future<void> _processPlayerDecision(int offerId) async {
    final TransferOffer? offer = await _transfers.getOffer(offerId);
    if (offer == null) return;
    if (offer.proposedSalary == null) return;

    // Simple AI: accept if salary >= current salary * 1.1
    final List<Map<String, Object?>> playerRows = await _db.query(
      t.players,
      where: 'player_id = ?',
      whereArgs: <Object?>[offer.playerId],
      limit: 1,
    );
    if (playerRows.isEmpty) return;
    
    final int currentSalary = (playerRows.first['salary'] as int?) ?? 0;
    final bool accepted = offer.proposedSalary! >= (currentSalary * 1.1).round();

    if (accepted) {
      // Player accepted - complete transfer
      final int msgId = await _messages.insert(
        title: 'Transfer completed!',
        body: '${offer.playerName} accepted your contract offer! '
              'Salary: ${fmt.money(offer.proposedSalary!)}/season, '
              'Duration: ${offer.proposedDurationYears} years.',
        teamId: userTeamId,
        sender: 'Transfer Desk',
        transferOfferId: offerId,
      );
      await _transfers.updateOfferStatus(offerId, t.offerPlayerAccepted, messageId: msgId);
      
      // Complete the transfer
      await _transfers.completeTransfer(offerId);
    } else {
      // Player rejected
      final int msgId = await _messages.insert(
        title: 'Contract rejected',
        body: '${offer.playerName} rejected your contract offer. '
              'They want at least ${fmt.money((currentSalary * 1.2).round())}/season.',
        teamId: userTeamId,
        sender: offer.playerName,
        transferOfferId: offerId,
      );
      await _transfers.updateOfferStatus(offerId, t.offerAccepted, messageId: msgId);
    }
    await refreshWorld();
  }

  Future<TransferOffer?> transferOffer(int offerId) =>
      _transfers.getOffer(offerId);

  /// Get pending transfer offers.
  Future<List<TransferOffer>> pendingTransferOffers() =>
      _transfers.pendingOffersForTeam(userTeamId);

  // ----------------------------------------------------------- sponsorships

  Future<List<ClubSponsorship>> activeSponsorships() =>
      _sponsorships.activeSponsorships(userTeamId, season?.seasonId ?? 0);

  Future<List<ClubSponsorship>> availableSponsorshipOffers() =>
      _sponsorships.availableOffers(
        teamId: userTeamId,
        seasonId: season?.seasonId ?? 0,
        clubPower: userTeam?.power ?? 60,
      );

  Future<void> signSponsorship(ClubSponsorship offer) async {
    await _sponsorships.signSponsorship(offer);
    await _messages.insert(
      title: 'Sponsorship signed: ${offer.sponsorName}',
      body: 'Signed ${offer.typeLabel} deal with ${offer.sponsorName}. '
          'Received upfront bonus of ${fmt.money(offer.baseReward)} and weekly '
          'payments of ${fmt.money(offer.weeklyReward)}.',
      teamId: userTeamId,
      sender: 'Commercial Director',
    );
    await refreshWorld();
  }

  // --------------------------------------------------------------- scouting

  Future<List<Scout>> hiredScouts() => _scouting.hiredScouts(userTeamId);

  List<Scout> availableScoutsToHire() => _scouting.availableScoutsToHire();

  Future<String?> hireScout(Scout candidate) async {
    final String? error = await _scouting.hireScout(userTeamId, candidate);
    if (error == null) await refreshWorld();
    return error;
  }

  Future<void> fireScout(int scoutId) async {
    await _scouting.fireScout(scoutId);
    await refreshWorld();
  }

  Future<List<ScoutWonderkid>> deployScout(Scout scout, String region) async {
    final String date = nextDate ?? '2025-08-01';
    final List<ScoutWonderkid> found = await _scouting.deployScout(
      teamId: userTeamId,
      scout: scout,
      region: region,
      date: date,
    );
    await _messages.insert(
      title: 'Scouting Report: ${scout.name} ($region)',
      body: '${scout.name} has completed scouting in $region and discovered '
          '${found.length} young wonderkids. Review their profiles in the Market Scouting tab.',
      teamId: userTeamId,
      sender: 'Chief Scout',
    );
    await refreshWorld();
    return found;
  }

  Future<List<ScoutWonderkid>> pendingWonderkids() =>
      _scouting.pendingWonderkids(userTeamId);

  Future<String?> signWonderkid(int reportId) async {
    final String? error = await _scouting.signWonderkid(
      reportId: reportId,
      teamId: userTeamId,
    );
    if (error == null) await refreshWorld();
    return error;
  }

  // ---------------------------------------------------------------- inbox

  Future<void> markMessageRead(Message m) async {
    if (m.isRead) return;
    await _messages.markRead(m.messageId);
    unreadCount = max(0, unreadCount - 1);
    notifyListeners();
  }
}

/// A live (watched) match session handed to the match screen.
class LiveMatchSession {
  LiveMatchSession({
    required this.match,
    required this.result,
    required this.homeTeam,
    required this.awayTeam,
    this.isCupFinal = false,
    this.isLeagueDecider = false,
    this.trophyName,
    this.leagueTitleWon = false,
    this.leg1Match,
    this.hasLeg2 = false,
  });

  final FixtureMatch match;
  final MatchResult result;
  final Team homeTeam;
  final Team awayTeam;
  final bool isCupFinal;
  final bool isLeagueDecider;
  final String? trophyName;
  final bool leagueTitleWon;
  final FixtureMatch? leg1Match;
  final bool hasLeg2;

  bool get isHighStakes => isCupFinal || isLeagueDecider;
  bool get isTwoLeggedTie => leg1Match != null || hasLeg2;
  bool get isLeg2 => match.leg == 2 && leg1Match != null;
  bool get isLeg1 => match.leg == 1 && hasLeg2;

  /// In Leg 1, current home team played away, and current away team played at home.
  int get leg1HomeGoals => leg1Match?.awayGoals ?? 0;
  int get leg1AwayGoals => leg1Match?.homeGoals ?? 0;

  /// Shootout kicks once a knockout tie ended level after 90 minutes.
  List<MatchEvent> get shootoutEvents => result.events
      .where((MatchEvent e) => e.type == MatchEvent.shootout)
      .toList();

  bool get decidedOnPenalties => shootoutEvents.isNotEmpty;

  int? get winnerId {
    if (result.homeGoals > result.awayGoals) return homeTeam.teamId;
    if (result.awayGoals > result.homeGoals) return awayTeam.teamId;
    if (decidedOnPenalties) {
      final int homePen = shootoutEvents
          .where((MatchEvent e) => e.isHome && e.detail?.startsWith('scored') == true)
          .length;
      final int awayPen = shootoutEvents
          .where((MatchEvent e) => !e.isHome && e.detail?.startsWith('scored') == true)
          .length;
      if (homePen > awayPen) return homeTeam.teamId;
      if (awayPen > homePen) return awayTeam.teamId;
    }
    return null;
  }

  bool isUserChampion(int userTeamId) {
    if (isCupFinal && winnerId == userTeamId) return true;
    if (isLeagueDecider && leagueTitleWon) return true;
    return false;
  }

  bool isUserRunnerUp(int userTeamId) {
    if (isCupFinal && winnerId != null && winnerId != userTeamId) return true;
    return false;
  }
}
