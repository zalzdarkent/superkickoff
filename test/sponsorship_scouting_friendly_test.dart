import 'dart:io';

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
    final String? signError = await scouting.signWonderkid(
      reportId: pending.first.reportId,
      teamId: 42,
    );
    expect(signError, isNull);

    final List<ScoutWonderkid> remaining = await scouting.pendingWonderkids(42);
    expect(remaining.length, pending.length - 1);
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
