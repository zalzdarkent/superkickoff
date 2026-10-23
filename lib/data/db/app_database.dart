import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../repositories/squad_repository.dart';
import 'schema.dart' as t;

/// Single access point for the SQLite game database.
///
/// The bundled asset [dbName] is copied into the app documents directory on
/// first launch (asset databases are read-only), then opened as a normal
/// writable SQLite database. It serves both as reference data (teams, players,
/// tournaments...) and as the save-game store (seasons, fixtures, results).
class AppDatabase {
  AppDatabase._();

  static const String dbName = 'superkickoff_2025.db';
  static const int assetRevision = 3;
  static String get localDbName => 'superkickoff_2025_v$assetRevision.db';
  static Database? _db;
  static String? _path;
  static String? _sessionPath;

  /// Opens (and lazily installs) the database. Desktop platforms use
  /// [sqflite_common_ffi]; Android/iOS use the default sqflite bindings.
  static Future<Database> open() async {
    if (_db != null) return _db!;
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final String target = p.join(docs.path, localDbName);
    final File file = File(target);
    if (!file.existsSync()) {
      final ByteData asset = await rootBundle.load('assets/data/$dbName');
      final List<int> bytes = asset.buffer.asUint8List();
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    _path = target;
    _sessionPath = '$target.session';
    _db = await databaseFactory.openDatabase(
      target,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await ensureLocalTables(_db!);
    await SquadRepository(_db!).refreshAllTeamPowers();
    return _db!;
  }

  /// Tables that belong to the save game rather than the bundled reference
  /// data. Created lazily so existing installs pick them up on the next run.
  static Future<void> ensureLocalTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.managerProfile} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL,
        country_id INTEGER NOT NULL
      )
    ''');
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamTraining} (
        team_id INTEGER PRIMARY KEY,
        season_id INTEGER NOT NULL,
        last_match_count INTEGER NOT NULL DEFAULT -1,
        sessions INTEGER NOT NULL DEFAULT 0,
        done_focuses TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.news} (
        news_id INTEGER PRIMARY KEY AUTOINCREMENT,
        ref TEXT NOT NULL UNIQUE,
        season_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        scope TEXT NOT NULL,
        category TEXT NOT NULL,
        headline TEXT NOT NULL,
        body TEXT NOT NULL,
        importance INTEGER NOT NULL DEFAULT 1,
        team_id INTEGER,
        player_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamYouthAcademy} (
        team_id INTEGER PRIMARY KEY,
        level INTEGER NOT NULL DEFAULT 1,
        last_graduated_season INTEGER,
        last_graduated_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.competitionPrizeRules} (
        tournament_id INTEGER PRIMARY KEY,
        base_pool INTEGER NOT NULL,
        participation_per_club INTEGER NOT NULL DEFAULT 0,
        win_bonus INTEGER NOT NULL DEFAULT 0,
        draw_bonus INTEGER NOT NULL DEFAULT 0,
        champion_bonus INTEGER NOT NULL DEFAULT 0,
        runner_up_bonus INTEGER NOT NULL DEFAULT 0,
        position_weights TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.competitionPrizeAwards} (
        award_id INTEGER PRIMARY KEY AUTOINCREMENT,
        season_id INTEGER NOT NULL,
        tournament_id INTEGER NOT NULL,
        team_id INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        reason TEXT,
        created_date TEXT NOT NULL,
        UNIQUE (season_id, tournament_id, team_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.transferOffers} (
        offer_id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        from_team_id INTEGER NOT NULL,
        to_team_id INTEGER NOT NULL,
        offer_amount INTEGER NOT NULL,
        player_value INTEGER NOT NULL,
        status INTEGER NOT NULL DEFAULT 1,
        counter_amount INTEGER,
        proposed_salary INTEGER,
        proposed_duration_years INTEGER,
        created_date TEXT NOT NULL,
        updated_date TEXT,
        message_id INTEGER,
        is_loan INTEGER NOT NULL DEFAULT 0,
        loan_seasons INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.academyProspects} (
        prospect_id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        age INTEGER NOT NULL DEFAULT 17,
        position_id INTEGER NOT NULL,
        power INTEGER NOT NULL,
        potential INTEGER NOT NULL,
        stars INTEGER NOT NULL DEFAULT 0,
        profile TEXT NOT NULL DEFAULT 'D',
        height INTEGER NOT NULL DEFAULT 178,
        country_id INTEGER NOT NULL,
        created_date TEXT NOT NULL,
        signed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.scouts} (
        scout_id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        stars INTEGER NOT NULL,
        region TEXT,
        salary INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'idle',
        return_date TEXT,
        last_report TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.scoutReports} (
        report_id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER NOT NULL,
        scout_id INTEGER NOT NULL,
        scout_name TEXT NOT NULL,
        region TEXT NOT NULL,
        date TEXT NOT NULL,
        player_name TEXT NOT NULL,
        age INTEGER NOT NULL,
        position_id INTEGER NOT NULL,
        power INTEGER NOT NULL,
        potential INTEGER NOT NULL,
        value INTEGER NOT NULL,
        country_id INTEGER NOT NULL,
        signed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO ${t.tournaments} (
        tournament_id, name, division_id, status, organization, rounds,
        play_days, slots, points, promotion_slots, relegation_spots,
        prize_teams, prize_top_scorer, prize_mvp
      ) VALUES (
        9999, 'Pre-Season Friendly', 0, 1, 4, 3,
        '3,6', '2', 0, 0, 0, 0, 0, 0
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO ${t.tournaments} (
        tournament_id, name, division_id, status, organization, rounds,
        play_days, slots, points, promotion_slots, relegation_spots,
        prize_teams, prize_top_scorer, prize_mvp
      ) VALUES
      (1650, 'AFC Challenge League', 0, 1, 2, 2, '2', '32', 1.0, 0, 0, 8000000, 0, 0),
      (1651, 'AFC Super Cup', 0, 1, 2, 1, '6', '2', 1.0, 0, 0, 4000000, 0, 0)
    ''');
    await db.execute(
      "UPDATE ${t.tournaments} SET name = CASE tournament_id "
      "WHEN 85 THEN 'BRI Super League' "
      "WHEN 86 THEN 'Pegadaian Championship' "
      "WHEN 189 THEN 'Liga Nusantara' "
      "WHEN 54 THEN 'UEFA Super Cup' "
      "ELSE name END WHERE tournament_id IN (54, 85, 86, 189)",
    );
    // Ensure international slots for AFC Challenge League (Indonesia, Thailand, Malaysia, Vietnam, India, etc.)
    await db.execute('''
      INSERT OR IGNORE INTO ${t.internationalSlots} (tournament_id, country_id, slots) VALUES
      -- AFC Challenge League (1650)
      (1650, 94, 2),  -- Indonesia
      (1650, 223, 2), -- Thailand
      (1650, 146, 2), -- Malaysia
      (1650, 243, 2), -- Vietnam
      (1650, 93, 2),  -- India
      (1650, 96, 2),  -- Iraq
      (1650, 95, 2),  -- Iran
      (1650, 184, 2), -- Qatar
      (1650, 240, 2), -- Uzbekistan
      (1650, 10, 2),  -- Saudi Arabia
      (1650, 124, 2), -- Japan
      (1650, 49, 2),  -- South Korea
      (1650, 41, 2),  -- China
      (1650, 14, 2),  -- Australia

      -- UEFA Super Cup (54)
      (54, 64, 1),   -- Spain
      (54, 185, 1),  -- England
      (54, 3, 1),    -- Germany
      (54, 122, 1),  -- Italy

      -- AFC Super Cup (1651)
      (1651, 10, 1),  -- Saudi Arabia
      (1651, 124, 1), -- Japan
      (1651, 49, 1),  -- South Korea
      (1651, 94, 1),  -- Indonesia

      -- Intercontinental Cup (56) - 8 clubs worldwide
      (56, 64, 1),   -- Europe (Spain)
      (56, 185, 1),  -- Europe (England)
      (56, 30, 1),   -- South America (Brazil)
      (56, 11, 1),   -- South America (Argentina)
      (56, 141, 1),  -- North America (Mexico)
      (56, 10, 1),   -- Asia (Saudi Arabia)
      (56, 94, 1),   -- Asia (Indonesia)
      (56, 58, 1),   -- Africa (Egypt)

      -- FIFA Club World Cup (163) - 16 clubs worldwide
      (163, 64, 2),  -- Spain
      (163, 185, 2), -- England
      (163, 3, 1),   -- Germany
      (163, 122, 1), -- Italy
      (163, 71, 1),  -- France
      (163, 30, 2),  -- Brazil
      (163, 11, 2),  -- Argentina
      (163, 141, 1), -- Mexico
      (163, 65, 1),  -- USA
      (163, 10, 1),  -- Saudi Arabia
      (163, 124, 1), -- Japan
      (163, 94, 1),  -- Indonesia
      (163, 58, 1)   -- Egypt
    ''');
    final List<Map<String, Object?>> offerColumns = await db.rawQuery(
      'PRAGMA table_info(${t.transferOffers})',
    );
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'is_loan',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN is_loan INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'loan_seasons',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN loan_seasons INTEGER NOT NULL DEFAULT 1',
      );
    }
    final List<Map<String, Object?>> trainingColumns = await db.rawQuery(
      'PRAGMA table_info(${t.teamTraining})',
    );
    if (!trainingColumns.any(
      (Map<String, Object?> column) => column['name'] == 'done_focuses',
    )) {
      await db.execute(
        "ALTER TABLE ${t.teamTraining} ADD COLUMN done_focuses TEXT NOT NULL DEFAULT ''",
      );
    }
    final List<Map<String, Object?>> academyColumns = await db.rawQuery(
      'PRAGMA table_info(${t.teamYouthAcademy})',
    );
    if (!academyColumns.any(
      (Map<String, Object?> column) => column['name'] == 'last_graduated_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.teamYouthAcademy} ADD COLUMN last_graduated_date TEXT',
      );
    }
    final List<Map<String, Object?>> messageColumns = await db.rawQuery(
      'PRAGMA table_info(${t.messages})',
    );
    if (!messageColumns.any(
      (Map<String, Object?> column) => column['name'] == 'transfer_offer_id',
    )) {
      await db.execute(
        'ALTER TABLE ${t.messages} ADD COLUMN transfer_offer_id INTEGER',
      );
    }
    // The bundled database only gave Persib a transfer budget. Backfill every
    // zero-budget club once, scaling available funds to club strength.
    await db.execute('''
      UPDATE teams
      SET budget = CASE
        WHEN power <= 40 THEN 500000
        ELSE MAX(500000, (power - 40) * (power - 40) * 40000)
      END
      WHERE COALESCE(budget, 0) <= 0
    ''');
    await db.execute('''
      UPDATE teams
      SET abbreviation = CASE name
        WHEN 'Persija' THEN 'PSJ'
        WHEN 'Persebaya' THEN 'PSB'
        WHEN 'Persijap' THEN 'PSJ'
        WHEN 'Persib' THEN 'PSB'
        WHEN 'Persik' THEN 'PSK'
        WHEN 'Persis' THEN 'PSS'
        WHEN 'Persita' THEN 'PST'
        WHEN 'Persekat' THEN 'PKT'
        WHEN 'Persiraja' THEN 'PSR'
        WHEN 'Persela' THEN 'PSL'
        WHEN 'Persiba' THEN 'PSB'
        WHEN 'Persiku' THEN 'PKU'
        WHEN 'Persipal' THEN 'PSP'
        WHEN 'Persipura' THEN 'PSP'
        WHEN 'Persipa' THEN 'PSP'
        WHEN 'Persibo' THEN 'PSB'
        WHEN 'Persikabo 1973' THEN 'PKB'
        WHEN 'Persikota' THEN 'PKT'
        WHEN 'Persewar' THEN 'PSW'
        WHEN 'Perserang' THEN 'PSR'
        WHEN 'Persekabpas' THEN 'PKP'
        WHEN 'Persikutim United' THEN 'PKU'
        WHEN 'Persikad' THEN 'PKD'
      END
      WHERE country_id = (SELECT country_id FROM countries WHERE name = 'Indonesia')
        AND abbreviation = 'Per'
    ''');
  }

  /// Test/dev helper: open an arbitrary file directly.
  static Future<Database> openFile(String path) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await ensureLocalTables(_db!);
    await SquadRepository(_db!).refreshAllTeamPowers();
    return _db!;
  }

  /// Captures the pre-session save so "Don't save" can restore it.
  static Future<void> beginSession() async {
    final String? path = _path;
    if (path == null || _db == null) return;
    final File snapshot = File(_sessionPath!);
    if (!snapshot.existsSync()) await File(path).copy(snapshot.path);
  }

  /// Commits or restores the snapshot created by [beginSession].
  static Future<void> finishSession({required bool save}) async {
    final String? path = _path;
    final String? snapshotPath = _sessionPath;
    if (path == null || snapshotPath == null) return;
    final File snapshot = File(snapshotPath);
    if (save || !snapshot.existsSync()) {
      if (snapshot.existsSync()) await snapshot.delete();
      return;
    }
    await _db?.close();
    _db = null;
    await snapshot.copy(path);
    await snapshot.delete();
    await open();
  }

  /// Starts a genuinely fresh local career without mutating the bundled DB.
  static Future<void> reset() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final String target = p.join(docs.path, localDbName);
    await _db?.close();
    _db = null;
    final File snapshot = File('$target.session');
    if (snapshot.existsSync()) await snapshot.delete();
    final ByteData asset = await rootBundle.load('assets/data/$dbName');
    await File(target).writeAsBytes(asset.buffer.asUint8List(), flush: true);
    _path = target;
    _sessionPath = '$target.session';
    await open();
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Progress reported while the long career-generation runs.
  static final ValueNotifier<String> status = ValueNotifier<String>(
    'Preparing database...',
  );
}
