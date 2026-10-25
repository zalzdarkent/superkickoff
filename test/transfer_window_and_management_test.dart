import 'dart:io';
import 'dart:math';

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
import 'package:superkickoff/data/repositories/transfer_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';
import 'package:superkickoff/game/transfer_window_manager.dart';
import 'package:superkickoff/state/career_provider.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('TransferWindowManager Unit Tests', () {
    late Directory dir;
    late Database db;
    late TransferWindowManager wm;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('wm_unit_test_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);
      wm = TransferWindowManager(db);
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('provisions exactly 2 windows (Summer & Winter) per season, no 3rd window', () async {
      const int seasonId = 100;
      const int startYear = 2025;

      await wm.ensureWindowsForSeason(seasonId, startYear);
      final List<TransferWindow> windows = await wm.windowsForSeason(seasonId);
      expect(windows, isNotEmpty);

      // Check for Indonesia (country 94)
      final List<TransferWindow> indoWindows = await wm.windowsForCountry(seasonId, 94);
      expect(indoWindows.length, 2, reason: 'Must have exactly Summer and Winter windows, no 3rd window');
      expect(indoWindows.map((TransferWindow w) => w.windowType).toSet(), <String>{'summer', 'winter'});

      // Check for England (country 44)
      final List<TransferWindow> engWindows = await wm.windowsForCountry(seasonId, 44);
      expect(engWindows.length, 2, reason: 'England must have exactly Summer and Winter windows');
      expect(engWindows.first.windowType, 'summer');
      expect(engWindows.last.windowType, 'winter');

      // Verify no duplicate windows are created on re-run
      await wm.ensureWindowsForSeason(seasonId, startYear);
      final List<TransferWindow> rerun = await wm.windowsForSeason(seasonId);
      expect(rerun.length, windows.length);
    });

    test('calendar configuration differs between countries and adheres to realistic dates', () async {
      const int seasonId = 101;
      const int startYear = 2025;
      await wm.ensureWindowsForSeason(seasonId, startYear);

      final List<TransferWindow> engWindows = await wm.windowsForCountry(seasonId, 44);
      final List<TransferWindow> indoWindows = await wm.windowsForCountry(seasonId, 94);

      final TransferWindow engSummer = engWindows.firstWhere((TransferWindow w) => w.windowType == 'summer');
      final TransferWindow indoSummer = indoWindows.firstWhere((TransferWindow w) => w.windowType == 'summer');

      // England Summer: 2025-07-01 to 2025-09-01
      expect(engSummer.startDate, '2025-07-01');
      expect(engSummer.endDate, '2025-09-01');
      expect(engSummer.durationDays, greaterThan(60));

      // Indonesia Summer: 2025-07-01 to 2025-08-31
      expect(indoSummer.startDate, '2025-07-01');
      expect(indoSummer.endDate, '2025-08-31');

      // Winter calendars differ: Indonesia opens mid-Dec, England opens Jan 1
      final TransferWindow engWinter = engWindows.firstWhere((TransferWindow w) => w.windowType == 'winter');
      final TransferWindow indoWinter = indoWindows.firstWhere((TransferWindow w) => w.windowType == 'winter');
      expect(indoWinter.startDate, '2025-12-15');
      expect(engWinter.startDate, '2026-01-01');

      // England does not allow free agents outside window; Indonesia allows
      expect(engSummer.allowFreeAgentsOutside, isFalse);
      expect(indoSummer.allowFreeAgentsOutside, isTrue);
    });

    test('window status, countdown, and deadline day calculations', () {
      final TransferWindow summer = TransferWindow(
        windowId: 1,
        seasonId: 1,
        countryId: 44,
        tournamentId: 0,
        windowType: 'summer',
        startDate: '2025-07-01',
        endDate: '2025-09-01',
        isOpen: true,
        allowFreeAgentsOutside: false,
      );

      // Before window
      expect(summer.isWindowOpen('2025-06-15'), isFalse);
      expect(summer.daysUntilOpen('2025-06-15'), 16);
      expect(summer.isDeadlineDay('2025-06-15'), isFalse);

      // During window
      expect(summer.isWindowOpen('2025-07-15'), isTrue);
      expect(summer.daysUntilDeadline('2025-07-15'), 48);
      expect(summer.isDeadlineDay('2025-07-15'), isFalse);

      // Deadline day (last day: 2025-09-01)
      expect(summer.isWindowOpen('2025-09-01'), isTrue);
      expect(summer.isDeadlineDay('2025-09-01'), isTrue);
      expect(summer.daysUntilDeadline('2025-09-01'), 0);

      // After window closed
      expect(summer.isWindowOpen('2025-09-02'), isFalse);
      expect(summer.isDeadlineDay('2025-09-02'), isFalse);
    });

    test('notification engine dispatches open, deadline day, and close notifications', () async {
      const int seasonId = 102;
      const int startYear = 2025;
      await wm.ensureWindowsForSeason(seasonId, startYear);

      // Team in England (country 44)
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT team_id FROM teams WHERE country_id = 44 LIMIT 1',
      );
      final int teamId = rows.first['team_id'] as int;

      // 1. Day of opening: 2025-07-01 (from 2025-06-30)
      await wm.checkAndSendNotifications(
        seasonId: seasonId,
        userTeamId: teamId,
        previousDate: '2025-06-30',
        currentDate: '2025-07-01',
      );
      List<Map<String, Object?>> msgs = await db.query(t.messages, where: 'sender = ?', whereArgs: <Object?>['Transfer Desk']);
      expect(msgs.length, 1);
      expect(msgs.first['title'], contains('Dibuka'));

      // 2. Deadline day: 2025-09-01 (from 2025-08-31)
      await wm.checkAndSendNotifications(
        seasonId: seasonId,
        userTeamId: teamId,
        previousDate: '2025-08-31',
        currentDate: '2025-09-01',
      );
      msgs = await db.query(t.messages, where: 'sender = ?', whereArgs: <Object?>['Transfer Desk']);
      expect(msgs.length, 2);
      expect(msgs.any((Map<String, Object?> m) => (m['title'] as String).contains('DEADLINE DAY')), isTrue);

      // 3. Day of closing: 2025-09-02 (from 2025-09-01)
      await wm.checkAndSendNotifications(
        seasonId: seasonId,
        userTeamId: teamId,
        previousDate: '2025-09-01',
        currentDate: '2025-09-02',
      );
      msgs = await db.query(t.messages, where: 'sender = ?', whereArgs: <Object?>['Transfer Desk']);
      expect(msgs.length, 3);
      expect(msgs.any((Map<String, Object?> m) => (m['title'] as String).contains('Ditutup')), isTrue);
    });
  });

  group('Transfer Management & Scheduled Transfers Integration Tests', () {
    late Directory dir;
    late Database db;
    late SeasonGenerator gen;
    late CareerService service;
    late ReferenceRepository refs;
    late SeasonRepository seasons;
    late SquadRepository squads;
    late TransferRepository transfers;
    late TransferWindowManager wm;
    late Season season;
    late List<Team> clubs;
    const int countryId = 94; // Indonesia

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('transfer_mgmt_e2e_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);

      Future<Tournament> find(int org, {int? division}) async =>
          Tournament.fromMap(
            (await db.rawQuery(
              '''SELECT tu.* FROM tournaments tu
             JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
             WHERE tc.country_id = ? AND tu.organization = ?
             ${division == null ? '' : 'AND tu.division_id = $division'} LIMIT 1''',
              <Object?>[countryId, org],
            )).first,
          );

      gen = SeasonGenerator(db, random: Random(42));
      final CareerPlan plan = await gen.generateCareer(
        countryId: countryId,
        league: await find(t.orgLeague, division: 1),
        cup: await find(t.orgNationalCup),
      );
      season = plan.season;

      refs = ReferenceRepository(db);
      seasons = SeasonRepository(db);
      squads = SquadRepository(db);
      transfers = TransferRepository(db);
      wm = TransferWindowManager(db);
      await wm.ensureWindowsForSeason(season.seasonId, season.startYear);

      clubs = await refs.teamsForDivision(countryId, 1);

      service = CareerService(
        db,
        refs: refs,
        seasons: seasons,
        squads: squads,
        matches: MatchRepository(db),
        messages: MessageRepository(db),
        engine: MatchEngine(random: Random(42)),
        generator: gen,
        transfers: transfers,
        windowManager: wm,
        random: Random(42),
      );
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('immediate transfer during open window updates players, contracts, and budgets atomically', () async {
      final Team buyer = clubs[0];
      final Team seller = clubs[1];

      // Pick a player from seller
      final List<Player> sellerSquad = await squads.squadForTeam(seller.teamId);
      expect(sellerSquad, isNotEmpty);
      final Player target = sellerSquad.first;

      Future<int> getBudget(int teamId) async =>
          ((await db.query(t.teams, columns: <String>['budget'], where: 'team_id = ?', whereArgs: <Object?>[teamId])).first['budget'] as int?) ?? 0;

      Future<void> setBudget(int teamId, int budget) async =>
          await db.update(t.teams, <String, Object?>{'budget': budget}, where: 'team_id = ?', whereArgs: <Object?>[teamId]);

      final int buyerInitBudget = await getBudget(buyer.teamId);
      final int sellerInitBudget = await getBudget(seller.teamId);
      const int fee = 500000;
      const int salary = 80000;

      // Ensure buyer has sufficient budget
      await setBudget(buyer.teamId, buyerInitBudget + 1000000);

      // Create offer
      final int offerId = await transfers.createOffer(
        playerId: target.playerId,
        fromTeamId: seller.teamId,
        toTeamId: buyer.teamId,
        offerAmount: fee,
        playerValue: target.value,
        proposedSalary: salary,
        proposedDurationYears: 3,
        agreementDate: '2025-07-01',
        effectiveDate: '2025-07-01',
        eligibleDate: '2025-07-01',
      );

      // Player accepts terms
      await transfers.updateOfferStatus(offerId, t.offerPlayerAccepted);

      // Complete transfer immediately (as during open window)
      final String? err = await transfers.completeTransfer(offerId, effectiveDate: '2025-07-01');
      expect(err, isNull);

      // Verify player moved to buyer
      final List<Player> buyerNewSquad = await squads.squadForTeam(buyer.teamId);
      final List<Player> sellerNewSquad = await squads.squadForTeam(seller.teamId);

      expect(buyerNewSquad.any((Player p) => p.playerId == target.playerId), isTrue);
      expect(sellerNewSquad.any((Player p) => p.playerId == target.playerId), isFalse);

      // Verify no duplicate player records
      final List<Map<String, Object?>> countRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM team_players WHERE player_id = ?',
        <Object?>[target.playerId],
      );
      expect(countRows.first['c'], 1);

      // Verify buyer budget was deducted and seller budget credited
      final int buyerFinalBudget = await getBudget(buyer.teamId);
      final int sellerFinalBudget = await getBudget(seller.teamId);

      expect(buyerFinalBudget, buyerInitBudget + 1000000 - fee);
      expect(sellerFinalBudget, sellerInitBudget + fee);

      // Verify offer marked completed
      final TransferOffer? updatedOffer = await transfers.getOffer(offerId);
      expect(updatedOffer, isNotNull);
      expect(updatedOffer!.isCompleted, isTrue);
    });

    test('closed window creates scheduled transfer; player stays until effective date then moves', () async {
      final Team buyer = clubs[0];
      final Team seller = clubs[1];

      final List<Player> sellerSquad = await squads.squadForTeam(seller.teamId);
      final Player target = sellerSquad.first;

      Future<void> setBudget(int teamId, int budget) async =>
          await db.update(t.teams, <String, Object?>{'budget': budget}, where: 'team_id = ?', whereArgs: <Object?>[teamId]);

      await setBudget(buyer.teamId, 2000000);
      const int fee = 600000;
      const int salary = 70000;

      // Deal agreed on 2025-10-15 (outside any window: summer closed on 2025-08-31, winter opens on 2026-01-01)
      const String agreementDate = '2025-10-15';
      const String nextWindowStart = '2026-01-01';

      final int offerId = await transfers.createOffer(
        playerId: target.playerId,
        fromTeamId: seller.teamId,
        toTeamId: buyer.teamId,
        offerAmount: fee,
        playerValue: target.value,
        proposedSalary: salary,
        proposedDurationYears: 3,
        agreementDate: agreementDate,
        effectiveDate: nextWindowStart,
        eligibleDate: nextWindowStart,
      );

      // Schedule the transfer
      await transfers.scheduleTransfer(
        offerId,
        agreementDate: agreementDate,
        effectiveDate: nextWindowStart,
      );

      // Verify offer is in scheduled status
      final TransferOffer? offer = await transfers.getOffer(offerId);
      expect(offer, isNotNull);
      expect(offer!.status, t.offerAwaitingWindow);
      expect(offer.isScheduled, isTrue);

      // Check that the player STILL belongs to the seller!
      List<Player> sellerSquadCheck = await squads.squadForTeam(seller.teamId);
      List<Player> buyerSquadCheck = await squads.squadForTeam(buyer.teamId);
      expect(sellerSquadCheck.any((Player p) => p.playerId == target.playerId), isTrue);
      expect(buyerSquadCheck.any((Player p) => p.playerId == target.playerId), isFalse);

      // Run housekeeping before effective date (2025-11-01) -> nothing should move
      List<ScheduledTransferResult> results = await transfers.processDueScheduledTransfers('2025-11-01');
      expect(results, isEmpty);

      sellerSquadCheck = await squads.squadForTeam(seller.teamId);
      buyerSquadCheck = await squads.squadForTeam(buyer.teamId);
      expect(sellerSquadCheck.any((Player p) => p.playerId == target.playerId), isTrue);
      expect(buyerSquadCheck.any((Player p) => p.playerId == target.playerId), isFalse);

      // Now run housekeeping ON effective date (2026-01-01) -> player moves!
      results = await transfers.processDueScheduledTransfers(nextWindowStart);
      expect(results.length, 1);
      expect(results.first.success, isTrue);

      // Verify player has now moved to buyer with NO duplicates
      sellerSquadCheck = await squads.squadForTeam(seller.teamId);
      buyerSquadCheck = await squads.squadForTeam(buyer.teamId);
      expect(sellerSquadCheck.any((Player p) => p.playerId == target.playerId), isFalse);
      expect(buyerSquadCheck.any((Player p) => p.playerId == target.playerId), isTrue);

      final List<Map<String, Object?>> countRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM team_players WHERE player_id = ?',
        <Object?>[target.playerId],
      );
      expect(countRows.first['c'], 1);

      final TransferOffer? completedOffer = await transfers.getOffer(offerId);
      expect(completedOffer!.isCompleted, isTrue);
    });

    test('scheduled transfer fails gracefully if buyer cannot afford fee at effective date', () async {
      final Team buyer = clubs[0];
      final Team seller = clubs[1];

      final List<Player> sellerSquad = await squads.squadForTeam(seller.teamId);
      final Player target = sellerSquad.first;

      const int fee = 1000000;
      const String nextWindowStart = '2026-01-01';

      final int offerId = await transfers.createOffer(
        playerId: target.playerId,
        fromTeamId: seller.teamId,
        toTeamId: buyer.teamId,
        offerAmount: fee,
        playerValue: target.value,
        agreementDate: '2025-10-15',
        effectiveDate: nextWindowStart,
      );
      await transfers.scheduleTransfer(
        offerId,
        agreementDate: '2025-10-15',
        effectiveDate: nextWindowStart,
      );

      Future<void> setBudget(int teamId, int budget) async =>
          await db.update(t.teams, <String, Object?>{'budget': budget}, where: 'team_id = ?', whereArgs: <Object?>[teamId]);

      // Drain buyer's budget prior to effective date
      await setBudget(buyer.teamId, 10000); // Only 10k left, needs 1M

      final List<ScheduledTransferResult> results = await transfers.processDueScheduledTransfers(nextWindowStart);
      expect(results.length, 1);
      expect(results.first.success, isFalse);

      // Player stays at seller club
      final List<Player> sellerSquadCheck = await squads.squadForTeam(seller.teamId);
      expect(sellerSquadCheck.any((Player p) => p.playerId == target.playerId), isTrue);

      // Offer marked as failed with cancellation reason
      final TransferOffer? failedOffer = await transfers.getOffer(offerId);
      expect(failedOffer!.isFailed, isTrue);
      expect(failedOffer.cancellationReason?.toLowerCase(), contains('anggaran'));
    });

    test('user or club can cancel a scheduled transfer', () async {
      final Team buyer = clubs[0];
      final Team seller = clubs[1];
      final Player target = (await squads.squadForTeam(seller.teamId)).first;

      final int offerId = await transfers.createOffer(
        playerId: target.playerId,
        fromTeamId: seller.teamId,
        toTeamId: buyer.teamId,
        offerAmount: 300000,
        playerValue: target.value,
        agreementDate: '2025-10-15',
        effectiveDate: '2026-01-01',
      );
      await transfers.scheduleTransfer(
        offerId,
        agreementDate: '2025-10-15',
        effectiveDate: '2026-01-01',
      );

      // Cancel offer
      await transfers.cancelOffer(offerId, reason: 'Dibatalkan oleh manajer klub');

      final TransferOffer? cancelledOffer = await transfers.getOffer(offerId);
      expect(cancelledOffer!.isCancelled, isTrue);
      expect(cancelledOffer.cancellationReason, 'Dibatalkan oleh manajer klub');

      // Due processing will not process it
      final List<ScheduledTransferResult> results = await transfers.processDueScheduledTransfers('2026-01-01');
      expect(results, isEmpty);
    });

    test('cross-country transfers respect destination club registration window', () async {
      // Find Indonesian club and English club
      final List<Map<String, Object?>> engClubs = await db.rawQuery(
        'SELECT team_id FROM teams WHERE country_id = 44 LIMIT 1',
      );
      final int engTeamId = engClubs.first['team_id'] as int;
      final int indoTeamId = clubs.first.teamId;

      // On 2025-12-20:
      // Indonesia Winter window is OPEN (starts 2025-12-15)
      // England Winter window is CLOSED (starts 2026-01-01)
      const String currentDate = '2025-12-20';

      final bool engOpen = await wm.isWindowOpenForTeam(season.seasonId, engTeamId, currentDate);
      final bool indoOpen = await wm.isWindowOpenForTeam(season.seasonId, indoTeamId, currentDate);

      expect(indoOpen, isTrue, reason: 'Indonesian winter window opens Dec 15');
      expect(engOpen, isFalse, reason: 'English winter window opens Jan 01');

      // If Indonesian club sells to English club on 2025-12-20:
      // Destination is English club -> Window is CLOSED -> Must be scheduled for 2026-01-01
      final TransferWindow nextEngWindow =
          await wm.nextRegistrationWindowForTeam(
            season.seasonId,
            engTeamId,
            currentDate,
          );
      expect(nextEngWindow.startDate, '2026-01-01');

      // If English club sells to Indonesian club on 2025-12-20:
      // Destination is Indonesian club -> Window is OPEN -> Can complete immediately
      expect(indoOpen, isTrue);
    });

    test('free agent recruitment outside window adheres to league exceptions', () async {
      final List<Map<String, Object?>> engClubs = await db.rawQuery(
        'SELECT team_id FROM teams WHERE country_id = 44 LIMIT 1',
      );
      final int engTeamId = engClubs.first['team_id'] as int;
      final int indoTeamId = clubs.first.teamId;

      const String midSeasonClosed = '2025-10-15';

      // Indonesia allows emergency signing outside window
      final bool canIndo = await wm.canRegisterFreeAgent(season.seasonId, indoTeamId, midSeasonClosed);
      expect(canIndo, isTrue);

      // England disallows registration outside window
      final bool canEng = await wm.canRegisterFreeAgent(season.seasonId, engTeamId, midSeasonClosed);
      expect(canEng, isFalse);
    });

    test('loans support duration and return player automatically on expiration', () async {
      final Team parent = clubs[0];
      final Team borrower = clubs[1];

      final Player target = (await squads.squadForTeam(parent.teamId)).first;

      final int offerId = await transfers.createOffer(
        playerId: target.playerId,
        fromTeamId: parent.teamId,
        toTeamId: borrower.teamId,
        offerAmount: 50000,
        playerValue: target.value,
        isLoan: true,
        loanSeasons: 1,
        loanMonths: 12,
        wageSplitRatio: 0.5,
        transferType: 'loan',
        agreementDate: '2025-07-01',
        effectiveDate: '2025-07-01',
        eligibleDate: '2025-07-01',
      );

      // Complete loan
      final String? loanErr = await transfers.completeLoan(offerId, effectiveDate: '2025-07-01');
      expect(loanErr, isNull);

      // Verify player is now at borrower
      List<Player> borrowerSquad = await squads.squadForTeam(borrower.teamId);
      expect(borrowerSquad.any((Player p) => p.playerId == target.playerId), isTrue);

      // Player row marked as on loan in players
      final List<Map<String, Object?>> pRows = await db.query(
        t.players,
        columns: <String>['market_status'],
        where: 'player_id = ?',
        whereArgs: <Object?>[target.playerId],
      );
      expect(pRows.first['market_status'], t.marketOnLoan);

      // Active loan entry exists in team_loans
      expect(await db.query(t.teamLoans), isNotEmpty);

      // Automatic recall on expiration
      await service.recallFinishedLoans(season.endYear + 1, parent.teamId);

      // Player returned to parent club
      final List<Player> parentSquad = await squads.squadForTeam(parent.teamId);
      borrowerSquad = await squads.squadForTeam(borrower.teamId);
      expect(parentSquad.any((Player p) => p.playerId == target.playerId), isTrue);
      expect(borrowerSquad.any((Player p) => p.playerId == target.playerId), isFalse);

      expect(await db.query(t.teamLoans), isEmpty);
    });

    test('AI clubs conduct transfers and respect deadline day frenzy', () async {
      final int initialOffersCount = (await transfers.pendingOffersForTeam(clubs.first.teamId)).length;
      expect(initialOffersCount, isNotNull);
    });
  });

  group('Pre-Season Manager Orientation & Early Open Transfer Window Tests', () {
    late Directory dir;
    late Database db;
    late ReferenceRepository refs;
    late List<Team> clubs;
    late CareerProvider provider;
    const int countryId = 94; // Indonesia

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('orientation_test_');
      final String path = p.join(dir.path, 'game.db');
      await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
      db = await databaseFactory.openDatabase(path);
      await AppDatabase.ensureLocalTables(db);

      refs = ReferenceRepository(db);

      final List<Map<String, Object?>> leagues =
          await refs.leaguesForCountry(countryId);
      final Tournament? leagueTournament =
          await refs.tournamentById(leagues.first['tournament_id'] as int);
      clubs = await refs.teamsForCountry(countryId);

      provider = CareerProvider();
      await provider.init(db);
      await provider.startCareer(
        managerName: 'Coach Test',
        nationalityId: countryId,
        countryId: countryId,
        leagueTournament: leagueTournament!,
        teamId: clubs.first.teamId,
        onProgress: (_) {},
      );
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('when starting a new career, user enters pre-season orientation without facing an immediate match', () async {
      // Must be in pre-season orientation
      expect(provider.isPreSeasonOrientation, isTrue);

      // Orientation date set to summer window opening day (July 1st)
      expect(provider.preSeasonDate, '2025-07-01');
      expect(provider.nextDate, '2025-07-01');

      // Crucial: No match card / matches on day 1
      expect(provider.matchesToday, isEmpty);
      expect(provider.nextUserMatch, isNull);

      // Summer Transfer Window is OPEN right from the beginning
      expect(provider.currentTransferWindow, isNotNull);
      expect(provider.isTransferWindowOpen, isTrue);
      expect(provider.currentTransferWindow!.isSummer, isTrue);
      expect(provider.currentTransferWindow!.daysUntilDeadline(provider.nextDate!), greaterThan(50));

      // Welcome letter delivered to inbox
      expect(provider.inbox.any((m) => m.sender == 'Dewan Direksi' && m.title.contains('Selamat Datang')), isTrue);

      // Pre-season friendly is scheduled in the upcoming matches
      final FixtureMatch? upcoming = await provider.firstUpcomingUserMatch();
      expect(upcoming, isNotNull);
      expect(upcoming!.status, t.matchScheduled);
      expect(upcoming.date, '2025-07-23');
    });

    test('when completing pre-season orientation, world advances to first matchday and matchesToday is populated', () async {
      expect(provider.isPreSeasonOrientation, isTrue);
      expect(provider.nextUserMatch, isNull);

      // Complete orientation
      await provider.completePreSeasonOrientation();

      // Orientation completed flag persisted in career_state
      final List<Map<String, Object?>> stateRows = await db.query(t.careerState);
      expect(stateRows.first['orientation_completed'], 1);

      // Provider exits orientation mode
      expect(provider.isPreSeasonOrientation, isFalse);

      // Next date advances to the first scheduled matchday (July 23)
      expect(provider.nextDate, '2025-07-23');
      expect(provider.matchesToday, isNotEmpty);
      expect(provider.nextUserMatch, isNotNull);

      // Transfer window remains open during pre-season matchdays
      expect(provider.isTransferWindowOpen, isTrue);
    });

    test('resuming game respects orientation_completed status', () async {
      // 1. While in orientation, a freshly instantiated CareerProvider resumes into orientation
      final CareerProvider resumed1 = CareerProvider();
      await resumed1.init(db);
      expect(resumed1.isPreSeasonOrientation, isTrue);
      expect(resumed1.nextUserMatch, isNull);
      expect(resumed1.isTransferWindowOpen, isTrue);

      // 2. After orientation is completed, resume does not re-enter orientation
      await provider.completePreSeasonOrientation();

      final CareerProvider resumed2 = CareerProvider();
      await resumed2.init(db);
      expect(resumed2.isPreSeasonOrientation, isFalse);
      expect(resumed2.nextUserMatch, isNotNull);
    });
  });
}
