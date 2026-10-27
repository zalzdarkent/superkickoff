import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/competition_config.dart';
import 'package:superkickoff/game/fixture_calendar.dart';
import 'package:superkickoff/game/international_calendar.dart';
import 'package:superkickoff/game/international_simulation_service.dart';
import 'package:superkickoff/game/international_tournament_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/national_team_selection_service.dart';
import 'package:superkickoff/game/national_team_service.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory tempDir;
  late ReferenceRepository refs;
  late NationalTeamService nationalTeams;
  late NationalTeamSelectionService selectionService;
  late InternationalCalendarService calendarService;
  late InternationalTournamentService tournamentService;
  late InternationalSimulationService simulationService;
  late CareerService careerService;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('intl_football_test_');
    final String dbPath = p.join(tempDir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(dbPath);
    db = await databaseFactory.openDatabase(dbPath);
    await AppDatabase.ensureLocalTables(db);

    refs = ReferenceRepository(db);
    final SeasonRepository seasonsRepo = SeasonRepository(db);
    final SquadRepository squadsRepo = SquadRepository(db);
    final MatchRepository matchRepo = MatchRepository(db);
    final MessageRepository messagesRepo = MessageRepository(db);
    final SeasonGenerator generator = SeasonGenerator(db);
    final MatchEngine engine = MatchEngine();
    nationalTeams = NationalTeamService(db);
    selectionService = NationalTeamSelectionService(db);
    calendarService = InternationalCalendarService(db);
    tournamentService = InternationalTournamentService(db);
    simulationService = InternationalSimulationService(db);
    careerService = CareerService(
      db,
      refs: refs,
      seasons: seasonsRepo,
      squads: squadsRepo,
      matches: matchRepo,
      messages: messagesRepo,
      engine: engine,
      generator: generator,
    );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('Phase 14: International Football Test Suite (All 22 Cases)', () {
    // 1. A player is eligible only for configured national teams.
    test('1. Player is eligible only for configured national teams', () async {
      // Find an Indonesian player (countryId 94)
      final List<Map<String, Object?>> rows = await db.query(
        t.players,
        where: 'country_id = 94',
        limit: 1,
      );
      expect(rows, isNotEmpty);
      final Player player = Player.fromMap(rows.first);

      // Primary nationality check
      expect(await nationalTeams.isEligibleForCountry(player.playerId, 94), isTrue);
      expect(await nationalTeams.isEligibleForCountry(player.playerId, 64), isFalse); // Spain

      // Add secondary eligibility for Spain
      await nationalTeams.addSecondaryEligibility(
        playerId: player.playerId,
        countryId: 64,
        reason: 'Ancestry/Residence',
      );
      expect(await nationalTeams.isEligibleForCountry(player.playerId, 64), isTrue);

      // Cap-tie player to Indonesia in a competitive match
      await nationalTeams.lockAllegiance(
        player.playerId,
        94,
        matchId: 101,
        matchType: 'competitive',
      );

      // Now player is permanently cap-tied to Indonesia; Spain is no longer eligible
      expect(await nationalTeams.isEligibleForCountry(player.playerId, 64), isFalse);
      expect(await nationalTeams.isEligibleForCountry(player.playerId, 94), isTrue);
    });

    // 2. A player is not called up solely because their club is in a particular country.
    test('2. Player is not called up solely because their club is in a particular country', () async {
      // Find a player whose country_id != 94
      final List<Map<String, Object?>> rows = await db.query(
        t.players,
        where: 'country_id != 94',
        limit: 1,
      );
      final Player foreignPlayer = Player.fromMap(rows.first);

      // Even if foreignPlayer is playing for an Indonesian club (e.g. club 1)
      final List<int> eligibleCountries =
          await nationalTeams.eligibleCountryIds(foreignPlayer.playerId);

      expect(eligibleCountries, isNot(contains(94)));
      expect(await nationalTeams.isEligibleForCountry(foreignPlayer.playerId, 94), isFalse);
    });

    // 3. National-team squads have valid position coverage (GK>=3, DEF>=7, MID>=6, ATT>=4).
    test('3. National-team squads have valid position coverage', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow window = windows.first;

      final CallupResult result = await selectionService.selectSquad(
        countryId: 94, // Indonesia
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );

      expect(result.squad.length, equals(23));

      final int gks = result.squad.where((p) => NationalTeamSelectionService.positionGroup(p.positionId) == 1).length;
      final int defs = result.squad.where((p) => NationalTeamSelectionService.positionGroup(p.positionId) == 2).length;
      final int mids = result.squad.where((p) => NationalTeamSelectionService.positionGroup(p.positionId) == 3).length;
      final int atts = result.squad.where((p) => NationalTeamSelectionService.positionGroup(p.positionId) == 4).length;

      expect(gks, greaterThanOrEqualTo(3));
      expect(defs, greaterThanOrEqualTo(7));
      expect(mids, greaterThanOrEqualTo(6));
      expect(atts, greaterThanOrEqualTo(4));
      expect(gks + defs + mids + atts, equals(23));
    });

    // 4. Squad size follows the competition configuration.
    test('4. Squad size follows competition configuration', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow window = windows.first;

      // Select with 23
      final CallupResult squad23 = await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
        targetSquadSize: 23,
      );
      expect(squad23.squad.length, equals(23));

      // Clear duties for test
      await db.delete(t.internationalDuty);

      // Select with 26
      final CallupResult squad26 = await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
        targetSquadSize: 26,
      );
      expect(squad26.squad.length, equals(26));
    });

    // 5. The same player is not called up into overlapping fixtures.
    test('5. Same player is not called up into overlapping fixtures', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow window = windows.first;

      final CallupResult result = await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );
      final int playerId = result.squad.first.playerId;

      // Player is now on active duty for this window
      final bool onDuty = await nationalTeams.isPlayerOnDuty(
        playerId,
        window.startDate,
      );
      expect(onDuty, isTrue);

      // Attempting to call up the player for an overlapping window/duty fails
      final bool canCallup = await selectionService.canCallupPlayer(
        playerId,
        window.startDate,
        window.endDate,
      );
      expect(canCallup, isFalse);
    });

    // 6. Mandatory release rules work for configured windows.
    test('6. Mandatory release rules work for configured windows', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow autumn = windows.first;

      expect(autumn.isMandatoryRelease, isTrue);
      expect(autumn.clubFixturesAllowed, isFalse);

      // Date inside release window is marked mandatory
      final bool isMandatory = await calendarService.isMandatoryReleaseDate(
        1,
        autumn.startDate,
      );
      expect(isMandatory, isTrue);

      final List<DateTime> unavailableDates =
          await calendarService.mandatoryUnavailableDates(1);
      expect(unavailableDates, isNotEmpty);
      expect(
        unavailableDates.any((d) => d.toIso8601String().startsWith(autumn.startDate)),
        isTrue,
      );
    });

    // 7. Optional friendlies outside release windows follow configured rules.
    test('7. Optional friendlies outside release windows follow rules', () async {
      // Create an optional, non-mandatory window
      const String customWindowId = 'custom_non_mandatory';
      final InternationalWindow optionalWindow = InternationalWindow(
        windowId: customWindowId,
        seasonId: 1,
        name: 'Invitational Friendly Window',
        windowType: InternationalWindowType.friendly,
        startDate: '2025-08-15',
        endDate: '2025-08-18',
        releaseStartDate: '2025-08-14',
        returnDate: '2025-08-19',
        isMandatoryRelease: false,
        maxMatches: 1,
        clubFixturesAllowed: true,
      );

      await db.insert(t.internationalWindows, optionalWindow.toMap());

      expect(optionalWindow.isMandatoryRelease, isFalse);
      expect(optionalWindow.clubFixturesAllowed, isTrue);

      final bool isMandatory = await calendarService.isMandatoryReleaseDate(
        1,
        '2025-08-16',
      );
      expect(isMandatory, isFalse);
    });

    // 8. A called-up player cannot play an overlapping club match.
    test('8. Called-up player cannot play overlapping club match', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow window = windows.first;

      final CallupResult squadResult = await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );
      final int dutyPlayerId = squadResult.squad.first.playerId;

      // Find player's club from team_players
      final List<Map<String, Object?>> tpRows = await db.query(
        t.teamPlayers,
        where: 'player_id = ?',
        whereArgs: <Object?>[dutyPlayerId],
      );
      final int clubId = tpRows.isNotEmpty ? (tpRows.first['team_id'] as int) : 1;
      if (tpRows.isEmpty) {
        await db.insert(t.teamPlayers, <String, Object?>{
          'team_id': clubId,
          'player_id': dutyPlayerId,
        });
      }

      // Prepare match input for club match on window.startDate
      final FixtureMatch clubMatch = FixtureMatch(
        matchId: 99991,
        seasonId: 1,
        tournamentId: 1,
        round: 1,
        phase: 1,
        status: t.matchScheduled,
        homeTeamId: clubId,
        awayTeamId: clubId == 1 ? 2 : 1,
        stadiumId: 1,
        date: window.startDate,
        homeGoals: null,
        awayGoals: null,
        winnerId: null,
      );
      final MatchInput input = await careerService.prepareMatchInput(clubMatch);

      // Player must NOT be in home squad
      expect(input.homeSquad.any((p) => p.playerId == dutyPlayerId), isFalse);
    });

    // 9. Players return to club availability after their release period.
    test('9. Players return to club availability after release period', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow window = windows.first;

      final CallupResult squadResult = await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );
      final int dutyPlayerId = squadResult.squad.first.playerId;

      // During window, player is on duty
      expect(
        await nationalTeams.isPlayerOnDuty(dutyPlayerId, window.startDate),
        isTrue,
      );

      // Advance date past returnDate
      final DateTime returnDt = DateTime.parse(window.returnDate);
      final String afterReturn =
          returnDt.add(const Duration(days: 2)).toIso8601String().substring(0, 10);

      final int releasedCount = await selectionService.releaseConcludedDuties(
        afterReturn,
      );
      expect(releasedCount, greaterThan(0));

      // After release, player is no longer on active duty
      expect(
        await nationalTeams.isPlayerOnDuty(dutyPlayerId, afterReturn),
        isFalse,
      );
    });

    // 10. International friendlies do not affect club standings.
    test('10. International friendlies do not affect club standings', () async {
      // Record dummy domestic league match
      await db.insert(t.matches, <String, Object?>{
        'match_id': 88881,
        'season_id': 1,
        'tournament_id': 1,
        'home_team_id': 1,
        'away_team_id': 2,
        'home_goals': 2,
        'away_goals': 1,
        'status': t.matchFinished,
        'date': '2025-08-20',
      });

      // Schedule and simulate an international friendly (tournament 900)
      final CountryMatch friendly = CountryMatch(
        matchId: 90001,
        tournamentId: t.tournamentFriendlies,
        seasonId: 1,
        homeCountryId: 94,
        awayCountryId: 64,
        status: t.matchScheduled,
        date: '2025-09-25',
      );
      await db.insert(t.countryMatches, friendly.toMap());

      await simulationService.simulateCountryMatch(
        matchId: 90001,
        homeGoals: 2,
        awayGoals: 1,
      );

      // Verify domestic club matches are untouched
      final List<Map<String, Object?>> clubMatches = await db.query(
        t.matches,
        where: 'season_id = 1 AND tournament_id = 1 AND match_id = 88881',
      );
      expect(clubMatches.first['home_goals'], equals(2));
      expect(clubMatches.first['away_goals'], equals(1));
    });

    // 11. International results update international statistics exactly once.
    test('11. International results update international statistics exactly once', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow window = windows.first;

      final CallupResult squadResult = await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );
      final int testPlayerId = squadResult.squad.first.playerId;

      final CountryMatch match = CountryMatch(
        matchId: 90002,
        tournamentId: t.tournamentFriendlies,
        seasonId: 1,
        homeCountryId: 94,
        awayCountryId: 64,
        status: t.matchScheduled,
        date: '2025-09-26',
      );
      await db.insert(t.countryMatches, match.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

      // Simulate match once
      await simulationService.simulateCountryMatch(
        matchId: 90002,
        homeGoals: 2,
        awayGoals: 0,
      );

      final PlayerNationalStats? stats1 =
          await nationalTeams.getPlayerStats(testPlayerId);
      expect(stats1, isNotNull);
      final int capsAfterOnce = stats1!.caps;
      expect(capsAfterOnce, greaterThanOrEqualTo(1));

      // Attempt second simulation of already finished match
      await simulationService.simulateCountryMatch(
        matchId: 90002,
        homeGoals: 2,
        awayGoals: 0,
      );

      final PlayerNationalStats? stats2 =
          await nationalTeams.getPlayerStats(testPlayerId);
      // Caps must not increase again
      expect(stats2!.caps, equals(capsAfterOnce));
    });

    // 12. Qualification standings and tie-breakers work correctly.
    test('12. Qualification standings and tie-breakers work correctly', () async {
      const int tourId = t.tournamentWorldCup;
      const int groupId = 1;

      // Create 3 simulated matches in group 1
      // Team 94 vs Team 64: 2-1 (94 wins)
      // Team 94 vs Team 35: 1-1 (Draw)
      // Team 64 vs Team 35: 3-0 (64 wins)
      final List<Map<String, Object?>> matches = <Map<String, Object?>>[
        <String, Object?>{
          'match_id': 91001,
          'tournament_id': tourId,
          'season_id': 1,
          'group_id': groupId,
          'home_country_id': 94,
          'away_country_id': 64,
          'home_goals': 2,
          'away_goals': 1,
          'status': t.matchFinished,
          'date': '2025-10-01',
        },
        <String, Object?>{
          'match_id': 91002,
          'tournament_id': tourId,
          'season_id': 1,
          'group_id': groupId,
          'home_country_id': 94,
          'away_country_id': 35,
          'home_goals': 1,
          'away_goals': 1,
          'status': t.matchFinished,
          'date': '2025-10-04',
        },
        <String, Object?>{
          'match_id': 91003,
          'tournament_id': tourId,
          'season_id': 1,
          'group_id': groupId,
          'home_country_id': 64,
          'away_country_id': 35,
          'home_goals': 3,
          'away_goals': 0,
          'status': t.matchFinished,
          'date': '2025-10-07',
        },
      ];

      for (final Map<String, Object?> m in matches) {
        await db.insert(t.countryMatches, m, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final List<InternationalStanding> standings =
          await tournamentService.getStandings(
        seasonId: 1,
        tournamentId: tourId,
        groupId: groupId,
      );

      expect(standings.length, equals(3));
      // Team 94: 4 pts (W1 D1)
      // Team 64: 3 pts (W1 L1)
      // Team 35: 1 pt (D1 L1)
      expect(standings[0].countryId, equals(94));
      expect(standings[0].points, equals(4));
      expect(standings[1].countryId, equals(64));
      expect(standings[1].points, equals(3));
      expect(standings[2].countryId, equals(35));
      expect(standings[2].points, equals(1));
    });

    // 13. Tournament progression follows completed results.
    test('13. Tournament progression follows completed results', () async {
      // Schedule QF round (phase 1) with 4 teams: 94 vs 64, and 35 vs 40
      final List<CountryMatch> r1 = await tournamentService.scheduleKnockoutRound(
        seasonId: 1,
        tournamentId: t.tournamentEuro,
        phase: 1,
        participatingCountryIds: <int>[94, 64, 35, 40],
        matchDate: '2026-06-20',
      );
      expect(r1.length, equals(2));

      // Simulate results:
      // Match 1: 94 beats 64 (3-1)
      // Match 2: 40 beats 35 (2-0)
      await simulationService.simulateCountryMatch(
        matchId: r1[0].matchId,
        homeGoals: 3,
        awayGoals: 1,
      );
      await simulationService.simulateCountryMatch(
        matchId: r1[1].matchId,
        homeGoals: 0,
        awayGoals: 2,
      );

      // Advance to Semifinals (phase 2)
      final List<CountryMatch> r2 = await tournamentService.advanceKnockoutRound(
        seasonId: 1,
        tournamentId: t.tournamentEuro,
        currentPhase: 1,
        nextMatchDate: '2026-06-25',
      );

      expect(r2.length, equals(1));
      // The winners (94 and 40) must be scheduled against each other
      expect(
        (r2.first.homeCountryId == 94 && r2.first.awayCountryId == 40) ||
            (r2.first.homeCountryId == 40 && r2.first.awayCountryId == 94),
        isTrue,
      );
    });

    // 14. Nations League promotion and relegation work when configured.
    test('14. Nations League promotion and relegation work when configured', () async {
      // 2 tiers: League A (div 1) with 4 teams, League B (div 2) with 4 teams
      // Populate mock standings for League A (teams 1, 2, 3, 4) and League B (teams 5, 6, 7, 8)
      final List<InternationalStanding> leagueA = <InternationalStanding>[
        InternationalStanding(countryId: 1, countryName: 'Team 1', points: 10),
        InternationalStanding(countryId: 2, countryName: 'Team 2', points: 7),
        InternationalStanding(countryId: 3, countryName: 'Team 3', points: 4),
        InternationalStanding(countryId: 4, countryName: 'Team 4', points: 1), // Relegated
      ];
      final List<InternationalStanding> leagueB = <InternationalStanding>[
        InternationalStanding(countryId: 5, countryName: 'Team 5', points: 12), // Promoted
        InternationalStanding(countryId: 6, countryName: 'Team 6', points: 8),
        InternationalStanding(countryId: 7, countryName: 'Team 7', points: 4),
        InternationalStanding(countryId: 8, countryName: 'Team 8', points: 2),
      ];

      final Map<int, List<InternationalStanding>> divisions = <int, List<InternationalStanding>>{
        1: leagueA,
        2: leagueB,
      };

      final NationsLeagueMovement movement =
          tournamentService.calculateNationsLeaguePromotionsRelegations(divisions);

      // Team 5 promotes to Div 1
      expect(movement.promotions[2], contains(5));
      // Team 4 relegates to Div 2
      expect(movement.relegations[1], contains(4));
    });

    // 15. EURO, World Cup, Asian Cup, and regional competitions use different formats.
    test('15. EURO, World Cup, Asian Cup, and regional competitions use different formats', () async {
      final CompetitionConfig wcConfig = await CompetitionConfig.forTournamentId(
        db,
        t.tournamentWorldCup,
        seasonStartYear: 2026,
      );
      final CompetitionConfig euroConfig = await CompetitionConfig.forTournamentId(
        db,
        t.tournamentEuro,
        seasonStartYear: 2026,
      );
      final CompetitionConfig asianCupConfig = await CompetitionConfig.forTournamentId(
        db,
        t.tournamentAsianCup,
        seasonStartYear: 2026,
      );
      final CompetitionConfig nlConfig = await CompetitionConfig.forTournamentId(
        db,
        t.tournamentNationsLeague,
        seasonStartYear: 2026,
      );

      // World Cup: 48 teams
      expect(wcConfig.fieldSize, equals(48));
      expect(wcConfig.groupCount, equals(12));

      // EURO: 24 teams
      expect(euroConfig.fieldSize, equals(24));
      expect(euroConfig.groupCount, equals(6));

      // Asian Cup: 24 teams
      expect(asianCupConfig.fieldSize, equals(24));
      expect(asianCupConfig.groupCount, equals(6));

      // Nations League: Multi-tier league system
      expect(nlConfig.type, equals(CompetitionType.international));
      expect(nlConfig.doubleRoundRobin, isTrue);
    });

    // 16. ASEAN Championship and FIFA ASEAN Cup remain separate competitions.
    test('16. ASEAN Championship and FIFA ASEAN Cup remain separate competitions', () async {
      expect(t.tournamentAseanChampionship, isNot(equals(t.tournamentFifaAseanCup)));

      final CompetitionConfig aseanChamp = await CompetitionConfig.forTournamentId(
        db,
        t.tournamentAseanChampionship,
        seasonStartYear: 2026,
      );
      final CompetitionConfig fifaAseanCup = await CompetitionConfig.forTournamentId(
        db,
        t.tournamentFifaAseanCup,
        seasonStartYear: 2026,
      );

      expect(aseanChamp.tournamentId, equals(902));
      expect(fifaAseanCup.tournamentId, equals(903));

      // Different field sizes and configurations
      expect(aseanChamp.fieldSize, equals(10));
      expect(fifaAseanCup.fieldSize, equals(14));
      expect(aseanChamp.name, isNot(equals(fifaAseanCup.name)));
    });

    // 17. Postponements preserve fixture identity and results.
    test('17. Postponements preserve fixture identity and results', () async {
      final CountryMatch match = CountryMatch(
        matchId: 92001,
        tournamentId: t.tournamentFriendlies,
        seasonId: 1,
        homeCountryId: 94,
        awayCountryId: 64,
        status: t.matchScheduled,
        date: '2025-09-22',
      );
      await db.insert(t.countryMatches, match.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

      // Postpone match to new date
      await tournamentService.postponeCountryMatch(
        matchId: 92001,
        newDate: '2025-09-29',
        reason: 'Inclement weather',
      );

      final List<Map<String, Object?>> rows = await db.query(
        t.countryMatches,
        where: 'match_id = 92001',
      );
      expect(rows.length, equals(1));
      expect(rows.first['date'], equals('2025-09-29'));
      expect(rows.first['original_date'], equals('2025-09-22'));
      expect(rows.first['reschedule_reason'], equals('Inclement weather'));
      expect(rows.first['match_id'], equals(92001)); // ID preserved
    });

    // 18. Calendar conflicts are detected and reported.
    test('18. Calendar conflicts are detected and reported', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow autumn = windows.first;

      // Insert domestic match directly inside the autumn mandatory window
      await db.insert(t.matches, <String, Object?>{
        'match_id': 88001,
        'tournament_id': 1,
        'season_id': 1,
        'home_team_id': 1,
        'away_team_id': 2,
        'date': autumn.startDate,
        'status': t.matchScheduled,
        'phase': 1,
        'round': 5,
        'leg': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final FixtureSchedulingService scheduler = FixtureSchedulingService(db);
      // Run clash resolver
      final int resolved = await scheduler.resolveFixtureClashes(1);
      expect(resolved, greaterThanOrEqualTo(1));

      // Verify the match was moved away from the mandatory window date
      final List<Map<String, Object?>> updated = await db.query(
        t.matches,
        where: 'match_id = 88001',
      );
      expect(updated.first['date'], isNot(equals(autumn.startDate)));
    });

    // 19. Reloading a save does not duplicate call-ups, fixtures, or player statistics.
    test('19. Reloading a save does not duplicate call-ups, fixtures, or player statistics', () async {
      // Run window generation twice
      await calendarService.generateWindowsForSeason(1, 2025);
      final List<InternationalWindow> firstRun =
          await calendarService.windowsForSeason(1);

      await calendarService.generateWindowsForSeason(1, 2025);
      final List<InternationalWindow> secondRun =
          await calendarService.windowsForSeason(1);

      expect(secondRun.length, equals(firstRun.length));

      // Run squad call-ups twice
      final InternationalWindow window = firstRun.first;
      await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );
      final List<Map<String, Object?>> callups1 = await db.query(
        t.countryCallups,
        where: 'country_id = 94',
      );

      await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );
      final List<Map<String, Object?>> callups2 = await db.query(
        t.countryCallups,
        where: 'country_id = 94',
      );

      expect(callups2.length, equals(callups1.length));
    });

    // 20. Existing saves remain loadable after database migration.
    test('20. Existing saves remain loadable after database migration', () async {
      // Call ensureLocalTables multiple times to simulate app restarts / save loading
      await AppDatabase.ensureLocalTables(db);
      await AppDatabase.ensureLocalTables(db);

      // Verify essential tables and tournament rows exist without error
      final List<Map<String, Object?>> tournaments = await db.query(
        t.tournaments,
        where: 'tournament_id IN (900, 901, 902, 903)',
      );
      expect(tournaments.length, equals(4));

      // Verify existing players and teams are intact
      final List<Map<String, Object?>> players = await db.query(t.players, limit: 10);
      expect(players.length, equals(10));
    });

    // 21. International duty affects player availability and fatigue without double application.
    test('21. International duty affects player availability and fatigue without double application', () async {
      final List<InternationalWindow> windows =
          await calendarService.generateWindowsForSeason(1, 2025);
      final InternationalWindow window = windows.first;

      final CallupResult squadResult = await selectionService.selectSquad(
        countryId: 94,
        seasonId: 1,
        window: window,
        tournamentId: t.tournamentFriendlies,
      );
      final int playerId = squadResult.squad.first.playerId;

      final List<Map<String, Object?>> pRows = await db.query(
        t.players,
        where: 'player_id = ?',
        whereArgs: <Object?>[playerId],
      );
      final int initialFitness = pRows.first['fitness'] as int;

      final CountryMatch match = CountryMatch(
        matchId: 93001,
        tournamentId: t.tournamentFriendlies,
        seasonId: 1,
        homeCountryId: 94,
        awayCountryId: 64,
        status: t.matchScheduled,
        date: window.startDate,
      );
      await db.insert(t.countryMatches, match.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

      // Simulate match once
      await simulationService.simulateCountryMatch(
        matchId: 93001,
        homeGoals: 1,
        awayGoals: 0,
      );

      final List<Map<String, Object?>> afterRows1 = await db.query(
        t.players,
        where: 'player_id = ?',
        whereArgs: <Object?>[playerId],
      );
      final int fitnessAfter1 = afterRows1.first['fitness'] as int;
      expect(fitnessAfter1, lessThanOrEqualTo(initialFitness));

      // Re-running simulation on already finished match does not re-reduce fitness
      await simulationService.simulateCountryMatch(
        matchId: 93001,
        homeGoals: 1,
        awayGoals: 0,
      );

      final List<Map<String, Object?>> afterRows2 = await db.query(
        t.players,
        where: 'player_id = ?',
        whereArgs: <Object?>[playerId],
      );
      expect(afterRows2.first['fitness'], equals(fitnessAfter1));
    });

    // 22. Edition-specific competition formats can change without modifying core scheduling code.
    test('22. Edition-specific competition formats can change without modifying core scheduling code', () async {
      // Verify a tournament can be configured with 16 teams (4 groups of 4)
      final CompetitionConfig config16 = CompetitionConfig(
        tournamentId: 999,
        name: 'Configurable Cup 2026',
        type: CompetitionType.international,
        format: CompetitionFormat.groupStage,
        fieldSize: 16,
        groupCount: 4,
        groupSize: 4,
        seasonStartYear: 2026,
      );

      // Verify the generic scheduling engine schedules 4 groups of 4 without custom code
      final List<int> teams = List<int>.generate(16, (i) => i + 1);
      final List<CountryMatch> fixtures = await tournamentService.scheduleGroupStage(
        seasonId: 1,
        tournamentId: config16.tournamentId,
        participatingCountryIds: teams,
        groupSize: config16.groupSize,
        groupCount: config16.groupCount,
        startDate: '2026-06-01',
      );

      expect(fixtures, isNotEmpty);
      final Set<int?> groups = fixtures.map((m) => m.groupId).toSet();
      expect(groups.length, equals(4)); // 4 distinct groups
    });
  });
}
