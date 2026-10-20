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
    int startYear = 2025,
  }) async {
    _startDate = DateTime(startYear, 8, 9); // first Saturday of August-ish

    final Season season = await _insertSeason(startYear);
    await db.insert(t.seasonTournaments, <String, Object?>{
      'season_id': season.seasonId,
      'tournament_id': league.tournamentId,
      'status': t.seasonTournamentActive,
    });
    if (cup != null) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': cup.tournamentId,
        'status': t.seasonTournamentActive,
      });
    }

    // ------------------------------------------------ participants
    final List<Team> leagueTeams = await _teamsOf(countryId, league.divisionId);
    final List<Team> cupTeams = await _teamsOf(countryId, null);
    final Map<int, Team> allTeams = <int, Team>{};
    for (final Team tm in <Team>[...leagueTeams, ...cupTeams]) {
      allTeams[tm.teamId] = tm;
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
    final int teamCount = leagueTeams.length;
    final int rounds = teamCount >= 2 ? (teamCount - 1) * 2 : 0;
    final List<FixtureSlot> slots = doubleRoundRobin(
        leagueTeams.map((Team tm) => tm.teamId).toList(), _rng);

    final List<Map<String, Object?>> matchRows = <Map<String, Object?>>[];
    for (final FixtureSlot slot in slots) {
      matchRows.add(_matchRow(
        season.seasonId,
        league.tournamentId,
        allTeams[slot.home]!,
        allTeams[slot.away]!,
        round: slot.round,
        phase: 1,
        leg: slot.leg,
        date: _iso(_leagueDate(slot.round)),
      ));
    }

    // ------------------------------------------------ cup first round
    int cupPhases = 0;
    if (cup != null && cupTeams.length >= 4) {
      final List<int> surviving = seedByIdes(cupTeams);
      cupPhases = knockoutRounds(surviving.length);
      final DateTime cupDate = _cupDate(1, rounds);
      await scheduleCupRound(
        season.seasonId,
        cup.tournamentId,
        surviving,
        phase: 1,
        date: cupDate,
        allTeams: allTeams,
      );
    }

    await _insertMatches(matchRows);
    return CareerPlan(
      season: season,
      leagueTournamentId: league.tournamentId,
      cupTournamentId: cup?.tournamentId,
      leagueRounds: rounds,
      cupRounds: cupPhases,
      teamCount: allTeams.length,
      matchCount: matchRows.length,
    );
  }

  /// Schedules the NEXT knockout round once a cup phase fully finished.
  /// [survivors] are the winning team ids (byes included). Returns the
  /// number of matches scheduled.
  Future<int> scheduleCupRound(
    int seasonId,
    int cupTournamentId,
    List<int> survivors, {
    required int phase,
    required DateTime date,
    required Map<int, Team> allTeams,
  }) async {
    final List<int> ids = List<int>.of(survivors)
      ..sort((int a, int b) => (allTeams[b]?.power ?? 0).compareTo(allTeams[a]?.power ?? 0));
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    while (ids.length > 1) {
      // Pair strongest vs weakest for balance.
      final int a = ids.removeAt(0);
      final int b = ids.removeLast();
      final Team? homeTeam = allTeams[a];
      final Team? awayTeam = allTeams[b];
      if (homeTeam == null || awayTeam == null) continue;
      rows.add(_matchRow(
        seasonId,
        cupTournamentId,
        homeTeam,
        awayTeam,
        round: phase,
        phase: 0,
        leg: 1,
        date: _iso(date),
      ));
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
    final rows = await db
        .query(t.seasons, where: 'season_id = ?', whereArgs: <Object?>[id], limit: 1);
    return Season.fromMap(rows.first);
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
  }) {
    return <String, Object?>{
      'tournament_id': tournamentId,
      'season_id': seasonId,
      'home_team_id': home.teamId,
      'away_team_id': away.teamId,
      'stadium_id': home.stadiumId,
      'round': round,
      'phase': phase,
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

  DateTime _leagueDate(int round) => _startDate.add(Duration(days: 7 * (round - 1)));

  /// Cup is on Wednesdays, interleaved: phase 1 mid-week before half-time.
  DateTime _cupDate(int phase, int leagueRounds) {
    final int spacing = max(2, leagueRounds ~/ 8);
    final int weekOffset = 2 + (phase - 1) * spacing;
    return _startDate.add(Duration(days: 7 * weekOffset - 3));
  }

  /// Sorts teams by power (seeding) and returns their ids.
  /// Seeds the cup by club power and trims the field to the largest power of
  /// two that fits, which keeps every knockout round evenly paired.
  List<int> seedByIdes(List<Team> teams) {
    final List<Team> sorted = List<Team>.of(teams)
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
  });

  final Season season;
  final int leagueTournamentId;
  final int? cupTournamentId;
  final int leagueRounds;
  final int cupRounds;
  final int teamCount;
  final int matchCount;
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
