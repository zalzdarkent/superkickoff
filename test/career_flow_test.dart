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
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/formation.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

int? firstInt(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? null : rows.first.values.first as int?;

/// End-to-end simulation of a whole career season: fixtures are generated,
/// every match is played through the real repositories, then the season rolls
/// over into the next one.
void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_flow_');
    final File source = File(p.join('assets', 'data', 'superkickoff_2025.db'));
    final File target = File(p.join(tempDir.path, 'flow.db'));
    await source.copy(target.path);
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

  test('plays a full season and starts the next one', () async {
    const int countryId = 141; // Mexico.
    final List<Map<String, Object?>> leagueRows = await db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ? AND tu.organization = ? AND tu.division_id = 1
      LIMIT 1
    ''',
      <Object?>[countryId, t.orgLeague],
    );
    final List<Map<String, Object?>> cupRows = await db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ? AND tu.organization = ?
      LIMIT 1
    ''',
      <Object?>[countryId, t.orgNationalCup],
    );
    final Tournament league = Tournament.fromMap(leagueRows.first);
    final Tournament cup = Tournament.fromMap(cupRows.first);

    final SeasonGenerator generator = SeasonGenerator(db, random: Random(11));
    final CareerPlan plan = await generator.generateCareer(
      countryId: countryId,
      league: league,
      cup: cup,
    );
    final int seasonId = plan.season.seasonId;

    final ReferenceRepository refs = ReferenceRepository(db);
    final SeasonRepository seasons = SeasonRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final MatchRepository matchRepo = MatchRepository(db);
    final MessageRepository messages = MessageRepository(db);
    final CareerService service = CareerService(
      db,
      refs: refs,
      seasons: seasons,
      squads: squads,
      matches: matchRepo,
      messages: messages,
      engine: MatchEngine(random: Random(11)),
      generator: generator,
      random: Random(11),
      marketTickChance: 0,
    );

    final List<Team> clubs = await refs.teamsForDivision(countryId, 1);
    expect(clubs.length, 18);
    final Team userClub = clubs.first;
    expect(
      await squads.setTicketPrice(
        userClub.teamId,
        seatType: 'general',
        price: 27,
      ),
      isNull,
    );
    expect(
      (await squads.clubOverview(userClub.teamId))?.ticketPriceGeneral,
      27,
    );
    final List<Map<String, Object?>> homeFixtures = await db.query(
      t.matches,
      where: 'season_id = ? AND home_team_id = ? AND status = ?',
      whereArgs: <Object?>[seasonId, userClub.teamId, t.matchScheduled],
      limit: 1,
    );
    expect(homeFixtures, isNotEmpty);
    final MatchInput homeInput = await service.prepareMatchInput(
      FixtureMatch.fromMap(homeFixtures.first),
    );
    expect(homeInput.ticketPriceGeneral, 27);

    final String initialFormation = await squads.formationForTeam(
      userClub.teamId,
    );
    expect(
      Formation.all.map((Formation f) => f.name),
      contains(initialFormation),
    );
    await squads.setFormation(userClub.teamId, '4-2-3-1');
    expect(await squads.formationForTeam(userClub.teamId), '4-2-3-1');
    await db.insert(t.careerHistory, <String, Object?>{
      'team_id': userClub.teamId,
      'season_id': seasonId,
      'country_id': countryId,
    });

    final Map<int, Team> teamCache = <int, Team>{
      for (final Team team in await refs.teamsForCountry(countryId))
        team.teamId: team,
    };

    // Watch one match live so incidents/events are persisted too.
    final String firstDate = (await service.nextMatchDate(seasonId))!;
    final List<FixtureMatch> firstFixtures = await service.matchesOnDate(
      seasonId,
      firstDate,
    );
    final FixtureMatch liveFixture = firstFixtures.firstWhere(
      (FixtureMatch m) =>
          m.homeTeamId == userClub.teamId || m.awayTeamId == userClub.teamId,
    );
    await service.simulateMatch(liveFixture, recordEvents: true);

    // The finished matchday can be read back for the results screen.
    final List<FixtureMatch> dateResults = await service.matchesOnDate(
      seasonId,
      firstDate,
      scheduledOnly: false,
    );
    expect(dateResults.length, firstFixtures.length);
    expect(
      dateResults.any((FixtureMatch m) => m.matchId == liveFixture.matchId),
      isTrue,
    );

    final List<Map<String, Object?>> playedRows = await db.rawQuery(
      'SELECT player_id FROM match_players '
      'WHERE match_id = ? AND minutes > 0 LIMIT 1',
      <Object?>[liveFixture.matchId],
    );
    final PlayerDetail? profile = await squads.playerDetail(
      playedRows.first['player_id'] as int,
      seasonId: seasonId,
    );
    expect(profile, isNotNull);
    expect(profile!.stats.matches, greaterThan(0));
    expect(profile.stats.minutes, greaterThan(0));

    final List<SquadStatRow> teamStats = await squads.squadSeasonStats(
      userClub.teamId,
      seasonId,
    );
    expect(teamStats.length, greaterThan(0));
    expect(teamStats.any((SquadStatRow row) => row.appearances > 0), isTrue);
    expect(teamStats.any((SquadStatRow row) => row.rating > 0), isTrue);

    int matchdays = 0;
    while (!await service.seasonComplete(seasonId)) {
      final String? date = await service.nextMatchDate(seasonId);
      expect(date, isNotNull, reason: 'season incomplete but no fixture date');

      final Map<int, MatchResult> results = await service.simulateMatchday(
        seasonId: seasonId,
        date: date!,
      );
      expect(results, isNotEmpty, reason: 'no fixtures on $date');

      await service.maybeScheduleNextCupRound(
        seasonId: seasonId,
        cupTournamentId: cup.tournamentId,
        teamCache: teamCache,
      );
      await service.weeklyHousekeeping(
        seasonId: seasonId,
        userTeamId: userClub.teamId,
      );
      matchdays++;
      expect(matchdays, lessThan(120), reason: 'season is not converging');
    }
    expect(matchdays, greaterThan(30));

    // ---------------------------------------------------------- standings
    final List<StandingRow> table = await seasons.standings(
      seasonId,
      league.tournamentId,
    );
    expect(table.length, 18);
    expect(table.every((StandingRow row) => row.played == 34), isTrue);
    expect(table.first.points, greaterThanOrEqualTo(table.last.points));

    // --------------------------------------------------------- leaderboards
    final List<LeaderRow> scorers = await seasons.topScorers(
      seasonId,
      league.tournamentId,
    );
    final List<LeaderRow> assists = await seasons.topAssists(
      seasonId,
      league.tournamentId,
    );
    final List<LeaderRow> cleanSheets = await seasons.topCleanSheets(
      seasonId,
      league.tournamentId,
    );
    final List<LeaderRow> rated = await seasons.topRated(
      seasonId,
      league.tournamentId,
    );
    expect(scorers, isNotEmpty);
    expect(scorers.first.value, greaterThan(0));
    expect(assists, isNotEmpty);
    expect(cleanSheets, isNotEmpty);
    expect(rated, isNotEmpty);
    expect(rated.first.value, inInclusiveRange(2.0, 10.0));

    final List<LeaderRow> clubScorers = await seasons.topScorers(
      seasonId,
      league.tournamentId,
      teamId: userClub.teamId,
    );
    final List<LeaderRow> clubRated = await seasons.topRated(
      seasonId,
      league.tournamentId,
      teamId: userClub.teamId,
    );
    expect(clubRated, isNotEmpty);
    expect(
      clubRated.every((LeaderRow r) => r.teamId == userClub.teamId),
      isTrue,
    );
    expect(
      clubScorers.every((LeaderRow r) => r.teamId == userClub.teamId),
      isTrue,
    );

    // ------------------------------------------------------ stored match data
    final int? playerRows = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM match_players'),
    );
    final int? missingTeam = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM match_players WHERE team_id = 0'),
    );
    expect(playerRows, greaterThan(0));
    expect(missingTeam, 0);

    final int? incidents = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM match_incidents'),
    );
    expect(incidents, greaterThan(0));

    // Every cup round produced a single final winner.
    final List<Map<String, Object?>> finalRound = await db.rawQuery(
      '''
      SELECT COUNT(*) AS games FROM matches
      WHERE season_id = ? AND tournament_id = ?
        AND phase = (SELECT MAX(phase) FROM matches
                     WHERE season_id = ? AND tournament_id = ?)
    ''',
      <Object?>[seasonId, cup.tournamentId, seasonId, cup.tournamentId],
    );
    expect(finalRound.first['games'], 1);
    final int? drawnKnockouts = firstInt(
      await db.rawQuery(
        '''
      SELECT COUNT(*) AS draws FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
        AND winner_id IS NULL
    ''',
        <Object?>[seasonId, cup.tournamentId, t.matchFinished],
      ),
    );
    expect(drawnKnockouts, 0, reason: 'cup ties are decided by shootout');

    // --------------------------------------------------------- season rollover
    final List<String> progress = <String>[];
    final Season next = await service.completeSeason(
      userTeamId: userClub.teamId,
      onProgress: progress.add,
    );
    expect(progress, isNotEmpty);
    expect(next.seasonId, isNot(seasonId));
    expect(next.startYear, 2026);

    // The league champion's honours list shows the title just won.
    final List<ClubTrophy> trophies = await seasons.clubTrophies(
      table.first.teamId,
    );
    expect(
      trophies.any(
        (ClubTrophy trophy) =>
            trophy.tournamentId == league.tournamentId &&
            trophy.seasonId == seasonId,
      ),
      isTrue,
    );

    final int? newMatches = firstInt(
      await db.rawQuery(
        'SELECT COUNT(*) FROM matches WHERE season_id = ?',
        <Object?>[next.seasonId],
      ),
    );
    expect(newMatches, greaterThan(300));

    // Relegation must be balanced by promotion so the league never shrinks.
    final int? topDivisionClubs = firstInt(
      await db.rawQuery(
        'SELECT COUNT(*) FROM teams WHERE country_id = ? AND division = 1',
        <Object?>[countryId],
      ),
    );
    expect(topDivisionClubs, 18);

    // Past-season tables stay readable after the rollover.
    final List<StandingRow> archivedTable = await seasons.standings(
      seasonId,
      league.tournamentId,
    );
    expect(archivedTable.length, 18);
    expect(archivedTable.every((StandingRow row) => row.played == 34), isTrue);
    final List<Season> allSeasons = await seasons.allSeasons();
    expect(allSeasons.length, 2);

    // Player career stats were archived before match rows were cleared.
    final int? archived = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM player_season_stats'),
    );
    expect(archived, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
