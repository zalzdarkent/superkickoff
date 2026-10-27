// ignore_for_file: prefer_initializing_formals

import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import '../data/repositories/facilities_repository.dart';
import '../data/repositories/match_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/prize_repository.dart';
import '../data/repositories/reference_repository.dart';
import '../data/repositories/scouting_repository.dart';
import '../data/repositories/season_repository.dart';
import '../data/repositories/squad_repository.dart';
import '../data/repositories/sponsorship_repository.dart';
import '../data/repositories/transfer_repository.dart';
import 'formation.dart';
import 'match_engine.dart';
import 'offseason.dart';
import 'player_valuation_service.dart';
import 'prize_engine.dart';
import 'competition_config.dart';
import 'fixture_scheduler.dart';
import 'season_generator.dart';
import 'training.dart';
import 'transfer_window_manager.dart';

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
    PrizeRepository? prizes,
    TransferRepository? transfers,
    SponsorshipRepository? sponsorships,
    ScoutingRepository? scouting,
    FacilitiesRepository? facilities,
    TransferWindowManager? windowManager,
    Random? random,
    this.marketTickChance = 0.45,
  }) : _refs = refs,
       _seasons = seasons,
       _squads = squads,
       _matchRepo = matches,
       _messages = messages,
       _prizes = prizes,
       _transfers = transfers,
       _sponsorships = sponsorships,
       _scouting = scouting,
       _facilities = facilities ?? FacilitiesRepository(db),
       _windowManager =
           windowManager ?? TransferWindowManager(db, messages: messages),
       _engine = engine,
       _gen = generator,
       _rng = random ?? Random();

  final Database db;
  final ReferenceRepository _refs;
  final SeasonRepository _seasons;
  final SquadRepository _squads;
  final MatchRepository _matchRepo;
  final MessageRepository _messages;
  final PrizeRepository? _prizes;
  final TransferRepository? _transfers;
  final SponsorshipRepository? _sponsorships;
  final ScoutingRepository? _scouting;
  final FacilitiesRepository _facilities;
  final TransferWindowManager _windowManager;
  final MatchEngine _engine;
  final SeasonGenerator _gen;
  final Random _rng;

  FacilitiesRepository get facilities => _facilities;

  TransferWindowManager get windowManager => _windowManager;
  String? _lastHousekeepingDate;

  /// Cup tournaments already resolved to knockout status.
  final Set<int> _cupTournaments = <int>{};

  /// Chance that the AI transfer market does something each week.
  final double marketTickChance;

  // ------------------------------------------------------------ fixtures

  /// All scheduled matches of a season, sorted by date.
  Future<List<FixtureMatch>> upcomingMatches(int seasonId) => db
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

  /// Matches on [date]. Scheduled games only unless [scheduledOnly] is false,
  /// which is used to show a finished matchday.
  Future<List<FixtureMatch>> matchesOnDate(
    int seasonId,
    String date, {
    bool scheduledOnly = true,
  }) => db
      .query(
        t.matches,
        where: scheduledOnly
            ? 'season_id = ? AND status = ? AND date = ?'
            : 'season_id = ? AND date = ?',
        whereArgs: scheduledOnly
            ? <Object?>[seasonId, t.matchScheduled, date]
            : <Object?>[seasonId, date],
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
    final List<Player> homeSquad = (await _squads.squadForTeam(home.teamId))
        .where(
          (Player player) => player.injuryDaysRemaining(match.date) == null,
        )
        .toList();
    final List<Player> awaySquad = (await _squads.squadForTeam(away.teamId))
        .where(
          (Player player) => player.injuryDaysRemaining(match.date) == null,
        )
        .toList();
    final Formation homeFormation = Formation.parse(
      await _squads.formationForTeam(home.teamId),
    );
    final Formation awayFormation = Formation.parse(
      await _squads.formationForTeam(away.teamId),
    );

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
    final Map<String, Object?> cap = rows.isEmpty
        ? <String, Object?>{}
        : rows.first;

    final ClubFacilities homeFac = await _facilities.getFacilities(home.teamId);
    final ClubFacilities awayFac = await _facilities.getFacilities(away.teamId);
    final ClubStaff? homePhysio = await _facilities.getStaffByRole(
      home.teamId,
      'head_physio',
    );
    final ClubStaff? awayPhysio = await _facilities.getStaffByRole(
      away.teamId,
      'head_physio',
    );
    final ClubStaff? homeAnalyst = await _facilities.getStaffByRole(
      home.teamId,
      'tactical_analyst',
    );
    final ClubStaff? awayAnalyst = await _facilities.getStaffByRole(
      away.teamId,
      'tactical_analyst',
    );

    final double homeInjuryReduction = (homeFac.injuryReductionRate +
            (homePhysio != null ? homePhysio.stars * 0.04 : 0.0))
        .clamp(0.0, 0.45);
    final double awayInjuryReduction = (awayFac.injuryReductionRate +
            (awayPhysio != null ? awayPhysio.stars * 0.04 : 0.0))
        .clamp(0.0, 0.45);

    final double homeTacticalBonus =
        (homeAnalyst != null && homeAnalyst.stars >= 3)
            ? (homeAnalyst.stars * 0.015)
            : 0.0;
    final double awayTacticalBonus =
        (awayAnalyst != null && awayAnalyst.stars >= 3)
            ? (awayAnalyst.stars * 0.015)
            : 0.0;

    return MatchInput(
      homeSquad: homeSquad,
      awaySquad: awaySquad,
      capacityGeneral: (cap['capacity_general'] as int?) ?? 0,
      capacityStand: (cap['capacity_stand'] as int?) ?? 0,
      capacityTerrace: (cap['capacity_terrace'] as int?) ?? 0,
      capacityBoxes: (cap['capacity_boxes'] as int?) ?? 0,
      homePower: home.power,
      homeFormation: homeFormation,
      awayFormation: awayFormation,
      homeTeamId: home.teamId,
      awayTeamId: away.teamId,
      homeLineupIds: await _lineupIds(home.teamId),
      awayLineupIds: await _lineupIds(away.teamId),
      refereeTemper: await _refereeTemper(match),
      homeInjuryReduction: homeInjuryReduction,
      awayInjuryReduction: awayInjuryReduction,
      homeTacticalBonus: homeTacticalBonus,
      awayTacticalBonus: awayTacticalBonus,
    );
  }

  Future<List<int>> _lineupIds(int teamId) async {
    final Map<int, int> slots = await _squads.lineupForTeam(teamId);
    final List<MapEntry<int, int>> entries = slots.entries.toList()
      ..sort(
        (MapEntry<int, int> a, MapEntry<int, int> b) => a.key.compareTo(b.key),
      );
    return entries.map((MapEntry<int, int> e) => e.value).toList();
  }

  Future<int> _refereeTemper(FixtureMatch match) async {
    final rows = await db.rawQuery(
      '''
      SELECT rt.type_id AS type_id
      FROM referees r
      LEFT JOIN referee_types rt ON rt.type_id = r.type_id
      WHERE r.country_id IN (
        SELECT country_id FROM teams WHERE team_id IN (?, ?)
      )
      ORDER BY RANDOM() LIMIT 1
    ''',
      <Object?>[match.homeTeamId, match.awayTeamId],
    );
    final int? typeId = rows.isEmpty ? null : rows.first['type_id'] as int?;
    return typeId ?? 2;
  }

  /// Ultra-fast simulation for background AI-vs-AI matches (cups, lower divisions).
  /// Generates score and advances bracket in < 0.1ms without heavy database operations.
  Future<MatchResult> simulateMatchFast(FixtureMatch match) async {
    final Team? home = await _refs.teamById(match.homeTeamId);
    final Team? away = await _refs.teamById(match.awayTeamId);
    final int homePower = home?.power ?? 60;
    final int awayPower = away?.power ?? 60;

    final (int homeGoals, int awayGoals) = _engine.quickSimulate(
      homePower: homePower + 3,
      awayPower: awayPower,
    );

    int? winnerId = homeGoals > awayGoals
        ? match.homeTeamId
        : (awayGoals > homeGoals ? match.awayTeamId : null);
    int? penaltyHome;
    int? penaltyAway;

    if (await _isKnockout(match)) {
      if (match.leg == 1) {
        final bool hasLeg2 =
            (Sqflite.firstIntValue(
                  await db.rawQuery(
                    '''
                SELECT COUNT(*) FROM matches
                WHERE season_id = ? AND tournament_id = ? AND phase = ? AND leg = 2
                  AND home_team_id = ? AND away_team_id = ?
                ''',
                    <Object?>[
                      match.seasonId,
                      match.tournamentId,
                      match.phase,
                      match.awayTeamId,
                      match.homeTeamId,
                    ],
                  ),
                ) ??
                0) >
            0;
        if (!hasLeg2 && winnerId == null) {
          penaltyHome = _rng.nextInt(3) + 4;
          penaltyAway = penaltyHome + (_rng.nextBool() ? 1 : -1);
          if (penaltyHome == penaltyAway) penaltyHome = penaltyHome + 1;
          winnerId = penaltyHome > penaltyAway
              ? match.homeTeamId
              : match.awayTeamId;
        }
      } else if (match.leg == 2) {
        final List<Map<String, Object?>> leg1Rows = await db.query(
          t.matches,
          where:
              'season_id = ? AND tournament_id = ? AND phase = ? AND leg = 1 '
              'AND home_team_id = ? AND away_team_id = ?',
          whereArgs: <Object?>[
            match.seasonId,
            match.tournamentId,
            match.phase,
            match.awayTeamId,
            match.homeTeamId,
          ],
          limit: 1,
        );
        if (leg1Rows.isNotEmpty) {
          final int leg1Away = (leg1Rows.first['away_goals'] as int?) ?? 0;
          final int leg1Home = (leg1Rows.first['home_goals'] as int?) ?? 0;
          final int homeAgg = homeGoals + leg1Away;
          final int awayAgg = awayGoals + leg1Home;
          if (homeAgg > awayAgg) {
            winnerId = match.homeTeamId;
          } else if (awayAgg > homeAgg) {
            winnerId = match.awayTeamId;
          } else if (match.awayGoalsRule && leg1Away != awayGoals) {
            winnerId = leg1Away > awayGoals
                ? match.homeTeamId
                : match.awayTeamId;
          } else {
            penaltyHome = _rng.nextInt(3) + 4;
            penaltyAway = penaltyHome + (_rng.nextBool() ? 1 : -1);
            if (penaltyHome == penaltyAway) penaltyHome = penaltyHome + 1;
            winnerId = penaltyHome > penaltyAway
                ? match.homeTeamId
                : match.awayTeamId;
          }
        }
      } else if (winnerId == null) {
        penaltyHome = _rng.nextInt(3) + 4;
        penaltyAway = penaltyHome + (_rng.nextBool() ? 1 : -1);
        if (penaltyHome == penaltyAway) penaltyHome = penaltyHome + 1;
        winnerId = penaltyHome > penaltyAway
            ? match.homeTeamId
            : match.awayTeamId;
      }
    }

    await db.update(
      t.matches,
      <String, Object?>{
        'home_goals': homeGoals,
        'away_goals': awayGoals,
        'winner_id': winnerId,
        'penalty_home_goals': penaltyHome,
        'penalty_away_goals': penaltyAway,
        'status': t.matchFinished,
      },
      where: 'match_id = ?',
      whereArgs: <Object?>[match.matchId],
    );

    return MatchResult(
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      events: const <MatchEvent>[],
      playerRows: const <MatchPlayerRow>[],
      attendanceGeneral: 0,
      attendanceStand: 0,
      attendanceTerrace: 0,
      attendanceBoxes: 0,
      revenue: 0,
      homeShots: homeGoals + _rng.nextInt(4) + 2,
      awayShots: awayGoals + _rng.nextInt(4) + 2,
      homeShotsOnTarget: homeGoals + _rng.nextInt(3),
      awayShotsOnTarget: awayGoals + _rng.nextInt(3),
      homeSaves: awayGoals > 0 ? _rng.nextInt(3) : 0,
      awaySaves: homeGoals > 0 ? _rng.nextInt(3) : 0,
      homePossession: 50,
      input: MatchInput(
        homeSquad: const <Player>[],
        awaySquad: const <Player>[],
        capacityGeneral: 0,
        capacityStand: 0,
        capacityTerrace: 0,
        capacityBoxes: 0,
        homePower: homePower,
        homeFormation: Formation.f442,
        awayFormation: Formation.f442,
        homeTeamId: match.homeTeamId,
        awayTeamId: match.awayTeamId,
        homeLineupIds: const <int>[],
        awayLineupIds: const <int>[],
        refereeTemper: 2,
      ),
    );
  }

  /// Simulates [match] and persists the full result. Returns the result for
  /// the live viewer (events are already minute-ordered).
  Future<MatchResult> simulateMatch(
    FixtureMatch match, {
    bool recordEvents = true,
    int? userTeamId,
    int? userLeagueId,
  }) async {
    final bool isUserTeam =
        (userTeamId != null) &&
        (match.homeTeamId == userTeamId || match.awayTeamId == userTeamId);
    final bool isTargetLeague = userLeagueId != null
        ? match.tournamentId == userLeagueId
        : !(await _isKnockout(match));

    // Fast-path: AI-vs-AI matches not in the user's league or cup matches.
    if (!recordEvents && !isUserTeam && !isTargetLeague) {
      return simulateMatchFast(match);
    }

    final MatchInput input = await prepareMatchInput(match);
    final Set<int> banned = await _suspendedPlayerIds(match);
    final MatchResult result = _engine.simulate(
      input,
      recordEvents: recordEvents,
      bannedIds: banned,
    );
    int? winnerId = result.homeGoals > result.awayGoals
        ? match.homeTeamId
        : (result.awayGoals > result.homeGoals ? match.awayTeamId : null);
    int? penaltyHome;
    int? penaltyAway;
    List<MatchEvent> events = result.events;

    // Check knockout rules and 2-legged ties:
    if (await _isKnockout(match)) {
      if (match.leg == 1) {
        final bool hasLeg2 =
            (Sqflite.firstIntValue(
                  await db.rawQuery(
                    '''
          SELECT COUNT(*) FROM matches
          WHERE season_id = ? AND tournament_id = ? AND phase = ? AND leg = 2
            AND home_team_id = ? AND away_team_id = ?
        ''',
                    <Object?>[
                      match.seasonId,
                      match.tournamentId,
                      match.phase,
                      match.awayTeamId,
                      match.homeTeamId,
                    ],
                  ),
                ) ??
                0) >
            0;

        if (!hasLeg2 && winnerId == null) {
          // Single-leg tie ended level -> shootout.
          final MatchPenaltyShootout shootout = _engine.penaltyShootout(
            result.input,
          );
          penaltyHome = shootout.homeScore;
          penaltyAway = shootout.awayScore;
          winnerId = shootout.homeScore > shootout.awayScore
              ? match.homeTeamId
              : match.awayTeamId;
          events = <MatchEvent>[...result.events, ...shootout.events];
        }
        // In Leg 1 of a 2-leg tie, draws stand without a shootout.
      } else if (match.leg == 2) {
        // Leg 2 of a 2-legged tie: evaluate aggregate score.
        final List<Map<String, Object?>> leg1Rows = await db.query(
          t.matches,
          where:
              'season_id = ? AND tournament_id = ? AND phase = ? AND leg = 1 '
              'AND home_team_id = ? AND away_team_id = ?',
          whereArgs: <Object?>[
            match.seasonId,
            match.tournamentId,
            match.phase,
            match.awayTeamId,
            match.homeTeamId,
          ],
          limit: 1,
        );
        if (leg1Rows.isNotEmpty) {
          final int leg1Away = (leg1Rows.first['away_goals'] as int?) ?? 0;
          final int leg1Home = (leg1Rows.first['home_goals'] as int?) ?? 0;
          final int homeAgg = result.homeGoals + leg1Away;
          final int awayAgg = result.awayGoals + leg1Home;

          if (homeAgg > awayAgg) {
            winnerId = match.homeTeamId;
          } else if (awayAgg > homeAgg) {
            winnerId = match.awayTeamId;
          } else if (match.awayGoalsRule && leg1Away != result.awayGoals) {
            // Away-goals rule is opt-in. The club with more away goals wins
            // without a shootout.
            winnerId = leg1Away > result.awayGoals
                ? match.homeTeamId
                : match.awayTeamId;
          } else {
            // Aggregate score is level: shootout in Leg 2 decides the tie.
            final MatchPenaltyShootout shootout = _engine.penaltyShootout(
              result.input,
            );
            penaltyHome = shootout.homeScore;
            penaltyAway = shootout.awayScore;
            winnerId = shootout.homeScore > shootout.awayScore
                ? match.homeTeamId
                : match.awayTeamId;
            events = <MatchEvent>[...result.events, ...shootout.events];
          }
        } else if (winnerId == null) {
          final MatchPenaltyShootout shootout = _engine.penaltyShootout(
            result.input,
          );
          penaltyHome = shootout.homeScore;
          penaltyAway = shootout.awayScore;
          winnerId = shootout.homeScore > shootout.awayScore
              ? match.homeTeamId
              : match.awayTeamId;
          events = <MatchEvent>[...result.events, ...shootout.events];
        }
      } else if (winnerId == null) {
        final MatchPenaltyShootout shootout = _engine.penaltyShootout(
          result.input,
        );
        penaltyHome = shootout.homeScore;
        penaltyAway = shootout.awayScore;
        winnerId = shootout.homeScore > shootout.awayScore
            ? match.homeTeamId
            : match.awayTeamId;
        events = <MatchEvent>[...result.events, ...shootout.events];
      }
    }
    final DateTime? matchDate = DateTime.tryParse(match.date ?? '');
    final Map<int, String> injuryReturnDates = <int, String>{
      if (matchDate != null)
        for (final MatchEvent event in result.events.where(
          (MatchEvent event) =>
              event.type == MatchEvent.injury && event.playerId != null,
        ))
          event.playerId!: matchDate
              .add(Duration(days: _rng.nextInt(14) + 1))
              .toIso8601String()
              .substring(0, 10),
    };
    await _matchRepo.saveResult(
      matchId: match.matchId,
      homeGoals: result.homeGoals,
      awayGoals: result.awayGoals,
      winnerId: winnerId,
      penaltyHomeGoals: penaltyHome,
      penaltyAwayGoals: penaltyAway,
      attendanceGeneral: result.attendanceGeneral,
      attendanceStand: result.attendanceStand,
      attendanceTerrace: result.attendanceTerrace,
      attendanceBoxes: result.attendanceBoxes,
      revenue: result.revenue,
      events: events.map((MatchEvent e) => e.toMap()).toList(),
      playerRows: result.playerRows.map(_playerRowToDb).toList(),
      injuredPlayerIds: result.events
          .where((MatchEvent e) => e.type == MatchEvent.injury)
          .map((MatchEvent e) => e.playerId ?? 0)
          .where((int id) => id > 0)
          .toList(),
      injuryReturnDates: injuryReturnDates,
      suspendedPlayerIds: result.events
          .where((MatchEvent e) => e.type == MatchEvent.red)
          .map((MatchEvent e) => e.playerId ?? 0)
          .where((int id) => id > 0)
          .toList(),
    );
    // Gate receipts stay with the home club.
    await _matchRepo.adjustBudget(match.homeTeamId, result.revenue);
    // Match fitness drops for everyone who featured, mitigated by club physios.
    final ClubStaff? homePhysio = await _facilities.getStaffByRole(
      match.homeTeamId,
      'head_physio',
    );
    final ClubStaff? awayPhysio = await _facilities.getStaffByRole(
      match.awayTeamId,
      'head_physio',
    );
    final int homeDrop = (homePhysio != null && homePhysio.stars >= 3)
        ? (homePhysio.stars >= 5 ? 5 : 6)
        : 8;
    final int awayDrop = (awayPhysio != null && awayPhysio.stars >= 3)
        ? (awayPhysio.stars >= 5 ? 5 : 6)
        : 8;

    final Set<int> homeIds = {
      for (final Player p in result.input.homeSquad) p.playerId,
    };
    final List<int> homeFeatured = <int>[
      for (final MatchPlayerRow row in result.playerRows)
        if (row.minutes > 0 && homeIds.contains(row.playerId)) row.playerId,
    ];
    final List<int> awayFeatured = <int>[
      for (final MatchPlayerRow row in result.playerRows)
        if (row.minutes > 0 && !homeIds.contains(row.playerId)) row.playerId,
    ];

    await _squads.applyMatchFatigue(homeFeatured, drop: homeDrop);
    await _squads.applyMatchFatigue(awayFeatured, drop: awayDrop);
    return result;
  }

  Future<bool> _isKnockout(FixtureMatch match) async {
    // Group and league-phase matches are table stages: draws stand after 90
    // minutes, just like leagues. `phase == 0` marks those stages.
    if (match.groupId != null) return false;
    if (match.phase == 0) return false;
    if (_cupTournaments.contains(match.tournamentId)) return true;
    final List<Map<String, Object?>> rows = await db.query(
      t.tournaments,
      columns: <String>['organization'],
      where: 'tournament_id = ?',
      whereArgs: <Object?>[match.tournamentId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final int org = (rows.first['organization'] as int?) ?? 0;
    final bool isCup = org == t.orgNationalCup || org == t.orgInternational;
    if (isCup) _cupTournaments.add(match.tournamentId);
    return isCup;
  }

  /// Player ids currently suspended for either club in [match].
  Future<Set<int>> _suspendedPlayerIds(FixtureMatch match) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.suspensions,
      columns: <String>['player_id'],
      where:
          'player_id IN (SELECT player_id FROM team_players '
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

  /// Quick-simulates scheduled matches on [date] except [skipMatchId],
  /// which the player will play live. If [tournamentId] is provided, only matches
  /// for that tournament will be simulated.
  Future<Map<int, MatchResult>> simulateMatchday({
    required int seasonId,
    required String date,
    int? skipMatchId,
    int? tournamentId,
    int? userTeamId,
    int? userLeagueId,
  }) async {
    final List<FixtureMatch> fixtures = await matchesOnDate(seasonId, date);
    final Map<int, MatchResult> results = <int, MatchResult>{};
    for (final FixtureMatch m in fixtures) {
      if (m.matchId == skipMatchId) continue;
      if (tournamentId != null && m.tournamentId != tournamentId) continue;
      results[m.matchId] = await simulateMatch(
        m,
        recordEvents: false,
        userTeamId: userTeamId,
        userLeagueId: userLeagueId,
      );
    }
    return results;
  }

  // ------------------------------------------------------------ housekeeping

  /// Weekly post-matchday tasks: suspension countdown, fitness recovery,
  /// per-team salaries and the AI transfer market.
  Future<void> weeklyHousekeeping({
    required int seasonId,
    required int userTeamId,
    String? currentDate,
  }) async {
    final Set<int> stillBanned = await _matchRepo.tickSuspensions();
    stillBanned.clear(); // ids already tracked in DB; provider re-reads
    // Only clubs registered for this season need recovery; touching all 55k
    // players every week would be needlessly slow.
    await db.execute(
      '''
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
    ''',
      <Object?>[t.statusActive, seasonId],
    );
    await _matchRepo.paySalaries(seasonId);
    if (_sponsorships != null) {
      await _sponsorships.payWeekly(userTeamId, seasonId);
    }
    if (_scouting != null) {
      final List<Scout> hired = await _scouting.hiredScouts(userTeamId);
      final int scoutWages = hired.fold<int>(
        0,
        (int sum, Scout s) => sum + s.salary,
      );
      if (scoutWages > 0) {
        await db.execute(
          'UPDATE teams SET budget = MAX(0, budget - ?) WHERE team_id = ?',
          <Object?>[scoutWages, userTeamId],
        );
      }
    }

    // Medical Centre & Head Physio recovery boost for user team
    final ClubFacilities userFac = await _facilities.getFacilities(userTeamId);
    final ClubStaff? userPhysio = await _facilities.getStaffByRole(
      userTeamId,
      'head_physio',
    );
    final int physioStars = userPhysio?.stars ?? 0;
    final int extraRecovery =
        userFac.weeklyFitnessBonus + (physioStars / 2).round();
    final int injuredBonus = physioStars + (userFac.medicalLevel >= 3 ? 2 : 0);

    if (extraRecovery > 0 || injuredBonus > 0) {
      await db.execute(
        '''
        UPDATE players
        SET fitness = CASE
              WHEN fitness <= 40 THEN MIN(55, fitness + ?)
              ELSE MIN(100, fitness + ?)
            END
        WHERE status_id = ? AND player_id IN (
          SELECT player_id FROM team_players WHERE team_id = ?
        )
      ''',
        <Object?>[injuredBonus, extraRecovery, t.statusActive, userTeamId],
      );
    }

    // Pay Coaching & Professional Staff Wages
    final int staffWages = await _facilities.totalWeeklyStaffWages(userTeamId);
    if (staffWages > 0) {
      await db.execute(
        'UPDATE teams SET budget = MAX(0, budget - ?) WHERE team_id = ?',
        <Object?>[staffWages, userTeamId],
      );
    }
    await db.execute('UPDATE teams SET budget = MAX(budget, 20000)');
    await _runYouthAcademy(userTeamId, seasonId);

    // Transfer window & scheduled transfer processing
    final String? nextDate = await nextMatchDate(seasonId);
    final String date = currentDate ?? nextDate ?? _todayIso();

    final Season? currentSeason = await _seasons.currentSeason();
    if (currentSeason != null) {
      await _windowManager.ensureWindowsForSeason(
        seasonId,
        currentSeason.startYear,
      );
    }

    if (_transfers != null) {
      final List<ScheduledTransferResult> results = await _transfers
          .processDueScheduledTransfers(date);
      for (final ScheduledTransferResult res in results) {
        if (res.offer.fromTeamId == userTeamId ||
            res.offer.toTeamId == userTeamId) {
          if (res.success) {
            await _messages.insert(
              title: 'Transfer Terjadwal Tuntas',
              body:
                  '${res.offer.playerName} resmi bergabung dengan ${res.offer.toTeamName} '
                  'sesuai kesepakatan transfer terjadwal.',
              teamId: userTeamId,
              sender: 'Transfer Desk',
              date: date,
              transferOfferId: res.offer.offerId,
            );
          } else {
            await _messages.insert(
              title: 'Transfer Terjadwal Dibatalkan',
              body:
                  'Kepindahan ${res.offer.playerName} ke ${res.offer.toTeamName} gagal: ${res.error}.',
              teamId: userTeamId,
              sender: 'Transfer Desk',
              date: date,
              transferOfferId: res.offer.offerId,
            );
          }
        }
      }
    }

    if (_lastHousekeepingDate != null) {
      await _windowManager.checkAndSendNotifications(
        seasonId: seasonId,
        userTeamId: userTeamId,
        previousDate: _lastHousekeepingDate!,
        currentDate: date,
      );
    }
    _lastHousekeepingDate = date;

    await _runMarketAi(userTeamId, seasonId: seasonId, currentDate: date);
    await runAiTraining(userTeamId: userTeamId, seasonId: seasonId);
  }

  /// Academy graduates arrive every three in-game months.
  Future<void> _runYouthAcademy(int userTeamId, int seasonId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT MAX(date) AS last_date FROM matches
      WHERE season_id = ? AND status = ? AND date IS NOT NULL
    ''',
      <Object?>[seasonId, t.matchFinished],
    );
    String? date = rows.isEmpty ? null : rows.first['last_date'] as String?;
    if (date == null) {
      final List<Map<String, Object?>> minRows = await db.rawQuery(
        'SELECT MIN(date) AS first_date FROM matches WHERE season_id = ? AND date IS NOT NULL',
        <Object?>[seasonId],
      );
      date = minRows.isEmpty ? null : minRows.first['first_date'] as String?;
    }
    if (date == null) return;
    final List<YouthProspect> graduates = await _squads
        .graduateYouthPlayersIfDue(teamId: userTeamId, date: date);
    if (graduates.isEmpty) return;
    await _messages.insert(
      title: 'Youth Academy Intake: ${graduates.length} new prospects',
      body:
          'Our youth academy has scouted ${graduates.length} new prospects. '
          'Review their profiles and decide which ones to promote to your squad.',
      teamId: userTeamId,
      sender: 'Youth Academy',
    );
  }

  /// Finds one interested AI club when the manager lists a player for loan.
  Future<void> requestLoanOffer({
    required int userTeamId,
    required Player player,
  }) async {
    final TransferRepository? transfers = _transfers;
    if (transfers == null) return;
    final int loanSeasons = 1 + _rng.nextInt(2);
    final int loanFee = const PlayerValuationService().calculateLoanFee(
      marketValue: player.value,
      loanSeasons: loanSeasons,
    );
    // Only clubs that can actually pay the fee make an offer.
    final List<Team> candidates = (await _registeredClubs())
        .where(
          (Team team) => team.teamId != userTeamId && team.budget >= loanFee,
        )
        .toList();
    if (candidates.isEmpty) return;

    final Team borrower = candidates[_rng.nextInt(candidates.length)];
    final int offerId = await transfers.createOffer(
      playerId: player.playerId,
      fromTeamId: userTeamId,
      toTeamId: borrower.teamId,
      offerAmount: loanFee,
      playerValue: player.value,
      isLoan: true,
      loanSeasons: loanSeasons,
    );
    await _messages.insert(
      title: 'Loan offer: ${player.name}',
      body:
          '${borrower.name} wants to take ${player.name} on loan for '
          '${loanSeasons == 1 ? '1 season' : '2 seasons'}. '
          'They offer a loan fee of ${_money(loanFee)} and will cover his wages.',
      teamId: userTeamId,
      sender: borrower.name,
      transferOfferId: offerId,
    );
  }

  /// Finds one interested AI buyer when the manager lists a player for sale.
  /// The manager receives the offer in the inbox and decides whether to sell.
  Future<void> requestSaleOffer({
    required int userTeamId,
    required Player player,
  }) async {
    final TransferRepository? transfers = _transfers;
    if (transfers == null) return;
    const PlayerValuationService valuation = PlayerValuationService();
    final int askingPrice = valuation.calculateAskingPrice(
      marketValue: player.value,
      contractMonthsRemaining: 24,
      isTransferListed: true,
    );
    final List<Team> candidates = (await _registeredClubs())
        .where(
          (Team team) =>
              team.teamId != userTeamId &&
              team.budget >= (askingPrice * 0.75).round(),
        )
        .toList();
    if (candidates.isEmpty) return;

    final Team buyer = candidates[_rng.nextInt(candidates.length)];
    final double offerFactor = 0.85 + _rng.nextDouble() * 0.25;
    final int offerAmount = (askingPrice * offerFactor)
        .round()
        .clamp(1, buyer.budget);
    final int offerId = await transfers.createOffer(
      playerId: player.playerId,
      fromTeamId: userTeamId,
      toTeamId: buyer.teamId,
      offerAmount: offerAmount,
      playerValue: player.value,
    );
    await _messages.insert(
      title: 'Transfer offer received',
      body:
          '${buyer.name} offered ${_money(offerAmount)} for ${player.name}. '
          'Open this message to accept, reject, or make a counter offer.',
      teamId: userTeamId,
      sender: buyer.name,
      transferOfferId: offerId,
    );
  }

  /// AI clubs buy listed players or plan scheduled transfers.
  Future<void> _runMarketAi(
    int userTeamId, {
    int? seasonId,
    String? currentDate,
  }) async {
    final String date = currentDate ?? _todayIso();
    final int effectiveSeasonId =
        seasonId ?? (await _seasons.currentSeason())?.seasonId ?? 0;

    // Check if user or clubs are in Deadline Day
    final TransferWindow? activeWindow = await _windowManager
        .activeWindowForTeam(effectiveSeasonId, userTeamId, date);
    final bool isDeadline = activeWindow?.isDeadlineDay(date) ?? false;
    // On deadline day, AI activity is significantly higher (frenzy)
    final double tickChance = isDeadline
        ? min(0.95, marketTickChance * 2.5)
        : marketTickChance;

    if (_rng.nextDouble() > tickChance) return;
    final List<Team> clubs = await _registeredClubs();
    if (clubs.length < 2) return;
    final List<Map<String, Object?>> listed = await _squads.marketPlayers(
      excludeTeamId: userTeamId,
      limit: 12,
    );
    for (final Map<String, Object?> entry in listed) {
      if (_rng.nextDouble() > 0.25) continue;
      final Player player = _playerFromRow(entry);
      final int sellerTeamId = entry['club_team_id'] as int? ?? 0;
      final Team buyer = clubs[_rng.nextInt(clubs.length)];
      if (buyer.teamId == sellerTeamId) continue;
      if (buyer.budget < player.value) continue;

      // Check destination club's registration window
      final bool isOpen = await _windowManager.isWindowOpenForTeam(
        effectiveSeasonId,
        buyer.teamId,
        date,
      );

      if (isOpen) {
        // Window is open: buy player immediately
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
            date: date,
          );
        }
      } else {
        // Window is closed: AI plans a scheduled transfer for the next valid window
        if (_transfers == null) continue;
        final TransferWindow nextWindow = await _windowManager
            .nextRegistrationWindowForTeam(
              effectiveSeasonId,
              buyer.teamId,
              date,
            );
        final int offerId = await _transfers.createOffer(
          playerId: player.playerId,
          fromTeamId: sellerTeamId,
          toTeamId: buyer.teamId,
          offerAmount: player.value,
          playerValue: player.value,
          agreementDate: date,
          effectiveDate: nextWindow.startDate,
          eligibleDate: nextWindow.startDate,
        );
        await _transfers.scheduleTransfer(
          offerId,
          agreementDate: date,
          effectiveDate: nextWindow.startDate,
        );

        if (sellerTeamId == userTeamId) {
          await _messages.insert(
            title: 'Transfer Terjadwal Disepakati',
            body:
                '${buyer.name} telah menyetujui transfer ${player.name} seharga ${_money(player.value)}. '
                'Pemain tetap berada di klub Anda hingga jendela transfer dibuka pada ${nextWindow.startDate}.',
            teamId: userTeamId,
            sender: 'Transfer Desk',
            date: date,
            transferOfferId: offerId,
          );
        }
      }
      break; // at most one AI transfer per housekeeping week
    }
  }

  /// Automated weekly training for AI clubs participating in [seasonId].
  /// Progress rate is tuned to be ~10% below the user club's maximum pace
  /// (90% success rate per eligible player vs user's 100% guarantee),
  /// ensuring AI squads progress naturally while preserving the user's
  /// managerial edge.
  /// Returns the number of AI players that improved during this session.
  Future<int> runAiTraining({
    required int userTeamId,
    required int seasonId,
  }) async {
    final List<Map<String, Object?>> aiClubRows = await db.rawQuery(
      '''
      SELECT tm.team_id, tm.budget FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ? AND tm.team_id != ?
    ''',
      <Object?>[seasonId, userTeamId],
    );
    if (aiClubRows.isEmpty) return 0;

    int totalImproved = 0;
    final Set<int> improvedTeamIds = <int>{};

    for (final Map<String, Object?> club in aiClubRows) {
      final int teamId = club['team_id'] as int;
      final int budget = (club['budget'] as int?) ?? 0;

      // Select up to TrainingRules.maxPlayers (3) players with room to grow:
      // Focus on younger players with highest growth room (potential - power)
      final List<Map<String, Object?>> eligible = await db.rawQuery(
        '''
        SELECT p.player_id, p.power, p.potential, p.age, p.value
        FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        WHERE tp.team_id = ? AND p.status_id = ? AND p.power < p.potential
        ORDER BY (p.potential - p.power) DESC, p.age ASC
        LIMIT ?
      ''',
        <Object?>[teamId, t.statusActive, TrainingRules.maxPlayers],
      );

      if (eligible.isEmpty) continue;

      bool teamImproved = false;
      for (final Map<String, Object?> player in eligible) {
        // AI progress rate is ~10% below user (90% chance vs user's 100%)
        if (_rng.nextDouble() > 0.90) continue;

        final int playerId = player['player_id'] as int;
        final int power = (player['power'] as int?) ?? 50;
        final int potential = (player['potential'] as int?) ?? power;
        final int age = (player['age'] as int?) ?? 22;
        final int value = (player['value'] as int?) ?? 0;

        final int newPower = min(potential, power + TrainingRules.powerGain);
        if (newPower <= power) continue;

        final int newValue = SquadRepository.valueAfterOverallChange(
          currentValue: value,
          previousPower: power,
          newPower: newPower,
          age: age,
        );

        await db.update(
          t.players,
          <String, Object?>{'power': newPower, 'value': newValue},
          where: 'player_id = ?',
          whereArgs: <Object?>[playerId],
        );
        teamImproved = true;
        totalImproved++;
      }

      if (teamImproved) {
        improvedTeamIds.add(teamId);
        if (budget >= TrainingRules.cost) {
          await db.execute(
            'UPDATE teams SET budget = budget - ? WHERE team_id = ?',
            <Object?>[TrainingRules.cost, teamId],
          );
        }
      }
    }

    // Refresh overall team power in database for teams with upgraded players
    for (final int teamId in improvedTeamIds) {
      await _squads.refreshTeamPower(teamId);
    }

    return totalImproved;
  }

  Future<List<Team>> _registeredClubs() async {
    final Season? season = await _seasons.currentSeason();
    if (season == null) return <Team>[];
    final rows = await db.rawQuery(
      '''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[season.seasonId],
    );
    return rows.map(Team.fromMap).toList();
  }

  Player _playerFromRow(Map<String, Object?> row) => Player(
    playerId: row['player_id'] as int,
    name: row['name'] as String,
    age: (row['age'] as int?) ?? 18,
    positionId: (row['position_id'] as int?) ?? 1,
    profile: (row['profile'] as String?) ?? 'D',
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

  static String _todayIso() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // -------------------------------------------------------- cup progression

  /// If the current cup phase fully finished, schedules the next round.
  /// Returns true when new cup fixtures were created.
  Future<bool> maybeScheduleNextCupRound({
    required int seasonId,
    required int cupTournamentId,
    required Map<int, Team> teamCache,
  }) async {
    final int remaining = await _seasons.remainingMatches(
      seasonId,
      cupTournamentId,
    );
    if (remaining != 0) return false;

    final CompetitionConfig config = await _competitionConfig(
      cupTournamentId,
      seasonId,
    );

    // Group-stage competitions: once every group match is played, the top
    // two clubs of each group enter the knockout bracket.
    final List<GroupTable> groups = await _seasons.groupTables(
      seasonId,
      cupTournamentId,
    );
    if (config.format == CompetitionFormat.groupStage && groups.isNotEmpty) {
      final int? knockoutMatches = Sqflite.firstIntValue(
        await db.rawQuery(
          '''
          SELECT COUNT(*) FROM matches
          WHERE season_id = ? AND tournament_id = ? AND group_id IS NULL
            AND phase > 0
        ''',
          <Object?>[seasonId, cupTournamentId],
        ),
      );
      if ((knockoutMatches ?? 0) == 0) {
        final KnockoutPlan plan = _planGroupKnockout(
          groups,
          config.groupQualifiersPerGroup,
        );
        if (plan.isEmpty) return false;
        final List<int> qualifiers = <int>{
          for (final (int a, int b) in plan.pairs) ...<int>[a, b],
          ...plan.byes,
        }.toList();
        final int scheduled = await _gen.scheduleCupRound(
          seasonId,
          cupTournamentId,
          qualifiers,
          phase: 1,
          date: await _nextCupDate(
            seasonId,
            cupTournamentId,
            teamIds: qualifiers,
          ),
          allTeams: teamCache,
          pairs: plan.pairs,
          byes: plan.byes,
        );
        await _gen.resolveFixtureClashes(seasonId);
        return scheduled > 0;
      }
    }

    // UEFA-style league phase: the configured number of top clubs advance
    // straight to the knockout stage (the bundled game does not model the
    // play-off round).
    if (config.format == CompetitionFormat.leaguePhase) {
      final int? knockoutMatches = Sqflite.firstIntValue(
        await db.rawQuery(
          '''
          SELECT COUNT(*) FROM matches
          WHERE season_id = ? AND tournament_id = ? AND group_id IS NULL
            AND phase > 0
        ''',
          <Object?>[seasonId, cupTournamentId],
        ),
      );
      if ((knockoutMatches ?? 0) == 0) {
        final List<StandingRow> table = await _seasons.standings(
          seasonId,
          cupTournamentId,
        );
        final List<int> qualifiers = table
            .take(config.leaguePhaseQualifiers)
            .map((StandingRow row) => row.teamId)
            .toList();
        if (qualifiers.length < 2) return false;
        final int scheduled = await _gen.scheduleCupRound(
          seasonId,
          cupTournamentId,
          qualifiers,
          phase: 1,
          date: await _nextCupDate(
            seasonId,
            cupTournamentId,
            teamIds: qualifiers,
          ),
          allTeams: teamCache,
        );
        await _gen.resolveFixtureClashes(seasonId);
        return scheduled > 0;
      }
    }

    final rows = await db.rawQuery(
      '''
      SELECT winner_id FROM matches
      WHERE season_id = ? AND tournament_id = ?
        AND phase = (SELECT MAX(phase) FROM matches
                     WHERE season_id = ? AND tournament_id = ?)
        AND (leg = 2 OR leg = (
          SELECT MAX(m2.leg) FROM matches m2
          WHERE m2.season_id = matches.season_id
            AND m2.tournament_id = matches.tournament_id
            AND m2.phase = matches.phase
        ))
        AND status = ? AND winner_id IS NOT NULL
      ORDER BY match_id ASC
    ''',
      <Object?>[
        seasonId,
        cupTournamentId,
        seasonId,
        cupTournamentId,
        t.matchFinished,
      ],
    );
    final List<int> winners = <int>[];
    final Set<int> seenWinners = <int>{};
    for (final Map<String, Object?> row in rows) {
      final int? wid = row['winner_id'] as int?;
      if (wid != null && seenWinners.add(wid)) {
        winners.add(wid);
      }
    }
    final rowsMax = await db.rawQuery(
      '''
      SELECT MAX(phase) AS max_phase FROM matches
      WHERE season_id = ? AND tournament_id = ?
    ''',
      <Object?>[seasonId, cupTournamentId],
    );
    final int? maxPhase = rowsMax.isEmpty
        ? null
        : rowsMax.first['max_phase'] as int?;
    if (maxPhase == null) return false;

    // Clubs with a bye in the finished phase never appear in the match rows,
    // but they are still part of the next round.
    final List<int> byes = await _gen.byesForPhase(
      seasonId,
      cupTournamentId,
      maxPhase,
    );
    final List<int> survivors = <int>[...byes, ...winners];
    if (byes.isNotEmpty) {
      survivors.sort(
        (int a, int b) =>
            (teamCache[b]?.power ?? 0).compareTo(teamCache[a]?.power ?? 0),
      );
    }
    if (survivors.length < 2) return false;

    final DateTime date = await _nextCupDate(
      seasonId,
      cupTournamentId,
      teamIds: survivors,
    );
    final List<(int, int)> nextPairs = <(int, int)>[];
    for (int i = 0; i + 1 < survivors.length; i += 2) {
      if (survivors[i] != survivors[i + 1]) {
        nextPairs.add((survivors[i], survivors[i + 1]));
      }
    }
    final int scheduled = await _gen.scheduleCupRound(
      seasonId,
      cupTournamentId,
      survivors,
      phase: maxPhase + 1,
      date: date,
      allTeams: teamCache,
      pairs: byes.isEmpty && nextPairs.length * 2 == survivors.length
          ? nextPairs
          : null,
    );
    await _gen.resolveFixtureClashes(seasonId);
    return scheduled > 0;
  }

  Future<CompetitionConfig> _competitionConfig(
    int tournamentId,
    int seasonId,
  ) async {
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
      );
    }
    return _gen.configForSeason(tournamentId, seasonId);
  }

  /// Pairs group winners against runners-up across different groups, placing
  /// teams from the same group in opposite halves of the bracket tree so they
  /// cannot meet before the final.
  static KnockoutPlan _planGroupKnockout(
    List<GroupTable> groups,
    int qualifiersPerGroup,
  ) {
    final List<(int, int)> pairs = <(int, int)>[];
    final Set<int> paired = <int>{};
    if (qualifiersPerGroup <= 0 || groups.isEmpty) {
      return KnockoutPlan(bracketSize: 0, pairs: pairs, byes: <int>[]);
    }

    void tryPair(int a, int b) {
      if (a != b && paired.add(a) && paired.add(b)) {
        pairs.add((a, b));
      }
    }

    if (qualifiersPerGroup != 2 || groups.length < 2 || groups.length.isOdd) {
      final List<int> qualified = <int>[];
      for (int place = 0; place < qualifiersPerGroup; place++) {
        final Iterable<GroupTable> orderedGroups = place.isOdd
            ? groups.reversed
            : groups;
        for (final GroupTable group in orderedGroups) {
          if (group.rows.length > place) {
            qualified.add(group.rows[place].teamId);
          }
        }
      }
      return KnockoutScheduler.planOpeningRound(qualified);
    }
    // Top bracket half: even group winners vs odd group runners-up.
    for (int i = 0; i < groups.length; i += 2) {
      if (groups[i].rows.isNotEmpty && groups[i + 1].rows.length > 1) {
        tryPair(groups[i].rows[0].teamId, groups[i + 1].rows[1].teamId);
      }
    }
    // Bottom bracket half: odd group winners vs even group runners-up.
    for (int i = 0; i < groups.length; i += 2) {
      if (groups[i + 1].rows.isNotEmpty && groups[i].rows.length > 1) {
        tryPair(groups[i + 1].rows[0].teamId, groups[i].rows[1].teamId);
      }
    }
    return KnockoutPlan(
      bracketSize: groups.length * qualifiersPerGroup,
      pairs: pairs,
      byes: <int>[],
    );
  }

  /// Safe weekday (Tuesdays, Wednesdays, or Thursdays) after the latest fixture
  /// of a cup, avoiding conflict with existing fixtures of participating teams.
  Future<DateTime> _nextCupDate(
    int seasonId,
    int tournamentId, {
    List<int>? teamIds,
  }) async {
    final CompetitionConfig config = await _competitionConfig(
      tournamentId,
      seasonId,
    );
    final List<Map<String, Object?>> lastDateRows = await db.rawQuery(
      '''
      SELECT MAX(date) AS last_date FROM matches
      WHERE season_id = ? AND tournament_id = ?
    ''',
      <Object?>[seasonId, tournamentId],
    );
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
    final int startYear = seasonRows.isEmpty
        ? 2025
        : (seasonRows.first['start_year'] as int? ?? 2025);
    final DateTime base =
        DateTime.tryParse(lastDate ?? '') ?? DateTime(startYear, 8, 9);

    final List<Map<String, Object?>> conflictRows = await db.rawQuery(
      '''
      SELECT date, home_team_id, away_team_id FROM matches
      WHERE season_id = ? AND date IS NOT NULL
    ''',
      <Object?>[seasonId],
    );
    final Map<int, List<DateTime>> teamMatchDates = <int, List<DateTime>>{};
    for (final Map<String, Object?> r in conflictRows) {
      final DateTime? d = DateTime.tryParse('${r['date']}');
      if (d == null) continue;
      final int h = r['home_team_id'] as int;
      final int a = r['away_team_id'] as int;
      teamMatchDates.putIfAbsent(h, () => <DateTime>[]).add(d);
      teamMatchDates.putIfAbsent(a, () => <DateTime>[]).add(d);
    }

    final Set<int> participating = teamIds == null
        ? const <int>{}
        : teamIds.toSet();
    final Set<String> unavailable = <String>{
      for (final DateTime date in config.unavailableDates) _isoDate(date),
    };

    bool sameDayClash(DateTime date) => participating.any((int id) {
      final List<DateTime>? dates = teamMatchDates[id];
      if (dates == null) return false;
      return dates.any((DateTime existing) => existing == date);
    });

    bool restClash(DateTime date) => participating.any((int id) {
      final List<DateTime>? dates = teamMatchDates[id];
      if (dates == null) return false;
      return dates.any(
        (DateTime existing) =>
            existing.difference(date).inDays.abs() < config.minRestDays,
      );
    });

    DateTime? fallback;
    final DateTime seed = base.add(
      Duration(days: max(7, config.matchdayIntervalDays)),
    );
    for (int offset = 0; offset <= 400; offset++) {
      final DateTime candidate = seed.add(Duration(days: offset));
      final int wd = candidate.weekday;
      if (wd != DateTime.tuesday &&
          wd != DateTime.wednesday &&
          wd != DateTime.thursday) {
        continue;
      }
      if (sameDayClash(candidate) ||
          unavailable.contains(_isoDate(candidate))) {
        continue;
      }
      fallback ??= candidate;
      if (!restClash(candidate)) return candidate;
    }
    return fallback ?? seed;
  }

  Future<int> resolveFixtureClashes(int seasonId) =>
      _gen.resolveFixtureClashes(seasonId);

  Future<void> repairSelfMatches(int seasonId) =>
      _gen.repairSelfMatches(seasonId);

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------- season end

  /// True once every scheduled match of the season has been played.
  Future<bool> seasonComplete(int seasonId) async {
    final int? remaining = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
      SELECT COUNT(*) FROM matches
      WHERE season_id = ? AND status = ?
    ''',
        <Object?>[seasonId, t.matchScheduled],
      ),
    );
    return (remaining ?? 1) == 0;
  }

  /// Computes and pays prize money for every completed competition, using the
  /// configuration-driven [PrizeEngine]. Payouts are idempotent per season.
  Future<Set<String>> _awardCompetitionPrizes({
    required int seasonId,
    required int userTeamId,
    required List<Tournament> tournaments,
  }) async {
    final PrizeRepository? prizes = _prizes;
    if (prizes == null || tournaments.isEmpty) return <String>{};

    final List<int> ids = tournaments
        .map((Tournament tour) => tour.tournamentId)
        .toList();
    final PrizeEngine engine = PrizeEngine(
      configOverrides: await prizes.overrides(ids),
    );
    final Set<String> titles = <String>{};
    final String date = _todayIso();

    for (final Tournament tour in tournaments) {
      final CompetitionProfile? profile = await _competitionProfile(
        seasonId,
        tour,
      );
      if (profile == null) continue;

      CompetitionPrizeResult? result;
      if (tour.isLeague) {
        final List<StandingRow> table = await _seasons.standings(
          seasonId,
          tour.tournamentId,
        );
        if (table.isEmpty) continue;
        result = engine.leaguePrizes(
          tournamentId: tour.tournamentId,
          profile: profile,
          rankedTeamIds: table.map((StandingRow r) => r.teamId).toList(),
        );
        if (table.first.teamId == userTeamId) titles.add(tour.name);
        final Team? champion = await _refs.teamById(table.first.teamId);
        await _messages.insert(
          title: 'Champion!',
          body:
              '${champion?.name ?? table.first.name} are champions of ${tour.name}.',
          sender: 'League',
        );
      } else {
        final int? winnerId = await _knockoutWinner(
          seasonId,
          tour.tournamentId,
        );
        if (winnerId == null) continue;
        final Map<int, int> reached = await _knockoutRoundsReached(
          seasonId,
          tour.tournamentId,
        );
        if (reached.isEmpty) continue;
        final int maxRound = reached.values.reduce(
          (int a, int b) => a > b ? a : b,
        );
        final int? runnerUpId = await _knockoutRunnerUp(
          seasonId,
          tour.tournamentId,
          maxRound,
          winnerId,
        );
        final Map<String, Map<int, int>> tally = await _matchTally(
          seasonId,
          tour.tournamentId,
        );
        result = engine.cupPrizes(
          tournamentId: tour.tournamentId,
          kind: profile.kind,
          profile: profile,
          reachedRoundByTeam: reached,
          maxRound: maxRound,
          winnerTeamId: winnerId,
          runnerUpTeamId: runnerUpId,
          winsByTeam: tally['wins'],
          drawsByTeam: tally['draws'],
        );
        if (winnerId == userTeamId) titles.add(tour.name);
        final Team? winner = await _refs.teamById(winnerId);
        await _messages.insert(
          title: 'Cup Glory',
          body: '${winner?.name ?? 'A club'} lifts the ${tour.name} trophy.',
          sender: 'Cup',
        );
      }

      final List<PrizeAward> paid = await prizes.pay(
        seasonId: seasonId,
        result: result,
        date: date,
      );
      final List<PrizeAward> mine = paid
          .where((PrizeAward a) => a.teamId == userTeamId)
          .toList();
      if (mine.isNotEmpty) {
        await _messages.insert(
          title: 'Prize money: ${tour.name}',
          body:
              '${tour.name} paid your club '
              '${_money(mine.fold<int>(0, (int s, PrizeAward a) => s + a.amount))} '
              'in prize money.',
          teamId: userTeamId,
          sender: 'Competition',
        );
      }
    }
    return titles;
  }

  /// Builds the input profile used to scale a competition's prize money.
  Future<CompetitionProfile?> _competitionProfile(
    int seasonId,
    Tournament tour,
  ) async {
    final int? entrants = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(DISTINCT team_id) FROM (
          SELECT home_team_id AS team_id FROM matches
          WHERE season_id = ? AND tournament_id = ?
          UNION
          SELECT away_team_id FROM matches
          WHERE season_id = ? AND tournament_id = ?
        )
      ''',
        <Object?>[seasonId, tour.tournamentId, seasonId, tour.tournamentId],
      ),
    );
    final int clubCount = entrants ?? tour.slots;
    if (clubCount <= 0) return null;

    final List<Map<String, Object?>> countryRows = await db.rawQuery(
      '''
      SELECT MAX(c.power) AS power, MAX(c.confederation) AS confederation
      FROM tournament_countries tc
      JOIN countries c ON c.country_id = tc.country_id
      WHERE tc.tournament_id = ?
    ''',
      <Object?>[tour.tournamentId],
    );
    final int countryPower =
        ((countryRows.isEmpty ? null : countryRows.first['power']) as int?) ??
        60;
    final int confederation =
        ((countryRows.isEmpty ? null : countryRows.first['confederation'])
            as int?) ??
        0;

    final CompetitionKind kind = PrizeEngine.kindOf(
      organization: tour.organization,
      entrants: clubCount,
      nameHintSlots: tour.slots,
    );
    return CompetitionProfile(
      kind: kind,
      tier: max(tour.divisionId, 1),
      entrants: clubCount,
      countryPower: countryPower,
      confederation: confederation,
      slots: tour.rounds,
      legacyPrizeTeams: tour.prizeTeams,
    );
  }

  /// Deepest knockout round each club reached in a cup competition.
  Future<Map<int, int>> _knockoutRoundsReached(
    int seasonId,
    int tournamentId,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT team_id, MAX(round_reached) AS round_reached FROM (
        SELECT home_team_id AS team_id, phase AS round_reached FROM matches
        WHERE season_id = ? AND tournament_id = ?
        UNION ALL
        SELECT away_team_id, phase FROM matches
        WHERE season_id = ? AND tournament_id = ?
      )
      GROUP BY team_id
    ''',
      <Object?>[seasonId, tournamentId, seasonId, tournamentId],
    );
    return <int, int>{
      for (final Map<String, Object?> row in rows)
        row['team_id'] as int: (row['round_reached'] as int?) ?? 0,
    };
  }

  /// Final runner-up: the club that lost the last knockout round.
  Future<int?> _knockoutRunnerUp(
    int seasonId,
    int tournamentId,
    int maxRound,
    int winnerId,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT home_team_id, away_team_id FROM matches
      WHERE season_id = ? AND tournament_id = ? AND phase = ?
        AND status = ? AND winner_id IS NOT NULL
      LIMIT 1
    ''',
      <Object?>[seasonId, tournamentId, maxRound, t.matchFinished],
    );
    if (rows.isEmpty) return null;
    final int home = rows.first['home_team_id'] as int;
    final int away = rows.first['away_team_id'] as int;
    final int runnerUp = home == winnerId ? away : home;
    return runnerUp == winnerId ? null : runnerUp;
  }

  /// Wins and draws per club in a competition.
  Future<Map<String, Map<int, int>>> _matchTally(
    int seasonId,
    int tournamentId,
  ) async {
    final Map<int, int> wins = <int, int>{};
    final Map<int, int> draws = <int, int>{};
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT home_team_id, away_team_id, home_goals, away_goals FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
        AND home_goals IS NOT NULL AND away_goals IS NOT NULL
    ''',
      <Object?>[seasonId, tournamentId, t.matchFinished],
    );
    for (final Map<String, Object?> row in rows) {
      final int home = row['home_team_id'] as int;
      final int away = row['away_team_id'] as int;
      final int hg = (row['home_goals'] as int?) ?? 0;
      final int ag = (row['away_goals'] as int?) ?? 0;
      if (hg == ag) {
        draws[home] = (draws[home] ?? 0) + 1;
        draws[away] = (draws[away] ?? 0) + 1;
        continue;
      }
      final int winner = hg > ag ? home : away;
      wins[winner] = (wins[winner] ?? 0) + 1;
    }
    return <String, Map<int, int>>{'wins': wins, 'draws': draws};
  }

  // ------------------------------------------------------------ off-season

  /// Runs the whole break in one go (no manager decisions). The game itself
  /// walks the stages one at a time; this is the headless equivalent.
  Future<Season> completeSeason({
    required int userTeamId,
    required void Function(String) onProgress,
  }) async {
    await beginOffseason(userTeamId: userTeamId, onProgress: onProgress);
    final Season current = (await _seasons.currentSeason())!;
    onProgress('Contracts and retirements...');
    await _enterContracts(current, userTeamId);
    onProgress('Player development...');
    await _enterDevelopment(current, userTeamId);
    return startNextSeason(userTeamId: userTeamId, onProgress: onProgress);
  }

  Future<OffseasonState?> offseasonState() async {
    final List<Map<String, Object?>> rows = await db.query(
      t.offseasonState,
      where: 'id = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : OffseasonState.fromMap(rows.first);
  }

  Future<void> _saveOffseason(
    OffseasonState s, {
    int? step,
    String? report,
    int? windowWeeks,
    String? camp,
    String? ambition,
  }) => db.insert(t.offseasonState, <String, Object?>{
    'id': 1,
    'season_id': s.seasonId,
    'step': step ?? s.step,
    'report': report ?? s.report,
    'window_weeks': windowWeeks ?? s.windowWeeks,
    'camp': camp ?? s.camp,
    'ambition': ambition ?? s.ambition,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Stage 1 — closes the competitions: prizes, history, promotion and
  /// relegation, sponsor and board verdicts. Opens the off-season.
  Future<OffseasonState> beginOffseason({
    required int userTeamId,
    required void Function(String) onProgress,
  }) async {
    final Season? current = await _seasons.currentSeason();
    if (current == null) {
      throw StateError('No season to complete');
    }
    final List<Tournament> tournaments = await _seasonTournaments(
      current.seasonId,
    );
    final Team? teamBefore = await _refs.teamById(userTeamId);
    final List<String> lines = <String>[];

    onProgress('Awarding prizes...');
    final Set<String> titles = await _awardCompetitionPrizes(
      seasonId: current.seasonId,
      userTeamId: userTeamId,
      tournaments: tournaments,
    );

    // Final league standing of the user club, before the tables move on.
    int userRank = 0;
    for (final Tournament tour in tournaments) {
      if (!tour.isLeague) continue;
      final List<StandingRow> table = await _seasons.standings(
        current.seasonId,
        tour.tournamentId,
      );
      final int idx = table.indexWhere(
        (StandingRow r) => r.teamId == userTeamId,
      );
      if (idx == -1) continue;
      userRank = idx + 1;
      final StandingRow row = table[idx];
      lines.add(
        'Finished ${_ordinal(userRank)} in ${tour.name} with ${row.points} pts '
        '(${row.wins}W ${row.draws}D ${row.losses}L, '
        '${row.goalsFor}:${row.goalsAgainst}).',
      );
      lines.add('Champions: ${table.first.name}.');
    }
    if (titles.isNotEmpty) lines.add('Trophies won: ${titles.join(', ')}.');

    final int? prize = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT SUM(amount) FROM ${t.competitionPrizeAwards} '
        'WHERE season_id = ? AND team_id = ?',
        <Object?>[current.seasonId, userTeamId],
      ),
    );
    if (prize != null && prize > 0) {
      lines.add('Prize money received: ${_money(prize)}.');
    }

    onProgress('Recording season history...');
    await _seasons.recordSeasonAwards(
      seasonId: current.seasonId,
      year: current.endYear,
    );
    await _seasons.recordCareerSeason(
      seasonId: current.seasonId,
      teamId: userTeamId,
      startYear: current.startYear,
      endYear: current.endYear,
      championships: titles.join(', '),
    );
    final List<Map<String, Object?>> awards = await db.rawQuery(
      '''
      SELECT a.type, p.name FROM ${t.playerAwards} a
      JOIN ${t.players} p ON p.player_id = a.player_id
      WHERE a.season_id = ?
    ''',
      <Object?>[current.seasonId],
    );
    const Map<int, String> awardLabels = <int, String>{
      t.awardTopScorer: 'Top scorer',
      t.awardMvp: 'Player of the season',
      t.awardYoungPlayer: 'Young player of the season',
    };
    for (final Map<String, Object?> a in awards) {
      final String? label = awardLabels[a['type']];
      if (label != null) lines.add('$label: ${a['name']}.');
    }

    onProgress('Promotion and relegation...');
    final List<Tournament> leagueTours = tournaments
        .where((Tournament t) => t.isLeague)
        .toList();
    final Team? userClubBefore = await _refs.teamById(userTeamId);
    if (userClubBefore != null) {
      await _applyCountryPromotionRelegation(
        seasonId: current.seasonId,
        countryId: userClubBefore.countryId,
        leagues: leagueTours,
        userTeamId: userTeamId,
      );
    }
    final Team? teamAfter = await _refs.teamById(userTeamId);
    if (teamBefore != null && teamAfter != null) {
      if (teamAfter.division < teamBefore.division) {
        lines.add('PROMOTED! We move up to division ${teamAfter.division}.');
      } else if (teamAfter.division > teamBefore.division) {
        lines.add('Relegated to division ${teamAfter.division}.');
      }
    }

    if (_sponsorships != null) {
      onProgress('Evaluating sponsor objectives...');
      final List<String> sponsorBonuses = await _sponsorships
          .evaluateSeasonTargets(
            teamId: userTeamId,
            seasonId: current.seasonId,
            finalLeagueRank: userRank,
          );
      for (final String msg in sponsorBonuses) {
        lines.add(msg);
        await _messages.insert(
          title: 'Sponsorship Bonus Paid!',
          body: msg,
          teamId: userTeamId,
          sender: 'Commercial Department',
        );
      }
    }
    lines.addAll(await _settleBoardObjective(current, userTeamId, userRank));

    final OffseasonState state = OffseasonState(
      seasonId: current.seasonId,
      step: OffseasonStep.summary.index,
      report: lines.join('\n'),
      windowWeeks: 0,
    );
    await _saveOffseason(state);
    return state;
  }

  Future<List<String>> _settleBoardObjective(
    Season current,
    int userTeamId,
    int userRank,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.boardObjectives,
      where: 'start_year = ? AND team_id = ? AND status = ?',
      whereArgs: <Object?>[current.startYear, userTeamId, 'pending'],
      limit: 1,
    );
    if (rows.isEmpty || userRank == 0) return <String>[];
    final int target = rows.first['target_rank'] as int;
    final int bonus = rows.first['bonus'] as int;
    final bool met = userRank <= target;
    await db.update(
      t.boardObjectives,
      <String, Object?>{'status': met ? 'met' : 'failed'},
      where: 'start_year = ? AND team_id = ?',
      whereArgs: <Object?>[current.startYear, userTeamId],
    );
    final String text = met
        ? 'Board objective met (top $target): bonus of ${_money(bonus)} paid.'
        : 'Board objective missed (top $target): the board is disappointed.';
    if (met) {
      await db.execute(
        'UPDATE teams SET budget = budget + ? WHERE team_id = ?',
        <Object?>[bonus, userTeamId],
      );
    }
    await _messages.insert(
      title: met ? 'Board objective achieved' : 'Board objective missed',
      body: text,
      teamId: userTeamId,
      sender: 'Board',
    );
    return <String>[text];
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// User players whose contract ends this summer, best first.
  Future<List<ExpiringContract>> expiringContracts(
    int userTeamId,
    int seasonEndYear,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT p.*, MAX(c.end_date) AS contract_end,
             MAX(c.salary) AS contract_salary
      FROM ${t.players} p
      JOIN ${t.teamPlayers} tp ON tp.player_id = p.player_id
      JOIN ${t.contracts} c ON c.player_id = p.player_id AND c.status = 1
      WHERE tp.team_id = ? AND p.status_id = ?
        AND CAST(substr(c.end_date, 1, 4) AS INTEGER) <= ?
      GROUP BY p.player_id
      ORDER BY p.power DESC
    ''',
      <Object?>[userTeamId, t.statusActive, seasonEndYear],
    );
    return rows.map((Map<String, Object?> r) {
      final int old = max(
        (r['salary'] as int?) ?? 0,
        (r['contract_salary'] as int?) ?? 0,
      );
      final int raised = max(old + 1, (old * 1.15).round());
      return ExpiringContract(
        player: Player.fromMap(r),
        endDate: (r['contract_end'] as String?) ?? '',
        newSalary: raised,
        signingBonus: raised * 2,
      );
    }).toList();
  }

  /// Stage 2 — loans end, everyone ages, the old retire, AI contracts roll
  /// over. The user's expiring deals are left for the manager to decide.
  Future<String> _enterContracts(Season current, int userTeamId) async {
    await recallFinishedLoans(current.endYear, userTeamId);

    final List<Map<String, Object?>> retiring = await db.rawQuery(
      '''
      SELECT p.name, p.age FROM ${t.players} p
      JOIN ${t.teamPlayers} tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
        AND (p.age + 1 >= 41 OR (p.age + 1 >= 37 AND p.power < 55))
    ''',
      <Object?>[userTeamId, t.statusActive],
    );
    await _ageAndRetire();

    // Every other club simply extends the deals that run out.
    await db.execute(
      '''
      UPDATE ${t.contracts} SET end_date = ? || substr(end_date, 5)
      WHERE status = 1 AND team_id != ? AND end_date IS NOT NULL
        AND CAST(substr(end_date, 1, 4) AS INTEGER) <= ?
    ''',
      <Object?>['${current.endYear + 2}', userTeamId, current.endYear],
    );

    final List<String> lines = <String>[
      for (final Map<String, Object?> r in retiring)
        '${r['name']} (${(r['age'] as int) + 1}) has retired from football.',
    ];
    if (retiring.isEmpty) lines.add('No one in the squad retired this summer.');
    final int expiring = (await expiringContracts(
      userTeamId,
      current.endYear,
    )).length;
    lines.add(
      expiring == 0
          ? 'No contracts expire this summer.'
          : '$expiring contract${expiring == 1 ? '' : 's'} expire this summer. '
                'Renew the players you want to keep — the rest will leave.',
    );
    return lines.join('\n');
  }

  /// Lets expiring user players that were not renewed walk out to other clubs.
  Future<List<String>> _releaseUnrenewed(Season current, int userTeamId) async {
    final List<ExpiringContract> leaving = await expiringContracts(
      userTeamId,
      current.endYear,
    );
    if (leaving.isEmpty) return <String>[];
    final List<Team> buyers = (await _registeredClubs())
        .where((Team team) => team.teamId != userTeamId)
        .toList();
    final List<String> lines = <String>[];
    for (final ExpiringContract c in leaving) {
      final int pid = c.player.playerId;
      if (buyers.isEmpty) continue;
      final Team club = buyers[_rng.nextInt(buyers.length)];
      await db.update(
        t.teamPlayers,
        <String, Object?>{'team_id': club.teamId},
        where: 'player_id = ?',
        whereArgs: <Object?>[pid],
      );
      await db.update(
        t.contracts,
        <String, Object?>{
          'team_id': club.teamId,
          'end_date': '${current.endYear + 2}-06-30',
        },
        where: 'player_id = ? AND status = 1',
        whereArgs: <Object?>[pid],
      );
      await db.update(
        t.players,
        <String, Object?>{
          'squad_status': t.squadReserve,
          'market_status': t.marketActive,
          'is_captain': 0,
        },
        where: 'player_id = ?',
        whereArgs: <Object?>[pid],
      );
      await db.delete(
        t.teamLineups,
        where: 'team_id = ? AND player_id = ?',
        whereArgs: <Object?>[userTeamId, pid],
      );
      lines.add('${c.player.name} left on a free transfer to ${club.name}.');
    }
    await _squads.refreshTeamPower(userTeamId);
    return lines;
  }

  /// Stage 3 — season performance and age shape every player's rating.
  Future<String> _enterDevelopment(Season current, int userTeamId) async {
    final List<Player> before = await _squads.squadForTeam(userTeamId);
    final Map<int, int> oldPower = <int, int>{
      for (final Player p in before) p.playerId: p.power,
    };

    // Needs the per-match rows, so it must run before the archive below.
    await _evaluateSeasonPerformanceAndWages(
      seasonId: current.seasonId,
      userTeamId: userTeamId,
    );
    await _developPlayers();
    for (final Tournament tour in await _seasonTournaments(current.seasonId)) {
      await _seasons.archiveSeasonTournament(
        current.seasonId,
        tour.tournamentId,
      );
    }
    await _squads.refreshAllTeamPowers();

    final List<Player> after = await _squads.squadForTeam(userTeamId);
    final List<(Player, int)> changes = <(Player, int)>[
      for (final Player p in after)
        if (oldPower.containsKey(p.playerId) && p.power != oldPower[p.playerId])
          (p, p.power - oldPower[p.playerId]!),
    ]..sort(((Player, int) a, (Player, int) b) => b.$2.compareTo(a.$2));
    final List<String> lines = <String>[
      for (final (Player, int) c in changes)
        '${c.$2 > 0 ? '+' : '-'} ${c.$1.name} (${c.$1.age}): '
            '${oldPower[c.$1.playerId]} → ${c.$1.power}',
    ];
    if (lines.isEmpty) lines.add('No notable changes in the squad.');
    return lines.join('\n');
  }

  /// Youngsters grow towards their potential, veterans slowly decline. The
  /// "random" step is derived from the player id and age so each statement is
  /// consistent with itself and the result still varies year to year.
  Future<void> _developPlayers() async {
    const String grow =
        'MIN(potential - power, 1 + (player_id * 7 + age * 13) % 3)';
    const String prime =
        'MIN(potential - power, (player_id * 7 + age * 13) % 2)';

    await db.execute(
      '''
      UPDATE ${t.players}
      SET power = power + ($grow)
      WHERE status_id = ? AND power < potential AND age <= 23
    ''',
      <Object?>[t.statusActive],
    );

    await db.execute(
      '''
      UPDATE ${t.players}
      SET power = power + ($prime)
      WHERE status_id = ? AND power < potential AND age BETWEEN 24 AND 27
    ''',
      <Object?>[t.statusActive],
    );

    // Accelerate wonderkids for teams with upgraded training ground facilities
    final List<Map<String, Object?>> facRows = await db.query(
      t.teamFacilities,
      where: 'training_level > 1',
    );
    for (final Map<String, Object?> row in facRows) {
      final int teamId = (row['team_id'] as int?) ?? 0;
      final int level = (row['training_level'] as int?) ?? 1;
      final int bonusGrowth = level >= 4 ? 2 : 1;
      await db.execute(
        '''
        UPDATE ${t.players}
        SET power = MIN(potential, power + ?)
        WHERE status_id = ? AND power < potential AND age <= 21
          AND player_id IN (SELECT player_id FROM ${t.teamPlayers} WHERE team_id = ?)
      ''',
        <Object?>[bonusGrowth, t.statusActive, teamId],
      );
    }

    await db.execute(
      '''
      UPDATE ${t.players}
      SET power = MAX(40, power - CASE WHEN age >= 34
            THEN 1 + (player_id * 5 + age * 11) % 2
            ELSE (player_id * 5 + age * 11) % 3 END)
      WHERE status_id = ? AND age >= 31
    ''',
      <Object?>[t.statusActive],
    );

    // Recompute Market Values cleanly for affected players using canonical valuation service.
    // Young developing players grow towards their target MV, while declining veterans lose value.
    final List<Map<String, Object?>> changed = await db.rawQuery(
      '''
      SELECT player_id, power, potential, age, position_id, value
      FROM ${t.players}
      WHERE status_id = ? AND ((power < potential AND age <= 27) OR age >= 31)
    ''',
      <Object?>[t.statusActive],
    );

    final Batch batch = db.batch();
    const PlayerValuationService valuation = PlayerValuationService();
    for (final Map<String, Object?> r in changed) {
      final int pid = r['player_id'] as int;
      final int pwr = (r['power'] as int?) ?? 50;
      final int pot = (r['potential'] as int?) ?? pwr;
      final int age = (r['age'] as int?) ?? 25;
      final int pos = (r['position_id'] as int?) ?? 7;
      final int curVal = (r['value'] as int?) ?? 0;

      final int targetVal = valuation.calculateTargetMarketValue(
        power: pwr,
        potential: pot,
        age: age,
        positionId: pos,
      );
      final int newVal = valuation.smoothValueUpdate(
        currentValue: curVal,
        targetValue: targetVal,
      );
      batch.rawUpdate(
        'UPDATE ${t.players} SET value = ? WHERE player_id = ?',
        <Object?>[newVal, pid],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Advances the stage the manager is on. Returns an error message when the
  /// stage is not finished yet, otherwise null.
  Future<String?> advanceOffseason({
    required int userTeamId,
    required void Function(String) onProgress,
  }) async {
    final OffseasonState? s = await offseasonState();
    if (s == null) return 'No off-season in progress.';
    final Season? current = await _seasons.currentSeason();
    if (current == null) return 'No season loaded.';
    final OffseasonStep step = s.current;
    switch (step) {
      case OffseasonStep.summary:
        onProgress('Contracts and retirements...');
        await _saveOffseason(
          s,
          step: OffseasonStep.contracts.index,
          report: await _enterContracts(current, userTeamId),
        );
      case OffseasonStep.contracts:
        onProgress('Player development...');
        final List<String> left = await _releaseUnrenewed(current, userTeamId);
        final String dev = await _enterDevelopment(current, userTeamId);
        await _saveOffseason(
          s,
          step: OffseasonStep.development.index,
          report: <String>[...left, dev].join('\n'),
        );
      case OffseasonStep.development:
        await _saveOffseason(
          s,
          step: OffseasonStep.transfers.index,
          windowWeeks: _transferWindowWeeks,
          report:
              'The transfer window is open for $_transferWindowWeeks weeks. '
              'Use the market below, then advance the weeks to the deadline.',
        );
      case OffseasonStep.transfers:
        if (s.windowWeeks > 0) {
          return 'The transfer window is still open — advance to the deadline.';
        }
        await _saveOffseason(
          s,
          step: OffseasonStep.preseason.index,
          report: 'Choose how the squad prepares for the new season.',
        );
      case OffseasonStep.preseason:
        if (s.camp == null) return 'Choose a pre-season camp first.';
        await _saveOffseason(
          s,
          step: OffseasonStep.board.index,
          report: 'The board will set a target for the coming season.',
        );
      case OffseasonStep.board:
        if (s.ambition == null) return 'Agree an objective with the board.';
        await _saveOffseason(
          s,
          step: OffseasonStep.newSeason.index,
          report: 'Everything is in place. The fixtures are ready to be drawn.',
        );
      case OffseasonStep.newSeason:
        return 'Start the new season instead.';
    }
    return null;
  }

  static const int _transferWindowWeeks = 4;

  /// One week of the window: AI clubs trade among themselves.
  Future<void> advanceTransferWindow(
    int userTeamId, {
    bool toDeadline = false,
  }) async {
    OffseasonState? s = await offseasonState();
    if (s == null || s.current != OffseasonStep.transfers) return;
    final int weeks = toDeadline ? s.windowWeeks : min(1, s.windowWeeks);
    for (int w = 0; w < weeks; w++) {
      for (int i = 0; i < 5; i++) {
        await _runMarketAi(userTeamId);
      }
    }
    await _saveOffseason(s, windowWeeks: s.windowWeeks - weeks);
  }

  /// Applies the chosen camp. Returns an error message, or null on success.
  Future<String?> choosePreseasonCamp(
    int userTeamId,
    PreseasonCamp camp,
  ) async {
    final OffseasonState? s = await offseasonState();
    if (s == null || s.current != OffseasonStep.preseason) {
      return 'Not in the pre-season stage.';
    }
    if (s.camp != null) return 'A camp has already been chosen.';
    final Team? team = await _refs.teamById(userTeamId);
    if (team == null) return 'Club not found.';
    if (camp.cost > team.budget) {
      return 'Not enough budget: the camp costs ${_money(camp.cost)}.';
    }
    await db.execute(
      'UPDATE teams SET budget = budget - ? WHERE team_id = ?',
      <Object?>[camp.cost, userTeamId],
    );
    await db.execute(
      '''
      UPDATE ${t.players} SET fitness = ?
      WHERE status_id = ? AND player_id IN
        (SELECT player_id FROM ${t.teamPlayers} WHERE team_id = ?)
    ''',
      <Object?>[
        camp == PreseasonCamp.tour ? 85 : 100,
        t.statusActive,
        userTeamId,
      ],
    );
    final List<String> lines = <String>[camp.label];
    if (camp == PreseasonCamp.training) {
      final List<Player> squad = await _squads.squadForTeam(userTeamId);
      final List<Player> prospects =
          squad
              .where((Player p) => p.age <= 23 && p.power < p.potential)
              .toList()
            ..sort(
              (Player a, Player b) =>
                  (b.potential - b.power).compareTo(a.potential - a.power),
            );
      for (final Player p in prospects.take(3)) {
        await db.update(
          t.players,
          <String, Object?>{'power': p.power + 1},
          where: 'player_id = ?',
          whereArgs: <Object?>[p.playerId],
        );
        await _squads.refreshPlayerValue(p.playerId, previousPower: p.power);
        lines.add('+ ${p.name}: ${p.power} → ${p.power + 1}');
      }
      await _squads.refreshTeamPower(userTeamId);
    }
    await _saveOffseason(s, camp: camp.name, report: lines.join('\n'));
    return null;
  }

  /// The three objectives the board puts on the table for next season.
  Future<List<BoardOption>> boardOptions(int userTeamId) async {
    final Team? team = await _refs.teamById(userTeamId);
    if (team == null) return <BoardOption>[];
    final List<Map<String, Object?>> rows = await db.query(
      t.teams,
      columns: <String>['team_id'],
      where: 'country_id = ? AND division = ?',
      whereArgs: <Object?>[team.countryId, team.division],
      orderBy: 'power DESC, team_id ASC',
    );
    final int size = max(1, rows.length);
    final int idx = rows.indexWhere(
      (Map<String, Object?> r) => r['team_id'] == userTeamId,
    );
    final int expected = idx == -1 ? size : idx + 1;
    return <BoardOption>[
      for (final BoardAmbition a in BoardAmbition.values)
        BoardOption(
          ambition: a,
          targetRank: (expected + a.rankOffset).clamp(1, size),
          bonus: ((max(300000, team.budget * a.rate) / 10000).round()) * 10000,
        ),
    ];
  }

  /// Agrees the objective: the advance is paid now, the bonus on success.
  Future<String?> chooseBoardAmbition(
    int userTeamId,
    BoardAmbition ambition,
  ) async {
    final OffseasonState? s = await offseasonState();
    final Season? current = await _seasons.currentSeason();
    if (s == null || current == null || s.current != OffseasonStep.board) {
      return 'Not in the board stage.';
    }
    if (s.ambition != null) return 'The objective has already been agreed.';
    final BoardOption option = (await boardOptions(userTeamId))
        .firstWhere((BoardOption o) => o.ambition == ambition);
    await db.insert(t.boardObjectives, <String, Object?>{
      'start_year': current.startYear + 1,
      'team_id': userTeamId,
      'target_rank': option.targetRank,
      'bonus': option.bonus,
      'status': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.execute(
      'UPDATE teams SET budget = budget + ? WHERE team_id = ?',
      <Object?>[option.advance, userTeamId],
    );
    await _saveOffseason(
      s,
      ambition: ambition.name,
      report:
          'Target: finish in the top ${option.targetRank}. '
          'The board adds ${_money(option.advance)} to the transfer budget now '
          'and pays ${_money(option.bonus)} if we deliver.',
    );
    return null;
  }

  /// Final stage — draws the new season and closes the off-season.
  Future<Season> startNextSeason({
    required int userTeamId,
    required void Function(String) onProgress,
  }) async {
    final Season? current = await _seasons.currentSeason();
    if (current == null) {
      throw StateError('No season to complete');
    }
    onProgress('Preparing the new season...');
    final Team? userTeam = await _refs.teamById(userTeamId);
    if (userTeam == null) {
      throw StateError('User team vanished');
    }
    final rows = await db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tu.organization = ? AND tc.country_id = ? AND tu.division_id = ?
      LIMIT 1
    ''',
      <Object?>[t.orgLeague, userTeam.countryId, userTeam.division],
    );
    final Tournament? nextLeague = rows.isEmpty
        ? null
        : Tournament.fromMap(rows.first);
    final Map<String, Object?>? cupRow = await _refs.nationalCup(
      userTeam.countryId,
    );
    final Tournament? nextCup = cupRow == null
        ? null
        : Tournament.fromMap(cupRow);
    if (nextLeague == null) {
      return current; // nothing more we can generate; provider decides.
    }

    final List<Tournament> allDomestic = await _refs.domesticLeagues(
      userTeam.countryId,
    );
    final CareerPlan plan = await _gen.generateCareer(
      countryId: userTeam.countryId,
      league: nextLeague,
      cup: nextCup,
      internationals: await _refs.internationalCups(userTeam.countryId),
      otherLeagues: allDomestic
          .where((Tournament l) => l.tournamentId != nextLeague.tournamentId)
          .toList(),
      startYear: current.startYear + 1,
    );
    final List<Team> seasonClubs = await _registeredClubs();
    final Map<int, Team> clubsMap = <int, Team>{
      for (final Team c in seasonClubs) c.teamId: c,
    };
    await _gen.schedulePreSeasonFriendlies(
      seasonId: plan.season.seasonId,
      userTeamId: userTeamId,
      allTeams: clubsMap,
    );
    await _windowManager.ensureWindowsForSeason(
      plan.season.seasonId,
      plan.season.startYear,
    );
    await _messages.insert(
      title: plan.season.name,
      body: 'Fixtures are out for the new season — good luck!',
      sender: 'League',
    );
    await db.delete(t.offseasonState);
    return plan.season;
  }

  /// Sends loaned players home once their loan end date has passed. Loans run
  /// whole seasons, so a loan agreed mid-season outlasts this season.
  Future<void> recallFinishedLoans(int seasonEndYear, int userTeamId) async {
    // Loans run whole seasons: only those whose end date has passed return.
    final List<Map<String, Object?>> loans = await db.query(
      t.teamLoans,
      where: "CAST(substr(date_to, 1, 4) AS INTEGER) <= ?",
      whereArgs: <Object?>[seasonEndYear],
    );
    for (final Map<String, Object?> loan in loans) {
      final int pid = loan['player_id'] as int;
      final int parentId = loan['from_team_id'] as int;
      await db.update(
        t.teamPlayers,
        <String, Object?>{'team_id': parentId},
        where: 'player_id = ?',
        whereArgs: <Object?>[pid],
      );
      await db.update(
        t.players,
        <String, Object?>{
          'market_status': t.marketActive,
          'squad_status': t.squadReserve,
        },
        where: 'player_id = ?',
        whereArgs: <Object?>[pid],
      );
      await db.delete(
        t.teamLoans,
        where: 'loan_id = ?',
        whereArgs: <Object?>[loan['loan_id']],
      );
      if (parentId == userTeamId) {
        final List<Map<String, Object?>> p = await db.query(
          t.players,
          columns: <String>['name'],
          where: 'player_id = ?',
          whereArgs: <Object?>[pid],
          limit: 1,
        );
        await _messages.insert(
          title: 'Loan ended',
          body:
              '${p.isEmpty ? 'A player' : p.first['name']} has returned from his loan spell.',
          teamId: userTeamId,
          sender: 'Transfer Desk',
        );
      }
    }
  }

  /// Winner of the last knockout round (the final) of a cup competition.
  Future<int?> _knockoutWinner(int seasonId, int tournamentId) async {
    final rows = await db.rawQuery(
      '''
      SELECT winner_id FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
        AND phase = (SELECT MAX(phase) FROM matches
                     WHERE season_id = ? AND tournament_id = ?)
        AND (leg = 2 OR leg = (
          SELECT MAX(m2.leg) FROM matches m2
          WHERE m2.season_id = matches.season_id
            AND m2.tournament_id = matches.tournament_id
            AND m2.phase = matches.phase
        ))
        AND winner_id IS NOT NULL
      LIMIT 1
    ''',
      <Object?>[
        seasonId,
        tournamentId,
        t.matchFinished,
        seasonId,
        tournamentId,
      ],
    );
    return rows.isEmpty ? null : rows.first['winner_id'] as int?;
  }

  Future<List<Tournament>> _seasonTournaments(int seasonId) async {
    final rows = await db.rawQuery(
      '''
      SELECT tu.* FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      WHERE st.season_id = ? AND st.status = ?
    ''',
      <Object?>[seasonId, t.seasonTournamentActive],
    );
    return rows.map(Tournament.fromMap).toList();
  }

  Future<void> _applyCountryPromotionRelegation({
    required int seasonId,
    required int countryId,
    required List<Tournament> leagues,
    required int userTeamId,
  }) async {
    final List<Tournament> sorted = List<Tournament>.of(leagues)
      ..sort(
        (Tournament a, Tournament b) => a.divisionId.compareTo(b.divisionId),
      );
    if (sorted.isEmpty) return;

    final Map<int, List<StandingRow>> tables = <int, List<StandingRow>>{};
    for (final Tournament tour in sorted) {
      final List<StandingRow> table = await _seasons.standings(
        seasonId,
        tour.tournamentId,
      );
      if (table.isNotEmpty) {
        tables[tour.divisionId] = table;
      }
    }

    final Map<int, int> newDivisions = <int, int>{};
    final Set<int> promotedTeamIds = <int>{};
    final Set<int> relegatedTeamIds = <int>{};

    for (int i = 0; i < sorted.length; i++) {
      final Tournament currentTour = sorted[i];
      final int div = currentTour.divisionId;
      final List<StandingRow>? table = tables[div];
      if (table == null || table.isEmpty) continue;

      final Tournament? lowerTour = sorted
          .where((Tournament t) => t.divisionId == div + 1)
          .firstOrNull;
      if (lowerTour != null) {
        final List<StandingRow>? lowerTable = tables[div + 1];
        final int swapCount = min(
          currentTour.relegationSpots > 0
              ? currentTour.relegationSpots
              : lowerTour.promotionSlots,
          min(table.length, lowerTable?.length ?? 0),
        );
        if (swapCount > 0 && lowerTable != null) {
          // Bottom swapCount of current division go down to div + 1
          for (int k = table.length - swapCount; k < table.length; k++) {
            final int tId = table[k].teamId;
            newDivisions[tId] = div + 1;
            relegatedTeamIds.add(tId);
          }
          // Top swapCount of lower division come up to div
          for (int k = 0; k < swapCount; k++) {
            final int tId = lowerTable[k].teamId;
            newDivisions[tId] = div;
            promotedTeamIds.add(tId);
          }
        } else if (swapCount > 0 &&
            (lowerTable == null || lowerTable.isEmpty)) {
          // Fallback if lower division was not simulated
          final lowerRows = await db.query(
            t.teams,
            columns: <String>['team_id'],
            where: 'country_id = ? AND division = ?',
            whereArgs: <Object?>[countryId, div + 1],
            orderBy: 'power DESC',
            limit: swapCount,
          );
          for (final Map<String, Object?> row in lowerRows) {
            final int tId = row['team_id'] as int;
            newDivisions[tId] = div;
            promotedTeamIds.add(tId);
          }
          for (int k = table.length - swapCount; k < table.length; k++) {
            final int tId = table[k].teamId;
            newDivisions[tId] = div + 1;
            relegatedTeamIds.add(tId);
          }
        }
      }
    }

    // Apply all division updates
    for (final MapEntry<int, int> entry in newDivisions.entries) {
      await db.update(
        t.teams,
        <String, Object?>{'division': entry.value},
        where: 'team_id = ?',
        whereArgs: <Object?>[entry.key],
      );
    }

    // Notify user if club promoted or relegated
    if (promotedTeamIds.contains(userTeamId)) {
      final int newDiv = newDivisions[userTeamId]!;
      final Tournament? targetTour = sorted
          .where((Tournament t) => t.divisionId == newDiv)
          .firstOrNull;
      await _messages.insert(
        title: 'PROMOTION CELEBRATION!',
        body:
            'Congratulations! By finishing in the promotion places, our club has earned promotion to ${targetTour?.name ?? 'Division $newDiv'} for next season!',
        teamId: userTeamId,
        sender: 'Board of Directors',
      );
    } else if (relegatedTeamIds.contains(userTeamId)) {
      final int newDiv = newDivisions[userTeamId]!;
      final Tournament? targetTour = sorted
          .where((Tournament t) => t.divisionId == newDiv)
          .firstOrNull;
      await _messages.insert(
        title: 'RELEGATION CONFIRMED',
        body:
            'A disappointing conclusion to the campaign. Our club has been relegated to ${targetTour?.name ?? 'Division $newDiv'}. We must rebuild and fight for immediate promotion next season.',
        teamId: userTeamId,
        sender: 'Board of Directors',
      );
    }
  }

  Future<void> _ageAndRetire() async {
    await _seasons.ageSquad();
    await db.execute(
      'UPDATE players SET status_id = ? WHERE status_id = ? AND age >= 41',
      <Object?>[t.statusRetired, t.statusActive],
    );
    // 37-40 year olds with fading power also hang up their boots.
    await db.execute(
      '''UPDATE players SET status_id = ? WHERE status_id = ? AND age >= 37
           AND power < 55''',
      <Object?>[t.statusRetired, t.statusActive],
    );
    await db.execute(
      '''DELETE FROM team_players WHERE player_id IN (
             SELECT player_id FROM players WHERE status_id = ?)''',
      <Object?>[t.statusRetired],
    );
    await db.execute(
      '''UPDATE contracts SET status = 0 WHERE player_id IN (
             SELECT player_id FROM players WHERE status_id = ?)''',
      <Object?>[t.statusRetired],
    );
  }

  /// Evaluates player performance from the finished season:
  /// 1. Good performance raises overall power and market value (MV).
  /// 2. Key/standout performers from the user club request a wage increase.
  Future<void> _evaluateSeasonPerformanceAndWages({
    required int seasonId,
    required int userTeamId,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT p.player_id, p.name, p.power, p.potential, p.age, p.salary, p.value,
             tp.team_id,
             COUNT(mp.match_id) AS apps,
             COALESCE(SUM(mp.goals), 0) AS goals,
             COALESCE(SUM(mp.assists), 0) AS assists,
             COALESCE(AVG(mp.rating), 0) / 10.0 AS avg_rating
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      JOIN match_players mp ON mp.player_id = p.player_id
      JOIN matches m ON m.match_id = mp.match_id
      WHERE m.season_id = ? AND m.status = ? AND p.status_id = ?
        AND mp.minutes > 0
      GROUP BY p.player_id
    ''',
      <Object?>[seasonId, t.matchFinished, t.statusActive],
    );

    for (final Map<String, Object?> r in rows) {
      final int playerId = r['player_id'] as int;
      final int power = (r['power'] as int?) ?? 50;
      final int potential = (r['potential'] as int?) ?? power;
      final int age = (r['age'] as int?) ?? 25;
      final int apps = (r['apps'] as int?) ?? 0;
      final int goals = (r['goals'] as int?) ?? 0;
      final int assists = (r['assists'] as int?) ?? 0;
      final double avgRating = ((r['avg_rating'] as num?) ?? 0).toDouble();
      final int teamId = (r['team_id'] as int?) ?? 0;
      final int currentSalary = (r['salary'] as int?) ?? 1000;
      final int currentValue = (r['value'] as int?) ?? 0;

      // Determine power boost from strong season stats:
      // Minimum 8 apps to establish consistency.
      int powerGain = 0;
      if (apps >= 8 && (avgRating >= 7.0 || (goals + assists) >= 10)) {
        if (power < potential) {
          powerGain = avgRating >= 7.5 ? 2 : 1;
        } else if (age <= 25) {
          // Young breakout stars can nudge past initial potential
          powerGain = 1;
        }
      }

      final int newPower = (power + powerGain).clamp(40, 99);
      final int newPotential = max(potential, newPower);
      final int newMv = SquadRepository.valueAfterOverallChange(
        currentValue: currentValue,
        previousPower: power,
        newPower: newPower,
        age: age,
      );

      await db.update(
        t.players,
        <String, Object?>{
          'power': newPower,
          'potential': newPotential,
          'value': newMv,
        },
        where: 'player_id = ?',
        whereArgs: <Object?>[playerId],
      );

      // If user's player had an outstanding season, request wage raise
      if (teamId == userTeamId && apps >= 10 && avgRating >= 7.0) {
        final int demandSalary = max(
          (currentSalary * 1.25).round(),
          currentSalary + 500,
        );
        final String playerName = r['name'] as String? ?? 'Player';
        await _messages.insert(
          title: 'Wage Increase Request: $playerName',
          body:
              '$playerName had an excellent season ($apps apps, $goals goals, '
              '$assists assists, avg rating ${avgRating.toStringAsFixed(1)}). '
              'His agent is requesting a wage increase to ${_money(demandSalary)}/season '
              'for the upcoming campaign.',
          teamId: userTeamId,
          playerId: playerId,
          sender: 'Player Representative',
        );
      }
    }

    // Off-season natural development for young reserve players (under 24)
    // with unrealized potential who didn't get match minutes.
    // Progress pace is kept modest (~50% chance of +1 OVR) so they don't stagnate completely.
    final List<Map<String, Object?>> unplayedYoungsters = await db.rawQuery(
      '''
      SELECT p.player_id, p.power, p.potential, p.age, p.value
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      JOIN season_teams st ON st.team_id = tp.team_id
      WHERE st.season_id = ? AND tp.team_id != ? AND p.status_id = ?
        AND p.age <= 23 AND p.power < p.potential
        AND p.player_id NOT IN (
          SELECT DISTINCT mp.player_id FROM match_players mp
          JOIN matches m ON m.match_id = mp.match_id
          WHERE m.season_id = ?
        )
    ''',
      <Object?>[seasonId, userTeamId, t.statusActive, seasonId],
    );
    for (final Map<String, Object?> r in unplayedYoungsters) {
      if (_rng.nextDouble() > 0.50) continue;
      final int pid = r['player_id'] as int;
      final int pwr = (r['power'] as int?) ?? 50;
      final int pot = (r['potential'] as int?) ?? pwr;
      final int age = (r['age'] as int?) ?? 20;
      final int val = (r['value'] as int?) ?? 0;
      final int newPwr = min(pot, pwr + 1);
      final int newMv = SquadRepository.valueAfterOverallChange(
        currentValue: val,
        previousPower: pwr,
        newPower: newPwr,
        age: age,
      );
      await db.update(
        t.players,
        <String, Object?>{'power': newPwr, 'value': newMv},
        where: 'player_id = ?',
        whereArgs: <Object?>[pid],
      );
    }

    // Refresh overall power for all registered clubs in the season after player progression
    final List<Team> seasonClubs = await _registeredClubs();
    for (final Team club in seasonClubs) {
      await _squads.refreshTeamPower(club.teamId);
    }
  }
}
