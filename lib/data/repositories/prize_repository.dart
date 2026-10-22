import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../../game/prize_engine.dart';

/// Persists competition prize rules (overrides) and every paid prize so a
/// competition can never pay the same club twice for the same season.
class PrizeRepository {
  PrizeRepository(this.db);

  final Database db;

  /// Loads stored overrides for the given competition ids.
  Future<Map<int, PrizeRule>> overrides(Iterable<int> tournamentIds) async {
    if (tournamentIds.isEmpty) return <int, PrizeRule>{};
    final String marks = List<String>.filled(
      tournamentIds.length,
      '?',
    ).join(',');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT * FROM ${t.competitionPrizeRules} WHERE tournament_id IN ($marks)',
      tournamentIds.toList(),
    );
    return <int, PrizeRule>{
      for (final Map<String, Object?> row in rows)
        row['tournament_id'] as int: PrizeRule(
          basePool: (row['base_pool'] as int?) ?? 0,
          participationPerClub: (row['participation_per_club'] as int?) ?? 0,
          winBonus: (row['win_bonus'] as int?) ?? 0,
          drawBonus: (row['draw_bonus'] as int?) ?? 0,
          championBonus: (row['champion_bonus'] as int?) ?? 0,
          runnerUpBonus: (row['runner_up_bonus'] as int?) ?? 0,
          positionWeights: _weights(row['position_weights'] as String?),
        ),
    };
  }

  static List<int> _weights(String? raw) {
    if (raw == null || raw.isEmpty) return const <int>[];
    return raw
        .split(',')
        .map((String part) => int.tryParse(part.trim()) ?? 0)
        .where((int value) => value > 0)
        .toList();
  }

  /// Prize rows already recorded for a season.
  Future<Map<int, Set<int>>> paidAwards({
    required int seasonId,
    required Iterable<int> tournamentIds,
  }) async {
    if (tournamentIds.isEmpty) return <int, Set<int>>{};
    final String marks = List<String>.filled(
      tournamentIds.length,
      '?',
    ).join(',');
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT tournament_id, team_id FROM ${t.competitionPrizeAwards} '
      'WHERE season_id = ? AND tournament_id IN ($marks)',
      <Object?>[seasonId, ...tournamentIds],
    );
    final Map<int, Set<int>> paid = <int, Set<int>>{};
    for (final Map<String, Object?> row in rows) {
      paid
          .putIfAbsent(row['tournament_id'] as int, () => <int>{})
          .add(row['team_id'] as int);
    }
    return paid;
  }

  /// Credits every award once, skipping clubs already paid this season.
  /// Returns the awards that were actually paid.
  Future<List<PrizeAward>> pay({
    required int seasonId,
    required CompetitionPrizeResult result,
    required String date,
  }) async {
    final List<PrizeAward> paid = <PrizeAward>[];
    await db.transaction((Transaction txn) async {
      for (final PrizeAward award in result.awards) {
        if (award.amount <= 0) continue;
        final int inserted = await txn.insert(
          t.competitionPrizeAwards,
          <String, Object?>{
            'season_id': seasonId,
            'tournament_id': result.tournamentId,
            'team_id': award.teamId,
            'amount': award.amount,
            'reason': award.reason,
            'created_date': date,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (inserted <= 0) continue;
        await txn.execute(
          'UPDATE teams SET budget = budget + ? WHERE team_id = ?',
          <Object?>[award.amount, award.teamId],
        );
        paid.add(award);
      }
    });
    return paid;
  }

  /// Total prize income for a club, newest first (used by finances screens).
  Future<List<Map<String, Object?>>> awardsForTeam(
    int teamId, {
    int limit = 30,
  }) {
    return db.rawQuery(
      '''
      SELECT a.*, tu.name AS tournament_name, s.name AS season_name
      FROM ${t.competitionPrizeAwards} a
      LEFT JOIN tournaments tu ON tu.tournament_id = a.tournament_id
      LEFT JOIN seasons s ON s.season_id = a.season_id
      WHERE a.team_id = ?
      ORDER BY a.season_id DESC, a.award_id DESC
      LIMIT ?
    ''',
      <Object?>[teamId, limit],
    );
  }

  Future<int> totalPrizeIncome(int teamId) async {
    final int? total = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) FROM ${t.competitionPrizeAwards} '
        'WHERE team_id = ?',
        <Object?>[teamId],
      ),
    );
    return total ?? 0;
  }
}
