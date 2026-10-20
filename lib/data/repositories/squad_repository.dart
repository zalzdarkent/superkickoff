import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Squad, lineup and transfer-market management.
class SquadRepository {
  SquadRepository(this.db);

  final Database db;

  /// Active squad members of a team, first team first, strongest first.
  Future<List<Player>> squadForTeam(int teamId) async {
    final rows = await db.rawQuery('''
      SELECT p.*
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
      ORDER BY p.squad_status DESC, p.power DESC
    ''', <Object?>[teamId, t.statusActive]);
    return rows.map(Player.fromMap).toList();
  }

  /// Bulk load every active player belonging to the given teams
  /// (used by the simulation engine).
  Future<List<Player>> playersForTeams(List<int> teamIds) {
    final String ids = teamIds.join(',');
    return db.rawQuery('''
      SELECT p.*
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id IN ($ids) AND p.status_id = ?
    ''', <Object?>[t.statusActive]).then((rows) => rows.map(Player.fromMap).toList());
  }

  Future<void> setSquadStatus(int playerId, int squadStatus) => db.update(
        t.players,
        <String, Object?>{'squad_status': squadStatus},
        where: 'player_id = ?',
        whereArgs: <Object?>[playerId],
      );

  /// Marks a player as captain and clears every other captain in the squad.
  Future<void> setCaptain(int teamId, int playerId) async {
    await db.update(
      t.players,
      <String, Object?>{'is_captain': 0},
      where: 'is_captain = 1 AND player_id IN '
          '(SELECT player_id FROM team_players WHERE team_id = ?)',
      whereArgs: <Object?>[teamId],
    );
    await db.update(
      t.players,
      <String, Object?>{'is_captain': 1},
      where: 'player_id = ?',
      whereArgs: <Object?>[playerId],
    );
  }

  Future<void> setMarketStatus(int playerId, int marketStatus) => db.update(
        t.players,
        <String, Object?>{'market_status': marketStatus},
        where: 'player_id = ?',
        whereArgs: <Object?>[playerId],
      );

  /// Persists post-match fitness changes.
  Future<void> updateFitness(Map<int, int> fitnessByPlayer) {
    return db.transaction((Transaction txn) async {
      for (final MapEntry<int, int> e in fitnessByPlayer.entries) {
        await txn.update(
          t.players,
          <String, Object?>{'fitness': e.value.clamp(0, 100)},
          where: 'player_id = ?',
          whereArgs: <Object?>[e.key],
        );
      }
    });
  }

  /// Applies post-match fatigue to the players who featured.
  Future<void> applyMatchFatigue(List<int> playerIds) async {
    if (playerIds.isEmpty) return;
    final String marks = List<String>.filled(playerIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE players SET fitness = MAX(15, fitness - 8) '
      'WHERE player_id IN ($marks)',
      playerIds,
    );
  }

  /// Weekly recovery: every squad member regains [amount] fitness points.
  Future<void> recoverFitness(int teamId, int amount) async {
    await db.execute('''
      UPDATE players
      SET fitness = CASE WHEN fitness + ? > 100 THEN 100 ELSE fitness + ? END
      WHERE player_id IN (SELECT player_id FROM team_players WHERE team_id = ?)
      AND status_id = ?
    ''', <Object?>[amount, amount, teamId, t.statusActive]);
  }

  // -------------------------------------------------------- transfer market

  /// Players currently listed for sale, most powerful first.
  Future<List<Map<String, Object?>>> marketPlayers({
    String? search,
    int? positionType,
    int? excludeTeamId,
    int limit = 50,
  }) {
    final String searchClause =
        search == null || search.isEmpty ? '' : 'AND p.name LIKE ? ';
    final String posClause = positionType == null
        ? ''
        : 'AND p.position_id IN '
            '(SELECT position_id FROM positions WHERE type = ?) ';
    final String excludeClause =
        excludeTeamId == null ? '' : 'AND tm.team_id != ? ';
    final String sql = '''
      SELECT p.player_id, p.name, p.age, p.position_id, p.power, p.potential,
             p.fitness, p.value, p.salary, p.country_id, p.stars,
             tm.team_id AS club_team_id, tm.name AS club_name,
             tm.abbreviation AS club_abbrev
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      JOIN teams tm ON tm.team_id = tp.team_id
      WHERE p.status_id = ? AND p.market_status = ${t.marketForSale}
      $excludeClause$searchClause$posClause
      ORDER BY p.power DESC
      LIMIT ?
    '''
        .trim();
    final List<Object?> args = <Object?>[t.statusActive];
    if (excludeTeamId != null) args.add(excludeTeamId);
    if (search != null && search.isNotEmpty) args.add('%$search%');
    if (positionType != null) args.add(positionType);
    args.add(limit);
    return db.rawQuery(sql, args);
  }

  /// Buys [player] for [buyerTeamId] in one transaction: moves the player,
  /// charges the budget, pays the selling club and logs the transfer.
  /// Returns the failure reason or null on success.
  Future<String?> buyMarketPlayer({
    required int buyerTeamId,
    required Player player,
  }) async {
    final Team? buyer = await db
        .query(t.teams, where: 'team_id = ?', whereArgs: <Object?>[buyerTeamId], limit: 1)
        .then((r) => r.isEmpty ? null : Team.fromMap(r.first));
    if (buyer == null) return 'Unknown team';
    if (buyer.budget < player.value) return 'Not enough budget';

    final String? error = await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> owner = await txn.query(
        t.teamPlayers,
        where: 'player_id = ?',
        whereArgs: <Object?>[player.playerId],
        columns: ['team_id'],
        limit: 1,
      );
      if (owner.isEmpty) return 'Player is not in any squad';
      final int sellerTeamId = owner.first['team_id'] as int;
      if (sellerTeamId == buyerTeamId) return 'Player already belongs to you';

      final List<Map<String, Object?>> seller = await txn.query(
        t.teams,
        where: 'team_id = ?',
        whereArgs: <Object?>[sellerTeamId],
        limit: 1,
      );
      final int sellerBudget =
          explicitBudget(seller.isEmpty ? null : seller.first);

      await txn.update(t.teamPlayers,
          <String, Object?>{'team_id': buyerTeamId},
          where: 'player_id = ?', whereArgs: <Object?>[player.playerId]);
      await txn.update(t.players, <String, Object?>{
        'market_status': t.marketActive,
        'squad_status':
            player.squadStatus == t.squadLoanListed ? t.squadFirstTeam : player.squadStatus,
        'is_captain': 0,
      },
          where: 'player_id = ?', whereArgs: <Object?>[player.playerId]);
      await txn.update(t.teams, <String, Object?>{'budget': buyer.budget - player.value},
          where: 'team_id = ?', whereArgs: <Object?>[buyerTeamId]);
      await txn.update(t.teams, <String, Object?>{'budget': sellerBudget + player.value},
          where: 'team_id = ?', whereArgs: <Object?>[sellerTeamId]);
      // Seller contract ends, buyer signs a 3-season contract.
      await txn.update(t.contracts, <String, Object?>{'status': 0},
          where: 'player_id = ? AND status = 1',
          whereArgs: <Object?>[player.playerId]);
      final int year = DateTime.now().year;
      await txn.insert(t.contracts, <String, Object?>{
        'player_id': player.playerId,
        'team_id': buyerTeamId,
        'start_date': '$year-07-01',
        'end_date': '${year + 3}-06-30',
        'status': 1,
        'salary': player.salary,
      });
      await txn.insert(t.playerTransfers, <String, Object?>{
        'player_id': player.playerId,
        'from_team_id': sellerTeamId,
        'to_team_id': buyerTeamId,
        'type': 1,
        'value': player.value,
        'date': _todayIso(),
      });
      return null;
    });
    return error;
  }

  int explicitBudget(Map<String, Object?>? teamRow) =>
      ((teamRow?['budget'] as int?) ?? 0);

  static String _todayIso() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
