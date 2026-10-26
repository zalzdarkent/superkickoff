import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/scouting_repository.dart';
import 'package:superkickoff/data/repositories/sponsorship_repository.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  late Directory dir;
  late Database db;
  late SponsorshipRepository sponsorships;
  late ScoutingRepository scouting;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('features_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);
    sponsorships = SponsorshipRepository(db);
    scouting = ScoutingRepository(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('sponsorship deals offer, sign, pay weekly, and evaluate targets', () async {
    // 1. Available offers
    final List<ClubSponsorship> offers = await sponsorships.availableOffers(
      teamId: 42,
      seasonId: 1,
      clubPower: 75,
    );
    expect(offers, isNotEmpty);
    final ClubSponsorship firstOffer = offers.first;

    // Budget before signing
    final int budgetBefore = (await db.query('teams', where: 'team_id = 42')).first['budget'] as int;

    // 2. Sign sponsorship
    await sponsorships.signSponsorship(firstOffer);
    final List<ClubSponsorship> active = await sponsorships.activeSponsorships(42, 1);
    expect(active.length, 1);
    expect(active.first.type, firstOffer.type);

    final int budgetAfter = (await db.query('teams', where: 'team_id = 42')).first['budget'] as int;
    expect(budgetAfter, budgetBefore + firstOffer.baseReward);

    // 3. Weekly reward
    final int weeklyPaid = await sponsorships.payWeekly(42, 1);
    expect(weeklyPaid, firstOffer.weeklyReward);

    // 4. End of season target bonus
    final List<String> bonuses = await sponsorships.evaluateSeasonTargets(
      teamId: 42,
      seasonId: 1,
      finalLeagueRank: 1, // Won the league
    );
    expect(bonuses, isNotEmpty);
  });

  test('sponsorship offers are guaranteed to be from 3 distinct brands across slots', () async {
    // 1. Initial 3 offers across slots 1, 2, 3
    final List<ClubSponsorship> offers = await sponsorships.availableOffers(
      teamId: 42,
      seasonId: 1,
      clubPower: 75,
    );

    expect(offers.length, 3);
    final Set<int> offerTypes = offers.map((ClubSponsorship o) => o.type).toSet();
    final Set<int> offerSponsorIds = offers.map((ClubSponsorship o) => o.sponsorId).toSet();
    final Set<String> offerNames = offers.map((ClubSponsorship o) => o.sponsorName.trim().toLowerCase()).toSet();

    // All 3 slot types (1: Main Shirt, 2: Stadium, 3: Sleeve)
    expect(offerTypes, <int>{1, 2, 3});
    // Crucial requirement: Must be 3 DIFFERENT brands, never duplicate brands (e.g., Etihad x 3)
    expect(offerSponsorIds.length, 3);
    expect(offerNames.length, 3);

    // 2. Sign slot 1
    await sponsorships.signSponsorship(offers[0]);

    // 3. Query offers again for the remaining 2 slots
    final List<ClubSponsorship> remainingOffers = await sponsorships.availableOffers(
      teamId: 42,
      seasonId: 1,
      clubPower: 75,
    );
    expect(remainingOffers.length, 2);
    // Remaining slots must NOT reuse the brand already signed in slot 1
    for (final ClubSponsorship rem in remainingOffers) {
      expect(rem.sponsorId, isNot(offers[0].sponsorId));
      expect(rem.sponsorName.trim().toLowerCase(), isNot(offers[0].sponsorName.trim().toLowerCase()));
    }
    // And remaining offers must also be distinct from each other
    expect(remainingOffers[0].sponsorId, isNot(remainingOffers[1].sponsorId));
    expect(
      remainingOffers[0].sponsorName.trim().toLowerCase(),
      isNot(remainingOffers[1].sponsorName.trim().toLowerCase()),
    );

    // 4. Sign slot 2 and slot 3
    await sponsorships.signSponsorship(remainingOffers[0]);
    final List<ClubSponsorship> lastOffers = await sponsorships.availableOffers(
      teamId: 42,
      seasonId: 1,
      clubPower: 75,
    );
    expect(lastOffers.length, 1);
    expect(lastOffers.first.sponsorId, isNot(offers[0].sponsorId));
    expect(lastOffers.first.sponsorId, isNot(remainingOffers[0].sponsorId));
    await sponsorships.signSponsorship(lastOffers.first);

    // 5. Verify all active sponsorships in the club have completely unique brands
    final List<ClubSponsorship> activeDeals = await sponsorships.activeSponsorships(42, 1);
    expect(activeDeals.length, 3);
    final Set<String> activeNames = activeDeals.map((ClubSponsorship d) => d.sponsorName.trim().toLowerCase()).toSet();
    expect(activeNames.length, 3);

    // 6. Test contract termination
    final ClubSponsorship dealToTerminate = activeDeals.first;
    await sponsorships.terminateSponsorship(dealToTerminate.sponsorshipId);

    final List<ClubSponsorship> postTerminationActive = await sponsorships.activeSponsorships(42, 1);
    expect(postTerminationActive.length, 2);
    expect(
      postTerminationActive.any((ClubSponsorship d) => d.sponsorshipId == dealToTerminate.sponsorshipId),
      isFalse,
    );

    // Terminated slot is now open again with a distinct brand offer
    final List<ClubSponsorship> reopenedOffers = await sponsorships.availableOffers(
      teamId: 42,
      seasonId: 1,
      clubPower: 75,
    );
    expect(reopenedOffers.length, 1);
    expect(reopenedOffers.first.type, dealToTerminate.type);
  });

  test('activeSponsorships auto-heals duplicate sponsor brands from existing saves', () async {
    // Simulate an existing save affected by the old bug where all 3 slots were "Etihad Airways"
    await db.insert('sponsorships', <String, Object?>{
      'sponsorship_id': 101,
      'team_id': 42,
      'sponsor_id': 1,
      'type': 1,
      'season_id': 1,
      'base_reward': 5000000,
      'progress': 150000,
      'target': 1,
      'is_unique_prize': 2000000,
      'status': 1,
      'extra_data': 'Etihad Airways',
    });
    await db.insert('sponsorships', <String, Object?>{
      'sponsorship_id': 102,
      'team_id': 42,
      'sponsor_id': 1,
      'type': 2,
      'season_id': 1,
      'base_reward': 3000000,
      'progress': 100000,
      'target': 10,
      'is_unique_prize': 1000000,
      'status': 1,
      'extra_data': 'Etihad Airways',
    });
    await db.insert('sponsorships', <String, Object?>{
      'sponsorship_id': 103,
      'team_id': 42,
      'sponsor_id': 1,
      'type': 3,
      'season_id': 1,
      'base_reward': 2000000,
      'progress': 75000,
      'target': 1,
      'is_unique_prize': 1500000,
      'status': 1,
      'extra_data': 'Etihad Airways',
    });

    // When querying active sponsorships, auto-heal should resolve duplicate brands
    final List<ClubSponsorship> healed = await sponsorships.activeSponsorships(42, 1);
    expect(healed.length, 3);

    final Set<String> brandNames = healed.map((ClubSponsorship s) => s.sponsorName.trim().toLowerCase()).toSet();
    final Set<int> sponsorIds = healed.map((ClubSponsorship s) => s.sponsorId).toSet();

    // Must now be 3 totally distinct brands and IDs!
    expect(brandNames.length, 3);
    expect(sponsorIds.length, 3);

    // Verify database was actually persisted with healed data
    final List<Map<String, Object?>> persistedRows = await db.query(
      'sponsorships',
      where: 'team_id = 42 AND season_id = 1 AND status = 1',
    );
    final Set<String> persistedNames = persistedRows
        .map((Map<String, Object?> r) => (r['extra_data'] as String).trim().toLowerCase())
        .toSet();
    expect(persistedNames.length, 3);
    final Set<int> persistedIds = persistedRows
        .map((Map<String, Object?> r) => r['sponsor_id'] as int)
        .toSet();
    expect(persistedIds.length, 3);
  });

  test('scouting department hires scouts, deploys to region and discovers wonderkids', () async {
    final List<Scout> available = scouting.availableScoutsToHire();
    expect(available, isNotEmpty);
    final Scout candidate = available.first; // 2 stars

    // Hire scout
    final String? hireError = await scouting.hireScout(42, candidate);
    expect(hireError, isNull);

    final List<Scout> hired = await scouting.hiredScouts(42);
    expect(hired.length, 1);
    final Scout scout = hired.first;
    expect(scout.stars, candidate.stars);

    // Deploy scout to South America
    final List<ScoutWonderkid> found = await scouting.deployScout(
      teamId: 42,
      scout: scout,
      region: 'South America',
      date: '2025-08-01',
    );
    expect(found.length, inInclusiveRange(2, 3));
    for (final ScoutWonderkid w in found) {
      expect(w.age, inInclusiveRange(16, 18));
      expect(w.potential, greaterThanOrEqualTo(w.power));
    }

    final List<ScoutWonderkid> pending = await scouting.pendingWonderkids(42);
    expect(pending.length, found.length);

    // Sign the top wonderkid
    final ScoutWonderkid selectedWonderkid = pending.first;
    final String? signError = await scouting.signWonderkid(
      reportId: selectedWonderkid.reportId,
      teamId: 42,
    );
    expect(signError, isNull);

    final List<Map<String, Object?>> signedPlayers = await db.rawQuery(
      '''
      SELECT p.height
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.name = ?
      ORDER BY p.player_id DESC
      LIMIT 1
      ''',
      <Object?>[42, selectedWonderkid.playerName],
    );
    final (int minimumHeight, int maximumHeight) =
        ScoutingRepository.heightRangeForPosition(selectedWonderkid.positionId);
    final int signedHeight = signedPlayers.first['height'] as int;
    expect(signedHeight, inInclusiveRange(minimumHeight, maximumHeight));

    final List<ScoutWonderkid> remaining = await scouting.pendingWonderkids(42);
    expect(remaining.length, pending.length - 1);

    final ScoutWonderkid rejectedWonderkid = remaining.first;
    expect(
      await scouting.rejectWonderkid(
        reportId: rejectedWonderkid.reportId,
        teamId: 551,
      ),
      isFalse,
    );
    expect(
      await scouting.rejectWonderkid(
        reportId: rejectedWonderkid.reportId,
        teamId: 42,
      ),
      isTrue,
    );
    final List<ScoutWonderkid> afterReject = await scouting.pendingWonderkids(
      42,
    );
    expect(afterReject.length, remaining.length - 1);
    expect(
      afterReject.any(
        (ScoutWonderkid prospect) =>
            prospect.reportId == rejectedWonderkid.reportId,
      ),
      isFalse,
    );
  });

  test('scouted players get varied heights within their position range', () {
    final math.Random rng = math.Random(42);

    for (int positionId = 1; positionId <= 11; positionId++) {
      final (int minimumHeight, int maximumHeight) =
          ScoutingRepository.heightRangeForPosition(positionId);
      final Set<int> heights = <int>{
        for (int i = 0; i < 100; i++)
          ScoutingRepository.heightForPosition(positionId, rng),
      };
      expect(heights, isNotEmpty);
      expect(
        heights.every((int height) {
          return height >= minimumHeight && height <= maximumHeight;
        }),
        isTrue,
      );
      expect(heights.length, greaterThan(1));
    }
  });

  test('schedules 3 pre-season friendlies before league start', () async {
    final SeasonGenerator generator = SeasonGenerator(db);
    final Map<int, Team> clubsMap = <int, Team>{
      42: Team(
        teamId: 42,
        name: 'Persib',
        abbreviation: 'PSB',
        countryId: 97,
        power: 70,
        value: 10000000,
        budget: 5000000,
        division: 1,
        stadiumId: 1,
        coachId: 1,
        foundedYear: 1933,
      ),
      551: Team(
        teamId: 551,
        name: 'Real Madrid',
        abbreviation: 'RMA',
        countryId: 64,
        power: 87,
        value: 100000000,
        budget: 80000000,
        division: 1,
        stadiumId: 2,
        coachId: 2,
        foundedYear: 1902,
      ),
      571: Team(
        teamId: 571,
        name: 'Liverpool',
        abbreviation: 'LIV',
        countryId: 185,
        power: 86,
        value: 90000000,
        budget: 70000000,
        division: 1,
        stadiumId: 3,
        coachId: 3,
        foundedYear: 1892,
      ),
      336: Team(
        teamId: 336,
        name: 'Bayern',
        abbreviation: 'BAY',
        countryId: 3,
        power: 86,
        value: 90000000,
        budget: 70000000,
        division: 1,
        stadiumId: 4,
        coachId: 4,
        foundedYear: 1900,
      ),
    };

    await generator.schedulePreSeasonFriendlies(
      seasonId: 1,
      userTeamId: 42,
      allTeams: clubsMap,
    );

    final List<Map<String, Object?>> friendlyMatches = await db.query(
      'matches',
      where: 'tournament_id = 9999 AND season_id = 1',
    );
    expect(friendlyMatches.length, 3);
  });
}
