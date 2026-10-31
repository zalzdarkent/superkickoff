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

    // Season 2025/2026: (2025 + 1) % 4 == 2 -> World Cup Final Year!
    // But now with Option 1:
    // startYear 2024 -> cycleYear 1 (Qualifiers Year)
    // startYear 2025 -> cycleYear 2 (World Cup Finals Year)
    // startYear 2026 -> cycleYear 3 (Asian/Euro Qualifiers Year)
    // startYear 2027 -> cycleYear 0 (Asian/Euro Finals Year)

    // 1. Test Season 1 (2024/2025 or cycleYear 1): World Cup Qualifiers ONLY
    final plan2024 = await gen.generateCareer(
      countryId: countryId,
      league: league,
      cup: null,
      startYear: 2024,
      userTeamId: userTeam.teamId,
    );
    final season2024 = plan2024.season;
    await windowManager.ensureWindowsForSeason(season2024.seasonId, season2024.startYear);

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

    final List<CountryMatch> wcQualifiers = await career.internationalTournaments.matchesForTournament(
      seasonId: season2024.seasonId,
      tournamentId: t.tournamentWorldCupQualifiers,
    );
    expect(wcQualifiers, isEmpty, reason: 'Kualifikasi World Cup sudah dihapus');

    final List<CountryMatch> s1Friendlies = await career.internationalTournaments.matchesForTournament(
      seasonId: season2024.seasonId,
      tournamentId: t.tournamentFriendlies,
    );
    expect(s1Friendlies, isNotEmpty, reason: 'Laga uji coba internasional terjadwal di musim persiapan');
    print('S1 International Friendlies count in 2024/2025: ${s1Friendlies.length}');

    final List<CountryMatch> wcFinalsInQualYear = await career.internationalTournaments.matchesForTournament(
      seasonId: season2024.seasonId,
      tournamentId: t.tournamentWorldCup,
    );
    expect(wcFinalsInQualYear, isEmpty, reason: 'Putaran final World Cup TIDAK BOLEH ada di musim persiapan');

    // Simulate friendlies in season2024
    await career.internationalSimulation.simulatePendingMatchesThroughDate(
      season2024.seasonId,
      '2025-06-30',
    );

    // 2. Test Season 2 (2025/2026): World Cup Finals ONLY (top nations worldwide with balanced pot seeding)
    final plan2025 = await gen.generateCareer(
      countryId: countryId,
      league: league,
      cup: null,
      startYear: 2025,
      userTeamId: userTeam.teamId,
    );
    final season2025 = plan2025.season;
    await windowManager.ensureWindowsForSeason(season2025.seasonId, season2025.startYear);

    final List<CountryMatch> wcQualsInFinalYear = await career.internationalTournaments.matchesForTournament(
      seasonId: season2025.seasonId,
      tournamentId: t.tournamentWorldCupQualifiers,
    );
    expect(wcQualsInFinalYear, isEmpty, reason: 'Kualifikasi World Cup tidak ada');

    final List<CountryMatch> wcFinals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2025.seasonId,
      tournamentId: t.tournamentWorldCup,
    );
    expect(wcFinals, isNotEmpty, reason: 'Putaran Final World Cup harus terjadwal di musim panas tahun final');
    print('World Cup Finals group matches count in 2025/2026: ${wcFinals.length}');

    // Verify group distribution is balanced (pot-based seeding, not all top teams in group 1)
    final Map<int, List<int>> groupCountryMap = <int, List<int>>{};
    for (final CountryMatch m in wcFinals) {
      final int gid = m.groupId ?? 1;
      groupCountryMap.putIfAbsent(gid, () => <int>[]);
      if (!groupCountryMap[gid]!.contains(m.homeCountryId)) groupCountryMap[gid]!.add(m.homeCountryId);
      if (!groupCountryMap[gid]!.contains(m.awayCountryId)) groupCountryMap[gid]!.add(m.awayCountryId);
    }
    expect(groupCountryMap.length, 12, reason: 'World Cup harus memiliki 12 grup');

    // 3. Verify NO domestic club fixtures are scheduled during Summer Tournament Window
    final clashingClubMatches = await db.rawQuery(
      'SELECT count(*) as count FROM matches WHERE season_id = ? AND date >= ? AND date <= ? AND status != ?',
      [season2025.seasonId, '2026-06-11', '2026-07-19', t.matchCancelled],
    );
    final int clubMatchesDuringWorldCup = (clashingClubMatches.first['count'] as int?) ?? 0;
    print('Club matches during World Cup window (2026-06-11 to 2026-07-19): $clubMatchesDuringWorldCup');
    expect(clubMatchesDuringWorldCup, 0, reason: 'Seluruh kompetisi klub harus libur/ditunda selama World Cup');

    // 4. Test Season 3 (2026/2027): International Friendlies & ASEAN tournaments (no Asian/Euro qualifiers)
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
    final List<CountryMatch> asianFinalsInQual = await career.internationalTournaments.matchesForTournament(
      seasonId: season2026.seasonId,
      tournamentId: t.tournamentAsianCup,
    );
    final List<CountryMatch> euroFinalsInQual = await career.internationalTournaments.matchesForTournament(
      seasonId: season2026.seasonId,
      tournamentId: t.tournamentEuro,
    );

    expect(asianQuals, isEmpty, reason: 'Kualifikasi Asian Cup sudah dihapus');
    expect(euroQuals, isEmpty, reason: 'Kualifikasi Euro sudah dihapus');
    expect(asianFinalsInQual, isEmpty, reason: 'Putaran final Asian Cup TIDAK BOLEH ada di musim persiapan');
    expect(euroFinalsInQual, isEmpty, reason: 'Putaran final Euro TIDAK BOLEH ada di musim persiapan');

    // 5. Test Season 4 (2027/2028): Asian Cup & Euro Finals directly take top continental nations
    final plan2027 = await gen.generateCareer(
      countryId: countryId,
      league: league,
      cup: null,
      startYear: 2027,
      userTeamId: userTeam.teamId,
    );
    final season2027 = plan2027.season;

    final List<CountryMatch> asianFinals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2027.seasonId,
      tournamentId: t.tournamentAsianCup,
    );
    final List<CountryMatch> euroFinals = await career.internationalTournaments.matchesForTournament(
      seasonId: season2027.seasonId,
      tournamentId: t.tournamentEuro,
    );
    expect(asianFinals, isNotEmpty, reason: 'Putaran Final Asian Cup harus terjadwal di musim final');
    expect(euroFinals, isNotEmpty, reason: 'Putaran Final EURO harus terjadwal di musim final');
    print('Asian Cup Finals: ${asianFinals.length} matches, EURO Finals: ${euroFinals.length} matches');

    // 6. Test simulating World Cup group matches and auto-advancing to Knockout Phase 1
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

    // Simulate all knockout stages (R32, R16, QF, SF, Final)
    String simDate = '2026-06-28';
    for (int step = 0; step < 6; step++) {
      await career.internationalSimulation.simulatePendingMatchesThroughDate(
        season2025.seasonId,
        simDate,
      );
      await career.internationalTournaments.checkAndAdvanceInternationalKnockouts(
        seasonId: season2025.seasonId,
        currentDate: simDate,
      );
      final DateTime curD = DateTime.parse(simDate);
      simDate = curD.add(const Duration(days: 4)).toIso8601String().substring(0, 10);
    }

    final podium = await career.internationalTournaments.getTournamentPodium(
      tournamentId: t.tournamentWorldCup,
      seasonId: season2025.seasonId,
    );
    expect(podium, isNotNull, reason: 'Turnamen World Cup yang selesai harus menghasilkan podium juara dan runner-up');
    final champ = await career.nationalTeams.getNationalTeam(podium!.championCountryId);
    final runner = await career.nationalTeams.getNationalTeam(podium.runnerUpCountryId);
    print('World Cup 2026 Champion: ${champ?.name}, Runner-Up: ${runner?.name}');

    // Test resolving effective season history when current season is 2026 (season2026.seasonId):
    // In Season 2026/2027, World Cup is not scheduled, so it must resolve to previous season (season2025.seasonId)
    final resolvedSeason = await career.internationalTournaments.resolveEffectiveSeasonId(
      tournamentId: t.tournamentWorldCup,
      currentSeasonId: season2026.seasonId,
    );
    expect(resolvedSeason, season2025.seasonId, reason: 'Di musim baru saat turnamen belum ada jadwal, histori harus menunjuk ke edisi terakhir');
  });
}

