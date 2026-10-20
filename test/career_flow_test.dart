import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/career_service.dart';
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
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('plays a full season and starts the next one', () async {
    const int countryId = 141; // Mexico.
    final List<Map<String, Object?>> leagueRows = await db.rawQuery('''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ? AND tu.organization = ? AND tu.division_id = 1
      LIMIT 1
    ''', <Object?>[countryId, t.orgLeague]);
    final List<Map<String, Object?>> cupRows = await db.rawQuery('''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ? AND tu.organization = ?
      LIMIT 1
    ''', <Object?>[countryId, t.orgNationalCup]);
    final Tournament league = Tournament.fromMap(leagueRows.first);
    final Tournament cup = Tournament.fromMap(cupRows.first);

    // ignore: avoid_print
    print('generating career...');
    final SeasonGenerator generator =
        SeasonGenerator(db, random: Random(11));
    final CareerPlan plan = await generator.generateCareer(
      countryId: countryId,
      league: league,
      cup: cup,
    );
    final int seasonId = plan.season.seasonId;
    // ignore: avoid_print
    print('career generated: season $seasonId, ${plan.matchCount} league matches');

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
    await db.insert(t.careerHistory, <String, Object?>{
      'team_id': userClub.teamId,
      'season_id': seasonId,
      'country_id': countryId,
    });

    final Map<int, Team> teamCache = <int, Team>{
      for (final Team team in await refs.teamsForCountry(countryId))
        team.teamId: team,
    };

    int matchdays = 0;
    while (!await service.seasonComplete(seasonId)) {
      final String? date = await service.nextMatchDate(seasonId);
      expect(date, isNotNull, reason: 'season incomplete but no fixture date');

      // ignore: avoid_print
      print('matchday $matchdays date=$date');
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
    // ignore: avoid_print
    print('season finished after $matchdays matchdays');

    // ---------------------------------------------------------- standings
    final List<StandingRow> table =
        await seasons.standings(seasonId, league.tournamentId);
    expect(table.length, 18);
    expect(table.every((StandingRow row) => row.played == 34), isTrue);
    expect(table.first.points, greaterThanOrEqualTo(table.last.points));

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
    final List<Map<String, Object?>> finalRound = await db.rawQuery('''
      SELECT COUNT(*) AS games FROM matches
      WHERE season_id = ? AND tournament_id = ?
        AND phase = (SELECT MAX(phase) FROM matches
                     WHERE season_id = ? AND tournament_id = ?)
    ''', <Object?>[
      seasonId,
      cup.tournamentId,
      seasonId,
      cup.tournamentId,
    ]);
    expect(finalRound.first['games'], 1);

    // --------------------------------------------------------- season rollover
    final List<String> progress = <String>[];
    // ignore: avoid_print
    print('starting season rollover...');
    final Season next = await service.completeSeason(
      userTeamId: userClub.teamId,
      onProgress: progress.add,
    );
    expect(progress, isNotEmpty);
    expect(next.seasonId, isNot(seasonId));
    expect(next.startYear, 2026);

    final int? newMatches = firstInt(await db.rawQuery(
      'SELECT COUNT(*) FROM matches WHERE season_id = ?',
      <Object?>[next.seasonId],
    ));
    expect(newMatches, greaterThan(300));

    // Player career stats were archived before match rows were cleared.
    final int? archived = firstInt(
      await db.rawQuery('SELECT COUNT(*) FROM player_season_stats'),
    );
    expect(archived, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
