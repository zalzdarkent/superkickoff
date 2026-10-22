import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Transfer offer management and negotiation.
class TransferRepository {
  TransferRepository(this.db);

  final Database db;

  /// Create a new transfer offer.
  Future<int> createOffer({
    required int playerId,
    required int fromTeamId,
    required int toTeamId,
    required int offerAmount,
    required int playerValue,
    bool isLoan = false,
    int loanSeasons = 1,
  }) async {
    return await db.insert(t.transferOffers, <String, Object?>{
      'player_id': playerId,
      'from_team_id': fromTeamId,
      'to_team_id': toTeamId,
      'offer_amount': offerAmount,
      'player_value': playerValue,
      'status': t.offerPending,
      'is_loan': isLoan ? 1 : 0,
      'loan_seasons': loanSeasons,
      'created_date': _todayIso(),
    });
  }

  /// Get pending offers for a team (incoming or outgoing).
  Future<List<TransferOffer>> pendingOffersForTeam(int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT o.*, p.name AS player_name, p.salary AS player_salary,
             ft.name AS from_team_name, tt.name AS to_team_name
      FROM transfer_offers o
      JOIN players p ON p.player_id = o.player_id
      JOIN teams ft ON ft.team_id = o.from_team_id
      JOIN teams tt ON tt.team_id = o.to_team_id
      WHERE (o.from_team_id = ? OR o.to_team_id = ?)
        AND o.status IN (?, ?, ?)
      ORDER BY o.created_date DESC
    ''',
      <Object?>[
        teamId,
        teamId,
        t.offerPending,
        t.offerCountered,
        t.offerContractNegotiation,
      ],
    );
    return rows.map(TransferOffer.fromMap).toList();
  }

  /// Get a specific offer by ID.
  Future<TransferOffer?> getOffer(int offerId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT o.*, p.name AS player_name, p.salary AS player_salary,
             ft.name AS from_team_name, tt.name AS to_team_name
      FROM transfer_offers o
      JOIN players p ON p.player_id = o.player_id
      JOIN teams ft ON ft.team_id = o.from_team_id
      JOIN teams tt ON tt.team_id = o.to_team_id
      WHERE o.offer_id = ?
      LIMIT 1
    ''',
      <Object?>[offerId],
    );
    return rows.isEmpty ? null : TransferOffer.fromMap(rows.first);
  }

  /// Update offer status.
  Future<void> updateOfferStatus(
    int offerId,
    int status, {
    int? counterAmount,
    int? offerAmount,
    int? messageId,
  }) async {
    await db.update(
      t.transferOffers,
      <String, Object?>{
        'status': status,
        'updated_date': _todayIso(),
        'counter_amount': ?counterAmount,
        'offer_amount': ?offerAmount,
        'message_id': ?messageId,
      },
      where: 'offer_id = ?',
      whereArgs: <Object?>[offerId],
    );
  }

  /// Update contract proposal.
  Future<void> updateContractProposal(
    int offerId, {
    required int salary,
    required int durationYears,
  }) async {
    await db.update(
      t.transferOffers,
      <String, Object?>{
        'proposed_salary': salary,
        'proposed_duration_years': durationYears,
        'status': t.offerContractNegotiation,
        'updated_date': _todayIso(),
      },
      where: 'offer_id = ?',
      whereArgs: <Object?>[offerId],
    );
  }

  /// Complete the transfer (move player, update budget, create contract).
  Future<String?> completeTransfer(int offerId) async {
    final TransferOffer? offer = await getOffer(offerId);
    if (offer == null) return 'Transfer offer not found';
    if (offer.status != t.offerPlayerAccepted) {
      return 'Transfer not yet accepted by player';
    }

    final String? error = await db.transaction((Transaction txn) async {
      // Get buyer team
      final List<Map<String, Object?>> buyerRows = await txn.query(
        t.teams,
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.toTeamId],
        limit: 1,
      );
      if (buyerRows.isEmpty) return 'Buyer team not found';
      final int buyerBudget = (buyerRows.first['budget'] as int?) ?? 0;
      if (buyerBudget < offer.offerAmount) return 'Not enough budget';

      // Get seller team
      final List<Map<String, Object?>> sellerRows = await txn.query(
        t.teams,
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.fromTeamId],
        limit: 1,
      );
      final int sellerBudget = sellerRows.isEmpty
          ? 0
          : ((sellerRows.first['budget'] as int?) ?? 0);

      // Move player
      await txn.update(
        t.teamPlayers,
        <String, Object?>{'team_id': offer.toTeamId},
        where: 'player_id = ?',
        whereArgs: <Object?>[offer.playerId],
      );

      // Update player status
      await txn.update(
        t.players,
        <String, Object?>{
          'market_status': t.marketActive,
          'squad_status': t.squadFirstTeam,
          'is_captain': 0,
          'salary': offer.proposedSalary ?? offer.playerSalary,
        },
        where: 'player_id = ?',
        whereArgs: <Object?>[offer.playerId],
      );

      // Update budgets
      await txn.update(
        t.teams,
        <String, Object?>{'budget': buyerBudget - offer.offerAmount},
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.toTeamId],
      );
      await txn.update(
        t.teams,
        <String, Object?>{'budget': sellerBudget + offer.offerAmount},
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.fromTeamId],
      );

      // End old contract
      await txn.update(
        t.contracts,
        <String, Object?>{'status': 0},
        where: 'player_id = ? AND status = 1',
        whereArgs: <Object?>[offer.playerId],
      );

      // Create new contract
      final int year = DateTime.now().year;
      final int duration = offer.proposedDurationYears ?? 3;
      await txn.insert(t.contracts, <String, Object?>{
        'player_id': offer.playerId,
        'team_id': offer.toTeamId,
        'start_date': '$year-07-01',
        'end_date': '${year + duration}-06-30',
        'status': 1,
        'salary': offer.proposedSalary ?? offer.playerSalary,
      });

      // Record transfer
      await txn.insert(t.playerTransfers, <String, Object?>{
        'player_id': offer.playerId,
        'from_team_id': offer.fromTeamId,
        'to_team_id': offer.toTeamId,
        'type': 1,
        'value': offer.offerAmount,
        'date': _todayIso(),
      });

      // Recalculate dynamic team power for both clubs.
      Future<void> updatePower(int teamId) async {
        final List<Map<String, Object?>> rows = await txn.rawQuery(
          '''
          SELECT p.power
          FROM players p
          JOIN team_players tp ON tp.player_id = p.player_id
          WHERE tp.team_id = ? AND p.status_id = ?
          ORDER BY p.power DESC
          LIMIT 11
        ''',
          <Object?>[teamId, t.statusActive],
        );
        if (rows.isEmpty) return;
        final int sum = rows.fold<int>(
          0,
          (int acc, Map<String, Object?> r) =>
              acc + ((r['power'] as int?) ?? 0),
        );
        final int newPower = (sum / rows.length).round();
        await txn.update(
          t.teams,
          <String, Object?>{'power': newPower},
          where: 'team_id = ?',
          whereArgs: <Object?>[teamId],
        );
      }

      await updatePower(offer.toTeamId);
      await updatePower(offer.fromTeamId);

      // Mark offer as completed
      await txn.update(
        t.transferOffers,
        <String, Object?>{
          'status': t.offerCompleted,
          'updated_date': _todayIso(),
        },
        where: 'offer_id = ?',
        whereArgs: <Object?>[offerId],
      );

      return null;
    });
    return error;
  }

  /// Calendar year the loan ends (June 30th). A loan agreed once the season is
  /// under way still runs [seasons] *full* seasons, so it outlasts this one.
  static Future<int> loanEndYear(DatabaseExecutor db, int seasons) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.seasons,
      orderBy: 'season_id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return DateTime.now().year + seasons;
    final int seasonId = rows.first['season_id'] as int;
    final int endYear = (rows.first['end_year'] as int?) ?? DateTime.now().year;
    final int started =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM matches WHERE season_id = ? '
            'AND tournament_id != 9999 AND status = ?',
            <Object?>[seasonId, t.matchFinished],
          ),
        ) ??
        0;
    return endYear + seasons - (started == 0 ? 1 : 0);
  }

  /// Complete a loan deal (moves player on loan, transfers loan fee).
  Future<String?> completeLoan(int offerId) async {
    final TransferOffer? offer = await getOffer(offerId);
    if (offer == null) return 'Loan offer not found';

    final String? error = await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> borrowerRows = await txn.query(
        t.teams,
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.toTeamId],
        limit: 1,
      );
      if (borrowerRows.isEmpty) return 'Borrowing team not found';
      final int borrowerBudget = (borrowerRows.first['budget'] as int?) ?? 0;
      final int owned =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM team_players WHERE player_id = ? AND team_id = ?',
              <Object?>[offer.playerId, offer.fromTeamId],
            ),
          ) ??
          0;
      if (owned == 0) return '${offer.playerName} is no longer at your club.';

      final List<Map<String, Object?>> lenderRows = await txn.query(
        t.teams,
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.fromTeamId],
        limit: 1,
      );
      final int lenderBudget = lenderRows.isEmpty
          ? 0
          : ((lenderRows.first['budget'] as int?) ?? 0);

      // Move player to borrower squad in team_players
      await txn.update(
        t.teamPlayers,
        <String, Object?>{'team_id': offer.toTeamId},
        where: 'player_id = ?',
        whereArgs: <Object?>[offer.playerId],
      );

      // Mark player status as on-loan
      await txn.update(
        t.players,
        <String, Object?>{
          'market_status': t.marketOnLoan,
          'squad_status': t.squadLoanListed,
          'is_captain': 0,
        },
        where: 'player_id = ?',
        whereArgs: <Object?>[offer.playerId],
      );

      // Transfer loan fee
      await txn.update(
        t.teams,
        <String, Object?>{
          // AI clubs never block a loan the manager already agreed to.
          'budget': max(0, borrowerBudget - offer.offerAmount),
        },
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.toTeamId],
      );
      await txn.update(
        t.teams,
        <String, Object?>{'budget': lenderBudget + offer.offerAmount},
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.fromTeamId],
      );

      // Record in team_loans
      final int endYear = await loanEndYear(txn, offer.loanSeasons);
      await txn.insert(t.teamLoans, <String, Object?>{
        'player_id': offer.playerId,
        'from_team_id': offer.fromTeamId,
        'to_team_id': offer.toTeamId,
        'date_from': _todayIso(),
        'date_to': '$endYear-06-30',
        'months': 12 * offer.loanSeasons,
        'notified': 0,
      });

      // Update offer status to completed
      await txn.update(
        t.transferOffers,
        <String, Object?>{
          'status': t.offerCompleted,
          'updated_date': _todayIso(),
        },
        where: 'offer_id = ?',
        whereArgs: <Object?>[offerId],
      );

      return null;
    });
    return error;
  }

  static String _todayIso() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
