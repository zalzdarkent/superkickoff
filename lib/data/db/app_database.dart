import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../repositories/club_logo_service.dart';
import '../repositories/league_logo_service.dart';
import '../repositories/squad_repository.dart';
import '../models/models.dart';
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
    final List<Map<String, Object?>> playerColumns = await db.rawQuery(
      'PRAGMA table_info(${t.players})',
    );
    if (!playerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'injury_return_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.players} ADD COLUMN injury_return_date TEXT',
      );
    }
    final List<Map<String, Object?>> stadiumColumns = await db.rawQuery(
      'PRAGMA table_info(${t.stadiums})',
    );
    final Set<String> existingStadiumColumns = stadiumColumns
        .map((Map<String, Object?> column) => column['name'] as String)
        .toSet();
    const Map<String, int> defaultTicketPrices = <String, int>{
      'ticket_price_general': Stadium.defaultGeneralTicketPrice,
      'ticket_price_stand': Stadium.defaultStandTicketPrice,
      'ticket_price_terrace': Stadium.defaultTerraceTicketPrice,
      'ticket_price_boxes': Stadium.defaultBoxesTicketPrice,
    };
    for (final MapEntry<String, int> entry in defaultTicketPrices.entries) {
      if (!existingStadiumColumns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE ${t.stadiums} ADD COLUMN ${entry.key} '
          'INTEGER NOT NULL DEFAULT ${entry.value}',
        );
      }
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.managerProfile} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL,
        country_id INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.offseasonState} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        season_id INTEGER NOT NULL,
        step INTEGER NOT NULL DEFAULT 0,
        report TEXT NOT NULL DEFAULT '',
        window_weeks INTEGER NOT NULL DEFAULT 0,
        camp TEXT,
        ambition TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.boardObjectives} (
        start_year INTEGER NOT NULL,
        team_id INTEGER NOT NULL,
        target_rank INTEGER NOT NULL,
        bonus INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        PRIMARY KEY (start_year, team_id)
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
        loan_seasons INTEGER NOT NULL DEFAULT 1,
        agreement_date TEXT,
        effective_date TEXT,
        eligible_date TEXT,
        transfer_type TEXT NOT NULL DEFAULT 'permanent',
        loan_months INTEGER,
        wage_split_ratio REAL NOT NULL DEFAULT 1.0,
        loan_start_date TEXT,
        loan_end_date TEXT,
        cancellation_reason TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.transferWindows} (
        window_id INTEGER PRIMARY KEY AUTOINCREMENT,
        season_id INTEGER NOT NULL,
        country_id INTEGER NOT NULL,
        tournament_id INTEGER NOT NULL DEFAULT 0,
        window_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        is_open INTEGER NOT NULL DEFAULT 0,
        allow_free_agents_outside INTEGER NOT NULL DEFAULT 1,
        UNIQUE (season_id, country_id, tournament_id, window_type)
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
      CREATE TABLE IF NOT EXISTS ${t.careerState} (
        season_id INTEGER PRIMARY KEY,
        orientation_completed INTEGER NOT NULL DEFAULT 0,
        pre_season_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamFacilities} (
        team_id INTEGER PRIMARY KEY,
        training_level INTEGER NOT NULL DEFAULT 1,
        medical_level INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamStaff} (
        staff_id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        name TEXT NOT NULL,
        stars INTEGER NOT NULL DEFAULT 1,
        salary INTEGER NOT NULL DEFAULT 5000,
        specialty TEXT,
        hired_date TEXT,
        UNIQUE (team_id, role)
      )
    ''');
    // ---------------------------------------------------- fixture scheduling
    // Persisted competition rules. CompetitionConfig derives safe defaults from
    // the bundled tournament data; this table stores explicit/season-specific
    // rules without touching the immutable reference database.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS competition_configs (
        tournament_id INTEGER NOT NULL,
        season_start_year INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'league',
        format TEXT NOT NULL DEFAULT 'doubleRoundRobin',
        participant_count INTEGER,
        double_round_robin INTEGER NOT NULL DEFAULT 1,
        matchday_interval_days INTEGER NOT NULL DEFAULT 7,
        min_rest_days INTEGER NOT NULL DEFAULT 2,
        group_size INTEGER NOT NULL DEFAULT 4,
        group_count INTEGER NOT NULL DEFAULT 0,
        group_double_round_robin INTEGER NOT NULL DEFAULT 1,
        group_qualifiers_per_group INTEGER NOT NULL DEFAULT 2,
        league_phase_opponents INTEGER NOT NULL DEFAULT 0,
        league_phase_home_matches INTEGER NOT NULL DEFAULT 0,
        league_phase_away_matches INTEGER NOT NULL DEFAULT 0,
        league_phase_qualifiers INTEGER NOT NULL DEFAULT 0,
        knockout_legs INTEGER NOT NULL DEFAULT 1,
        final_single_match INTEGER NOT NULL DEFAULT 1,
        neutral_final INTEGER NOT NULL DEFAULT 0,
        extra_time INTEGER NOT NULL DEFAULT 1,
        penalties INTEGER NOT NULL DEFAULT 1,
        away_goals INTEGER NOT NULL DEFAULT 0,
        use_byes INTEGER NOT NULL DEFAULT 1,
        trim_to_power_of_two INTEGER NOT NULL DEFAULT 0,
        field_size INTEGER,
        promotion_slots INTEGER NOT NULL DEFAULT 0,
        relegation_slots INTEGER NOT NULL DEFAULT 0,
        unavailable_dates TEXT NOT NULL DEFAULT '[]',
        allowed_weekdays TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY (tournament_id, season_start_year)
      )
    ''');
    final List<Map<String, Object?>> configColumns = await db.rawQuery(
      'PRAGMA table_info(competition_configs)',
    );
    if (!configColumns.any(
      (Map<String, Object?> column) => column['name'] == 'unavailable_dates',
    )) {
      await db.execute(
        "ALTER TABLE competition_configs ADD COLUMN "
        "unavailable_dates TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (!configColumns.any(
      (Map<String, Object?> column) =>
          column['name'] == 'group_qualifiers_per_group',
    )) {
      await db.execute(
        'ALTER TABLE competition_configs ADD COLUMN '
        'group_qualifiers_per_group INTEGER NOT NULL DEFAULT 2',
      );
    }
    if (!configColumns.any(
      (Map<String, Object?> column) => column['name'] == 'allowed_weekdays',
    )) {
      await db.execute(
        "ALTER TABLE competition_configs ADD COLUMN "
        "allowed_weekdays TEXT NOT NULL DEFAULT '[]'",
      );
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fixture_reschedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        match_id INTEGER NOT NULL,
        old_date TEXT,
        new_date TEXT NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS knockout_byes (
        season_id INTEGER NOT NULL,
        tournament_id INTEGER NOT NULL,
        phase INTEGER NOT NULL,
        team_id INTEGER NOT NULL,
        PRIMARY KEY (season_id, tournament_id, phase, team_id)
      )
    ''');
    // New match metadata. Existing saves keep every row and receive NULL/0
    // defaults for the new columns.
    final List<Map<String, Object?>> matchColumns = await db.rawQuery(
      'PRAGMA table_info(${t.matches})',
    );
    bool hasMatchColumn(String name) =>
        matchColumns.any((Map<String, Object?> c) => c['name'] == name);
    if (!hasMatchColumn('kickoff_time')) {
      await db.execute('ALTER TABLE ${t.matches} ADD COLUMN kickoff_time TEXT');
    }
    if (!hasMatchColumn('original_date')) {
      await db.execute(
        'ALTER TABLE ${t.matches} ADD COLUMN original_date TEXT',
      );
    }
    if (!hasMatchColumn('reschedule_reason')) {
      await db.execute(
        'ALTER TABLE ${t.matches} ADD COLUMN reschedule_reason TEXT',
      );
    }
    if (!hasMatchColumn('neutral_venue')) {
      await db.execute(
        'ALTER TABLE ${t.matches} ADD COLUMN neutral_venue INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!hasMatchColumn('extra_time')) {
      await db.execute(
        'ALTER TABLE ${t.matches} ADD COLUMN extra_time INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!hasMatchColumn('away_goals_rule')) {
      await db.execute(
        'ALTER TABLE ${t.matches} ADD COLUMN away_goals_rule INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_matches_season_date '
      'ON ${t.matches}(season_id, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_matches_tournament_phase '
      'ON ${t.matches}(tournament_id, phase, round)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_matches_status_date '
      'ON ${t.matches}(status, date)',
    );
    // A fixture may only exist once per competition/season/round/leg. The
    // expression index also separates group fixtures. If a legacy save already
    // contains duplicates the unique index is skipped, and the validator will
    // report them instead of deleting data.
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_matches_fixture '
        'ON ${t.matches}(season_id, tournament_id, phase, leg, round, '
        'home_team_id, away_team_id, IFNULL(group_id, -1))',
      );
    } catch (_) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_matches_fixture_lookup '
        'ON ${t.matches}(season_id, tournament_id, phase, leg, round)',
      );
    }
    try {
      await db.execute('ALTER TABLE ${t.playerAwards} ADD COLUMN rating REAL');
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE ${t.playerAwards} ADD COLUMN stat_subtitle TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE ${t.playerAwards} ADD COLUMN position_id INTEGER',
      );
    } catch (_) {}
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
    // Remove super cups and world cups from international_slots (they are champion-based, not country quotas)
    await db.execute('''
      DELETE FROM ${t.internationalSlots} WHERE tournament_id IN (54, 56, 163, 1651);
    ''');
    // Keep Indonesia's direct ACL Elite slot; India and Vietnam have no direct slot.
    await db.execute('''
      DELETE FROM ${t.internationalSlots} WHERE tournament_id = 99 AND country_id IN (93, 243);
    ''');
    // Deduplicate international_slots if duplicates exist
    await db.execute('''
      DELETE FROM ${t.internationalSlots} WHERE rowid NOT IN (
        SELECT MIN(rowid) FROM ${t.internationalSlots} GROUP BY tournament_id, country_id
      );
    ''');
    // Ensure unique index
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_international_slots_tour_country
      ON ${t.internationalSlots} (tournament_id, country_id);
    ''');
    // Indonesia's league champion qualifies directly for ACL Elite; lower
    // league places feed ACL Two and the AFC Challenge League.
    await db.execute('''
      INSERT OR REPLACE INTO ${t.internationalSlots}
        (tournament_id, country_id, slots) VALUES
        (99, 94, 1),
        (164, 94, 1),
        (1650, 94, 1);
      UPDATE ${t.internationalSlots} SET slots = 2
        WHERE tournament_id = 164 AND country_id IN (60, 124, 49, 184);
    ''');
    // Ensure international slots for AFC Challenge League (1650).
    await db.execute('''
      INSERT OR IGNORE INTO ${t.internationalSlots} (tournament_id, country_id, slots) VALUES
      -- AFC Challenge League (1650)
      (1650, 94, 1),  -- Indonesia (1 slot for runner-up / cup winner)
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
      (1650, 14, 2);  -- Australia
    ''');

    // ---------------- International football tables & migrations ----------------
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.internationalWindows} (
        window_id TEXT PRIMARY KEY,
        season_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        window_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        release_start_date TEXT NOT NULL,
        return_date TEXT NOT NULL,
        is_mandatory INTEGER NOT NULL DEFAULT 1,
        max_matches INTEGER NOT NULL DEFAULT 2,
        club_fixtures_allowed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.internationalDuty} (
        duty_id INTEGER PRIMARY KEY AUTOINCREMENT,
        season_id INTEGER NOT NULL,
        country_id INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        window_id TEXT NOT NULL,
        release_date TEXT NOT NULL,
        return_date TEXT NOT NULL,
        squad_number INTEGER DEFAULT 0,
        is_captain INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'active',
        UNIQUE(season_id, player_id, window_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.playerNationalEligibility} (
        player_id INTEGER NOT NULL,
        country_id INTEGER NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 1,
        is_locked INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        PRIMARY KEY (player_id, country_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.countryMatches} (
        match_id INTEGER PRIMARY KEY AUTOINCREMENT,
        tournament_id INTEGER,
        season_id INTEGER,
        referee_id INTEGER,
        stadium_id INTEGER,
        home_country_id INTEGER DEFAULT 0,
        away_country_id INTEGER DEFAULT 0,
        home_goals INTEGER DEFAULT 0,
        away_goals INTEGER DEFAULT 0,
        winner_id INTEGER DEFAULT 0,
        attendance_general INTEGER DEFAULT 0,
        attendance_stand INTEGER DEFAULT 0,
        attendance_terrace INTEGER DEFAULT 0,
        attendance_boxes INTEGER DEFAULT 0,
        revenue INTEGER DEFAULT 0,
        phase INTEGER DEFAULT 0,
        round INTEGER DEFAULT 0,
        status INTEGER DEFAULT 1,
        leg INTEGER DEFAULT 1,
        date TEXT,
        penalty_home_goals INTEGER,
        penalty_away_goals INTEGER,
        group_id INTEGER,
        window_id TEXT,
        original_date TEXT,
        reschedule_reason TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.countryCallups} (
        country_id INTEGER,
        player_id INTEGER,
        season_id INTEGER,
        PRIMARY KEY (season_id, player_id, country_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.matchPlayersCountries} (
        player_id INTEGER NOT NULL,
        match_id INTEGER NOT NULL,
        country_id INTEGER NOT NULL,
        starter INTEGER,
        minutes INTEGER,
        points INTEGER,
        rating INTEGER,
        mvp INTEGER,
        goals INTEGER,
        yellow_cards INTEGER,
        red_cards INTEGER,
        assists INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.playerSeasonStatsCountries} (
        player_id INTEGER NOT NULL,
        country_id INTEGER NOT NULL,
        season_id INTEGER NOT NULL,
        matches_played INTEGER,
        minutes INTEGER,
        rating INTEGER,
        starts INTEGER,
        yellow_cards INTEGER,
        red_cards INTEGER,
        mvps INTEGER,
        goals INTEGER,
        assists INTEGER,
        PRIMARY KEY (player_id, country_id, season_id)
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_pssc_player_country_season
      ON ${t.playerSeasonStatsCountries} (player_id, country_id, season_id);
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.seasonCountries} (
        country_id INTEGER,
        season_id INTEGER,
        coach_id INTEGER,
        position INTEGER DEFAULT 0,
        PRIMARY KEY (country_id, season_id)
      )
    ''');

    final List<Map<String, Object?>> countryMatchColumns = await db.rawQuery(
      'PRAGMA table_info(${t.countryMatches})',
    );
    bool hasCountryMatchColumn(String name) =>
        countryMatchColumns.any((Map<String, Object?> c) => c['name'] == name);
    if (!hasCountryMatchColumn('group_id')) {
      await db.execute(
        'ALTER TABLE ${t.countryMatches} ADD COLUMN group_id INTEGER',
      );
    }
    if (!hasCountryMatchColumn('window_id')) {
      await db.execute(
        'ALTER TABLE ${t.countryMatches} ADD COLUMN window_id TEXT',
      );
    }
    if (!hasCountryMatchColumn('original_date')) {
      await db.execute(
        'ALTER TABLE ${t.countryMatches} ADD COLUMN original_date TEXT',
      );
    }
    if (!hasCountryMatchColumn('reschedule_reason')) {
      await db.execute(
        'ALTER TABLE ${t.countryMatches} ADD COLUMN reschedule_reason TEXT',
      );
    }

    await db.execute('''
      INSERT OR IGNORE INTO ${t.tournaments} (
        tournament_id, name, division_id, status, organization, rounds,
        play_days, slots, points, promotion_slots, relegation_spots,
        prize_teams, prize_top_scorer, prize_mvp
      ) VALUES
      (900, 'International Friendly', 0, 1, 2, 1, '2,5,6', '0', 0, 0, 0, 0, 0, 0),
      (901, 'UEFA Nations League', 0, 1, 2, 2, '2,5,6', '16', 3, 4, 4, 15000000, 2000000, 500000),
      (902, 'ASEAN Championship', 0, 1, 2, 1, '2,5,6', '10', 3, 0, 0, 3000000, 500000, 100000),
      (903, 'FIFA ASEAN Cup', 0, 1, 2, 1, '2,5,6', '14', 3, 0, 0, 4000000, 600000, 150000),
      (904, 'World Cup Qualifiers', 0, 1, 2, 2, '2,5,6', '0', 3, 0, 0, 5000000, 1000000, 250000)
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
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'agreement_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN agreement_date TEXT',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'effective_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN effective_date TEXT',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'eligible_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN eligible_date TEXT',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'transfer_type',
    )) {
      await db.execute(
        "ALTER TABLE ${t.transferOffers} ADD COLUMN transfer_type TEXT NOT NULL DEFAULT 'permanent'",
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'loan_months',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN loan_months INTEGER',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'wage_split_ratio',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN wage_split_ratio REAL NOT NULL DEFAULT 1.0',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'loan_start_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN loan_start_date TEXT',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'loan_end_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN loan_end_date TEXT',
      );
    }
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'cancellation_reason',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN cancellation_reason TEXT',
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
    final List<Map<String, Object?>> teamColumns = await db.rawQuery(
      'PRAGMA table_info(${t.teams})',
    );
    if (!teamColumns.any(
      (Map<String, Object?> column) => column['name'] == 'logo_base64',
    )) {
      try {
        await db.execute('ALTER TABLE ${t.teams} ADD COLUMN logo_base64 TEXT');
      } catch (_) {}
    }
    await const ClubLogoService().seedDefaultLogos(db);

    final List<Map<String, Object?>> tournamentColumns = await db.rawQuery(
      'PRAGMA table_info(${t.tournaments})',
    );
    if (!tournamentColumns.any(
      (Map<String, Object?> column) => column['name'] == 'logo_base64',
    )) {
      try {
        await db.execute(
          'ALTER TABLE ${t.tournaments} ADD COLUMN logo_base64 TEXT',
        );
      } catch (_) {}
    }
    await const LeagueLogoService().seedDefaultLogos(db);

    // Normalize country names from Spanish to standard Indonesian
    try {
      await db.rawUpdate('''
        UPDATE ${t.countries} SET name = CASE country_id
          WHEN 124 THEN 'Jepang'
          WHEN 3 THEN 'Jerman'
          WHEN 49 THEN 'Korea Selatan'
          WHEN 48 THEN 'Korea Utara'
          WHEN 64 THEN 'Spanyol'
          WHEN 65 THEN 'Amerika Serikat'
          WHEN 71 THEN 'Prancis'
          WHEN 185 THEN 'Inggris'
          WHEN 249 THEN 'Skotlandia'
          WHEN 250 THEN 'Wales'
          WHEN 251 THEN 'Irlandia Utara'
          WHEN 172 THEN 'Belanda'
          WHEN 17 THEN 'Belgia'
          WHEN 218 THEN 'Swiss'
          WHEN 217 THEN 'Swedia'
          WHEN 168 THEN 'Norwegia'
          WHEN 55 THEN 'Denmark'
          WHEN 58 THEN 'Mesir'
          WHEN 150 THEN 'Maroko'
          WHEN 215 THEN 'Afrika Selatan'
          WHEN 37 THEN 'Kamerun'
          WHEN 50 THEN 'Pantai Gading'
          WHEN 187 THEN 'Ceko'
          WHEN 62 THEN 'Slowakia'
          WHEN 63 THEN 'Slovenia'
          WHEN 52 THEN 'Kroasia'
          WHEN 181 THEN 'Polandia'
          WHEN 192 THEN 'Rumania'
          WHEN 193 THEN 'Rusia'
          WHEN 235 THEN 'Turki'
          WHEN 237 THEN 'Ukraina'
          WHEN 78 THEN 'Yunani'
          WHEN 92 THEN 'Hungaria'
          WHEN 15 THEN 'Austria'
          WHEN 41 THEN 'Tiongkok'
          WHEN 223 THEN 'Thailand'
          WHEN 243 THEN 'Vietnam'
          WHEN 68 THEN 'Filipina'
          WHEN 210 THEN 'Singapura'
          WHEN 146 THEN 'Malaysia'
          WHEN 36 THEN 'Kamboja'
          WHEN 26 THEN 'Myanmar'
          WHEN 170 THEN 'Selandia Baru'
          WHEN 10 THEN 'Arab Saudi'
          WHEN 60 THEN 'Uni Emirat Arab'
          WHEN 141 THEN 'Meksiko'
          WHEN 30 THEN 'Brasil'
          WHEN 11 THEN 'Argentina'
          WHEN 184 THEN 'Qatar'
          WHEN 131 THEN 'Kuwait'
          WHEN 95 THEN 'Iran'
          WHEN 96 THEN 'Irak'
          WHEN 126 THEN 'Yordania'
          WHEN 132 THEN 'Lebanon'
          WHEN 240 THEN 'Uzbekistan'
          WHEN 127 THEN 'Kazakhstan'
          WHEN 14 THEN 'Australia'
          ELSE name
        END
        WHERE name IN (
          'Japón', 'Alemania', 'España', 'Francia', 'Inglaterra', 'Países Bajos',
          'Bélgica', 'Corea del Sur', 'Corea del Norte', 'Estados Unidos', 'Suiza',
          'Suecia', 'Noruega', 'Dinamarca', 'Egipto', 'Marruecos', 'Sudáfrica',
          'Camerún', 'Costa de Marfil', 'República Checa', 'Rusia', 'Turquía',
          'Grecia', 'Hungría', 'Austria', 'China', 'Tailandia', 'Filipinas',
          'Singapur', 'Malasia', 'Camboya', 'Birmania', 'Nueva Zelanda',
          'Arabia Saudita', 'Emiratos Árabes Unidos', 'México', 'Brasil',
          'Argentina', 'Polonia', 'Ucrania', 'Croacia', 'Eslovaquia',
          'Eslovenia', 'Rumanía', 'Escocia', 'Gales', 'Irlanda del Norte'
        )
      ''');
    } catch (_) {}
    await _ensureGlobalSponsors(db);
  }

  /// Seeds real, prestigious global corporate brands into the sponsors table
  /// so that each slot has authentic, diverse partners.
  static Future<void> _ensureGlobalSponsors(Database db) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(t.sponsors);
      final Set<String> existing = rows
          .map(
            (Map<String, Object?> r) =>
                ((r['name'] as String?) ?? '').toLowerCase().trim(),
          )
          .toSet();

      const List<String> globalBrands = <String>[
        // Airlines & Tourism
        'Fly Emirates',
        'Etihad Airways',
        'Qatar Airways',
        'Singapore Airlines',
        'Turkish Airlines',
        'Lufthansa',
        'Visit Rwanda',
        'Visit Saudi',

        // Tech, Digital & Entertainment
        'Spotify',
        'Samsung',
        'Sony PlayStation',
        'Snapdragon',
        'Apple',
        'Google Pixel',
        'Rakuten',
        'Nintendo',
        'Intel',
        'HP',

        // Automotive & Engineering
        'BMW',
        'Mercedes-Benz',
        'Audi',
        'Toyota',
        'Jeep',
        'Pirelli',
        'Hyundai',
        'Chevrolet',

        // Banking, Insurance & Finance
        'Standard Chartered',
        'Allianz',
        'Santander',
        'Barclays',
        'AIA',
        'HSBC',
        'AXA',
        'UBS',

        // Energy & Telecommunications
        'Petronas',
        'Shell',
        'Aramco',
        'Vodafone',
        'T-Mobile',
        'O2',
        'Movistar',

        // Sports, Beverages & Lifestyle
        'Red Bull',
        'Heineken',
        'Pepsi Max',
        'Coca-Cola',
        'Monster Energy',
        'Gatorade',
        'Nike',
        'Adidas',
        'Puma',
        'Hublot',
        'Tag Heuer',
        'Rolex',
      ];

      for (final String brand in globalBrands) {
        if (!existing.contains(brand.toLowerCase().trim())) {
          await db.insert(t.sponsors, <String, Object?>{
            'name': brand,
            'level': 1,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    } catch (_) {}
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
