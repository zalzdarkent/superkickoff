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

FixtureMatch fx(
  int id,
  int home,
  int away,
  int leg, {
  int? hg,
  int? ag,
  int? ph,
  int? pa,
}) => FixtureMatch.fromMap(<String, Object?>{
  'match_id': id,
  'tournament_id': 9,
  'phase': 1,
  'leg': leg,
  'status': hg == null ? 1 : 2,
  'home_team_id': home,
  'away_team_id': away,
  'stadium_id': 1,
  'home_goals': hg,
  'away_goals': ag,
  'penalty_home_goals': ph,
  'penalty_away_goals': pa,
});

void main() {
  test('groupTies merges both legs and computes the aggregate', () {
    final List<KnockoutTie> ties = groupTies(<FixtureMatch>[
      fx(1, 10, 20, 1, hg: 2, ag: 1),
      fx(2, 30, 40, 1, hg: 0, ag: 0),
      fx(3, 20, 10, 2, hg: 1, ag: 0, ph: 3, pa: 4),
      fx(4, 40, 30, 2),
    ]);
    expect(ties.length, 2);
    final KnockoutTie done = ties.first;
    expect(done.twoLegged, isTrue);
    expect(done.complete, isTrue);
    // Club 10: 2 + 0, club 20: 1 + 1.
    expect((done.homeAgg, done.awayAgg), (2, 2));
    // Shootout is stored from leg 2's view (home = club 20): 20 lost 3-4.
    expect(done.penalties, (4, 3));
    expect(ties.last.complete, isFalse, reason: 'leg 2 still to play');
  });

  group('with a real career database', () {
    late Directory dir;
    late Database db;
    late SeasonGenerator gen;
    late CareerService service;
    late SeasonRepository seasons;
    late SquadRepository squads;
    late TransferRepository transfers;
    late Season season;
    late Team userClub;
    late List<Team> clubs;
    const int countryId = 141;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('loan_two_leg_e2e_');
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
      gen = SeasonGenerator(db, random: Random(3));
      final CareerPlan plan = await gen.generateCareer(
        countryId: countryId,
        league: await find(t.orgLeague, division: 1),
        cup: await find(t.orgNationalCup),
      );
      season = plan.season;
      final ReferenceRepository refs = ReferenceRepository(db);
      seasons = SeasonRepository(db);
      squads = SquadRepository(db);
      transfers = TransferRepository(db);
      service = CareerService(
        db,
        refs: refs,
        seasons: seasons,
        squads: squads,
        matches: MatchRepository(db),
        messages: MessageRepository(db),
        engine: MatchEngine(random: Random(3)),
        generator: gen,
        transfers: transfers,
        random: Random(3),
        marketTickChance: 0,
      );
      clubs = await refs.teamsForDivision(countryId, 1);
      userClub = clubs.first;
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    test(
      'two-legged cup tie: both legs decide one winner and an aggregate',
      () async {
        // Tournament 164 is configured with rounds == 2.
        final Map<int, Team> cache = <int, Team>{
          for (final Team c in clubs) c.teamId: c,
        };
        final List<int> four = clubs.take(4).map((Team c) => c.teamId).toList();
        await gen.scheduleCupRound(
          season.seasonId,
          164,
          four,
          phase: 1,
          date: DateTime(2026, 2, 3),
          allTeams: cache,
        );
        final List<FixtureMatch> all = await seasons.fixturesForSeason(
          season.seasonId,
          tournamentId: 164,
        );
        expect(all.length, 4);
        for (final FixtureMatch m in all) {
          await service.simulateMatch(m, recordEvents: false);
        }
        final List<FixtureMatch> played = await seasons.fixturesForSeason(
          season.seasonId,
          tournamentId: 164,
        );
        final List<KnockoutTie> ties = groupTies(played);
        expect(ties.length, 2);
        for (final KnockoutTie tie in ties) {
          expect(tie.complete, isTrue);
          expect(tie.winnerId, isNotNull);
          final int winner = tie.homeAgg > tie.awayAgg
              ? tie.first.homeTeamId
              : tie.awayAgg > tie.homeAgg
              ? tie.first.awayTeamId
              : (tie.penalties!.$1 > tie.penalties!.$2
                    ? tie.first.homeTeamId
                    : tie.first.awayTeamId);
          expect(
            tie.winnerId,
            winner,
            reason: 'aggregate/shootout must pick the winner',
          );
        }
      },
    );

    Future<(int, Player)> offerLoan({int? budget}) async {
      final Player player = (await squads.squadForTeam(userClub.teamId)).first;
      await service.requestLoanOffer(
        userTeamId: userClub.teamId,
        player: player,
      );
      final List<TransferOffer> offers = await transfers.pendingOffersForTeam(
        userClub.teamId,
      );
      final TransferOffer offer = offers.firstWhere(
        (TransferOffer o) => o.isLoan,
      );
      if (budget != null) {
        await db.update(
          t.teams,
          <String, Object?>{'budget': budget},
          where: 'team_id = ?',
          whereArgs: <Object?>[offer.toTeamId],
        );
      }
      return (offer.offerId, player);
    }

    test(
      'loan offers state a 1-2 season length and come from clubs that can pay',
      () async {
        await db.update(t.teams, <String, Object?>{
          'budget': 0,
        }); // nobody can pay
        final Player player = (await squads.squadForTeam(userClub.teamId))
            .first;
        await service.requestLoanOffer(
          userTeamId: userClub.teamId,
          player: player,
        );
        expect(await transfers.pendingOffersForTeam(userClub.teamId), isEmpty);

        await db.update(t.teams, <String, Object?>{'budget': 100000000});
        final (int id, _) = await offerLoan();
        final TransferOffer offer = (await transfers.getOffer(id))!;
        expect(offer.loanSeasons, inInclusiveRange(1, 2));
        final Team borrower = (await ReferenceRepository(db)
            .teamById(offer.toTeamId))!;
        expect(borrower.budget, greaterThanOrEqualTo(offer.offerAmount));
      },
    );

    test('accepting never fails with "not enough budget" when the borrower got poorer', () async {
      await db.update(t.teams, <String, Object?>{'budget': 100000000});
      final (int id, Player player) = await offerLoan(budget: 1);
      expect(await transfers.completeLoan(id), isNull);
      final List<Map<String, Object?>> row = await db.query(
        t.teamPlayers,
        where: 'player_id = ?',
        whereArgs: <Object?>[player.playerId],
      );
      expect(row.first['team_id'], isNot(userClub.teamId));
    });

    test('a loan made mid-season survives the end of that season', () async {
      await db.update(t.teams, <String, Object?>{'budget': 100000000});
      // Play the first matchday so the season counts as "under way".
      final String date = (await service.nextMatchDate(season.seasonId))!;
      await service.simulateMatchday(seasonId: season.seasonId, date: date);

      final (int id, Player player) = await offerLoan();
      await db.update(
        t.transferOffers,
        <String, Object?>{'loan_seasons': 1},
        where: 'offer_id = ?',
        whereArgs: <Object?>[id],
      );
      expect(await transfers.completeLoan(id), isNull);

      Future<int> owner() async =>
          (await db.query(
                t.teamPlayers,
                where: 'player_id = ?',
                whereArgs: <Object?>[player.playerId],
              )).first['team_id']
              as int;

      await service.recallFinishedLoans(season.endYear, userClub.teamId);
      expect(
        await owner(),
        isNot(userClub.teamId),
        reason: 'still on loan after season 1',
      );
      expect(await db.query(t.teamLoans), isNotEmpty);

      await service.recallFinishedLoans(season.endYear + 1, userClub.teamId);
      expect(
        await owner(),
        userClub.teamId,
        reason: 'back after a full season',
      );
      expect(await db.query(t.teamLoans), isEmpty);
    });

    test('a two-season loan stays through two season ends', () async {
      await db.update(t.teams, <String, Object?>{'budget': 100000000});
      final String date = (await service.nextMatchDate(season.seasonId))!;
      await service.simulateMatchday(seasonId: season.seasonId, date: date);
      final (int id, Player player) = await offerLoan();
      await db.update(
        t.transferOffers,
        <String, Object?>{'loan_seasons': 2},
        where: 'offer_id = ?',
        whereArgs: <Object?>[id],
      );
      expect(await transfers.completeLoan(id), isNull);

      await service.recallFinishedLoans(season.endYear + 1, userClub.teamId);
      expect(await db.query(t.teamLoans), isNotEmpty);
      await service.recallFinishedLoans(season.endYear + 2, userClub.teamId);
      expect(await db.query(t.teamLoans), isEmpty);
      expect(player.playerId, isNonZero);
    });
  });
}
