import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';
import '../../game/training.dart';

/// Squad, lineup and transfer-market management.
class SquadRepository {
  SquadRepository(this.db);

  final Database db;

  /// Recomputes and updates the club's overall power based on its squad
  /// composition (average power of the top 11 active squad players).
  Future<int> refreshTeamPower(int teamId, [Transaction? txn]) async {
    final DatabaseExecutor executor = txn ?? db;
    final List<Map<String, Object?>> rows = await executor.rawQuery(
      '''
      SELECT p.power
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
      ORDER BY p.power DESC
      LIMIT 11
    ''',
      <Object?>[teamId, t.statusActive],
    );
    if (rows.isEmpty) return 0;
    final int sum = rows.fold<int>(
      0,
      (int acc, Map<String, Object?> r) => acc + ((r['power'] as int?) ?? 0),
    );
    final int newPower = (sum / rows.length).round();
    await executor.update(
      t.teams,
      <String, Object?>{'power': newPower},
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
    );
    return newPower;
  }

  /// Recalculates every club's power from its top 11 active players.
  Future<void> refreshAllTeamPowers([Transaction? txn]) async {
    final DatabaseExecutor executor = txn ?? db;
    await executor.rawUpdate(
      '''
      UPDATE teams
      SET power = (
        SELECT CAST(ROUND(AVG(top_players.power)) AS INTEGER)
        FROM (
          SELECT p.power
          FROM players p
          JOIN team_players tp ON tp.player_id = p.player_id
          WHERE tp.team_id = teams.team_id AND p.status_id = ?
          ORDER BY p.power DESC
          LIMIT 11
        ) AS top_players
      )
      WHERE EXISTS (
        SELECT 1
        FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        WHERE tp.team_id = teams.team_id AND p.status_id = ?
      )
      ''',
      <Object?>[t.statusActive, t.statusActive],
    );
  }

  /// Returns an MV derived from the player's existing value, so a higher
  /// overall can never reset a valuable player to a lower price tier.
  static int valueAfterOverallChange({
    required int currentValue,
    required int previousPower,
    required int newPower,
    required int age,
  }) {
    if (currentValue <= 0 || newPower <= previousPower) return currentValue;
    final int increase = newPower - previousPower;
    // Steeper curve: each overall point is worth more on an already-valuable
    // player, and younger players appreciate faster.
    final double baseRate = age <= 23
        ? 0.16
        : age <= 27
        ? 0.14
        : age <= 30
        ? 0.10
        : 0.06;
    // Higher overall points carry premium value per point.
    final double overallFactor = 0.6 + previousPower / 100;
    final double rate = baseRate * overallFactor;
    final int gain = (currentValue * rate * increase).round();
    return currentValue + gain;
  }

  /// Updates the market value after an overall increase.
  Future<void> refreshPlayerValue(
    int playerId, {
    required int previousPower,
    Transaction? txn,
  }) async {
    final DatabaseExecutor ex = txn ?? db;
    final List<Map<String, Object?>> rows = await ex.query(
      t.players,
      columns: <String>['power', 'age', 'value'],
      where: 'player_id = ?',
      whereArgs: <Object?>[playerId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final int power = (rows.first['power'] as int?) ?? previousPower;
    final int age = (rows.first['age'] as int?) ?? 25;
    final int currentValue = (rows.first['value'] as int?) ?? 0;
    final int newValue = valueAfterOverallChange(
      currentValue: currentValue,
      previousPower: previousPower,
      newPower: power,
      age: age,
    );
    if (newValue == currentValue) return;
    await ex.update(
      t.players,
      <String, Object?>{'value': newValue},
      where: 'player_id = ?',
      whereArgs: <Object?>[playerId],
    );
  }

  /// Active squad members of a team, first team first, strongest first.
  Future<List<Player>> squadForTeam(int teamId) async {
    final rows = await db.rawQuery(
      '''
      SELECT p.*
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
      ORDER BY p.squad_status DESC, p.power DESC
    ''',
      <Object?>[teamId, t.statusActive],
    );
    return rows.map(Player.fromMap).toList();
  }

  /// Bulk load every active player belonging to the given teams
  /// (used by the simulation engine).
  Future<List<Player>> playersForTeams(List<int> teamIds) {
    final String ids = teamIds.join(',');
    return db
        .rawQuery(
          '''
      SELECT p.*
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id IN ($ids) AND p.status_id = ?
    ''',
          <Object?>[t.statusActive],
        )
        .then((rows) => rows.map(Player.fromMap).toList());
  }

  // ---------------------------------------------------------------- tactics

  bool _tacticsReady = false;

  Future<void> _ensureTacticsTable() async {
    if (_tacticsReady) return;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamTactics} (
        team_id INTEGER PRIMARY KEY,
        formation TEXT NOT NULL DEFAULT '4-4-2'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamLineups} (
        team_id INTEGER NOT NULL,
        slot INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        PRIMARY KEY (team_id, slot)
      )
    ''');
    _tacticsReady = true;
  }

  /// Formation saved for [teamId] (defaults to 4-4-2).
  Future<String> formationForTeam(int teamId) async {
    await _ensureTacticsTable();
    final List<Map<String, Object?>> rows = await db.query(
      t.teamTactics,
      columns: <String>['formation'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    return (rows.isEmpty ? null : rows.first['formation'] as String?) ??
        '4-4-2';
  }

  /// Persists the chosen formation for [teamId].
  Future<void> setFormation(int teamId, String formation) async {
    await _ensureTacticsTable();
    await db.insert(t.teamTactics, <String, Object?>{
      'team_id': teamId,
      'formation': formation,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Saved XI: formation slot index -> player id.
  Future<Map<int, int>> lineupForTeam(int teamId) async {
    await _ensureTacticsTable();
    final List<Map<String, Object?>> rows = await db.query(
      t.teamLineups,
      columns: <String>['slot', 'player_id'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      orderBy: 'slot ASC',
    );
    return <int, int>{
      for (final Map<String, Object?> row in rows)
        row['slot'] as int: row['player_id'] as int,
    };
  }

  /// Replaces the saved XI.
  Future<void> saveLineup(int teamId, Map<int, int> slots) async {
    await _ensureTacticsTable();
    await db.transaction((Transaction txn) async {
      await txn.delete(
        t.teamLineups,
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      for (final MapEntry<int, int> entry in slots.entries) {
        await txn.insert(t.teamLineups, <String, Object?>{
          'team_id': teamId,
          'slot': entry.key,
          'player_id': entry.value,
        });
      }
    });
  }

  Future<void> clearLineup(int teamId) => db.delete(
    t.teamLineups,
    where: 'team_id = ?',
    whereArgs: <Object?>[teamId],
  );

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
      where:
          'is_captain = 1 AND player_id IN '
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
    await db.execute(
      '''
      UPDATE players
      SET fitness = CASE WHEN fitness + ? > 100 THEN 100 ELSE fitness + ? END
      WHERE player_id IN (SELECT player_id FROM team_players WHERE team_id = ?)
      AND status_id = ?
    ''',
      <Object?>[amount, amount, teamId, t.statusActive],
    );
  }

  // -------------------------------------------------------- transfer market

  /// Players currently listed for sale, most powerful first.
  Future<List<Map<String, Object?>>> marketPlayers({
    String? search,
    int? positionType,
    int? minAge,
    int? maxAge,
    int? minPrice,
    int? maxPrice,
    int? excludeTeamId,
    int limit = 50,
  }) {
    final String searchClause = search == null || search.isEmpty
        ? ''
        : 'AND p.name LIKE ? ';
    final String posClause = positionType == null
        ? ''
        : 'AND p.position_id IN '
              '(SELECT position_id FROM positions WHERE type = ?) ';
    final String excludeClause = excludeTeamId == null
        ? ''
        : 'AND tm.team_id != ? ';
    final String minAgeClause = minAge == null ? '' : 'AND p.age >= ? ';
    final String maxAgeClause = maxAge == null ? '' : 'AND p.age <= ? ';
    final String minPriceClause = minPrice == null ? '' : 'AND p.value >= ? ';
    final String maxPriceClause = maxPrice == null ? '' : 'AND p.value <= ? ';
    final String sql =
        '''
      SELECT p.player_id, p.name, p.age, p.position_id, p.profile, p.power,
             p.potential, p.fitness, p.value, p.salary, p.country_id, p.stars,
             tm.team_id AS club_team_id, tm.name AS club_name,
             tm.abbreviation AS club_abbrev
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      JOIN teams tm ON tm.team_id = tp.team_id
      WHERE p.status_id = ? AND p.market_status = ${t.marketForSale}
      $excludeClause$searchClause$posClause$minAgeClause$maxAgeClause$minPriceClause$maxPriceClause
      ORDER BY p.power DESC
      LIMIT ?
    '''
            .trim();
    final List<Object?> args = <Object?>[t.statusActive];
    if (excludeTeamId != null) args.add(excludeTeamId);
    if (search != null && search.isNotEmpty) args.add('%$search%');
    if (positionType != null) args.add(positionType);
    if (minAge != null) args.add(minAge);
    if (maxAge != null) args.add(maxAge);
    if (minPrice != null) args.add(minPrice);
    if (maxPrice != null) args.add(maxPrice);
    args.add(limit);
    return db.rawQuery(sql, args);
  }

  /// All active players (not just listed), with optional filters.
  Future<List<Map<String, Object?>>> allMarketPlayers({
    String? search,
    int? positionType,
    int? minAge,
    int? maxAge,
    int? minPrice,
    int? maxPrice,
    int? excludeTeamId,
    int limit = 100,
  }) {
    final String searchClause = search == null || search.isEmpty
        ? ''
        : 'AND p.name LIKE ? ';
    final String posClause = positionType == null
        ? ''
        : 'AND p.position_id IN '
              '(SELECT position_id FROM positions WHERE type = ?) ';
    final String excludeClause = excludeTeamId == null
        ? ''
        : 'AND tm.team_id != ? ';
    final String minAgeClause = minAge == null ? '' : 'AND p.age >= ? ';
    final String maxAgeClause = maxAge == null ? '' : 'AND p.age <= ? ';
    final String minPriceClause = minPrice == null ? '' : 'AND p.value >= ? ';
    final String maxPriceClause = maxPrice == null ? '' : 'AND p.value <= ? ';
    final String sql =
        '''
      SELECT p.player_id, p.name, p.age, p.position_id, p.profile, p.power,
             p.potential, p.fitness, p.value, p.salary, p.country_id, p.stars,
             tm.team_id AS club_team_id, tm.name AS club_name,
             tm.abbreviation AS club_abbrev
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      JOIN teams tm ON tm.team_id = tp.team_id
      WHERE p.status_id = ?
      $excludeClause$searchClause$posClause$minAgeClause$maxAgeClause$minPriceClause$maxPriceClause
      ORDER BY p.power DESC
      LIMIT ?
    '''
            .trim();
    final List<Object?> args = <Object?>[t.statusActive];
    if (excludeTeamId != null) args.add(excludeTeamId);
    if (search != null && search.isNotEmpty) args.add('%$search%');
    if (positionType != null) args.add(positionType);
    if (minAge != null) args.add(minAge);
    if (maxAge != null) args.add(maxAge);
    if (minPrice != null) args.add(minPrice);
    if (maxPrice != null) args.add(maxPrice);
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
        .query(
          t.teams,
          where: 'team_id = ?',
          whereArgs: <Object?>[buyerTeamId],
          limit: 1,
        )
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
      final int sellerBudget = explicitBudget(
        seller.isEmpty ? null : seller.first,
      );

      await txn.update(
        t.teamPlayers,
        <String, Object?>{'team_id': buyerTeamId},
        where: 'player_id = ?',
        whereArgs: <Object?>[player.playerId],
      );
      await txn.update(
        t.players,
        <String, Object?>{
          'market_status': t.marketActive,
          'squad_status': player.squadStatus == t.squadLoanListed
              ? t.squadFirstTeam
              : player.squadStatus,
          'is_captain': 0,
        },
        where: 'player_id = ?',
        whereArgs: <Object?>[player.playerId],
      );
      await txn.update(
        t.teams,
        <String, Object?>{'budget': buyer.budget - player.value},
        where: 'team_id = ?',
        whereArgs: <Object?>[buyerTeamId],
      );
      await txn.update(
        t.teams,
        <String, Object?>{'budget': sellerBudget + player.value},
        where: 'team_id = ?',
        whereArgs: <Object?>[sellerTeamId],
      );
      // Seller contract ends, buyer signs a 3-season contract.
      await txn.update(
        t.contracts,
        <String, Object?>{'status': 0},
        where: 'player_id = ? AND status = 1',
        whereArgs: <Object?>[player.playerId],
      );
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
      await refreshTeamPower(buyerTeamId, txn);
      await refreshTeamPower(sellerTeamId, txn);
      return null;
    });
    return error;
  }

  int explicitBudget(Map<String, Object?>? teamRow) =>
      ((teamRow?['budget'] as int?) ?? 0);

  // ------------------------------------------------------- profiles & club

  /// Per-player statistics for every squad member in [seasonId]. Players with
  /// no appearance stay in the list with zeroes.
  Future<List<SquadStatRow>> squadSeasonStats(int teamId, int seasonId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT p.player_id, p.name, p.position_id, p.profile, p.age, p.power,
             COUNT(CASE WHEN m.season_id = ? AND m.status = ?
                        THEN mp.match_id END) AS apps,
             COALESCE(SUM(CASE WHEN m.season_id = ? AND m.status = ?
                               THEN mp.minutes END), 0) AS minutes,
             COALESCE(SUM(CASE WHEN m.season_id = ? AND m.status = ?
                               THEN mp.goals END), 0) AS goals,
             COALESCE(SUM(CASE WHEN m.season_id = ? AND m.status = ?
                               THEN mp.assists END), 0) AS assists,
             COALESCE(SUM(CASE WHEN m.season_id = ? AND m.status = ?
                               THEN mp.mvp END), 0) AS mvps,
             COALESCE(SUM(CASE WHEN m.season_id = ? AND m.status = ?
                               THEN mp.yellow_cards END), 0) AS yellows,
             COALESCE(SUM(CASE WHEN m.season_id = ? AND m.status = ?
                               THEN mp.red_cards END), 0) AS reds,
             COALESCE(AVG(CASE WHEN m.season_id = ? AND m.status = ?
                               THEN mp.rating END), 0) / 10.0 AS rating
      FROM team_players tp
      JOIN players p ON p.player_id = tp.player_id
      LEFT JOIN match_players mp
        ON mp.player_id = p.player_id AND mp.team_id = tp.team_id
       AND mp.minutes > 0
      LEFT JOIN matches m ON m.match_id = mp.match_id
      WHERE tp.team_id = ? AND p.status_id = ?
      GROUP BY p.player_id
      ORDER BY rating DESC, goals DESC, apps DESC, p.name ASC
    ''',
      <Object?>[
        seasonId,
        t.matchFinished,
        seasonId,
        t.matchFinished,
        seasonId,
        t.matchFinished,
        seasonId,
        t.matchFinished,
        seasonId,
        t.matchFinished,
        seasonId,
        t.matchFinished,
        seasonId,
        t.matchFinished,
        seasonId,
        t.matchFinished,
        teamId,
        t.statusActive,
      ],
    );
    return <SquadStatRow>[
      for (final Map<String, Object?> row in rows)
        SquadStatRow(
          playerId: row['player_id'] as int,
          name: row['name'] as String,
          positionId: (row['position_id'] as int?) ?? 1,
          profile: (row['profile'] as String?) ?? 'D',
          age: (row['age'] as int?) ?? 0,
          power: (row['power'] as int?) ?? 0,
          appearances: (row['apps'] as int?) ?? 0,
          minutes: (row['minutes'] as int?) ?? 0,
          goals: (row['goals'] as int?) ?? 0,
          assists: (row['assists'] as int?) ?? 0,
          mvps: (row['mvps'] as int?) ?? 0,
          yellowCards: (row['yellows'] as int?) ?? 0,
          redCards: (row['reds'] as int?) ?? 0,
          rating: ((row['rating'] as num?) ?? 0).toDouble(),
        ),
    ];
  }

  /// Full profile for the player sheet: contract, season stats and transfers.
  Future<PlayerDetail?> playerDetail(int playerId, {int? seasonId}) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT p.*, tp.team_id AS club_id, tm.name AS club_name,
             c.name AS country_name
      FROM players p
      LEFT JOIN team_players tp ON tp.player_id = p.player_id
      LEFT JOIN teams tm ON tm.team_id = tp.team_id
      LEFT JOIN countries c ON c.country_id = p.country_id
      WHERE p.player_id = ?
      LIMIT 1
    ''',
      <Object?>[playerId],
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.first;

    ContractInfo? contract;
    final List<Map<String, Object?>> contractRows = await db.query(
      t.contracts,
      where: 'player_id = ? AND status = 1',
      whereArgs: <Object?>[playerId],
      orderBy: 'end_date DESC',
      limit: 1,
    );
    if (contractRows.isNotEmpty) {
      final Map<String, Object?> c = contractRows.first;
      contract = ContractInfo(
        startDate: (c['start_date'] as String?) ?? '',
        endDate: (c['end_date'] as String?) ?? '',
        salary: (c['salary'] as int?) ?? 0,
        goalBonus: c['goal_bonus'] as int?,
        assistBonus: c['assist_bonus'] as int?,
        mvpBonus: c['mvp_bonus'] as int?,
        titleBonus: c['title_bonus'] as int?,
        appearanceBonus: c['appearance_bonus'] as int?,
      );
    }

    PlayerSeasonSummary stats = PlayerSeasonSummary.empty;
    if (seasonId != null) {
      final List<Map<String, Object?>> statRows = await db.rawQuery(
        '''
        SELECT COUNT(*) AS matches,
               COALESCE(SUM(mp.minutes), 0) AS minutes,
               COALESCE(SUM(mp.goals), 0) AS goals,
               COALESCE(SUM(mp.assists), 0) AS assists,
               COALESCE(SUM(mp.mvp), 0) AS mvps,
               COALESCE(SUM(mp.yellow_cards), 0) AS yellows,
               COALESCE(SUM(mp.red_cards), 0) AS reds,
               COALESCE(AVG(mp.rating), 0) / 10.0 AS rating
        FROM match_players mp
        JOIN matches m ON m.match_id = mp.match_id
        WHERE mp.player_id = ? AND mp.minutes > 0
          AND m.status = ? AND m.season_id = ?
      ''',
        <Object?>[playerId, t.matchFinished, seasonId],
      );
      final Map<String, Object?> s = statRows.first;
      stats = PlayerSeasonSummary(
        matches: (s['matches'] as int?) ?? 0,
        minutes: (s['minutes'] as int?) ?? 0,
        goals: (s['goals'] as int?) ?? 0,
        assists: (s['assists'] as int?) ?? 0,
        mvps: (s['mvps'] as int?) ?? 0,
        yellowCards: (s['yellows'] as int?) ?? 0,
        redCards: (s['reds'] as int?) ?? 0,
        rating: ((s['rating'] as num?) ?? 0).toDouble(),
      );
    }

    final List<Map<String, Object?>> transferRows = await db.rawQuery(
      '''
      SELECT pt.*, p.name AS player_name, ft.name AS from_name,
             tt.name AS to_name
      FROM player_transfers pt
      JOIN players p ON p.player_id = pt.player_id
      LEFT JOIN teams ft ON ft.team_id = pt.from_team_id
      LEFT JOIN teams tt ON tt.team_id = pt.to_team_id
      WHERE pt.player_id = ?
      ORDER BY pt.date DESC, pt.transfer_id DESC
      LIMIT 10
    ''',
      <Object?>[playerId],
    );

    final List<Map<String, Object?>> suspensionRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(matches_remaining), 0) AS remaining
      FROM suspensions
      WHERE player_id = ? AND matches_remaining > 0
    ''',
      <Object?>[playerId],
    );

    final List<Map<String, Object?>> careerRows = await db.rawQuery(
      '''
      SELECT pss.*, s.name AS season_name, tm.name AS team_name
      FROM player_season_stats pss
      LEFT JOIN seasons s ON s.season_id = pss.season_id
      LEFT JOIN teams tm ON tm.team_id = pss.team_id
      WHERE pss.player_id = ?
      ORDER BY pss.season_id DESC
    ''',
      <Object?>[playerId],
    );
    final List<Map<String, Object?>> awardRows = await db.rawQuery(
      '''
      SELECT pa.*, tm.name AS team_name
      FROM player_awards pa
      LEFT JOIN teams tm ON tm.team_id = pa.team_id
      WHERE pa.player_id = ?
      ORDER BY pa.year DESC, pa.type ASC
    ''',
      <Object?>[playerId],
    );

    return PlayerDetail(
      player: Player.fromMap(row),
      clubId: row['club_id'] as int?,
      clubName: (row['club_name'] as String?) ?? '',
      countryName: (row['country_name'] as String?) ?? '',
      contract: contract,
      stats: stats,
      transfers: <TransferRecord>[
        for (final Map<String, Object?> tr in transferRows)
          TransferRecord(
            playerId: (tr['player_id'] as int?) ?? 0,
            playerName: (tr['player_name'] as String?) ?? '',
            date: (tr['date'] as String?) ?? '',
            fromTeamId: tr['from_team_id'] as int?,
            toTeamId: tr['to_team_id'] as int?,
            fromTeamName: (tr['from_name'] as String?) ?? 'Free agent',
            toTeamName: (tr['to_name'] as String?) ?? 'Free agent',
            value: (tr['value'] as int?) ?? 0,
            type: (tr['type'] as int?) ?? 1,
          ),
      ],
      suspensionMatches: (suspensionRows.first['remaining'] as int?) ?? 0,
      career: <PlayerCareerRow>[
        for (final Map<String, Object?> r in careerRows)
          PlayerCareerRow(
            seasonId: (r['season_id'] as int?) ?? 0,
            seasonName: (r['season_name'] as String?) ?? 'Season',
            teamName: (r['team_name'] as String?) ?? '',
            matches: (r['matches_played'] as int?) ?? 0,
            minutes: (r['minutes'] as int?) ?? 0,
            starts: (r['starts'] as int?) ?? 0,
            goals: (r['goals'] as int?) ?? 0,
            assists: (r['assists'] as int?) ?? 0,
            mvps: (r['mvps'] as int?) ?? 0,
            yellowCards: (r['yellow_cards'] as int?) ?? 0,
            redCards: (r['red_cards'] as int?) ?? 0,
            ratingSum: (r['rating'] as int?) ?? 0,
          ),
      ],
      awards: <PlayerAward>[
        for (final Map<String, Object?> r in awardRows)
          PlayerAward(
            awardId: (r['award_id'] as int?) ?? 0,
            playerId: (r['player_id'] as int?) ?? 0,
            playerName: (row['name'] as String?) ?? '',
            teamName: (r['team_name'] as String?) ?? '',
            type: (r['type'] as int?) ?? 0,
            year: (r['year'] as int?) ?? 0,
            seasonId: (r['season_id'] as int?) ?? 0,
            goals: r['goals'] as int?,
          ),
      ],
    );
  }

  /// Snapshot of the club finances, stadium and coach for the club hub.
  Future<ClubOverview?> clubOverview(
    int teamId, {
    String? managerName,
    String? managerCountry,
  }) async {
    final String expiryCutoff = DateTime.now()
        .add(const Duration(days: 365))
        .toIso8601String()
        .substring(0, 10);
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT t.*, c.name AS country_name,
             s.name AS stadium_name, s.city AS stadium_city,
             s.capacity_general, s.capacity_stand, s.capacity_terrace,
             s.capacity_boxes, s.max_general, s.max_stand, s.max_terrace,
             s.max_boxes,
             co.name AS coach_name, co.age AS coach_age, co.points AS coach_points,
             cc.name AS coach_country,
             (SELECT COALESCE(SUM(p.value), 0)
                FROM players p JOIN team_players tp ON tp.player_id = p.player_id
               WHERE tp.team_id = t.team_id AND p.status_id = ?) AS squad_value,
             (SELECT COALESCE(SUM(p.salary), 0)
                FROM players p JOIN team_players tp ON tp.player_id = p.player_id
               WHERE tp.team_id = t.team_id AND p.status_id = ?) AS wage_bill,
             (SELECT COUNT(*) FROM contracts ct
               WHERE ct.team_id = t.team_id AND ct.status = 1
                 AND ct.end_date IS NOT NULL AND ct.end_date <= ?) AS expiring,
             (SELECT COALESCE(SUM(value), 0) FROM player_transfers
               WHERE to_team_id = t.team_id) AS transfer_spend,
             (SELECT COALESCE(SUM(value), 0) FROM player_transfers
               WHERE from_team_id = t.team_id) AS transfer_income
      FROM teams t
      LEFT JOIN countries c ON c.country_id = t.country_id
      LEFT JOIN stadiums s ON s.stadium_id = t.stadium_id
      LEFT JOIN coaches co ON co.coach_id = t.coach_id
      LEFT JOIN countries cc ON cc.country_id = co.country_id
      WHERE t.team_id = ?
      LIMIT 1
    ''',
      <Object?>[t.statusActive, t.statusActive, expiryCutoff, teamId],
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> r = rows.first;
    return ClubOverview(
      team: Team.fromMap(r),
      countryName: (r['country_name'] as String?) ?? '',
      stadiumName: (r['stadium_name'] as String?) ?? 'Unknown stadium',
      stadiumCity: (r['stadium_city'] as String?) ?? '',
      general: (r['capacity_general'] as int?) ?? 0,
      stand: (r['capacity_stand'] as int?) ?? 0,
      terrace: (r['capacity_terrace'] as int?) ?? 0,
      boxes: (r['capacity_boxes'] as int?) ?? 0,
      maxGeneral: (r['max_general'] as int?) ?? 0,
      maxStand: (r['max_stand'] as int?) ?? 0,
      maxTerrace: (r['max_terrace'] as int?) ?? 0,
      maxBoxes: (r['max_boxes'] as int?) ?? 0,
      coachName: managerName ?? (r['coach_name'] as String?) ?? 'No coach',
      coachAge: managerName == null ? (r['coach_age'] as int?) ?? 0 : 0,
      coachPoints: managerName == null ? (r['coach_points'] as int?) ?? 0 : 0,
      coachCountry: managerCountry ?? (r['coach_country'] as String?) ?? '',
      squadValue: (r['squad_value'] as int?) ?? 0,
      wageBill: (r['wage_bill'] as int?) ?? 0,
      expiringContracts: (r['expiring'] as int?) ?? 0,
      transferSpend: (r['transfer_spend'] as int?) ?? 0,
      transferIncome: (r['transfer_income'] as int?) ?? 0,
    );
  }

  /// Adds roughly 10% to every stand, up to the stadium's maximum. Returns an
  /// error message, or null when the upgrade succeeded.
  Future<String?> expandStadium(int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT t.budget, t.stadium_id,
             s.capacity_general, s.capacity_stand, s.capacity_terrace,
             s.capacity_boxes, s.max_general, s.max_stand, s.max_terrace,
             s.max_boxes
      FROM teams t JOIN stadiums s ON s.stadium_id = t.stadium_id
      WHERE t.team_id = ?
      LIMIT 1
    ''',
      <Object?>[teamId],
    );
    if (rows.isEmpty) return 'Club or stadium not found.';
    final Map<String, Object?> r = rows.first;
    final int general = (r['capacity_general'] as int?) ?? 0;
    final int stand = (r['capacity_stand'] as int?) ?? 0;
    final int terrace = (r['capacity_terrace'] as int?) ?? 0;
    final int boxes = (r['capacity_boxes'] as int?) ?? 0;
    final int newGeneral = ClubOverview.nextTier(
      general,
      (r['max_general'] as int?) ?? general,
    );
    final int newStand = ClubOverview.nextTier(
      stand,
      (r['max_stand'] as int?) ?? stand,
    );
    final int newTerrace = ClubOverview.nextTier(
      terrace,
      (r['max_terrace'] as int?) ?? terrace,
    );
    final int newBoxes = ClubOverview.nextTier(
      boxes,
      (r['max_boxes'] as int?) ?? boxes,
    );
    final int newSeats =
        (newGeneral - general) +
        (newStand - stand) +
        (newTerrace - terrace) +
        (newBoxes - boxes);
    if (newSeats <= 0) return 'Stadium is already at maximum capacity.';
    final int cost = newSeats * 1200;
    final int budget = (r['budget'] as int?) ?? 0;
    if (budget < cost) {
      return 'Not enough budget: the upgrade costs ${_moneyShort(cost)}.';
    }
    await db.transaction((Transaction txn) async {
      await txn.update(
        t.stadiums,
        <String, Object?>{
          'capacity_general': newGeneral,
          'capacity_stand': newStand,
          'capacity_terrace': newTerrace,
          'capacity_boxes': newBoxes,
        },
        where: 'stadium_id = ?',
        whereArgs: <Object?>[r['stadium_id']],
      );
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - cost},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
    });
    return null;
  }

  // ------------------------------------------------------ contracts & bans

  /// Extends a user player's contract by two seasons. The player gets a 15%
  /// raise and a signing bonus of two salaries, paid from the club budget.
  Future<String?> renewContract({
    required int playerId,
    required int teamId,
    required int currentYear,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT p.name AS player_name, p.salary AS player_salary, tm.budget,
             c.contract_id, c.salary AS contract_salary, c.end_date
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      JOIN teams tm ON tm.team_id = tp.team_id
      LEFT JOIN contracts c ON c.player_id = p.player_id AND c.status = 1
      WHERE p.player_id = ? AND tp.team_id = ? AND p.status_id = ?
      ORDER BY c.end_date DESC
      LIMIT 1
    ''',
      <Object?>[playerId, teamId, t.statusActive],
    );
    if (rows.isEmpty) return 'This player is not in your squad.';
    final Map<String, Object?> r = rows.first;
    final int? contractId = r['contract_id'] as int?;
    if (contractId == null) return 'This player has no active contract.';
    final int oldSalary = math.max(
      (r['player_salary'] as int?) ?? 0,
      (r['contract_salary'] as int?) ?? 0,
    );
    final int newSalary = math.max(oldSalary + 1, (oldSalary * 1.15).round());
    final int signingBonus = newSalary * 2;
    final int budget = (r['budget'] as int?) ?? 0;
    if (budget < signingBonus) {
      return 'Not enough budget: the signing bonus is '
          '${_moneyShort(signingBonus)}.';
    }
    final String oldEnd = (r['end_date'] as String?) ?? '';
    final int oldEndYear =
        int.tryParse(oldEnd.length >= 4 ? oldEnd.substring(0, 4) : '') ?? 0;
    final int baseYear = math.max(oldEndYear, currentYear);
    final String suffix = oldEnd.length >= 10
        ? oldEnd.substring(4, 10)
        : '-05-31';
    final String newEnd = '${baseYear + 2}$suffix';
    await db.transaction((Transaction txn) async {
      await txn.update(
        t.contracts,
        <String, Object?>{'salary': newSalary, 'end_date': newEnd, 'status': 1},
        where: 'contract_id = ?',
        whereArgs: <Object?>[contractId],
      );
      await txn.update(
        t.players,
        <String, Object?>{'salary': newSalary},
        where: 'player_id = ?',
        whereArgs: <Object?>[playerId],
      );
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - signingBonus},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
    });
    return null;
  }

  /// Player id -> remaining suspension matches for every banned squad member.
  Future<Map<int, int>> suspensionsForTeam(int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT s.player_id, SUM(s.matches_remaining) AS remaining
      FROM suspensions s
      JOIN team_players tp ON tp.player_id = s.player_id
      WHERE tp.team_id = ? AND s.matches_remaining > 0
      GROUP BY s.player_id
    ''',
      <Object?>[teamId],
    );
    return <int, int>{
      for (final Map<String, Object?> row in rows)
        row['player_id'] as int: (row['remaining'] as int?) ?? 0,
    };
  }

  // ---------------------------------------------------------- youth academy

  int youthAcademyUpgradeCost(int level) => level.clamp(1, 9) * 1000000;

  Future<YouthAcademyState> youthAcademyState(int teamId) async {
    await db.insert(t.teamYouthAcademy, <String, Object?>{
      'team_id': teamId,
      'level': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final List<Map<String, Object?>> rows = await db.query(
      t.teamYouthAcademy,
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final Map<String, Object?> row = rows.first;
    final int level = (row['level'] as int?) ?? 1;
    return YouthAcademyState(
      level: level,
      upgradeCost: youthAcademyUpgradeCost(level),
      lastGraduatedDate: row['last_graduated_date'] as String?,
    );
  }

  Future<String?> upgradeYouthAcademy(int teamId) async {
    final YouthAcademyState state = await youthAcademyState(teamId);
    if (state.isMaxLevel) return 'Youth Academy is already level 10.';
    final List<Map<String, Object?>> teams = await db.query(
      t.teams,
      columns: <String>['budget'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final int budget = teams.isEmpty ? 0 : (teams.first['budget'] as int? ?? 0);
    if (budget < state.upgradeCost) {
      return 'Not enough budget: upgrade costs ${_moneyShort(state.upgradeCost)}.';
    }
    await db.transaction((Transaction txn) async {
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - state.upgradeCost},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      await txn.update(
        t.teamYouthAcademy,
        <String, Object?>{'level': state.level + 1},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
    });
    return null;
  }

  /// Produces 5–9 prospects every three in-game months.
  /// Prospects wait for the manager's review before joining the squad.
  Future<List<YouthProspect>> graduateYouthPlayersIfDue({
    required int teamId,
    required String date,
  }) async {
    final YouthAcademyState academy = await youthAcademyState(teamId);
    final DateTime currentDate = DateTime.tryParse(date) ?? DateTime.now();
    final DateTime? previousDate = DateTime.tryParse(
      academy.lastGraduatedDate ?? '',
    );
    if (previousDate == null) {
      await db.update(
        t.teamYouthAcademy,
        <String, Object?>{'last_graduated_date': date},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      return <YouthProspect>[];
    }
    if (currentDate.difference(previousDate).inDays < 90)
      return <YouthProspect>[];
    final List<Map<String, Object?>> teams = await db.query(
      t.teams,
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    if (teams.isEmpty) return <YouthProspect>[];
    final Map<String, Object?> team = teams.first;
    final math.Random random = math.Random();
    final int countryId = (team['country_id'] as int?) ?? 141;
    final List<Map<String, Object?>> nameRows = await db.query(
      t.players,
      columns: <String>['name'],
      where: 'country_id = ? AND name IS NOT NULL',
      whereArgs: <Object?>[countryId],
      orderBy: 'RANDOM()',
      limit: 12,
    );
    final int prospectCount = 5 + random.nextInt(5);
    final List<YouthProspect> prospects = <YouthProspect>[];
    await db.transaction((Transaction txn) async {
      await txn.update(
        t.teamYouthAcademy,
        <String, Object?>{'last_graduated_date': date},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      for (int i = 0; i < prospectCount; i++) {
        final int prospectPower = 42 + academy.level * 2 + random.nextInt(4);
        final int prospectPotential =
            (prospectPower + 12 + academy.level + random.nextInt(6)).clamp(
              prospectPower,
              95,
            );
        final int positionId = 1 + random.nextInt(11);
        final String name = _academyName(nameRows, random);
        final int height = 168 + random.nextInt(23);
        final int stars = academy.level >= 7 ? 1 : 0;
        final String profile = random.nextBool() ? 'D' : 'I';
        final int prospectId = await txn.insert(
          t.academyProspects,
          <String, Object?>{
            'team_id': teamId,
            'name': name,
            'age': 17,
            'position_id': positionId,
            'power': prospectPower,
            'potential': prospectPotential,
            'stars': stars,
            'profile': profile,
            'height': height,
            'country_id': countryId,
            'created_date': date,
            'signed': 0,
          },
        );
        prospects.add(
          YouthProspect(
            prospectId: prospectId,
            teamId: teamId,
            name: name,
            age: 17,
            positionId: positionId,
            power: prospectPower,
            potential: prospectPotential,
            stars: stars,
            profile: profile,
            height: height,
            countryId: countryId,
            createdDate: date,
            signed: false,
          ),
        );
      }
    });
    return prospects;
  }

  /// Prospects waiting to be signed by the manager.
  Future<List<YouthProspect>> pendingProspects(int teamId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.academyProspects,
      where: 'team_id = ? AND signed = 0',
      whereArgs: <Object?>[teamId],
      orderBy: 'power DESC, potential DESC',
    );
    return rows.map(YouthProspect.fromMap).toList();
  }

  /// Signs an academy prospect into the active club squad.
  Future<Player?> signProspect(int prospectId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.academyProspects,
      where: 'prospect_id = ? AND signed = 0',
      whereArgs: <Object?>[prospectId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> p = rows.first;
    final int teamId = p['team_id'] as int;
    final int power = p['power'] as int;
    final int potential = p['potential'] as int;
    final int positionId = p['position_id'] as int;
    final String name = p['name'] as String;
    final int countryId = p['country_id'] as int;
    final int age = p['age'] as int;
    final String profile = (p['profile'] as String?) ?? 'D';
    final int height = (p['height'] as int?) ?? 178;
    final int stars = (p['stars'] as int?) ?? 0;
    final int value = power * power * 1000;
    final int salary = 1200;

    late final int playerId;
    await db.transaction((Transaction txn) async {
      playerId = await txn.insert(t.players, <String, Object?>{
        'name': name,
        'age': age,
        'height': height,
        'stars': stars,
        'value': value,
        'salary': salary,
        'profile': profile,
        'fitness': 100,
        'status_id': t.statusActive,
        'power': power,
        'potential': potential,
        'market_status': t.marketActive,
        'country_id': countryId,
        'position_id': positionId,
        'squad_status': t.squadReserve,
        'is_captain': 0,
        'shirt_number': 0,
        'skill_a': 0,
        'skill_b': 0,
      });
      await txn.insert(t.teamPlayers, <String, Object?>{
        'team_id': teamId,
        'player_id': playerId,
      });
      await txn.update(
        t.academyProspects,
        <String, Object?>{'signed': 1},
        where: 'prospect_id = ?',
        whereArgs: <Object?>[prospectId],
      );
      await refreshTeamPower(teamId, txn);
    });

    return Player(
      playerId: playerId,
      name: name,
      age: age,
      positionId: positionId,
      power: power,
      potential: potential,
      fitness: 100,
      value: value,
      salary: salary,
      countryId: countryId,
      squadStatus: t.squadReserve,
      marketStatus: t.marketActive,
      statusId: t.statusActive,
      isCaptain: false,
      shirtNumber: 0,
      stars: stars,
      skillA: 0,
      skillB: 0,
      height: height,
      championships: null,
    );
  }

  String _academyName(List<Map<String, Object?>> rows, math.Random random) {
    final List<List<String>> parts = <List<String>>[
      for (final Map<String, Object?> row in rows)
        ((row['name'] as String?) ?? '')
            .trim()
            .split(RegExp(r'\s+'))
            .where((String part) => part.isNotEmpty)
            .toList(),
    ].where((List<String> name) => name.isNotEmpty).toList();
    if (parts.isEmpty) return 'Youth Player ${random.nextInt(9000) + 1000}';
    final List<String> first = parts[random.nextInt(parts.length)];
    final List<String> last = parts[random.nextInt(parts.length)];
    return '${first.first} ${last.last}';
  }

  // --------------------------------------------------------------- training

  /// Availability and eligible-player counts for this matchday.
  Future<TrainingState> trainingStatus({
    required int teamId,
    required int seasonId,
  }) async {
    final List<Map<String, Object?>> matchRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS played FROM matches
      WHERE season_id = ? AND status = ?
        AND (home_team_id = ? OR away_team_id = ?)
    ''',
      <Object?>[seasonId, t.matchFinished, teamId, teamId],
    );
    final int matchesPlayed = (matchRows.first['played'] as int?) ?? 0;

    final List<Map<String, Object?>> sessionRows = await db.query(
      t.teamTraining,
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final Set<String> done = <String>{};
    int sessions = 0;
    if (sessionRows.isNotEmpty) {
      final Map<String, Object?> row = sessionRows.first;
      final int rowSeason = (row['season_id'] as int?) ?? -1;
      final int lastCount = (row['last_match_count'] as int?) ?? -1;
      sessions = rowSeason == seasonId ? ((row['sessions'] as int?) ?? 0) : 0;
      if (rowSeason == seasonId && lastCount >= matchesPlayed) {
        done.addAll(
          ((row['done_focuses'] as String?) ?? '')
              .split(',')
              .where((String f) => f.isNotEmpty),
        );
      }
    }

    final List<Map<String, Object?>> countRows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN p.position_id = 1
          AND p.power < p.potential THEN 1 ELSE 0 END), 0) AS gk,
        COALESCE(SUM(CASE WHEN p.position_id IN (2, 3, 4)
          AND p.power < p.potential THEN 1 ELSE 0 END), 0) AS def,
        COALESCE(SUM(CASE WHEN p.position_id IN (5, 6, 7)
          AND p.power < p.potential THEN 1 ELSE 0 END), 0) AS mid,
        COALESCE(SUM(CASE WHEN p.position_id IN (8, 9, 10, 11)
          AND p.power < p.potential THEN 1 ELSE 0 END), 0) AS att,
        COALESCE(SUM(CASE WHEN p.fitness < 100 THEN 1 ELSE 0 END), 0) AS fit
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
    ''',
      <Object?>[teamId, t.statusActive],
    );
    final Map<String, Object?> c = countRows.first;
    return TrainingState(
      doneFocuses: done,
      sessions: sessions,
      matchesPlayed: matchesPlayed,
      cost: TrainingRules.cost,
      eligible: <String, int>{
        TrainingFocus.goalkeeper.name: (c['gk'] as int?) ?? 0,
        TrainingFocus.defence.name: (c['def'] as int?) ?? 0,
        TrainingFocus.midfield.name: (c['mid'] as int?) ?? 0,
        TrainingFocus.attack.name: (c['att'] as int?) ?? 0,
        TrainingFocus.fitness.name: (c['fit'] as int?) ?? 0,
      },
    );
  }

  /// Runs one training session for this matchday. Power focuses improve up to
  /// three players; fitness improves the whole squad.
  Future<TrainingOutcome> runTraining({
    required int teamId,
    required int seasonId,
    required TrainingFocus focus,
  }) async {
    final TrainingState state = await trainingStatus(
      teamId: teamId,
      seasonId: seasonId,
    );
    if (state.doneFocuses.contains(focus.name)) {
      return TrainingOutcome(
        error: '${focus.label} training is already done for this matchday.',
      );
    }
    if ((state.eligible[focus.name] ?? 0) <= 0) {
      return TrainingOutcome(
        error: focus.isFitness
            ? 'Every player is already at full fitness.'
            : 'No ${focus.label.toLowerCase()} players can improve right now.',
      );
    }
    final List<Map<String, Object?>> teamRows = await db.query(
      t.teams,
      columns: <String>['budget'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final int budget = teamRows.isEmpty
        ? 0
        : ((teamRows.first['budget'] as int?) ?? 0);
    if (budget < TrainingRules.cost) {
      return TrainingOutcome(
        error:
            'Not enough budget: a session costs '
            '${_moneyShort(TrainingRules.cost)}.',
      );
    }

    late final List<Map<String, Object?>> selected;
    if (focus.isFitness) {
      selected = await db.rawQuery(
        '''
        SELECT p.player_id, p.name, p.power AS previous_power FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        WHERE tp.team_id = ? AND p.status_id = ? AND p.fitness < 100
      ''',
        <Object?>[teamId, t.statusActive],
      );
    } else {
      selected = await db.rawQuery(
        '''
        SELECT p.player_id, p.name, p.power AS previous_power FROM players p
        JOIN team_players tp ON tp.player_id = p.player_id
        WHERE tp.team_id = ? AND p.status_id = ?
          AND p.position_id IN (${focus.positionIds.join(',')})
          AND p.power < p.potential
        ORDER BY (p.potential - p.power) DESC, p.age ASC
        LIMIT ?
      ''',
        <Object?>[teamId, t.statusActive, TrainingRules.maxPlayers],
      );
    }
    if (selected.isEmpty) {
      return const TrainingOutcome(
        error: 'No players are eligible for this training focus.',
      );
    }
    final List<int> ids = <int>[
      for (final Map<String, Object?> row in selected) row['player_id'] as int,
    ];
    final String placeholders = List<String>.filled(ids.length, '?').join(',');
    await db.transaction((Transaction txn) async {
      if (focus.isFitness) {
        await txn.rawUpdate(
          'UPDATE players SET fitness = MIN(100, fitness + ?) '
          'WHERE player_id IN ($placeholders)',
          <Object?>[TrainingRules.fitnessGain, ...ids],
        );
      } else {
        await txn.rawUpdate(
          'UPDATE players SET power = MIN(potential, power + ?), '
          'fitness = MIN(100, fitness + ?) '
          'WHERE player_id IN ($placeholders)',
          <Object?>[TrainingRules.powerGain, TrainingRules.fitnessGain, ...ids],
        );
      }
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - TrainingRules.cost},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      await txn.insert(t.teamTraining, <String, Object?>{
        'team_id': teamId,
        'season_id': seasonId,
        'last_match_count': state.matchesPlayed,
        'sessions': state.sessions + 1,
        'done_focuses': <String>{...state.doneFocuses, focus.name}.join(','),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (!focus.isFitness) {
        await refreshTeamPower(teamId, txn);
        // Update MV of each player that just improved.
        for (final Map<String, Object?> player in selected) {
          await refreshPlayerValue(
            player['player_id'] as int,
            previousPower: (player['previous_power'] as int?) ?? 0,
            txn: txn,
          );
        }
      }
    });
    return TrainingOutcome(
      improved: <String>[
        for (final Map<String, Object?> row in selected)
          (row['name'] as String?) ?? '',
      ],
      cost: TrainingRules.cost,
    );
  }

  /// Transfer history involving [teamId], newest first.
  Future<List<TransferRecord>> transferHistory(
    int teamId, {
    int limit = 50,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT pt.*, p.name AS player_name, ft.name AS from_name,
             tt.name AS to_name
      FROM player_transfers pt
      JOIN players p ON p.player_id = pt.player_id
      LEFT JOIN teams ft ON ft.team_id = pt.from_team_id
      LEFT JOIN teams tt ON tt.team_id = pt.to_team_id
      WHERE pt.from_team_id = ? OR pt.to_team_id = ?
      ORDER BY pt.date DESC, pt.transfer_id DESC
      LIMIT ?
    ''',
      <Object?>[teamId, teamId, limit],
    );
    return <TransferRecord>[
      for (final Map<String, Object?> r in rows)
        TransferRecord(
          playerId: (r['player_id'] as int?) ?? 0,
          playerName: (r['player_name'] as String?) ?? '',
          date: (r['date'] as String?) ?? '',
          fromTeamId: r['from_team_id'] as int?,
          toTeamId: r['to_team_id'] as int?,
          fromTeamName: (r['from_name'] as String?) ?? 'Free agent',
          toTeamName: (r['to_name'] as String?) ?? 'Free agent',
          value: (r['value'] as int?) ?? 0,
          type: (r['type'] as int?) ?? 1,
        ),
    ];
  }

  static String _moneyShort(int amount) {
    if (amount >= 1000000) return '\$${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '\$${(amount / 1000).toStringAsFixed(0)}K';
    return '\$$amount';
  }

  static String _todayIso() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
