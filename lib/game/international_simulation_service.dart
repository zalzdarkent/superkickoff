import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import 'formation.dart';
import 'international_calendar.dart';
import 'match_engine.dart';
import 'national_team_selection_service.dart';
import 'national_team_service.dart';

/// Simulates international matches using the core MatchEngine and persists international stats.
class InternationalSimulationService {
  InternationalSimulationService(
    this.db, {
    MatchEngine? engine,
    Random? random,
  })  : _rng = random ?? Random(),
        _engine = engine ?? MatchEngine(random: random),
        _selectionService = NationalTeamSelectionService(db, random: random),
        _nationalService = NationalTeamService(db),
        _calendarService = InternationalCalendarService(db);

  final Database db;
  final Random _rng;
  final MatchEngine _engine;
  final NationalTeamSelectionService _selectionService;
  final NationalTeamService _nationalService;
  final InternationalCalendarService _calendarService;

  /// Simulates a single national-team match.
  ///
  /// Reuses MatchEngine, ensures idempotency, records caps/goals, applies fatigue and injuries.
  Future<MatchResult?> simulateCountryMatch({
    CountryMatch? match,
    int? matchId,
    int? homeGoals,
    int? awayGoals,
    InternationalWindow? window,
  }) async {
    CountryMatch? targetMatch = match;
    if (targetMatch == null && matchId != null) {
      final List<Map<String, Object?>> rows = await db.query(
        t.countryMatches,
        where: 'match_id = ?',
        whereArgs: <Object?>[matchId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        targetMatch = CountryMatch.fromMap(rows.first);
      }
    }
    if (targetMatch == null) return null;
    final CountryMatch currentMatch = targetMatch;

    // Idempotency: Finished matches are never simulated twice
    if (currentMatch.status == t.matchFinished) {
      return MatchResult(
        homeGoals: currentMatch.homeGoals ?? 0,
        awayGoals: currentMatch.awayGoals ?? 0,
        events: const <MatchEvent>[],
        playerRows: const <MatchPlayerRow>[],
        attendanceGeneral: 0,
        attendanceStand: 0,
        attendanceTerrace: 0,
        attendanceBoxes: 0,
        revenue: 0,
        homeShots: 0,
        awayShots: 0,
        homeShotsOnTarget: 0,
        awayShotsOnTarget: 0,
        homeSaves: 0,
        awaySaves: 0,
        homePossession: 50,
        input: MatchInput(
          homeSquad: const <Player>[],
          awaySquad: const <Player>[],
          capacityGeneral: 0,
          capacityStand: 0,
          capacityTerrace: 0,
          capacityBoxes: 0,
          homePower: 50,
        ),
      );
    }

    // 1. Fetch squads for home and away countries
    List<Player> homeSquad = await _squadForCountry(
      countryId: currentMatch.homeCountryId,
      seasonId: currentMatch.seasonId,
      window: window,
    );
    List<Player> awaySquad = await _squadForCountry(
      countryId: currentMatch.awayCountryId,
      seasonId: currentMatch.seasonId,
      window: window,
    );

    // Fallbacks if squad is unexpectedly empty
    if (homeSquad.isEmpty) homeSquad = await _fallbackCountrySquad(currentMatch.homeCountryId);
    if (awaySquad.isEmpty) awaySquad = await _fallbackCountrySquad(currentMatch.awayCountryId);

    final Country? homeCountry = await _nationalService.getNationalTeam(currentMatch.homeCountryId);
    final Country? awayCountry = await _nationalService.getNationalTeam(currentMatch.awayCountryId);

    // 2. Prepare MatchInput
    final MatchInput input = MatchInput(
      homeSquad: homeSquad,
      awaySquad: awaySquad,
      homeTeamId: currentMatch.homeCountryId,
      awayTeamId: currentMatch.awayCountryId,
      homePower: homeCountry?.power ?? 70,
      awayPower: awayCountry?.power ?? 70,
      homeFormation: Formation.f442,
      awayFormation: Formation.f442,
      capacityGeneral: 40000,
      capacityStand: 15000,
      capacityTerrace: 8000,
      capacityBoxes: 2000,
      refereeTemper: 2 + _rng.nextInt(2),
    );

    // 3. Simulate Match
    final MatchResult result = _engine.simulate(input);

    int finalHomeGoals = homeGoals ?? result.homeGoals;
    int finalAwayGoals = awayGoals ?? result.awayGoals;
    int? winnerId;
    int? penH;
    int? penA;

    // Knockout match: Must determine a winner if single-leg tie ends in draw
    final bool isKnockout = currentMatch.phase > 0 && currentMatch.leg == 1;
    if (isKnockout && finalHomeGoals == finalAwayGoals && currentMatch.tournamentId != t.tournamentFriendlies) {
      final MatchPenaltyShootout shootout = _engine.penaltyShootout(input);
      penH = shootout.homeScore;
      penA = shootout.awayScore;
      winnerId = penH >= penA ? currentMatch.homeCountryId : currentMatch.awayCountryId;
    } else {
      if (finalHomeGoals > finalAwayGoals) {
        winnerId = currentMatch.homeCountryId;
      } else if (finalAwayGoals > finalHomeGoals) {
        winnerId = currentMatch.awayCountryId;
      } else {
        winnerId = 0;
      }
    }

    // 4. Persist in a single database transaction
    await db.transaction((Transaction txn) async {
      // 4a. Update country_matches
      await txn.update(
        t.countryMatches,
        <String, Object?>{
          'home_goals': finalHomeGoals,
          'away_goals': finalAwayGoals,
          'winner_id': winnerId,
          'penalty_home_goals': penH,
          'penalty_away_goals': penA,
          'status': t.matchFinished,
        },
        where: 'match_id = ?',
        whereArgs: <Object?>[currentMatch.matchId],
      );

      // 4b. Record per-player stats in match_players_countries and player_season_stats_countries
      final List<int> injuredIds = <int>[];
      for (final MatchPlayerRow row in result.playerRows) {
        final int cId = row.teamId; // teamId in row holds countryId
        await txn.insert(
          t.matchPlayersCountries,
          <String, Object?>{
            'player_id': row.playerId,
            'match_id': currentMatch.matchId,
            'country_id': cId,
            'starter': row.starter,
            'minutes': row.minutes,
            'points': row.points,
            'rating': row.rating,
            'mvp': row.mvp,
            'goals': row.goals,
            'yellow_cards': row.yellowCards,
            'red_cards': row.redCards,
            'assists': row.assists,
          },
        );

        // Upsert into player_season_stats_countries
        await txn.rawInsert(
          '''
          INSERT INTO ${t.playerSeasonStatsCountries} (
            player_id, country_id, season_id, matches_played, minutes, rating,
            starts, yellow_cards, red_cards, mvps, goals, assists
          ) VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(player_id, country_id, season_id) DO UPDATE SET
            matches_played = matches_played + 1,
            minutes = minutes + excluded.minutes,
            rating = (rating * matches_played + excluded.rating) / (matches_played + 1),
            starts = starts + excluded.starts,
            yellow_cards = yellow_cards + excluded.yellow_cards,
            red_cards = red_cards + excluded.red_cards,
            mvps = mvps + excluded.mvps,
            goals = goals + excluded.goals,
            assists = assists + excluded.assists
          ''',
          <Object?>[
            row.playerId,
            cId,
            currentMatch.seasonId,
            row.minutes,
            row.rating,
            row.starter,
            row.yellowCards,
            row.redCards,
            row.mvp,
            row.goals,
            row.assists,
          ],
        );

        // Apply fatigue: starters lose ~8-12 fitness, subs lose ~4-6 fitness
        final int fatigue = row.starter == 1 ? 8 + _rng.nextInt(5) : (row.minutes > 0 ? 4 + _rng.nextInt(3) : 0);
        if (fatigue > 0) {
          await txn.rawUpdate(
            'UPDATE ${t.players} SET fitness = MAX(30, fitness - ?) WHERE player_id = ?',
            <Object?>[fatigue, row.playerId],
          );
        }

        // Cap-tie player if competitive match and minutes > 0
        if (currentMatch.tournamentId != t.tournamentFriendlies && row.minutes > 0) {
          await txn.insert(
            t.playerNationalEligibility,
            <String, Object?>{
              'player_id': row.playerId,
              'country_id': cId,
              'is_primary': 1,
              'is_locked': 1,
              'notes': 'Cap-tied in official tournament',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // 4c. Process injuries from match events
      for (final MatchEvent event in result.events) {
        if (event.type == MatchEvent.injury && event.playerId != null) {
          final int pId = event.playerId!;
          injuredIds.add(pId);
          final int days = 7 + _rng.nextInt(21);
          final DateTime ret = DateTime.now().add(Duration(days: days));
          final String retStr = '${ret.year}-${ret.month.toString().padLeft(2, '0')}-${ret.day.toString().padLeft(2, '0')}';
          await txn.rawUpdate(
            '''
            UPDATE ${t.players}
            SET fitness = 40,
                injury_return_date = CASE
                  WHEN injury_return_date IS NULL OR injury_return_date < ?
                  THEN ?
                  ELSE injury_return_date
                END
            WHERE player_id = ?
            ''',
            <Object?>[retStr, retStr, pId],
          );
        }
      }
    });

    return result;
  }

  /// Simulates all scheduled international matches occurring on [date].
  Future<Map<int, MatchResult>> simulateMatchesOnDate(
    int seasonId,
    String date, {
    InternationalWindow? window,
  }) async {
    final String clean = date.length >= 10 ? date.substring(0, 10) : date;
    final List<Map<String, Object?>> rows = await db.query(
      t.countryMatches,
      where: 'season_id = ? AND date LIKE ? AND status = ?',
      whereArgs: <Object?>[seasonId, '$clean%', t.matchScheduled],
    );

    final Map<int, MatchResult> results = <int, MatchResult>{};
    for (final Map<String, Object?> r in rows) {
      final CountryMatch match = CountryMatch.fromMap(r);
      final MatchResult? res = await simulateCountryMatch(match: match, window: window);
      if (res != null) {
        results[match.matchId] = res;
      }
    }
    return results;
  }

  /// Simulates all scheduled international country matches on or before [upToDate].
  /// This ensures that international fixtures on dates without club matches
  /// (e.g. during international breaks) are simulated and results recorded.
  Future<int> simulatePendingMatchesThroughDate(
    int seasonId,
    String upToDate,
  ) async {
    final String clean = upToDate.length >= 10 ? upToDate.substring(0, 10) : upToDate;
    final List<Map<String, Object?>> rows = await db.query(
      t.countryMatches,
      where: 'season_id = ? AND date <= ? AND status = ?',
      whereArgs: <Object?>[seasonId, clean, t.matchScheduled],
      orderBy: 'date ASC, match_id ASC',
    );
    if (rows.isEmpty) return 0;

    int simulatedCount = 0;
    for (final Map<String, Object?> r in rows) {
      final CountryMatch match = CountryMatch.fromMap(r);
      final InternationalWindow? win = match.date != null
          ? await _calendarService.windowForDate(seasonId, match.date!)
          : null;
      final MatchResult? res = await simulateCountryMatch(match: match, window: win);
      if (res != null) {
        simulatedCount++;
      }
    }
    return simulatedCount;
  }

  /// Retrieves the selected squad for [countryId] from [country_callups], or invokes selection if not yet made.
  Future<List<Player>> _squadForCountry({
    required int countryId,
    required int seasonId,
    InternationalWindow? window,
  }) async {
    final List<Map<String, Object?>> callupRows = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${t.players} p
      JOIN ${t.countryCallups} cc ON cc.player_id = p.player_id
      WHERE cc.country_id = ? AND cc.season_id = ?
      ''',
      <Object?>[countryId, seasonId],
    );

    if (callupRows.length >= 11) {
      return callupRows.map(Player.fromMap).toList();
    }

    // Call-ups not yet run; generate them
    if (window != null) {
      final NationalTeamSquadSelection sel = await _selectionService.selectSquadForCountry(
        countryId: countryId,
        seasonId: seasonId,
        window: window,
      );
      return sel.players;
    }

    return callupRows.map(Player.fromMap).toList();
  }

  /// Safe fallback if country has no saved callups.
  Future<List<Player>> _fallbackCountrySquad(int countryId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.players,
      where: 'country_id = ? AND status_id = ?',
      whereArgs: <Object?>[countryId, t.statusActive],
      orderBy: 'power DESC',
      limit: 23,
    );
    return rows.map(Player.fromMap).toList();
  }
}
