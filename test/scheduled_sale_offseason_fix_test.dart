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
import 'package:superkickoff/game/offseason.dart';
import 'package:superkickoff/game/season_generator.dart';
import 'package:superkickoff/game/transfer_window_manager.dart';

void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_scheduled_test_');
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

  test('scheduled transfer outside window completes properly in offseason without being released as free agent', () async {
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
    final plan = await gen.generateCareer(
      countryId: countryId,
      league: league,
      cup: null,
      startYear: 2025,
      userTeamId: userTeam.teamId,
    );

    await windowManager.ensureWindowsForSeason(plan.season.seasonId, plan.season.startYear);

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

    // Pick a player from userTeam
    final userPlayers = await squads.squadForTeam(userTeam.teamId);
    final player = userPlayers.first;

    // Set contract to expire in season.endYear (2026)
    await db.update(
      t.contracts,
      {'end_date': '${plan.season.endYear}-06-30'},
      where: 'player_id = ? AND status = 1',
      whereArgs: [player.playerId],
    );

    // Pick a buyer
    final buyer = teams.last;
    final int buyerInitialBudget = buyer.budget;
    final int userInitialBudget = userTeam.budget;
    const int transferFee = 150000;

    // Outside window transfer agreement
    final nextWindow = await windowManager.nextRegistrationWindowForTeam(
      plan.season.seasonId,
      buyer.teamId,
      '${plan.season.endYear}-04-01',
    );

    final offerId = await transfers.createOffer(
      fromTeamId: userTeam.teamId,
      toTeamId: buyer.teamId,
      playerId: player.playerId,
      offerAmount: transferFee,
      playerValue: transferFee,
      agreementDate: '${plan.season.endYear}-04-01',
      effectiveDate: nextWindow.startDate,
    );

    await transfers.scheduleTransfer(
      offerId,
      agreementDate: '${plan.season.endYear}-04-01',
      effectiveDate: nextWindow.startDate,
    );

    // Enter Offseason
    await career.beginOffseason(
      userTeamId: userTeam.teamId,
      onProgress: (s) {},
    );

    // Step 1: Summary -> Contracts
    await career.advanceOffseason(
      userTeamId: userTeam.teamId,
      onProgress: (s) {},
    );

    // Verify player is NOT in expiringContracts!
    final expiring = await career.expiringContracts(userTeam.teamId, plan.season.endYear);
    final isPlayerInExpiring = expiring.any((c) => c.player.playerId == player.playerId);
    expect(isPlayerInExpiring, isFalse, reason: 'Pemain dengan transfer terjadwal tidak boleh masuk expiring contracts');

    // Step 2: Contracts -> Development
    await career.advanceOffseason(
      userTeamId: userTeam.teamId,
      onProgress: (s) {},
    );

    // Player should NOT be in the release report
    final reportDev = (await career.offseasonState())?.report ?? '';
    expect(reportDev.contains('${player.name} left on a free transfer'), isFalse);

    // Step 3: Development -> Transfers (offseason window opens, scheduled transfers process)
    await career.advanceOffseason(
      userTeamId: userTeam.teamId,
      onProgress: (s) {},
    );

    // Verify player has moved to buyer, NOT a random club!
    final tpRow = await db.query(t.teamPlayers, where: 'player_id = ?', whereArgs: [player.playerId]);
    expect(tpRow.length, 1);
    expect(tpRow.first['team_id'], buyer.teamId, reason: 'Pemain harus bergabung ke klub pembeli');

    // Verify transfer offer is completed
    final offerAfter = await transfers.getOffer(offerId);
    expect(offerAfter!.status, t.offerCompleted);

    // Verify budgets updated
    final userTeamAfter = await refs.teamById(userTeam.teamId);
    final buyerAfter = await refs.teamById(buyer.teamId);
    expect(userTeamAfter!.budget, userInitialBudget + transferFee);
    expect(buyerAfter!.budget, buyerInitialBudget - transferFee);
  });
}

