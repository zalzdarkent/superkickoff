import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import 'national_team_service.dart';

/// Squad selection outcome for a national team window.
class NationalTeamSquadSelection {
  const NationalTeamSquadSelection({
    required this.countryId,
    required this.countryName,
    required this.players,
    required this.captainId,
    required this.squadNumbers,
  });

  final int countryId;
  final String countryName;
  final List<Player> players;
  final int captainId;
  final Map<int, int> squadNumbers; // playerId -> shirt number

  List<Player> get squad => players;
}

typedef CallupResult = NationalTeamSquadSelection;

/// Service that selects balanced, eligible national-team squads and coordinates call-ups.
class NationalTeamSelectionService {
  NationalTeamSelectionService(this.db, {Random? random})
      : _nationalService = NationalTeamService(db);

  final Database db;
  final NationalTeamService _nationalService;

  Future<NationalTeamSquadSelection> selectSquad({
    required int countryId,
    required int seasonId,
    required InternationalWindow window,
    int squadSize = 23,
    int targetSquadSize = 23,
    int? tournamentId,
  }) => selectSquadForCountry(
    countryId: countryId,
    seasonId: seasonId,
    window: window,
    squadSize: targetSquadSize != 23 ? targetSquadSize : squadSize,
  );

  /// Checks whether [playerId] is free to be called up for a date range.
  Future<bool> canCallupPlayer(int playerId, String startDate, String endDate) async {
    final List<Map<String, Object?>> overlapping = await db.rawQuery(
      '''
      SELECT * FROM ${t.internationalDuty}
      WHERE player_id = ? AND status = 'active'
        AND NOT (return_date < ? OR release_date > ?)
      ''',
      <Object?>[playerId, startDate, endDate],
    );
    return overlapping.isEmpty;
  }

  static int positionGroup(int positionId) {
    if (positionId == 1) return 1; // GK
    if (positionId <= 4) return 2; // DEF
    if (positionId <= 8) return 3; // MID
    return 4; // ATT
  }

  /// Selects a balanced squad for [countryId] during [window].
  Future<NationalTeamSquadSelection> selectSquadForCountry({
    required int countryId,
    required int seasonId,
    required InternationalWindow window,
    int squadSize = 23,
    int minGk = 3,
    int minDef = 7,
    int minMid = 6,
    int minAtt = 4,
    int? userTeamId,
  }) async {
    final Country? country = await _nationalService.getNationalTeam(countryId);
    final String countryName = country?.name ?? 'National Team';

    // Idempotency: If squad was already selected for this window, return existing squad
    final List<Map<String, Object?>> existingDuties = await db.query(
      t.internationalDuty,
      where: 'season_id = ? AND country_id = ? AND window_id = ? AND status = ?',
      whereArgs: <Object?>[seasonId, countryId, window.windowId, 'active'],
    );
    if (existingDuties.length >= squadSize) {
      final List<int> pIds = existingDuties.map((r) => r['player_id'] as int).toList();
      final List<Map<String, Object?>> pRows = await db.rawQuery(
        'SELECT * FROM ${t.players} WHERE player_id IN (${pIds.join(',')})',
      );
      final Map<int, Player> pMap = <int, Player>{
        for (final r in pRows) (r['player_id'] as int): Player.fromMap(r),
      };
      final List<Player> existingSquad = <Player>[];
      final Map<int, int> existingNumbers = <int, int>{};
      int capId = 0;
      for (final r in existingDuties) {
        final int pid = r['player_id'] as int;
        if (pMap.containsKey(pid)) {
          existingSquad.add(pMap[pid]!);
        }
        existingNumbers[pid] = (r['squad_number'] as int?) ?? 1;
        if ((r['is_captain'] as int?) == 1) {
          capId = pid;
        }
      }
      return NationalTeamSquadSelection(
        countryId: countryId,
        countryName: countryName,
        players: existingSquad,
        captainId: capId != 0 ? capId : (existingSquad.isNotEmpty ? existingSquad.first.playerId : 0),
        squadNumbers: existingNumbers,
      );
    }

    // 1. Gather all eligible players
    final List<Map<String, Object?>> primaryRows = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${t.players} p
      WHERE p.country_id = ? AND p.status_id = ?
      ORDER BY p.power DESC
      ''',
      <Object?>[countryId, t.statusActive],
    );

    final List<Map<String, Object?>> secondaryRows = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${t.players} p
      JOIN ${t.playerNationalEligibility} pne ON pne.player_id = p.player_id
      WHERE pne.country_id = ? AND p.status_id = ?
      ORDER BY p.power DESC
      ''',
      <Object?>[countryId, t.statusActive],
    );

    final Map<int, Player> pool = <int, Player>{};
    for (final Map<String, Object?> r in primaryRows) {
      final Player p = Player.fromMap(r);
      pool[p.playerId] = p;
    }
    for (final Map<String, Object?> r in secondaryRows) {
      final Player p = Player.fromMap(r);
      pool[p.playerId] = p;
    }

    // 2. Filter out injured or already-called-up players for overlapping duty
    final List<Map<String, Object?>> overlappingRows = await db.rawQuery(
      '''
      SELECT DISTINCT player_id
      FROM ${t.internationalDuty}
      WHERE status = 'active'
        AND NOT (return_date < ? OR release_date > ?)
      ''',
      <Object?>[window.releaseStartDate, window.returnDate],
    );
    final Set<int> busyPlayerIds = overlappingRows
        .map((Map<String, Object?> r) => r['player_id'] as int)
        .toSet();

    final List<Player> available = <Player>[];
    for (final Player p in pool.values) {
      // Injury check: fitness floor 40 or future injury return date
      if (p.fitness < 40) continue;
      if (p.injuryReturnDate != null && p.injuryReturnDate!.isNotEmpty) {
        if (p.injuryReturnDate!.compareTo(window.startDate) > 0) continue;
      }

      // Check overlapping international duty
      if (busyPlayerIds.contains(p.playerId)) continue;

      available.add(p);
    }

    // Sort available pool by effective power + fitness
    available.sort((Player a, Player b) {
      final double scoreA = a.power + (a.fitness / 100.0) * 3.0;
      final double scoreB = b.power + (b.fitness / 100.0) * 3.0;
      return scoreB.compareTo(scoreA);
    });

    // 3. Position group quotas
    final List<Player> gks = available.where((p) => positionGroup(p.positionId) == 1).toList();
    final List<Player> defs = available.where((p) => positionGroup(p.positionId) == 2).toList();
    final List<Player> mids = available.where((p) => positionGroup(p.positionId) == 3).toList();
    final List<Player> atts = available.where((p) => positionGroup(p.positionId) == 4).toList();

    final List<Player> selected = <Player>[];
    final Set<int> selectedIds = <int>{};
    final Set<String> selectedNames = <String>{};

    bool canSelect(Player p) {
      if (selectedIds.contains(p.playerId)) return false;
      final String normName = p.name.trim().toLowerCase();
      if (normName.isNotEmpty && selectedNames.contains(normName)) return false;
      return true;
    }

    void markSelected(Player p) {
      selected.add(p);
      selectedIds.add(p.playerId);
      final String normName = p.name.trim().toLowerCase();
      if (normName.isNotEmpty) selectedNames.add(normName);
    }

    void pick(List<Player> group, int count) {
      for (final Player p in group) {
        if (!canSelect(p)) continue;
        if (selected.length >= squadSize) break;
        markSelected(p);
        if (selected.where((x) => group.contains(x)).length >= count) break;
      }
    }

    // Pick minimum requirements
    pick(gks, minGk);
    pick(defs, minDef);
    pick(mids, minMid);
    pick(atts, minAtt);

    // Fill remaining slots with the best remaining outfield players
    for (final Player p in available) {
      if (selected.length >= squadSize) break;
      if (canSelect(p)) {
        markSelected(p);
      }
    }

    // If still empty (e.g. tiny nation), add all available players
    if (selected.isEmpty && pool.isNotEmpty) {
      for (final Player p in pool.values) {
        if (selected.length >= squadSize) break;
        if (canSelect(p)) {
          markSelected(p);
        }
      }
    }

    // 4. Determine Captain & Shirt numbers
    int captainId = 0;
    if (selected.isNotEmpty) {
      // Pick highest power outfield player or highest power overall
      final List<Player> sortedByPower = List<Player>.of(selected)
        ..sort((a, b) => b.power.compareTo(a.power));
      final Player cap = sortedByPower.firstWhere(
        (p) => p.positionId != 1,
        orElse: () => sortedByPower.first,
      );
      captainId = cap.playerId;
    }

    final Map<int, int> numbers = <int, int>{};
    int num = 1;
    // Assign 1 to first goalkeeper
    final Player startingGk = selected.firstWhere(
      (p) => positionGroup(p.positionId) == 1,
      orElse: () => selected.first,
    );
    numbers[startingGk.playerId] = 1;
    num = 2;
    for (final Player p in selected) {
      if (numbers.containsKey(p.playerId)) continue;
      numbers[p.playerId] = num++;
    }

    // 5. Persist Call-ups and International Duty
    await db.transaction((Transaction txn) async {
      await txn.delete(
        t.countryCallups,
        where: 'country_id = ? AND season_id = ?',
        whereArgs: <Object?>[countryId, seasonId],
      );
      for (final Player p in selected) {
        final bool isCap = p.playerId == captainId;
        final int shirt = numbers[p.playerId] ?? 0;

        await txn.insert(
          t.countryCallups,
          <String, Object?>{
            'country_id': countryId,
            'player_id': p.playerId,
            'season_id': seasonId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.insert(
          t.internationalDuty,
          <String, Object?>{
            'season_id': seasonId,
            'country_id': countryId,
            'player_id': p.playerId,
            'window_id': window.windowId,
            'release_date': window.releaseStartDate,
            'return_date': window.returnDate,
            'squad_number': shirt,
            'is_captain': isCap ? 1 : 0,
            'status': 'active',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    // 6. Notify user manager if any player from user club was called up
    if (userTeamId != null && userTeamId > 0) {
      await _notifyUserClubCallups(
        selected: selected,
        countryName: countryName,
        window: window,
        userTeamId: userTeamId,
      );
    }

    return NationalTeamSquadSelection(
      countryId: countryId,
      countryName: countryName,
      players: selected,
      captainId: captainId,
      squadNumbers: numbers,
    );
  }

  /// Sends inbox messages when user club players are selected for national duty.
  Future<void> _notifyUserClubCallups({
    required List<Player> selected,
    required String countryName,
    required InternationalWindow window,
    required int userTeamId,
  }) async {
    final List<Map<String, Object?>> clubPlayerRows = await db.query(
      t.teamPlayers,
      columns: <String>['player_id'],
      where: 'team_id = ?',
      whereArgs: <Object?>[userTeamId],
    );
    final Set<int> clubPlayerIds = clubPlayerRows.map((r) => r['player_id'] as int).toSet();

    for (final Player p in selected) {
      if (clubPlayerIds.contains(p.playerId)) {
        await db.insert(
          t.messages,
          <String, Object?>{
            'title': 'Panggilan Tim Nasional: ${p.name}',
            'sender': 'Timnas $countryName',
            'player_id': p.playerId,
            'team_id': userTeamId,
            'body': '${p.name} telah dipanggil membela $countryName untuk agenda ${window.name} '
                '(${window.startDate} s/d ${window.endDate}). Pemain akan bertugas dari '
                '${window.releaseStartDate} dan kembali ke klub pada ${window.returnDate}.',
            'date': window.releaseStartDate,
            'is_read': 0,
          },
        );
      }
    }
  }

  /// Replaces an injured or withdrawn player with an eligible replacement.
  Future<Player?> replaceCalledUpPlayer({
    required int countryId,
    required int seasonId,
    required int injuredPlayerId,
    required InternationalWindow window,
  }) async {
    // 1. Mark existing duty withdrawn
    await db.update(
      t.internationalDuty,
      <String, Object?>{'status': 'withdrawn'},
      where: 'season_id = ? AND country_id = ? AND player_id = ? AND window_id = ?',
      whereArgs: <Object?>[seasonId, countryId, injuredPlayerId, window.windowId],
    );

    // 2. Fetch injured player's position
    final List<Map<String, Object?>> pRows = await db.query(
      t.players,
      columns: <String>['position_id'],
      where: 'player_id = ?',
      whereArgs: <Object?>[injuredPlayerId],
      limit: 1,
    );
    final int group = pRows.isNotEmpty ? positionGroup(pRows.first['position_id'] as int) : 2;

    // 3. Find best available eligible replacement
    final List<Map<String, Object?>> candidates = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${t.players} p
      WHERE (p.country_id = ? OR p.player_id IN (
        SELECT player_id FROM ${t.playerNationalEligibility} WHERE country_id = ?
      ))
      AND p.status_id = ?
      AND p.fitness >= 40
      AND p.player_id != ?
      AND p.player_id NOT IN (
        SELECT player_id FROM ${t.internationalDuty}
        WHERE season_id = ? AND window_id = ? AND status = 'active'
      )
      ORDER BY p.power DESC
      ''',
      <Object?>[countryId, countryId, t.statusActive, injuredPlayerId, seasonId, window.windowId],
    );

    if (candidates.isEmpty) return null;

    // Prefer same position group
    Player? replacement;
    for (final Map<String, Object?> r in candidates) {
      final Player p = Player.fromMap(r);
      if (positionGroup(p.positionId) == group) {
        replacement = p;
        break;
      }
    }
    replacement ??= Player.fromMap(candidates.first);

    // 4. Persist replacement callup
    await db.insert(
      t.countryCallups,
      <String, Object?>{
        'country_id': countryId,
        'player_id': replacement.playerId,
        'season_id': seasonId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert(
      t.internationalDuty,
      <String, Object?>{
        'season_id': seasonId,
        'country_id': countryId,
        'player_id': replacement.playerId,
        'window_id': window.windowId,
        'release_date': window.releaseStartDate,
        'return_date': window.returnDate,
        'squad_number': 23,
        'is_captain': 0,
        'status': 'active',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return replacement;
  }

  /// Automatically releases all players whose international duty concluded on or before [currentDate].
  Future<int> releaseConcludedDuties([String? currentDate]) async {
    final String actualDate = currentDate ?? DateTime.now().toIso8601String();
    final String clean = actualDate.length >= 10 ? actualDate.substring(0, 10) : actualDate;
    final int updated = await db.update(
      t.internationalDuty,
      <String, Object?>{'status': 'returned'},
      where: "status = 'active' AND return_date < ?",
      whereArgs: <Object?>[clean],
    );
    return updated;
  }
}
