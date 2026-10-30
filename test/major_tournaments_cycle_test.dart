import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/data/repositories/transfer_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';
import 'package:superkickoff/game/transfer_window_manager.dart';

void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_major_tournaments_');
    final File target = File(p.join(tempDir.path, 'test.db'));
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(target.path);
    db = await databaseFactory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await AppDatabase.ensureLocalTables(db);
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('Major tournaments and qualifiers cycle schedules properly and halts club fixtures during World Cup', () async {
    const int countryId = 71; // Indonesia
    final refs = ReferenceRepository(db);
    final seasons = SeasonRepository(db);
    final squads = SquadRepository(db);
    final transfers = TransferRepository(db);
    final windowManager = TransferWindowManager(db);

    final tourRow = await db.rawQuery(
      'SELECT tu.* FROM tournaments tu JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id '
      'WHERE tu.organization = ? AND tc.country_id = ? AND tu.division_id = 1 LIMIT 1',
      [t.orgLeague, countryId],
    );
    final league = Tournament.fromMap(tourRow.first);
    final teams = await refs.teamsForDivision(countryId, 1);
    final userTeam = teams.first;

    final gen = SeasonGenerator(db, random: Random(42));

    // Season 2025/2026: (2025 + 1) % 4 == 2 -> World Cup Year!
    final plan2025 = await gen.generateCareer(
      countryId: countryId,
      league: league,
      cup: null,
      startYear: 2025,
      userTeamId: userTeam.teamId,
    );
    final season2025 = plan2025.season;
    await windowManager.ensureWindowsForSeason(season2025.seasonId, season2025.startYear);

    final career = CareerService(
      db,
      refs: refs,
      seasons: seasons,
      squads: squads,
      matches: MatchRepository(db),
      messages: MessageRepository(db),
      engine: MatchEngine(random: Random(42)),
      generator: gen,
      transfers: transfers,
      random: Random(42),
    );

    // 1. Verify World Cup Qualifiers scheduled for 2025/2026
    final List<CountryMatch> wcQualifiers = await career.internationalTournaments.matchesForTournament(
      seasonId: season2025.seasonId,
      tournamentId: t.tournamentWorldCupQualifiers,
    );
    expect(wcQualifiers, isNotEmpty, reason: 'Kualifikasi World Cup harus terjadwal');
    print('World Cup Qualifiers fixtures count: ${wcQualifiers.length}');

    // 2. Verify World Cup Finals scheduled for Summer 2026 (48 teams in 12 groups = 72 group matches)
    final List<CountryMatch> wcFinals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2025.seasonId,
      tournamentId: t.tournamentWorldCup,
    );
    expect(wcFinals, isNotEmpty, reason: 'Putaran Final World Cup harus terjadwal di musim panas');
    print('World Cup Finals group matches count: ${wcFinals.length}');

    // 3. Verify NO domestic club fixtures are scheduled during Summer Tournament Window
    final summerWindow = (await windowManager.windowsForCountry(season2025.seasonId, countryId))
        .firstWhere((w) => w.windowType == 'summer', orElse: () => throw StateError('No summer window'));
    
    final clashingClubMatches = await db.rawQuery(
      'SELECT count(*) as count FROM matches WHERE season_id = ? AND date >= ? AND date <= ? AND status != ?',
      [season2025.seasonId, '2026-06-11', '2026-07-19', t.matchCancelled],
    );
    final int clubMatchesDuringWorldCup = (clashingClubMatches.first['count'] as int?) ?? 0;
    print('Club matches during World Cup window (2026-06-11 to 2026-07-19): $clubMatchesDuringWorldCup');
    expect(clubMatchesDuringWorldCup, 0, reason: 'Seluruh kompetisi klub harus libur/ditunda selama World Cup');

    // 4. Test Season 2026/2027: (2026 + 1) % 4 == 3 -> Asian Cup & Euro Year!
    final plan2026 = await gen.generateCareer(
      countryId: countryId,
      league: league,
      cup: null,
      startYear: 2026,
      userTeamId: userTeam.teamId,
    );
    final season2026 = plan2026.season;

    final List<CountryMatch> asianQuals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2026.seasonId,
      tournamentId: t.tournamentAsianCupQualifiers,
    );
    final List<CountryMatch> euroQuals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2026.seasonId,
      tournamentId: t.tournamentEuroQualifiers,
    );
    final List<CountryMatch> asianFinals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2026.seasonId,
      tournamentId: t.tournamentAsianCup,
    );
    final List<CountryMatch> euroFinals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2026.seasonId,
      tournamentId: t.tournamentEuro,
    );

    expect(asianQuals, isNotEmpty, reason: 'Kualifikasi Asian Cup harus terjadwal');
    expect(euroQuals, isNotEmpty, reason: 'Kualifikasi Euro harus terjadwal');
    expect(asianFinals, isNotEmpty, reason: 'Putaran Final Asian Cup harus terjadwal');
    expect(euroFinals, isNotEmpty, reason: 'Putaran Final EURO harus terjadwal');
    print('Asian Cup: ${asianFinals.length} matches, EURO: ${euroFinals.length} matches');

    // 5. Test simulating World Cup group matches and auto-advancing to Knockout Phase 1
    final int simulated = await career.internationalSimulation.simulatePendingMatchesThroughDate(
      season2025.seasonId,
      '2026-06-25',
    );
    print('Simulated country matches through group stage: $simulated');

    await career.internationalTournaments.checkAndAdvanceInternationalKnockouts(
      seasonId: season2025.seasonId,
      currentDate: '2026-06-25',
    );

    final List<CountryMatch> wcKnockout = (await career.internationalTournaments.matchesForTournament(
      seasonId: season2025.seasonId,
      tournamentId: t.tournamentWorldCup,
    )).where((m) => m.phase > 0).toList();

    expect(wcKnockout, isNotEmpty, reason: 'Babak gugur (Knockout) World Cup harus otomatis terbentuk setelah fase grup selesai');
    print('World Cup Knockout round 1 matches scheduled: ${wcKnockout.length}');
  });
}

