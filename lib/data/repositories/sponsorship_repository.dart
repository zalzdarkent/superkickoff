import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Repository for club sponsorships and commercial revenue.
class SponsorshipRepository {
  SponsorshipRepository(this.db);

  final Database db;

  /// Active sponsorships for [teamId] in [seasonId].
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
    return rows.map(ClubSponsorship.fromMap).toList();
  }

  /// Generates sponsor proposals for unfilled slots (1=Main Kit, 2=Stadium, 3=Sleeve).
  Future<List<ClubSponsorship>> availableOffers({
    required int teamId,
    required int seasonId,
    required int clubPower,
  }) async {
    final List<ClubSponsorship> active = await activeSponsorships(
      teamId,
      seasonId,
    );
    final Set<int> filledTypes = active
        .map((ClubSponsorship s) => s.type)
        .toSet();

    final List<Map<String, Object?>> sponsorRows = await db.query(t.sponsors);
    final math.Random rng = math.Random(teamId * 31 + seasonId * 7);

    final List<ClubSponsorship> offers = <ClubSponsorship>[];
    for (int type = 1; type <= 3; type++) {
      if (filledTypes.contains(type)) continue;

      final double scale = math.max(1.0, (clubPower - 40) / 10);
      final int baseUpfront = switch (type) {
        1 => (1200000 * scale).round(),
        2 => (800000 * scale).round(),
        _ => (500000 * scale).round(),
      };
      final int weekly = (baseUpfront / 38 * 0.8).round();
      final int target = clubPower >= 75 ? 3 : (clubPower >= 65 ? 6 : 10);
      final int targetBonus = (baseUpfront * 0.75).round();

      final Map<String, Object?> sp = sponsorRows.isNotEmpty
          ? sponsorRows[rng.nextInt(sponsorRows.length)]
          : <String, Object?>{'sponsor_id': type, 'name': 'Global Partner $type'};

      offers.add(
        ClubSponsorship(
          sponsorshipId: 0,
          type: type,
          teamId: teamId,
          sponsorId: (sp['sponsor_id'] as int?) ?? type,
          sponsorName: (sp['name'] as String?) ?? 'Partner',
          seasonId: seasonId,
          baseReward: baseUpfront,
          weeklyReward: weekly,
          target: target,
          bonusPrize: targetBonus,
          status: 1,
          extraData: (sp['name'] as String?) ?? 'Sponsor',
        ),
      );
    }
    return offers;
  }

  /// Signs a sponsorship deal, crediting the signing bonus immediately.
  Future<void> signSponsorship(ClubSponsorship offer) async {
    await db.transaction((Transaction txn) async {
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
      if (finalLeagueRank > 0 && finalLeagueRank <= s.target && s.bonusPrize > 0) {
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
