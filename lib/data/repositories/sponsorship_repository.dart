import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Repository for club sponsorships and commercial revenue.
class SponsorshipRepository {
  SponsorshipRepository(this.db);

  final Database db;

  /// Active sponsorships for [teamId] in [seasonId].
  ///
  /// Guarantees that every active sponsorship slot has a distinct, unique brand.
  /// If an existing save has duplicate sponsors (e.g., from older versions),
  /// it automatically heals and replaces duplicates with distinct corporate partners.
  Future<List<ClubSponsorship>> activeSponsorships(
    int teamId,
    int seasonId,
  ) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT s.*, sp.name AS sponsor_name
      FROM ${t.sponsorships} s
      LEFT JOIN ${t.sponsors} sp ON sp.sponsor_id = s.sponsor_id
      WHERE s.team_id = ? AND s.season_id = ? AND s.status = 1
      ORDER BY s.type ASC
    ''',
      <Object?>[teamId, seasonId],
    );

    final List<ClubSponsorship> active =
        rows.map(ClubSponsorship.fromMap).toList();
    if (active.length <= 1) return active;

    // Detect if there are duplicates (same sponsor_id or same sponsorName)
    final Set<int> seenIds = <int>{};
    final Set<String> seenNames = <String>{};
    bool hasDuplicates = false;

    for (final ClubSponsorship s in active) {
      final String nameLower = s.sponsorName.toLowerCase().trim();
      if (seenIds.contains(s.sponsorId) || seenNames.contains(nameLower)) {
        hasDuplicates = true;
        break;
      }
      seenIds.add(s.sponsorId);
      seenNames.add(nameLower);
    }

    if (!hasDuplicates) {
      return active;
    }

    // Auto-heal duplicate active sponsorships in DB so all slots have distinct brands
    final List<Map<String, Object?>> allSponsors = await db.query(t.sponsors);
    final math.Random fixRng = math.Random(teamId * 7919 + seasonId * 61);
    final List<Map<String, Object?>> shuffled =
        List<Map<String, Object?>>.from(allSponsors)..shuffle(fixRng);

    final Set<int> fixedIds = <int>{};
    final Set<String> fixedNames = <String>{};

    for (final ClubSponsorship s in active) {
      final String currentName = s.sponsorName.toLowerCase().trim();
      if (fixedIds.contains(s.sponsorId) || fixedNames.contains(currentName)) {
        final Map<String, Object?> rep = shuffled.firstWhere(
          (Map<String, Object?> candidate) {
            final int id = (candidate['sponsor_id'] as int?) ?? 0;
            final String name =
                ((candidate['name'] as String?) ?? '').toLowerCase().trim();
            return !fixedIds.contains(id) &&
                !fixedNames.contains(name) &&
                name.isNotEmpty;
          },
          orElse: () => <String, Object?>{
            'sponsor_id': 100 + s.type,
            'name': 'Corporate Partner ${s.type}',
          },
        );

        final int repId = (rep['sponsor_id'] as int?) ?? (100 + s.type);
        final String repName =
            (rep['name'] as String?) ?? 'Corporate Partner ${s.type}';

        await db.update(
          t.sponsorships,
          <String, Object?>{
            'sponsor_id': repId,
            'extra_data': repName,
          },
          where: 'sponsorship_id = ?',
          whereArgs: <Object?>[s.sponsorshipId],
        );

        fixedIds.add(repId);
        fixedNames.add(repName.toLowerCase().trim());
      } else {
        fixedIds.add(s.sponsorId);
        fixedNames.add(currentName);
      }
    }

    // Re-query sanitized records
    final List<Map<String, Object?>> fixedRows = await db.rawQuery(
      '''
      SELECT s.*, sp.name AS sponsor_name
      FROM ${t.sponsorships} s
      LEFT JOIN ${t.sponsors} sp ON sp.sponsor_id = s.sponsor_id
      WHERE s.team_id = ? AND s.season_id = ? AND s.status = 1
      ORDER BY s.type ASC
    ''',
      <Object?>[teamId, seasonId],
    );
    return fixedRows.map(ClubSponsorship.fromMap).toList();
  }

  /// Generates sponsor proposals for unfilled slots (1=Main Kit, 2=Stadium, 3=Sleeve).
  ///
  /// Guarantees that all 3 slots come from 3 DIFFERENT brands, and never duplicate
  /// any active sponsor or each other, with stable deterministic assignment.
  Future<List<ClubSponsorship>> availableOffers({
    required int teamId,
    required int seasonId,
    required int clubPower,
  }) async {
    final List<ClubSponsorship> active = await activeSponsorships(
      teamId,
      seasonId,
    );
    final Set<int> filledTypes =
        active.map((ClubSponsorship s) => s.type).toSet();

    if (filledTypes.length >= 3) {
      return const <ClubSponsorship>[];
    }

    final Set<int> usedSponsorIds =
        active.map((ClubSponsorship s) => s.sponsorId).toSet();
    final Set<String> usedSponsorNames = active
        .map((ClubSponsorship s) => s.sponsorName.toLowerCase().trim())
        .toSet();

    final List<Map<String, Object?>> sponsorRows = await db.query(t.sponsors);

    // Create a deterministic pseudo-random permutation for this (teamId, seasonId)
    final math.Random rng = math.Random(teamId * 10007 + seasonId * 997);
    final List<Map<String, Object?>> pool =
        List<Map<String, Object?>>.from(sponsorRows);
    if (pool.isNotEmpty) {
      pool.shuffle(rng);
    }

    final List<ClubSponsorship> offers = <ClubSponsorship>[];
    int poolCursor = 0;

    for (int type = 1; type <= 3; type++) {
      if (filledTypes.contains(type)) {
        continue;
      }

      final double scale = math.max(1.0, (clubPower - 40) / 10);
      final int baseUpfront = switch (type) {
        1 => (1200000 * scale).round(),
        2 => (800000 * scale).round(),
        _ => (500000 * scale).round(),
      };
      final int weekly = (baseUpfront / 38 * 0.8).round();
      final int target = clubPower >= 75 ? 3 : (clubPower >= 65 ? 6 : 10);
      final int targetBonus = (baseUpfront * 0.75).round();

      // Find the next distinct brand from pool
      Map<String, Object?>? selected;
      while (poolCursor < pool.length) {
        final Map<String, Object?> candidate = pool[poolCursor++];
        final int candidateId = (candidate['sponsor_id'] as int?) ?? 0;
        final String candidateName =
            ((candidate['name'] as String?) ?? '').toLowerCase().trim();

        if (!usedSponsorIds.contains(candidateId) &&
            !usedSponsorNames.contains(candidateName) &&
            candidateName.isNotEmpty) {
          selected = candidate;
          break;
        }
      }

      final int sId = selected != null
          ? ((selected['sponsor_id'] as int?) ?? (type * 100 + seasonId))
          : (type * 100 + seasonId);
      final String sName = selected != null
          ? ((selected['name'] as String?) ?? 'Global Partner $type')
          : 'Global Partner $type';

      usedSponsorIds.add(sId);
      usedSponsorNames.add(sName.toLowerCase().trim());

      offers.add(
        ClubSponsorship(
          sponsorshipId: 0,
          type: type,
          teamId: teamId,
          sponsorId: sId,
          sponsorName: sName,
          seasonId: seasonId,
          baseReward: baseUpfront,
          weeklyReward: weekly,
          target: target,
          bonusPrize: targetBonus,
          status: 1,
          extraData: sName,
        ),
      );
    }
    return offers;
  }

  /// Signs a sponsorship deal, crediting the signing bonus immediately.
  /// Also ensures any incumbent deal of the same slot type is replaced cleanly.
  Future<void> signSponsorship(ClubSponsorship offer) async {
    await db.transaction((Transaction txn) async {
      // Deactivate any existing active deal for the same slot
      await txn.update(
        t.sponsorships,
        <String, Object?>{'status': 0},
        where: 'team_id = ? AND season_id = ? AND type = ? AND status = 1',
        whereArgs: <Object?>[offer.teamId, offer.seasonId, offer.type],
      );

      await txn.insert(t.sponsorships, <String, Object?>{
        'type': offer.type,
        'team_id': offer.teamId,
        'sponsor_id': offer.sponsorId,
        'tournament_id': 0,
        'season_id': offer.seasonId,
        'is_priority': 1,
        'is_unique_prize': offer.bonusPrize,
        'base_reward': offer.baseReward,
        'target': offer.target,
        'progress': offer.weeklyReward,
        'success': 0,
        'status': 1,
        'extra_data': offer.sponsorName,
      });

      await txn.execute(
        'UPDATE teams SET budget = budget + ? WHERE team_id = ?',
        <Object?>[offer.baseReward, offer.teamId],
      );
    });
  }

  /// Terminates an active sponsorship contract, freeing the slot for new deals.
  Future<void> terminateSponsorship(int sponsorshipId) async {
    await db.update(
      t.sponsorships,
      <String, Object?>{'status': 0},
      where: 'sponsorship_id = ?',
      whereArgs: <Object?>[sponsorshipId],
    );
  }

  /// Pays weekly sponsorship installments to the club.
  Future<int> payWeekly(int teamId, int seasonId) async {
    final List<ClubSponsorship> active = await activeSponsorships(
      teamId,
      seasonId,
    );
    if (active.isEmpty) return 0;
    final int total = active.fold<int>(
      0,
      (int sum, ClubSponsorship s) => sum + s.weeklyReward,
    );
    if (total > 0) {
      await db.execute(
        'UPDATE teams SET budget = budget + ? WHERE team_id = ?',
        <Object?>[total, teamId],
      );
    }
    return total;
  }

  /// Evaluates end-of-season targets and pays bonuses for met objectives.
  Future<List<String>> evaluateSeasonTargets({
    required int teamId,
    required int seasonId,
    required int finalLeagueRank,
  }) async {
    final List<ClubSponsorship> active = await activeSponsorships(
      teamId,
      seasonId,
    );
    final List<String> rewards = <String>[];
    for (final ClubSponsorship s in active) {
      if (finalLeagueRank > 0 &&
          finalLeagueRank <= s.target &&
          s.bonusPrize > 0) {
        await db.execute(
          'UPDATE teams SET budget = budget + ? WHERE team_id = ?',
          <Object?>[s.bonusPrize, teamId],
        );
        rewards.add(
          '${s.sponsorName} paid \$${(s.bonusPrize / 1000000).toStringAsFixed(1)}M '
          'for achieving a top-${s.target} league finish!',
        );
      }
      await db.update(
        t.sponsorships,
        <String, Object?>{'status': 0},
        where: 'sponsorship_id = ?',
        whereArgs: <Object?>[s.sponsorshipId],
      );
    }
    return rewards;
  }
}
