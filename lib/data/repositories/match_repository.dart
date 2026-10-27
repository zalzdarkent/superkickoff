import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;

/// Persistence for match results: score, revenue, incidents, per-player stats,
/// cards/suspensions and injuries.
class MatchRepository {
  MatchRepository(this.db);

  final Database db;

  /// One event produced by the engine, ready for timeline display & storage.
  static const String evGoal = 'goal';
  static const String evPenalty = 'penalty';
  static const String evOwnGoal = 'own_goal';
  static const String evYellow = 'yellow';
  static const String evRed = 'red';
  static const String evSave = 'save';
  static const String evInjury = 'injury';
  static const String evSubstitution = 'substitution';
  static const String evVar = 'var';

  Future<void> saveResult({
    required int matchId,
    required int homeGoals,
    required int awayGoals,
    required int? winnerId,
    int? penaltyHomeGoals,
    int? penaltyAwayGoals,
    required int attendanceGeneral,
    required int attendanceStand,
    required int attendanceTerrace,
    required int attendanceBoxes,
    required int revenue,
    required List<Map<String, Object?>> events,
    required List<Map<String, Object?>> playerRows,
    required List<int> injuredPlayerIds,
    Map<int, String> injuryReturnDates = const <int, String>{},
    required List<int> suspendedPlayerIds,
  }) {
    return db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> current = await txn.query(
        t.matches,
        columns: <String>['status'],
        where: 'match_id = ?',
        whereArgs: <Object?>[matchId],
        limit: 1,
      );
      if (current.isEmpty ||
          current.first['status'] != t.matchScheduled) {
        throw StateError(
          'Match $matchId is missing or is no longer scheduled.',
        );
      }
      // 1. Update match row.
      final int updated = await txn.update(
        t.matches,
        <String, Object?>{
          'home_goals': homeGoals,
          'away_goals': awayGoals,
          'winner_id': winnerId,
          'penalty_home_goals': penaltyHomeGoals,
          'penalty_away_goals': penaltyAwayGoals,
          'attendance_general': attendanceGeneral,
          'attendance_stand': attendanceStand,
          'attendance_terrace': attendanceTerrace,
          'attendance_boxes': attendanceBoxes,
          'revenue': revenue,
          'status': t.matchFinished,
        },
        where: 'match_id = ?',
        whereArgs: <Object?>[matchId],
      );
      if (updated != 1) {
        throw StateError('Match $matchId could not be completed.');
      }
      // 2. Incidents as JSON rows.
      if (events.isNotEmpty) {
        final String json = jsonEncode(events);
        await txn.insert(t.matchIncidents, <String, Object?>{
          'match_id': matchId,
          'data': json,
        });
      }
      // 3. Per-player stats.
      for (final Map<String, Object?> row in playerRows) {
        await txn.insert(
          t.matchPlayers,
          <String, Object?>{
            'match_id': matchId,
            'team_id': row['team_id'] ?? 0,
            'starter': row['starter'] ?? 0,
            'minutes': row['minutes'] ?? 0,
            'points': row['points'] ?? 0,
            'rating': row['rating'] ?? 0,
            'mvp': row['mvp'] ?? 0,
            'goals': row['goals'] ?? 0,
            'assists': row['assists'] ?? 0,
            'yellow_cards': row['yellow_cards'] ?? 0,
            'red_cards': row['red_cards'] ?? 0,
          }..['player_id'] = row['player_id'],
        );
      }
      // 4. Suspensions: red card => 1-2 matches out.
      for (final int playerId in suspendedPlayerIds) {
        await txn.insert(t.suspensions, <String, Object?>{
          'player_id': playerId,
          'type': 2,
          'matches_remaining': 2,
        });
      }
      // 5. Injuries reduce fitness and persist a recovery date.
      for (final int playerId in injuredPlayerIds) {
        final String? returnDate = injuryReturnDates[playerId];
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
          <Object?>[returnDate, returnDate, playerId],
        );
      }
    });
  }

  /// Decrements remaining match bans; deletes finished ones. Returns the
  /// player ids that are still suspended this round.
  Future<Set<int>> tickSuspensions() async {
    final rows = await db.query(t.suspensions);
    final Set<int> stillOut = <int>{};
    for (final Map<String, Object?> r in rows) {
      final int id = r['suspension_id'] as int;
      final int remaining = ((r['matches_remaining'] as int?) ?? 1) - 1;
      if (remaining > 0) {
        await db.update(
          t.suspensions,
          <String, Object?>{'matches_remaining': remaining},
          where: 'suspension_id = ?',
          whereArgs: <Object?>[id],
        );
        stillOut.add(r['player_id'] as int);
      } else {
        await db.delete(
          t.suspensions,
          where: 'suspension_id = ?',
          whereArgs: <Object?>[id],
        );
      }
    }
    return stillOut;
  }

  Future<List<Map<String, Object?>>> incidents(int matchId) => db.query(
    t.matchIncidents,
    where: 'match_id = ?',
    whereArgs: <Object?>[matchId],
    limit: 1,
  );

  Future<List<Map<String, Object?>>> matchPlayers(int matchId) => db.query(
    t.matchPlayers,
    where: 'match_id = ?',
    whereArgs: <Object?>[matchId],
    orderBy: 'starter DESC, minutes DESC',
  );

  /// Adds [amount] to a team's budget (e.g. gate receipts, sponsor money).
  Future<void> adjustBudget(int teamId, int amount) async {
    await db.execute(
      '''
      UPDATE teams SET budget = budget + ? WHERE team_id = ?
    ''',
      <Object?>[amount, teamId],
    );
  }

  /// Deducts one week of salaries for the teams in a season.
  Future<void> paySalaries(int seasonId) async {
    await db.execute(
      '''
      UPDATE teams SET budget = budget - (
        SELECT COALESCE(SUM(p.salary), 0)
        FROM team_players tp
        JOIN players p ON p.player_id = tp.player_id
        WHERE tp.team_id = teams.team_id AND p.status_id = ?
      ) / 4
      WHERE team_id IN (SELECT team_id FROM season_teams WHERE season_id = ?)
    ''',
      <Object?>[t.statusActive, seasonId],
    );
  }
}
