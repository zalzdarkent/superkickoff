import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/data/repositories/transfer_repository.dart';

void main() {
  test('loan offer creation and completion moves player and transfers fee', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final Directory dir = await Directory.systemTemp.createTemp('loan_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    final Database db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);
    final SquadRepository squads = SquadRepository(db);
    final TransferRepository transfers = TransferRepository(db);

    // Get a player from Persib (team_id 42)
    final List<Player> persibSquad = await squads.squadForTeam(42);
    expect(persibSquad, isNotEmpty);
    final Player player = persibSquad.first;

    // List player for loan
    await squads.setSquadStatus(player.playerId, t.squadLoanListed);
    final List<Player> updatedSquad = await squads.squadForTeam(42);
    expect(
      updatedSquad.firstWhere((p) => p.playerId == player.playerId).squadStatus,
      t.squadLoanListed,
    );

    // Another club creates a loan offer
    const int borrowerTeamId = 551; // Real Madrid
    final int offerId = await transfers.createOffer(
      playerId: player.playerId,
      fromTeamId: 42,
      toTeamId: borrowerTeamId,
      offerAmount: 500000,
      playerValue: player.value,
      isLoan: true,
    );

    final TransferOffer? offer = await transfers.getOffer(offerId);
    expect(offer, isNotNull);
    expect(offer!.isLoan, isTrue);
    expect(offer.status, t.offerPending);

    // Complete the loan
    final String? error = await transfers.completeLoan(offerId);
    expect(error, isNull);

    // Player should now belong to borrower in team_players with marketOnLoan
    final List<Map<String, Object?>> teamPlayerRow = await db.query(
      'team_players',
      where: 'player_id = ?',
      whereArgs: <Object?>[player.playerId],
    );
    expect(teamPlayerRow.first['team_id'], borrowerTeamId);

    final List<Map<String, Object?>> playerRow = await db.query(
      'players',
      where: 'player_id = ?',
      whereArgs: <Object?>[player.playerId],
    );
    expect(playerRow.first['market_status'], t.marketOnLoan);

    // Loan record in team_loans
    final List<Map<String, Object?>> loanRows = await db.query(
      'team_loans',
      where: 'player_id = ?',
      whereArgs: <Object?>[player.playerId],
    );
    expect(loanRows, isNotEmpty);
    expect(loanRows.first['from_team_id'], 42);
    expect(loanRows.first['to_team_id'], borrowerTeamId);

    await db.close();
    await dir.delete(recursive: true);
  });
}
