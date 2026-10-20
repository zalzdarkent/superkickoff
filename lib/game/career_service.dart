// ignore_for_file: prefer_initializing_formals

import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import '../data/repositories/match_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/reference_repository.dart';
import '../data/repositories/season_repository.dart';
import '../data/repositories/squad_repository.dart';
import 'match_engine.dart';
import 'season_generator.dart';

/// Orchestrates career progression on top of the repositories and the match
/// engine: AI match-day simulation, weekly housekeeping, cup round
/// progression, end-of-season awards / promotion / relegation, next season
/// generation and transfer-market AI.
class CareerService {
  CareerService(
    this.db, {
    required ReferenceRepository refs,
    required SeasonRepository seasons,
    required SquadRepository squads,
    required MatchRepository matches,
    required MessageRepository messages,
    required MatchEngine engine,
    required SeasonGenerator generator,
    Random? random,
    this.marketTickChance = 0.45,
  })  : _refs = refs,
        _seasons = seasons,
        _squads = squads,
        _matchRepo = matches,
        _messages = messages,
        _engine = engine,
        _gen = generator,
        _rng = random ?? Random();



  final Database db;
  final ReferenceRepository _refs;
  final SeasonRepository _seasons;
  final SquadRepository _squads;
  final MatchRepository _matchRepo;
  final MessageRepository _messages;
  final MatchEngine _engine;
  final SeasonGenerator _gen;
  final Random _rng;

  /// Chance that the AI transfer market does something each week.
  final double marketTickChance;

  // ------------------------------------------------------------ fixtures

  /// All scheduled matches of a season, sorted by date.
  Future<List<FixtureMatch>> upcomingMatches(int seasonId) =>
      db
          .query(
        t.matches,
        where: 'season_id = ? AND status = ?',
        whereArgs: <Object?>[seasonId, t.matchScheduled],
        orderBy: 'date ASC, match_id ASC',
      )
          .then((rows) => rows.map(FixtureMatch.fromMap).toList());

  /// The date of the next scheduled match (the current match day).
  Future<String?> nextMatchDate(int seasonId) async {
    final rows = await db.query(
      t.matches,
      columns: ['date'],
      where: 'season_id = ? AND status = ?',
      whereArgs: <Object?>[seasonId, t.matchScheduled],
      orderBy: 'date ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['date'] as String?;
  }

  /// All scheduled matches on [date].
  Future<List<FixtureMatch>> matchesOnDate(int seasonId, String date) =>
      db
          .query(
        t.matches,
        where: 'season_id = ? AND status = ? AND date = ?',
        whereArgs: <Object?>[seasonId, t.matchScheduled, date],
      )
          .then((rows) => rows.map(FixtureMatch.fromMap).toList());

  // ------------------------------------------------------------ simulation

  /// Builds engine input for [match]: squads, stadium capacity, referee.
  Future<MatchInput> prepareMatchInput(FixtureMatch match) async {
    final Team? home = await _refs.teamById(match.homeTeamId);
    final Team? away = await _refs.teamById(match.awayTeamId);
    if (home == null || away == null) {
      throw StateError('Missing teams for match ${match.matchId}');
    }
    final List<Player> homeSquad = await _squads.squadForTeam(home.teamId);
    final List<Player> awaySquad = await _squads.squadForTeam(away.teamId);

    final rows = await db.query(
      t.stadiums,
      columns: <String>[
        'capacity_general',
        'capacity_stand',
        'capacity_terrace',
        'capacity_boxes',
      ],
      where: 'stadium_id = ?',
      whereArgs: <Object?>[match.stadiumId],
      limit: 1,
    );
    final Map<String, Object?> cap =
        rows.isEmpty ? <String, Object?>{} : rows.first;

    return MatchInput(
      homeSquad: homeSquad,
      awaySquad: awaySquad,
      capacityGeneral: (cap['capacity_general'] as int?) ?? 0,
      capacityStand: (cap['capacity_stand'] as int?) ?? 0,
      capacityTerrace: (cap['capacity_terrace'] as int?) ?? 0,
      capacityBoxes: (cap['capacity_boxes'] as int?) ?? 0,
      homePower: home.power,
      homeTeamId: home.teamId,
      awayTeamId: away.teamId,
      refereeTemper: await _refereeTemper(match),
    );
  }

  Future<int> _refereeTemper(FixtureMatch match) async {
    final rows = await db.rawQuery('''
      SELECT rt.type_id AS type_id
      FROM referees r
      LEFT JOIN referee_types rt ON rt.type_id = r.type_id
      WHERE r.country_id IN (
        SELECT country_id FROM teams WHERE team_id IN (?, ?)
      )
      ORDER BY RANDOM() LIMIT 1
    ''', <Object?>[match.homeTeamId, match.awayTeamId]);
    final int? typeId = rows.isEmpty ? null : rows.first['type_id'] as int?;
    return typeId ?? 2;
  }

  /// Simulates [match] and persists the full result. Returns the result for
  /// the live viewer (events are already minute-ordered).
  Future<MatchResult> simulateMatch(
    FixtureMatch match, {
    bool recordEvents = true,
  }) async {
    final MatchInput input = await prepareMatchInput(match);
    final Set<int> banned = await _suspendedPlayerIds(match);
    final MatchResult result = _engine.simulate(
      input,
      recordEvents: recordEvents,
      bannedIds: banned,
    );
    await _matchRepo.saveResult(
      matchId: match.matchId,
      homeGoals: result.homeGoals,
      awayGoals: result.awayGoals,
      winnerId: result.homeGoals > result.awayGoals
          ? match.homeTeamId
          : (result.awayGoals > result.homeGoals ? match.awayTeamId : null),
      attendanceGeneral: result.attendanceGeneral,
      attendanceStand: result.attendanceStand,
      attendanceTerrace: result.attendanceTerrace,
      attendanceBoxes: result.attendanceBoxes,
      revenue: result.revenue,
      events: result.events.map((MatchEvent e) => e.toMap()).toList(),
      playerRows: result.playerRows.map(_playerRowToDb).toList(),
      injuredPlayerIds: result.events
          .where((MatchEvent e) => e.type == MatchEvent.injury)
          .map((MatchEvent e) => e.playerId ?? 0)
          .where((int id) => id > 0)
          .toList(),
      suspendedPlayerIds: result.events
          .where((MatchEvent e) => e.type == MatchEvent.red)
          .map((MatchEvent e) => e.playerId ?? 0)
          .where((int id) => id > 0)
          .toList(),
    );
    // Gate receipts stay with the home club.
    await _matchRepo.adjustBudget(match.homeTeamId, result.revenue);
    // Match fitness drops for everyone who featured.
    await _squads.applyMatchFatigue(<int>[
      for (final MatchPlayerRow row in result.playerRows)
        if (row.minutes > 0) row.playerId,
    ]);
    return result;
  }

  /// Player ids currently suspended for either club in [match].
  Future<Set<int>> _suspendedPlayerIds(FixtureMatch match) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.suspensions,
      columns: <String>['player_id'],
      where: 'player_id IN (SELECT player_id FROM team_players '
          'WHERE team_id IN (?, ?))',
      whereArgs: <Object?>[match.homeTeamId, match.awayTeamId],
    );
    return <int>{
      for (final Map<String, Object?> row in rows) row['player_id'] as int,
    };
  }

  static Map<String, Object?> _playerRowToDb(MatchPlayerRow row) =>
      <String, Object?>{
        'player_id': row.playerId,
        'team_id': row.teamId,
        'starter': row.starter,
        'minutes': row.minutes,
        'points': row.points,
        'rating': row.rating,
        'mvp': row.mvp,
        'goals': row.goals,
        'assists': row.assists,
        'yellow_cards': row.yellowCards,
        'red_cards': row.redCards,
      };

  /// Quick-simulates every scheduled match on [date] except [skipMatchId],
  /// which the player will play live.
  Future<Map<int, MatchResult>> simulateMatchday({
    required int seasonId,
    required String date,
    int? skipMatchId,
  }) async {
    final List<FixtureMatch> fixtures = await matchesOnDate(seasonId, date);
    final Map<int, MatchResult> results = <int, MatchResult>{};
    for (final FixtureMatch m in fixtures) {
      if (m.matchId == skipMatchId) continue;
      results[m.matchId] = await simulateMatch(m, recordEvents: false);
    }
    return results;
  }

  // ------------------------------------------------------------ housekeeping

  /// Weekly post-matchday tasks: suspension countdown, fitness recovery,
  /// per-team salaries and the AI transfer market.
  Future<void> weeklyHousekeeping({
    required int seasonId,
    required int userTeamId,
  }) async {
    final Set<int> stillBanned = await _matchRepo.tickSuspensions();
    stillBanned.clear(); // ids already tracked in DB; provider re-reads
    // Only clubs registered for this season need recovery; touching all 55k
    // players every week would be needlessly slow.
    await db.execute('''
      UPDATE players
      SET fitness = CASE
            WHEN fitness <= 40 THEN MIN(45, fitness + 2)
            ELSE MIN(100, fitness + 6)
          END
      WHERE status_id = ? AND player_id IN (
        SELECT tp.player_id
        FROM team_players tp
        JOIN season_teams st ON st.team_id = tp.team_id
        WHERE st.season_id = ?
      )
    ''', <Object?>[t.statusActive, seasonId]);
    await _matchRepo.paySalaries(seasonId);
    await db.execute('UPDATE teams SET budget = MAX(budget, 20000)');
    await _runMarketAi(userTeamId);
  }

  /// AI clubs occasionally buy listed players off the market (including
  /// players the user put up for sale).
  Future<void> _runMarketAi(int userTeamId) async {
    if (_rng.nextDouble() > marketTickChance) return;
    final List<Team> clubs = await _registeredClubs();
    if (clubs.length < 2) return;
    final List<Map<String, Object?>> listed = await _squads.marketPlayers(
      excludeTeamId: userTeamId,
      limit: 12,
    );
    for (final Map<String, Object?> entry in listed) {
      if (_rng.nextDouble() > 0.20) continue;
      final Player player = _playerFromRow(entry);
      final int sellerTeamId = entry['club_team_id'] as int? ?? 0;
      final Team buyer = clubs[_rng.nextInt(clubs.length)];
      if (buyer.teamId == sellerTeamId) continue;
      if (buyer.budget < player.value) continue;
      final String? error = await _squads.buyMarketPlayer(
        buyerTeamId: buyer.teamId,
        player: player,
      );
      if (error != null) continue;
      if (sellerTeamId == userTeamId) {
        await _messages.insert(
          title: 'Player sold',
          body:
              '${player.name} has been sold to ${buyer.name} for ${_money(player.value)}.',
          teamId: userTeamId,
          sender: 'Transfer Desk',
        );
      }
      break; // at most one AI transfer per housekeeping week
    }
  }

  Future<List<Team>> _registeredClubs() async {
    final Season? season = await _seasons.currentSeason();
    if (season == null) return <Team>[];
    final rows = await db.rawQuery('''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''', <Object?>[season.seasonId]);
    return rows.map(Team.fromMap).toList();
  }

  Player _playerFromRow(Map<String, Object?> row) => Player(
        playerId: row['player_id'] as int,
        name: row['name'] as String,
        age: (row['age'] as int?) ?? 18,
        positionId: (row['position_id'] as int?) ?? 1,
        power: (row['power'] as int?) ?? 50,
        potential: (row['potential'] as int?) ?? 50,
        fitness: (row['fitness'] as int?) ?? 100,
        value: (row['value'] as int?) ?? 0,
        salary: (row['salary'] as int?) ?? 0,
        countryId: (row['country_id'] as int?) ?? 0,
        squadStatus: t.squadFirstTeam,
        marketStatus: t.marketForSale,
        statusId: t.statusActive,
        isCaptain: false,
        shirtNumber: 0,
        stars: (row['stars'] as int?) ?? 0,
        skillA: 0,
        skillB: 0,
        height: 178,
        championships: null,
      );

  static String _money(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return '$amount';
  }

  // -------------------------------------------------------- cup progression

  /// If the current cup phase fully finished, schedules the next round.
  /// Returns true when new cup fixtures were created.
  Future<bool> maybeScheduleNextCupRound({
    required int seasonId,
    required int cupTournamentId,
    required Map<int, Team> teamCache,
  }) async {
    final int remaining =
        await _seasons.remainingMatches(seasonId, cupTournamentId);
    if (remaining != 0) return false;
    final rows = await db.rawQuery('''
      SELECT winner_id FROM matches
      WHERE season_id = ? AND tournament_id = ?
        AND phase = (SELECT MAX(phase) FROM matches
                     WHERE season_id = ? AND tournament_id = ?)
        AND status = ? AND winner_id IS NOT NULL
    ''', <Object?>[seasonId, cupTournamentId, seasonId, cupTournamentId, t.matchFinished]);
    final List<int> survivors = <int>[
      for (final Map<String, Object?> row in rows)
        if (row['winner_id'] is int) row['winner_id'] as int,
    ];
    if (survivors.length < 2) return false;
    final rowsMax = await db.rawQuery('''
      SELECT MAX(phase) AS max_phase FROM matches
      WHERE season_id = ? AND tournament_id = ?
    ''', <Object?>[seasonId, cupTournamentId]);
    final int? maxPhase =
        rowsMax.isEmpty ? null : rowsMax.first['max_phase'] as int?;
    if (maxPhase == null) return false;
    final List<Map<String, Object?>> lastDateRows = await db.rawQuery('''
      SELECT MAX(date) AS last_date FROM matches
      WHERE season_id = ? AND tournament_id = ?
    ''', <Object?>[seasonId, cupTournamentId]);
    final String? lastDate = lastDateRows.isEmpty
        ? null
        : lastDateRows.first['last_date'] as String?;
    final List<Map<String, Object?>> seasonRows = await db.query(
      t.seasons,
      columns: <String>['start_year'],
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
      limit: 1,
    );
    final int startYear =
        seasonRows.isEmpty ? 2025 : (seasonRows.first['start_year'] as int? ?? 2025);
    final DateTime base =
        DateTime.tryParse(lastDate ?? '') ?? DateTime(startYear, 8, 9);
    final DateTime date =
        _nextWednesday(base.add(const Duration(days: 8)));
    final int scheduled = await _gen.scheduleCupRound(
      seasonId,
      cupTournamentId,
      survivors,
      phase: maxPhase + 1,
      date: date,
      allTeams: teamCache,
    );
    return scheduled > 0;
  }

  DateTime _nextWednesday(DateTime from) {
    DateTime d = from;
    while (d.weekday != DateTime.wednesday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  // ------------------------------------------------------------- season end

  /// True once every scheduled match of the season has been played.
  Future<bool> seasonComplete(int seasonId) async {
    final int? remaining = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM matches
      WHERE season_id = ? AND status = ?
    ''', <Object?>[seasonId, t.matchScheduled]));
    return (remaining ?? 1) == 0;
  }

  /// End-of-season flow: prizes, promotion/relegation, ageing & retirement,
  /// archiving (which also aggregates player stats), then the next season.
  Future<Season> completeSeason({
    required int userTeamId,
    required void Function(String) onProgress,
  }) async {
    final Season? current = await _seasons.currentSeason();
    if (current == null) {
      throw StateError('No season to complete');
    }
    final List<Tournament> tournaments =
        await _seasonTournaments(current.seasonId);

    onProgress('Awarding prizes...');
    for (final Tournament tour in tournaments) {
      if (tour.isLeague) {
        final List<StandingRow> table =
            await _seasons.standings(current.seasonId, tour.tournamentId);
        if (table.isEmpty) continue;
        await _matchRepo.adjustBudget(table.first.teamId, tour.prizeTeams);
        final Team? champion = await _refs.teamById(table.first.teamId);
        await _messages.insert(
          title: 'Champion!',
          body:
              '${champion?.name ?? table.first.name} are champions of ${tour.name}.',
          sender: 'League',
        );
      } else if (tour.isNationalCup) {
        final rows = await db.rawQuery('''
          SELECT winner_id, COUNT(*) AS wins FROM matches
          WHERE season_id = ? AND tournament_id = ? AND winner_id IS NOT NULL
          GROUP BY winner_id ORDER BY wins DESC LIMIT 1
        ''', <Object?>[current.seasonId, tour.tournamentId]);
        if (rows.isEmpty) continue;
        final int cupWinnerId = rows.first['winner_id'] as int;
        await _matchRepo.adjustBudget(cupWinnerId, tour.prizeTeams);
        final Team? winner = await _refs.teamById(cupWinnerId);
        await _messages.insert(
          title: 'Cup Glory',
          body: '${winner?.name ?? 'A club'} lifts the ${tour.name} trophy.',
          sender: 'Cup',
        );
      }
    }

    onProgress('Promotion and relegation...');
    for (final Tournament tour in tournaments) {
      if (!tour.isLeague) continue;
      final List<StandingRow> table =
          await _seasons.standings(current.seasonId, tour.tournamentId);
      await _applyPromotionRelegation(tour, table);
    }

    onProgress('Ageing squads...');
    await _ageAndRetire();

    onProgress('Archiving season stats...');
    for (final Tournament tour in tournaments) {
      await _seasons.archiveSeasonTournament(
          current.seasonId, tour.tournamentId);
    }

    onProgress('Preparing the new season...');
    final Team? userTeam = await _refs.teamById(userTeamId);
    if (userTeam == null) {
      throw StateError('User team vanished');
    }
    final rows = await db.rawQuery('''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tu.organization = ? AND tc.country_id = ? AND tu.division_id = ?
      LIMIT 1
    ''', <Object?>[t.orgLeague, userTeam.countryId, userTeam.division]);
    final Tournament? nextLeague =
        rows.isEmpty ? null : Tournament.fromMap(rows.first);
    final Map<String, Object?>? cupRow =
        await _refs.nationalCup(userTeam.countryId);
    final Tournament? nextCup =
        cupRow == null ? null : Tournament.fromMap(cupRow);
    if (nextLeague == null) {
      return current; // nothing more we can generate; provider decides.
    }

    final CareerPlan plan = await _gen.generateCareer(
      countryId: userTeam.countryId,
      league: nextLeague,
      cup: nextCup,
      startYear: current.startYear + 1,
    );
    await _messages.insert(
      title: plan.season.name,
      body: 'Fixtures are out for the new season — good luck!',
      sender: 'League',
    );
    return plan.season;
  }

  Future<List<Tournament>> _seasonTournaments(int seasonId) async {
    final rows = await db.rawQuery('''
      SELECT tu.* FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      WHERE st.season_id = ? AND st.status = ?
    ''', <Object?>[seasonId, t.seasonTournamentActive]);
    return rows.map(Tournament.fromMap).toList();
  }

  Future<void> _applyPromotionRelegation(
    Tournament tour,
    List<StandingRow> table,
  ) async {
    if (table.isEmpty) return;
    // Promote the top N (their division moves up: 2 -> 1).
    for (int i = 0; i < min(table.length, tour.promotionSlots); i++) {
      final StandingRow row = table[i];
      if (tour.divisionId > 1) {
        await db.execute(
          'UPDATE teams SET division = division - 1 WHERE team_id = ? AND division > 1',
          <Object?>[row.teamId],
        );
      }
    }
    // Relegate the bottom M (their division moves down).
    for (int i = max(0, table.length - tour.relegationSpots);
        i < table.length;
        i++) {
      final StandingRow row = table[i];
      await db.execute(
        'UPDATE teams SET division = division + 1 WHERE team_id = ?',
        <Object?>[row.teamId],
      );
    }
  }

  Future<void> _ageAndRetire() async {
    await _seasons.ageSquad();
    await db.execute(
        'UPDATE players SET status_id = ? WHERE status_id = ? AND age >= 41',
        <Object?>[t.statusRetired, t.statusActive]);
    // 37-40 year olds with fading power also hang up their boots.
    await db.execute(
        '''UPDATE players SET status_id = ? WHERE status_id = ? AND age >= 37
           AND power < 55''',
        <Object?>[t.statusRetired, t.statusActive]);
    await db.execute(
        '''DELETE FROM team_players WHERE player_id IN (
             SELECT player_id FROM players WHERE status_id = ?)''',
        <Object?>[t.statusRetired]);
    await db.execute(
        '''UPDATE contracts SET status = 0 WHERE player_id IN (
             SELECT player_id FROM players WHERE status_id = ?)''',
        <Object?>[t.statusRetired]);
  }
}
