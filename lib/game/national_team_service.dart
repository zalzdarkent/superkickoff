import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';

/// Service managing national teams, player eligibility, allegiance,
/// and international statistics.
class NationalTeamService {
  NationalTeamService(this.db);

  final Database db;

  /// Fetches all national teams (countries), optionally filtered by confederation.
  Future<List<Country>> getNationalTeams({int? confederation}) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.countries,
      where: confederation != null ? 'confederation = ?' : null,
      whereArgs: confederation != null ? <Object?>[confederation] : null,
      orderBy: 'power DESC, name ASC',
    );
    return rows.map(Country.fromMap).toList();
  }

  /// Fetches a specific national team by [countryId].
  Future<Country?> getNationalTeam(int countryId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.countries,
      where: 'country_id = ?',
      whereArgs: <Object?>[countryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Country.fromMap(rows.first);
  }

  /// Returns all eligible country IDs for [playerId].
  ///
  /// Considers primary nationality, secondary eligibility, and cap-tie locking.
  /// A player is NEVER eligible for a country merely because their club resides there.
  Future<List<int>> eligibleCountryIdsForPlayer(int playerId) async {
    // 1. Check if the player is already cap-tied
    final List<Map<String, Object?>> lockedRows = await db.query(
      t.playerNationalEligibility,
      columns: <String>['country_id'],
      where: 'player_id = ? AND is_locked = 1',
      whereArgs: <Object?>[playerId],
      limit: 1,
    );
    if (lockedRows.isNotEmpty) {
      return <int>[lockedRows.first['country_id'] as int];
    }

    // Check if cap-tied via official competitive matches
    final List<Map<String, Object?>> competitiveMatches = await db.rawQuery(
      '''
      SELECT mpc.country_id
      FROM ${t.matchPlayersCountries} mpc
      JOIN ${t.countryMatches} cm ON cm.match_id = mpc.match_id
      WHERE mpc.player_id = ? AND cm.tournament_id != ? AND mpc.minutes > 0
      LIMIT 1
      ''',
      <Object?>[playerId, t.tournamentFriendlies],
    );
    if (competitiveMatches.isNotEmpty) {
      final int lockedCountryId = competitiveMatches.first['country_id'] as int;
      await lockAllegiance(playerId, lockedCountryId);
      return <int>[lockedCountryId];
    }

    // 2. Query primary country from players table
    final List<Map<String, Object?>> playerRow = await db.query(
      t.players,
      columns: <String>['country_id'],
      where: 'player_id = ?',
      whereArgs: <Object?>[playerId],
      limit: 1,
    );
    if (playerRow.isEmpty) return <int>[];
    final int primaryCountryId = playerRow.first['country_id'] as int;

    final Set<int> result = <int>{primaryCountryId};

    // 3. Query secondary nationalities
    final List<Map<String, Object?>> secondaryRows = await db.query(
      t.playerNationalEligibility,
      columns: <String>['country_id'],
      where: 'player_id = ?',
      whereArgs: <Object?>[playerId],
    );
    for (final Map<String, Object?> r in secondaryRows) {
      result.add(r['country_id'] as int);
    }

    return result.toList();
  }

  /// Verifies whether [playerId] is eligible to represent [countryId].
  Future<bool> isPlayerEligibleForCountry(int playerId, int countryId) async {
    final List<int> eligible = await eligibleCountryIdsForPlayer(playerId);
    return eligible.contains(countryId);
  }

  Future<bool> isEligibleForCountry(int playerId, int countryId) =>
      isPlayerEligibleForCountry(playerId, countryId);

  Future<List<int>> eligibleCountryIds(int playerId) =>
      eligibleCountryIdsForPlayer(playerId);

  /// Registers a secondary nationality for [playerId].
  Future<void> addSecondaryNationality(
    int playerId,
    int countryId, {
    String? notes,
  }) async {
    await db.insert(
      t.playerNationalEligibility,
      <String, Object?>{
        'player_id': playerId,
        'country_id': countryId,
        'is_primary': 0,
        'is_locked': 0,
        'notes': notes ?? 'Secondary nationality',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> addSecondaryEligibility({
    required int playerId,
    required int countryId,
    String? reason,
  }) => addSecondaryNationality(playerId, countryId, notes: reason);

  /// Permanently ties [playerId]'s allegiance to [countryId] after competitive representation.
  Future<void> lockAllegiance(
    int playerId,
    int countryId, {
    int? matchId,
    String? matchType,
  }) async {
    await db.transaction((Transaction txn) async {
      await txn.insert(
        t.playerNationalEligibility,
        <String, Object?>{
          'player_id': playerId,
          'country_id': countryId,
          'is_primary': 1,
          'is_locked': 1,
          'notes': 'Cap-tied in official competitive match',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Delete any other competing eligibility
      await txn.delete(
        t.playerNationalEligibility,
        where: 'player_id = ? AND country_id != ?',
        whereArgs: <Object?>[playerId, countryId],
      );
    });
  }

  Future<PlayerNationalStats?> getPlayerStats(int playerId) => playerInternationalStats(playerId);

  /// Fetches aggregate international stats for [playerId].
  Future<PlayerNationalStats> playerInternationalStats(
    int playerId, {
    int? countryId,
    int? seasonId,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS matches_played,
        SUM(minutes) AS minutes,
        SUM(starter) AS starts,
        SUM(goals) AS goals,
        SUM(assists) AS assists,
        SUM(yellow_cards) AS yellow_cards,
        SUM(red_cards) AS red_cards,
        SUM(mvp) AS mvps,
        AVG(rating) AS avg_rating
      FROM ${t.matchPlayersCountries}
      WHERE player_id = ?
        ${countryId != null ? 'AND country_id = $countryId' : ''}
        ${seasonId != null ? 'AND match_id IN (SELECT match_id FROM ${t.countryMatches} WHERE season_id = $seasonId)' : ''}
      ''',
      <Object?>[playerId],
    );

    if (rows.isEmpty || rows.first['matches_played'] == 0) {
      return PlayerNationalStats(
        playerId: playerId,
        countryId: countryId ?? 0,
        seasonId: seasonId,
      );
    }

    final Map<String, Object?> r = rows.first;
    final int played = (r['matches_played'] as int?) ?? 0;
    final double rawRating = (r['avg_rating'] as num?)?.toDouble() ?? 60.0;

    return PlayerNationalStats(
      playerId: playerId,
      countryId: countryId ?? 0,
      seasonId: seasonId,
      matchesPlayed: played,
      minutes: (r['minutes'] as int?) ?? 0,
      starts: (r['starts'] as int?) ?? 0,
      goals: (r['goals'] as int?) ?? 0,
      assists: (r['assists'] as int?) ?? 0,
      yellowCards: (r['yellow_cards'] as int?) ?? 0,
      redCards: (r['red_cards'] as int?) ?? 0,
      mvps: (r['mvps'] as int?) ?? 0,
      rating: rawRating > 10 ? rawRating / 10.0 : rawRating,
    );
  }

  /// Returns active international duty record for [playerId] on [date], if any.
  Future<InternationalDuty?> activeDutyForPlayer(int playerId, String date) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.internationalDuty,
      where: 'player_id = ? AND status = ?',
      whereArgs: <Object?>[playerId, 'active'],
    );
    for (final Map<String, Object?> r in rows) {
      final InternationalDuty duty = InternationalDuty.fromMap(r);
      if (duty.isActiveOn(date)) return duty;
    }
    return null;
  }

  /// Checks if [playerId] is on active international duty on [date].
  Future<bool> isPlayerOnDuty(int playerId, String date) async {
    final InternationalDuty? duty = await activeDutyForPlayer(playerId, date);
    return duty != null;
  }

  /// Fetches the national-team squad players for [countryId] with their stats and player details.
  Future<List<PlayerNationalStats>> getCountrySquad(int countryId, {int? seasonId}) async {
    final List<Map<String, Object?>> callupRows = await db.rawQuery(
      '''
      SELECT p.player_id, p.name, p.position_id, p.power, d.squad_number, tm.name AS club_name
      FROM ${t.countryCallups} cc
      JOIN ${t.players} p ON p.player_id = cc.player_id
      LEFT JOIN ${t.internationalDuty} d ON d.player_id = cc.player_id AND d.country_id = cc.country_id
      LEFT JOIN ${t.teamPlayers} tp ON tp.player_id = p.player_id
      LEFT JOIN ${t.teams} tm ON tm.team_id = tp.team_id
      WHERE cc.country_id = ? ${seasonId != null ? 'AND cc.season_id = $seasonId' : ''}
      ORDER BY p.power DESC
      ''',
      <Object?>[countryId],
    );

    List<Map<String, Object?>> source = callupRows;
    if (source.isEmpty) {
      source = await db.rawQuery(
        '''
        SELECT p.player_id, p.name, p.position_id, p.power, 0 AS squad_number, tm.name AS club_name
        FROM ${t.players} p
        LEFT JOIN ${t.teamPlayers} tp ON tp.player_id = p.player_id
        LEFT JOIN ${t.teams} tm ON tm.team_id = tp.team_id
        WHERE p.country_id = ? AND p.status_id = ?
        ORDER BY p.power DESC
        LIMIT 23
        ''',
        <Object?>[countryId, t.statusActive],
      );
    }

    final List<PlayerNationalStats> squad = <PlayerNationalStats>[];
    for (final Map<String, Object?> r in source) {
      final int pid = r['player_id'] as int;
      final PlayerNationalStats stats = await playerInternationalStats(
        pid,
        countryId: countryId,
        seasonId: seasonId,
      );
      final int rawPos = (r['position_id'] as int?) ?? 1;
      final int posGroup = rawPos == 1 ? 1 : (rawPos <= 4 ? 2 : (rawPos <= 8 ? 3 : 4));
      squad.add(
        stats.copyWith(
          playerName: (r['name'] as String?) ?? 'Player $pid',
          positionId: posGroup,
          power: (r['power'] as int?) ?? 50,
          shirtNumber: (r['squad_number'] as int?) ?? 0,
          clubName: r['club_name'] as String?,
        ),
      );
    }
    return squad;
  }
}

