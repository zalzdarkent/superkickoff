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
      orderBy: 'power DESC, points DESC, name ASC',
    );
    return rows.map(Country.fromMap).toList();
  }

  /// Fetches FIFA World Rankings sorted by power DESC, points DESC, name ASC.
  /// If previous_rank has not been initialized for countries, it initializes it.
  Future<List<Country>> getFifaRankings({int? confederation}) async {
    final List<Country> list = await getNationalTeams(confederation: confederation);
    return list;
  }

  /// Snapshots the current world rankings into `previous_rank`.
  /// Call this when international windows finish, at end-of-season, or during ranking updates.
  Future<void> snapshotWorldRankings([DatabaseExecutor? executor]) async {
    final DatabaseExecutor exec = executor ?? db;
    final List<Map<String, Object?>> rows = await exec.query(
      t.countries,
      columns: <String>['country_id'],
      orderBy: 'power DESC, points DESC, name ASC',
    );
    final Batch batch = exec.batch();
    for (int i = 0; i < rows.length; i++) {
      final int cId = rows[i]['country_id'] as int;
      batch.update(
        t.countries,
        <String, Object?>{'previous_rank': i + 1},
        where: 'country_id = ?',
        whereArgs: <Object?>[cId],
      );
    }
    await batch.commit(noResult: true);
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
        COALESCE(SUM(minutes), 0) AS minutes,
        COALESCE(SUM(starter), 0) AS starts,
        COALESCE(SUM(goals), 0) AS goals,
        COALESCE(SUM(assists), 0) AS assists,
        COALESCE(SUM(yellow_cards), 0) AS yellow_cards,
        COALESCE(SUM(red_cards), 0) AS red_cards,
        COALESCE(SUM(mvp), 0) AS mvps,
        AVG(rating) AS avg_rating
      FROM ${t.matchPlayersCountries}
      WHERE player_id = ?
        ${countryId != null ? 'AND country_id = $countryId' : ''}
        ${seasonId != null ? 'AND match_id IN (SELECT match_id FROM ${t.countryMatches} WHERE season_id = $seasonId)' : ''}
      ''',
      <Object?>[playerId],
    );

    final List<Map<String, Object?>> archivedRows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(matches_played), 0) AS matches_played,
        COALESCE(SUM(minutes), 0) AS minutes,
        COALESCE(SUM(starts), 0) AS starts,
        COALESCE(SUM(goals), 0) AS goals,
        COALESCE(SUM(assists), 0) AS assists,
        COALESCE(SUM(yellow_cards), 0) AS yellow_cards,
        COALESCE(SUM(red_cards), 0) AS red_cards,
        COALESCE(SUM(mvps), 0) AS mvps,
        AVG(CASE WHEN matches_played > 0 THEN CAST(rating AS REAL) / matches_played END) AS avg_rating
      FROM ${t.playerSeasonStatsCountries}
      WHERE player_id = ?
        ${countryId != null ? 'AND country_id = $countryId' : ''}
        ${seasonId != null ? 'AND season_id = $seasonId' : ''}
      ''',
      <Object?>[playerId],
    );

    final Map<String, Object?> r = rows.isNotEmpty ? rows.first : const <String, Object?>{};
    final Map<String, Object?> ar = archivedRows.isNotEmpty ? archivedRows.first : const <String, Object?>{};
    final int livePlayed = (r['matches_played'] as int?) ?? 0;
    final int archPlayed = (ar['matches_played'] as int?) ?? 0;
    final int played = livePlayed + archPlayed;

    if (played == 0) {
      return PlayerNationalStats(
        playerId: playerId,
        countryId: countryId ?? 0,
        seasonId: seasonId,
      );
    }

    final double liveRating = (r['avg_rating'] as num?)?.toDouble() ?? 60.0;
    final double archRating = (ar['avg_rating'] as num?)?.toDouble() ?? 60.0;
    final double rawRating = livePlayed > 0 && archPlayed > 0
        ? ((liveRating * livePlayed) + (archRating * archPlayed)) / played
        : (livePlayed > 0 ? liveRating : archRating);

    return PlayerNationalStats(
      playerId: playerId,
      countryId: countryId ?? 0,
      seasonId: seasonId,
      matchesPlayed: played,
      minutes: ((r['minutes'] as int?) ?? 0) + ((ar['minutes'] as int?) ?? 0),
      starts: ((r['starts'] as int?) ?? 0) + ((ar['starts'] as int?) ?? 0),
      goals: ((r['goals'] as int?) ?? 0) + ((ar['goals'] as int?) ?? 0),
      assists: ((r['assists'] as int?) ?? 0) + ((ar['assists'] as int?) ?? 0),
      yellowCards: ((r['yellow_cards'] as int?) ?? 0) + ((ar['yellow_cards'] as int?) ?? 0),
      redCards: ((r['red_cards'] as int?) ?? 0) + ((ar['red_cards'] as int?) ?? 0),
      mvps: ((r['mvps'] as int?) ?? 0) + ((ar['mvps'] as int?) ?? 0),
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
  /// Deduplicates across windows and seasons so the same player or player name never repeats.
  Future<List<PlayerNationalStats>> getCountrySquad(int countryId, {int? seasonId}) async {
    int? targetSeasonId = seasonId;
    if (targetSeasonId == null) {
      final List<Map<String, Object?>> maxRows = await db.rawQuery(
        'SELECT MAX(season_id) AS max_s FROM ${t.countryCallups} WHERE country_id = ?',
        <Object?>[countryId],
      );
      targetSeasonId = maxRows.isNotEmpty ? maxRows.first['max_s'] as int? : null;
    }

    List<Map<String, Object?>> callupRows = <Map<String, Object?>>[];
    if (targetSeasonId != null) {
      callupRows = await db.rawQuery(
        '''
        SELECT p.player_id,
               p.name,
               p.position_id,
               p.power,
               COALESCE(
                 (SELECT d.squad_number
                  FROM ${t.internationalDuty} d
                  WHERE d.player_id = p.player_id AND d.country_id = cc.country_id
                  ORDER BY d.duty_id DESC
                  LIMIT 1),
                 0
               ) AS squad_number,
               (SELECT tm.name
                FROM ${t.teamPlayers} tp
                JOIN ${t.teams} tm ON tm.team_id = tp.team_id
                WHERE tp.player_id = p.player_id
                LIMIT 1) AS club_name
        FROM ${t.countryCallups} cc
        JOIN ${t.players} p ON p.player_id = cc.player_id
        WHERE cc.country_id = ? AND cc.season_id = ? AND p.status_id = ?
        GROUP BY p.player_id
        ORDER BY p.power DESC
        ''',
        <Object?>[countryId, targetSeasonId, t.statusActive],
      );
    }

    final List<Map<String, Object?>> deduplicated = <Map<String, Object?>>[];
    final Set<int> seenIds = <int>{};
    final Set<String> seenNames = <String>{};

    void addCandidate(Map<String, Object?> r) {
      if (deduplicated.length >= 23) return;
      final int pid = (r['player_id'] as int?) ?? 0;
      if (pid == 0 || seenIds.contains(pid)) return;
      final String normName = ((r['name'] as String?) ?? '').trim().toLowerCase();
      if (normName.isNotEmpty && seenNames.contains(normName)) return;
      seenIds.add(pid);
      if (normName.isNotEmpty) seenNames.add(normName);
      deduplicated.add(r);
    }

    for (final Map<String, Object?> r in callupRows) {
      addCandidate(r);
    }

    if (deduplicated.length < 23) {
      final List<Map<String, Object?>> poolRows = await db.rawQuery(
        '''
        SELECT p.player_id,
               p.name,
               p.position_id,
               p.power,
               0 AS squad_number,
               (SELECT tm.name
                FROM ${t.teamPlayers} tp
                JOIN ${t.teams} tm ON tm.team_id = tp.team_id
                WHERE tp.player_id = p.player_id
                LIMIT 1) AS club_name
        FROM ${t.players} p
        WHERE (p.country_id = ? OR p.player_id IN (
          SELECT player_id FROM ${t.playerNationalEligibility} WHERE country_id = ?
        )) AND p.status_id = ?
        ORDER BY p.power DESC
        LIMIT 80
        ''',
        <Object?>[countryId, countryId, t.statusActive],
      );

      int posGroupOf(Map<String, Object?> r) {
        final int raw = (r['position_id'] as int?) ?? 1;
        return raw == 1 ? 1 : (raw <= 4 ? 2 : (raw <= 8 ? 3 : 4));
      }

      int countGroup(int group) =>
          deduplicated.where((Map<String, Object?> r) => posGroupOf(r) == group).length;

      const Map<int, int> minTargets = <int, int>{1: 3, 2: 7, 3: 6, 4: 4};
      for (final MapEntry<int, int> entry in minTargets.entries) {
        for (final Map<String, Object?> r in poolRows) {
          if (deduplicated.length >= 23) break;
          if (countGroup(entry.key) >= entry.value) break;
          if (posGroupOf(r) == entry.key) {
            addCandidate(r);
          }
        }
      }
      for (final Map<String, Object?> r in poolRows) {
        if (deduplicated.length >= 23) break;
        addCandidate(r);
      }
    }

    final Set<int> usedNumbers = <int>{};
    int nextNumber = 1;
    final List<PlayerNationalStats> squad = <PlayerNationalStats>[];

    for (final Map<String, Object?> r in deduplicated) {
      final int pid = r['player_id'] as int;
      final PlayerNationalStats stats = await playerInternationalStats(
        pid,
        countryId: countryId,
        seasonId: seasonId,
      );
      final int rawPos = (r['position_id'] as int?) ?? 1;
      final int posGroup = rawPos == 1 ? 1 : (rawPos <= 4 ? 2 : (rawPos <= 8 ? 3 : 4));
      int shirt = (r['squad_number'] as int?) ?? 0;
      if (shirt <= 0 || usedNumbers.contains(shirt)) {
        while (usedNumbers.contains(nextNumber)) {
          nextNumber++;
        }
        shirt = nextNumber;
      }
      usedNumbers.add(shirt);
      squad.add(
        stats.copyWith(
          playerName: (r['name'] as String?) ?? 'Player $pid',
          positionId: posGroup,
          power: (r['power'] as int?) ?? 50,
          shirtNumber: shirt,
          clubName: r['club_name'] as String?,
        ),
      );
    }
    return squad;
  }

  /// Recalculates power for all countries dynamically from their top 11 active players.
  ///
  /// This ensures that as players grow through training, match performance,
  /// or youth development, their national team power updates dynamically in the world ranking
  /// and matchmaking ladders.
  Future<void> refreshAllCountryPowers([Transaction? txn]) async {
    final DatabaseExecutor executor = txn ?? db;
    // 1. Snapshot previous rank before updating powers if previous_rank is unset or needs tracking
    final List<Map<String, Object?>> unranked = await executor.query(
      t.countries,
      columns: <String>['country_id'],
      where: 'previous_rank IS NULL',
      limit: 1,
    );
    if (unranked.isNotEmpty) {
      await snapshotWorldRankings(executor);
    }

    await executor.rawUpdate(
      '''
      UPDATE ${t.countries}
      SET power = (
        SELECT CAST(ROUND(AVG(top_p.power)) AS INTEGER)
        FROM (
          SELECT p.power
          FROM ${t.players} p
          WHERE p.country_id = countries.country_id AND p.status_id = ?
          ORDER BY p.power DESC
          LIMIT 11
        ) AS top_p
      )
      WHERE EXISTS (
        SELECT 1
        FROM ${t.players} p
        WHERE p.country_id = countries.country_id AND p.status_id = ?
      )
      ''',
      <Object?>[t.statusActive, t.statusActive],
    );
  }

  /// Recalculates power for a specific country from its top 11 active players.
  Future<int> refreshCountryPower(int countryId, [Transaction? txn]) async {
    final DatabaseExecutor executor = txn ?? db;
    final List<Map<String, Object?>> rows = await executor.rawQuery(
      '''
      SELECT p.power
      FROM ${t.players} p
      WHERE p.country_id = ? AND p.status_id = ?
      ORDER BY p.power DESC
      LIMIT 11
      ''',
      <Object?>[countryId, t.statusActive],
    );
    if (rows.isEmpty) return 0;
    final int sum = rows.fold<int>(
      0,
      (int acc, Map<String, Object?> r) => acc + ((r['power'] as int?) ?? 0),
    );
    final int newPower = (sum / rows.length).round();
    await executor.update(
      t.countries,
      <String, Object?>{'power': newPower},
      where: 'country_id = ?',
      whereArgs: <Object?>[countryId],
    );
    return newPower;
  }
}


