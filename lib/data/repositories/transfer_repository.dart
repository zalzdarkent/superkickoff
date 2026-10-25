import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Result of processing a scheduled transfer when effective date arrives.
class ScheduledTransferResult {
  ScheduledTransferResult({
    required this.offer,
    required this.success,
    this.error,
  });

  final TransferOffer offer;
  final bool success;
  final String? error;
}

/// Transfer offer management, negotiation, and window execution.
class TransferRepository {
  TransferRepository(this.db);

  final Database db;

  /// Create a new transfer offer (buy, sell, or loan).
  Future<int> createOffer({
    required int playerId,
    required int fromTeamId,
    required int toTeamId,
    required int offerAmount,
    required int playerValue,
    bool isLoan = false,
    int loanSeasons = 1,
    int? loanMonths,
    double wageSplitRatio = 1.0,
    String transferType = 'permanent',
    int? proposedSalary,
    int? proposedDurationYears,
    String? agreementDate,
    String? effectiveDate,
    String? eligibleDate,
    String? loanStartDate,
    String? loanEndDate,
  }) async {
    final String today = _todayIso();
    return await db.insert(t.transferOffers, <String, Object?>{
      'player_id': playerId,
      'from_team_id': fromTeamId,
      'to_team_id': toTeamId,
      'offer_amount': offerAmount,
      'player_value': playerValue,
      'status': t.offerPending,
      'is_loan': isLoan ? 1 : 0,
      'loan_seasons': loanSeasons,
      'loan_months': loanMonths ?? (isLoan ? loanSeasons * 12 : null),
      'wage_split_ratio': wageSplitRatio,
      'transfer_type': isLoan ? 'loan' : transferType,
      'proposed_salary': proposedSalary,
      'proposed_duration_years': proposedDurationYears,
      'created_date': today,
      'agreement_date': agreementDate,
      'effective_date': effectiveDate,
      'eligible_date': eligibleDate,
      'loan_start_date': loanStartDate,
      'loan_end_date': loanEndDate,
    });
  }

  /// Get pending offers for a team (incoming or outgoing).
  Future<List<TransferOffer>> pendingOffersForTeam(int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT o.*, p.name AS player_name, p.salary AS player_salary,
             COALESCE(ft.name, 'Free Agent') AS from_team_name, tt.name AS to_team_name
      FROM transfer_offers o
      JOIN players p ON p.player_id = o.player_id
      LEFT JOIN teams ft ON ft.team_id = o.from_team_id
      JOIN teams tt ON tt.team_id = o.to_team_id
      WHERE (o.from_team_id = ? OR o.to_team_id = ?)
        AND o.status IN (?, ?, ?, ?, ?, ?)
      ORDER BY o.created_date DESC
    ''',
      <Object?>[
        teamId,
        teamId,
        t.offerPending,
        t.offerCountered,
        t.offerContractNegotiation,
        t.offerAccepted,
        t.offerPlayerAccepted,
        t.offerAwaitingWindow,
      ],
    );
    return rows.map(TransferOffer.fromMap).toList();
  }

  /// Get all scheduled offers (awaiting transfer window) involving a team.
  Future<List<TransferOffer>> scheduledOffersForTeam(int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT o.*, p.name AS player_name, p.salary AS player_salary,
             COALESCE(ft.name, 'Free Agent') AS from_team_name, tt.name AS to_team_name
      FROM transfer_offers o
      JOIN players p ON p.player_id = o.player_id
      LEFT JOIN teams ft ON ft.team_id = o.from_team_id
      JOIN teams tt ON tt.team_id = o.to_team_id
      WHERE (o.from_team_id = ? OR o.to_team_id = ?)
        AND o.status = ?
      ORDER BY o.effective_date ASC, o.created_date DESC
    ''',
      <Object?>[teamId, teamId, t.offerAwaitingWindow],
    );
    return rows.map(TransferOffer.fromMap).toList();
  }

  /// Get a specific offer by ID.
  Future<TransferOffer?> getOffer(int offerId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT o.*, p.name AS player_name, p.salary AS player_salary,
             COALESCE(ft.name, 'Free Agent') AS from_team_name, tt.name AS to_team_name
      FROM transfer_offers o
      JOIN players p ON p.player_id = o.player_id
      LEFT JOIN teams ft ON ft.team_id = o.from_team_id
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
    String? agreementDate,
    String? effectiveDate,
    String? eligibleDate,
    String? cancellationReason,
  }) async {
    final Map<String, Object?> values = <String, Object?>{
      'status': status,
      'updated_date': _todayIso(),
    };
    if (counterAmount != null) values['counter_amount'] = counterAmount;
    if (offerAmount != null) values['offer_amount'] = offerAmount;
    if (messageId != null) values['message_id'] = messageId;
    if (agreementDate != null) values['agreement_date'] = agreementDate;
    if (effectiveDate != null) values['effective_date'] = effectiveDate;
    if (eligibleDate != null) values['eligible_date'] = eligibleDate;
    if (cancellationReason != null) {
      values['cancellation_reason'] = cancellationReason;
    }

    await db.update(
      t.transferOffers,
      values,
      where: 'offer_id = ?',
      whereArgs: <Object?>[offerId],
    );
  }

  /// Schedule a finalized agreement for the next registration window.
  /// Player remains at the originating club until [effectiveDate].
  Future<void> scheduleTransfer(
    int offerId, {
    required String agreementDate,
    required String effectiveDate,
    String? eligibleDate,
  }) async {
    await db.update(
      t.transferOffers,
      <String, Object?>{
        'status': t.offerAwaitingWindow,
        'agreement_date': agreementDate,
        'effective_date': effectiveDate,
        'eligible_date': eligibleDate ?? effectiveDate,
        'updated_date': _todayIso(),
      },
      where: 'offer_id = ?',
      whereArgs: <Object?>[offerId],
    );
  }

  /// Cancels an active or scheduled offer.
  Future<void> cancelOffer(int offerId, {required String reason}) async {
    await db.update(
      t.transferOffers,
      <String, Object?>{
        'status': t.offerCancelled,
        'cancellation_reason': reason,
        'updated_date': _todayIso(),
      },
      where: 'offer_id = ?',
      whereArgs: <Object?>[offerId],
    );
  }

  /// Fails an offer (e.g. insufficient club funds on window opening).
  Future<void> failOffer(int offerId, {required String reason}) async {
    await db.update(
      t.transferOffers,
      <String, Object?>{
        'status': t.offerFailed,
        'cancellation_reason': reason,
        'updated_date': _todayIso(),
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

  /// Complete the transfer atomically (moves player, updates budgets, creates contract).
  Future<String?> completeTransfer(int offerId, {String? effectiveDate}) async {
    final TransferOffer? offer = await getOffer(offerId);
    if (offer == null) return 'Transfer offer not found';
    if (offer.status != t.offerPlayerAccepted &&
        offer.status != t.offerAwaitingWindow) {
      return 'Transfer not yet accepted by player';
    }

    final String moveDate = effectiveDate ?? _todayIso();

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

      // Move player atomically in team_players
      final int existingCount = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM team_players WHERE player_id = ?',
          <Object?>[offer.playerId],
        ),
      ) ?? 0;

      if (existingCount > 0) {
        await txn.update(
          t.teamPlayers,
          <String, Object?>{'team_id': offer.toTeamId},
          where: 'player_id = ?',
          whereArgs: <Object?>[offer.playerId],
        );
      } else {
        await txn.insert(t.teamPlayers, <String, Object?>{
          'team_id': offer.toTeamId,
          'player_id': offer.playerId,
        });
      }

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

      // Deduct buyer budget
      await txn.update(
        t.teams,
        <String, Object?>{'budget': buyerBudget - offer.offerAmount},
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.toTeamId],
      );

      // Credit seller budget (if not free agent)
      if (offer.fromTeamId > 0) {
        final List<Map<String, Object?>> sellerRows = await txn.query(
          t.teams,
          where: 'team_id = ?',
          whereArgs: <Object?>[offer.fromTeamId],
          limit: 1,
        );
        final int sellerBudget = sellerRows.isEmpty
            ? 0
            : ((sellerRows.first['budget'] as int?) ?? 0);

        await txn.update(
          t.teams,
          <String, Object?>{'budget': sellerBudget + offer.offerAmount},
          where: 'team_id = ?',
          whereArgs: <Object?>[offer.fromTeamId],
        );
      }

      // End old contract
      await txn.update(
        t.contracts,
        <String, Object?>{'status': 0},
        where: 'player_id = ? AND status = 1',
        whereArgs: <Object?>[offer.playerId],
      );

      // Create new contract
      final DateTime dateParsed =
          DateTime.tryParse(moveDate) ?? DateTime.now();
      final int year = dateParsed.year;
      final int duration = offer.proposedDurationYears ?? 3;
      await txn.insert(t.contracts, <String, Object?>{
        'player_id': offer.playerId,
        'team_id': offer.toTeamId,
        'start_date': moveDate,
        'end_date': '${year + duration}-06-30',
        'status': 1,
        'salary': offer.proposedSalary ?? offer.playerSalary,
      });

      // Record transfer history
      await txn.insert(t.playerTransfers, <String, Object?>{
        'player_id': offer.playerId,
        'from_team_id': offer.fromTeamId,
        'to_team_id': offer.toTeamId,
        'type': 1,
        'value': offer.offerAmount,
        'date': moveDate,
      });

      // Recalculate dynamic team power
      Future<void> updatePower(int teamId) async {
        if (teamId <= 0) return;
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
      if (offer.fromTeamId > 0) {
        await updatePower(offer.fromTeamId);
      }

      // Mark offer as completed
      await txn.update(
        t.transferOffers,
        <String, Object?>{
          'status': t.offerCompleted,
          'effective_date': moveDate,
          'eligible_date': moveDate,
          'updated_date': _todayIso(),
        },
        where: 'offer_id = ?',
        whereArgs: <Object?>[offerId],
      );

      return null;
    });

    return error;
  }

  /// Calendar year the loan ends (June 30th).
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

  /// Complete a loan deal atomically.
  Future<String?> completeLoan(int offerId, {String? effectiveDate}) async {
    final TransferOffer? offer = await getOffer(offerId);
    if (offer == null) return 'Loan offer not found';

    final String moveDate = effectiveDate ?? _todayIso();

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
      final String endDate = '$endYear-06-30';
      await txn.insert(t.teamLoans, <String, Object?>{
        'player_id': offer.playerId,
        'from_team_id': offer.fromTeamId,
        'to_team_id': offer.toTeamId,
        'date_from': moveDate,
        'date_to': endDate,
        'months': 12 * offer.loanSeasons,
        'notified': 0,
      });

      // Update offer status to completed
      await txn.update(
        t.transferOffers,
        <String, Object?>{
          'status': t.offerCompleted,
          'effective_date': moveDate,
          'eligible_date': moveDate,
          'loan_start_date': moveDate,
          'loan_end_date': endDate,
          'updated_date': _todayIso(),
        },
        where: 'offer_id = ?',
        whereArgs: <Object?>[offerId],
      );

      return null;
    });
    return error;
  }

  /// Process all scheduled transfers whose effective_date <= [currentDate].
  Future<List<ScheduledTransferResult>> processDueScheduledTransfers(
    String currentDate,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT o.offer_id, o.is_loan
      FROM transfer_offers o
      WHERE o.status = ? AND o.effective_date IS NOT NULL AND o.effective_date <= ?
    ''',
      <Object?>[t.offerAwaitingWindow, currentDate],
    );

    final List<ScheduledTransferResult> results = <ScheduledTransferResult>[];
    for (final Map<String, Object?> r in rows) {
      final int offerId = r['offer_id'] as int;
      final bool isLoan = (r['is_loan'] as int? ?? 0) == 1;
      final TransferOffer? offer = await getOffer(offerId);
      if (offer == null) continue;

      // Validate destination club budget
      final List<Map<String, Object?>> buyerRows = await db.query(
        t.teams,
        columns: <String>['budget'],
        where: 'team_id = ?',
        whereArgs: <Object?>[offer.toTeamId],
        limit: 1,
      );
      final int buyerBudget =
          buyerRows.isEmpty ? 0 : ((buyerRows.first['budget'] as int?) ?? 0);
      if (buyerBudget < offer.offerAmount) {
        const String reason =
            'Anggaran transfer klub tidak mencukupi saat jendela transfer dibuka';
        await failOffer(offerId, reason: reason);
        results.add(
          ScheduledTransferResult(offer: offer, success: false, error: reason),
        );
        continue;
      }

      // Mark temporarily as accepted so completeTransfer/completeLoan completes smoothly
      await db.update(
        t.transferOffers,
        <String, Object?>{'status': t.offerPlayerAccepted},
        where: 'offer_id = ?',
        whereArgs: <Object?>[offerId],
      );

      final String? error = isLoan
          ? await completeLoan(offerId, effectiveDate: currentDate)
          : await completeTransfer(offerId, effectiveDate: currentDate);

      if (error != null) {
        await failOffer(offerId, reason: error);
        results.add(
          ScheduledTransferResult(offer: offer, success: false, error: error),
        );
      } else {
        final TransferOffer? completedOffer = await getOffer(offerId);
        results.add(
          ScheduledTransferResult(
            offer: completedOffer ?? offer,
            success: true,
          ),
        );
      }
    }
    return results;
  }

  static String _todayIso() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
