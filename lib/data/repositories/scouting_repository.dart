import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';
import '../../game/player_valuation_service.dart';

/// Scouting department: hire scouts, dispatch them to regions, and discover wonderkids.
class ScoutingRepository {
  ScoutingRepository(this.db);

  final Database db;

  static const List<String> regions = <String>[
    'South America',
    'Europe',
    'Africa',
    'Asia',
  ];

  static int hiringCostForStars(int stars) => switch (stars) {
    1 => 150000,
    2 => 400000,
    3 => 900000,
    4 => 1800000,
    _ => 3500000,
  };

  static int salaryForStars(int stars) => switch (stars) {
    1 => 4000,
    2 => 10000,
    3 => 22000,
    4 => 45000,
    _ => 85000,
  };

  /// Scouts currently hired by [teamId].
  Future<List<Scout>> hiredScouts(int teamId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.scouts,
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      orderBy: 'stars DESC',
    );
    return rows.map(Scout.fromMap).toList();
  }

  /// Available scout market to recruit.
  List<Scout> availableScoutsToHire() {
    return <Scout>[
      Scout(
        scoutId: 1,
        teamId: 0,
        name: 'Carlos Mendez',
        stars: 2,
        region: 'South America',
        salary: salaryForStars(2),
        status: 'available',
      ),
      Scout(
        scoutId: 2,
        teamId: 0,
        name: 'Hans Becker',
        stars: 3,
        region: 'Europe',
        salary: salaryForStars(3),
        status: 'available',
      ),
      Scout(
        scoutId: 3,
        teamId: 0,
        name: 'Amara Diallo',
        stars: 4,
        region: 'Africa',
        salary: salaryForStars(4),
        status: 'available',
      ),
      Scout(
        scoutId: 4,
        teamId: 0,
        name: 'Takeshi Yamada',
        stars: 3,
        region: 'Asia',
        salary: salaryForStars(3),
        status: 'available',
      ),
      Scout(
        scoutId: 5,
        teamId: 0,
        name: 'Jean-Luc Dubois',
        stars: 5,
        region: 'Europe',
        salary: salaryForStars(5),
        status: 'available',
      ),
    ];
  }

  /// Hires a scout for [teamId] if budget allows.
  Future<String?> hireScout(int teamId, Scout candidate) async {
    final int cost = hiringCostForStars(candidate.stars);
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
    if (budget < cost) {
      return 'Not enough budget. Hiring cost is \$${(cost / 1000).toStringAsFixed(0)}K.';
    }

    final List<Scout> current = await hiredScouts(teamId);
    if (current.length >= 4) {
      return 'Scout capacity full (max 4 scouts). Fire one before hiring.';
    }

    await db.transaction((Transaction txn) async {
      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - cost},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );
      await txn.insert(t.scouts, <String, Object?>{
        'team_id': teamId,
        'name': candidate.name,
        'stars': candidate.stars,
        'region': candidate.region,
        'salary': candidate.salary,
        'status': 'idle',
      });
    });
    return null;
  }

  /// Releases a hired scout.
  Future<void> fireScout(int scoutId) => db.delete(
    t.scouts,
    where: 'scout_id = ?',
    whereArgs: <Object?>[scoutId],
  );

  /// Dispatches scout to a region. Generates immediate discovery report.
  Future<List<ScoutWonderkid>> deployScout({
    required int teamId,
    required Scout scout,
    required String region,
    required String date,
  }) async {
    final math.Random rng = math.Random();
    final List<Map<String, Object?>> headScoutRows = await db.query(
      t.teamStaff,
      where: 'team_id = ? AND role = ?',
      whereArgs: <Object?>[teamId, 'head_scout'],
      limit: 1,
    );
    final int headScoutStars = headScoutRows.isNotEmpty
        ? ((headScoutRows.first['stars'] as int?) ?? 1)
        : 0;
    final int extraProspect = (headScoutStars >= 4 && rng.nextDouble() < 0.6) ? 1 : 0;
    final int count = 2 + rng.nextInt(2) + extraProspect; // 2 to 4 wonderkids
    final List<ScoutWonderkid> found = <ScoutWonderkid>[];

    // Country IDs corresponding to region
    final List<int> countryPool = switch (region) {
      'South America' => <int>[24, 8, 41, 46], // Brasil, Argentina, Colombia, Chile
      'Africa' => <int>[4, 6, 42, 60], // Nigeria, Algeria, Senegal, etc.
      'Asia' => <int>[97, 102, 103, 105], // Indonesia, Japan, Korea, Australia
      _ => <int>[3, 64, 71, 185], // Germany, Spain, France, England
    };

    final int potBonus = headScoutStars >= 3 ? (headScoutStars - 2) * 2 : 0;
    final int baseOvr = 52 + scout.stars * 4;
    final int basePot = (72 + scout.stars * 4 + potBonus).clamp(72, 95);

    await db.transaction((Transaction txn) async {
      await txn.update(
        t.scouts,
        <String, Object?>{
          'status': 'scouting',
          'region': region,
          'last_report': date,
        },
        where: 'scout_id = ?',
        whereArgs: <Object?>[scout.scoutId],
      );

      for (int i = 0; i < count; i++) {
        final int countryId = countryPool[rng.nextInt(countryPool.length)];
        final List<Map<String, Object?>> nameRows = await txn.query(
          t.players,
          columns: <String>['name'],
          where: 'country_id = ? AND name IS NOT NULL',
          whereArgs: <Object?>[countryId],
          orderBy: 'RANDOM()',
          limit: 10,
        );
        final String name = _wonderkidName(nameRows, rng);
        final int age = 16 + rng.nextInt(3); // 16 to 18
        final int power = (baseOvr + rng.nextInt(5)).clamp(55, 82);
        final int potential = (basePot + rng.nextInt(6)).clamp(power + 8, 96);
        final int positionId = 1 + rng.nextInt(11);
        final int value = const PlayerValuationService().calculateTargetMarketValue(
          power: power,
          potential: potential,
          age: age,
          positionId: positionId,
        );

        final int reportId = await txn.insert(t.scoutReports, <String, Object?>{
          'team_id': teamId,
          'scout_id': scout.scoutId,
          'scout_name': scout.name,
          'region': region,
          'date': date,
          'player_name': name,
          'age': age,
          'position_id': positionId,
          'power': power,
          'potential': potential,
          'value': value,
          'country_id': countryId,
          'signed': 0,
        });

        found.add(
          ScoutWonderkid(
            reportId: reportId,
            teamId: teamId,
            scoutId: scout.scoutId,
            scoutName: scout.name,
            region: region,
            date: date,
            playerName: name,
            age: age,
            positionId: positionId,
            power: power,
            potential: potential,
            value: value,
            countryId: countryId,
            signed: false,
          ),
        );
      }
    });

    return found;
  }

  /// Pending wonderkids awaiting signing.
  Future<List<ScoutWonderkid>> pendingWonderkids(int teamId) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.scoutReports,
      where: 'team_id = ? AND signed = 0',
      whereArgs: <Object?>[teamId],
      orderBy: 'potential DESC, power DESC',
    );
    return rows.map(ScoutWonderkid.fromMap).toList();
  }

  Future<bool> rejectWonderkid({
    required int reportId,
    required int teamId,
  }) async {
    final int deleted = await db.delete(
      t.scoutReports,
      where: 'report_id = ? AND team_id = ? AND signed = 0',
      whereArgs: <Object?>[reportId, teamId],
    );
    return deleted > 0;
  }

  /// Signs scouted wonderkid to the team squad.
  Future<String?> signWonderkid({
    required int reportId,
    required int teamId,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.scoutReports,
      where: 'report_id = ? AND signed = 0',
      whereArgs: <Object?>[reportId],
      limit: 1,
    );
    if (rows.isEmpty) return 'Wonderkid report not found';
    final Map<String, Object?> r = rows.first;
    final int value = (r['value'] as int?) ?? 1000000;
    final int signingFee = (value * 0.75).round(); // Discounted scouting fee
    final int height = heightForPosition(
      (r['position_id'] as int?) ?? 1,
      math.Random(),
    );

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
    if (budget < signingFee) {
      return 'Not enough budget. Signing fee is \$${(signingFee / 1000000).toStringAsFixed(1)}M.';
    }

    await db.transaction((Transaction txn) async {
      final int playerId = await txn.insert(t.players, <String, Object?>{
        'name': r['player_name'],
        'age': r['age'],
        'height': height,
        'stars': ((r['potential'] as int?) ?? 80) >= 88 ? 1 : 0,
        'value': value,
        'salary': 2500,
        'profile': 'D',
        'fitness': 100,
        'status_id': t.statusActive,
        'power': r['power'],
        'potential': r['potential'],
        'market_status': t.marketActive,
        'country_id': r['country_id'],
        'position_id': r['position_id'],
        'squad_status': t.squadFirstTeam,
        'is_captain': 0,
        'shirt_number': 0,
        'skill_a': 0,
        'skill_b': 0,
      });

      await txn.insert(t.teamPlayers, <String, Object?>{
        'team_id': teamId,
        'player_id': playerId,
      });

      final int startYear = DateTime.now().year;
      await txn.insert(t.contracts, <String, Object?>{
        'player_id': playerId,
        'team_id': teamId,
        'start_date': '$startYear-07-01',
        'end_date': '${startYear + 3}-06-30',
        'status': 1,
        'salary': 2500,
      });

      await txn.update(
        t.teams,
        <String, Object?>{'budget': budget - signingFee},
        where: 'team_id = ?',
        whereArgs: <Object?>[teamId],
      );

      await txn.update(
        t.scoutReports,
        <String, Object?>{'signed': 1},
        where: 'report_id = ?',
        whereArgs: <Object?>[reportId],
      );
    });

    return null;
  }

  static int heightForPosition(int positionId, math.Random rng) {
    final (int minimum, int maximum) = heightRangeForPosition(positionId);
    return minimum + rng.nextInt(maximum - minimum + 1);
  }

  static (int, int) heightRangeForPosition(int positionId) {
    return switch (positionId) {
      1 => (178, 205),
      2 || 3 => (178, 198),
      4 => (175, 185),
      5 || 6 || 7 => (175, 194),
      8 || 9 => (175, 187),
      10 || 11 => (182, 196),
      _ => (175, 194),
    };
  }

  static String _wonderkidName(
    List<Map<String, Object?>> rows,
    math.Random rng,
  ) {
    final List<List<String>> parts = <List<String>>[
      for (final Map<String, Object?> row in rows)
        ((row['name'] as String?) ?? '')
            .trim()
            .split(RegExp(r'\s+'))
            .where((String part) => part.isNotEmpty)
            .toList(),
    ].where((List<String> name) => name.isNotEmpty).toList();
    if (parts.isEmpty) return 'Wonderkid ${rng.nextInt(9000) + 1000}';
    final List<String> first = parts[rng.nextInt(parts.length)];
    final List<String> last = parts[rng.nextInt(parts.length)];
    return '${first.first} ${last.last}';
  }
}
