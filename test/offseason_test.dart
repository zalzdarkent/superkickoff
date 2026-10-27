import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
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
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/offseason.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_offseason_');
    final File target = File(p.join(tempDir.path, 'offseason.db'));
    await File(p.join('assets', 'data', 'superkickoff_2025.db'))
        .copy(target.path);
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

  test('off-season runs in order and then starts the next season', () async {
    const int countryId = 141;
    Future<Tournament> tour(int org, {int? division}) async =>
        Tournament.fromMap(
          (await db.rawQuery(
            '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ? AND tu.organization = ?
        AND (? IS NULL OR tu.division_id = ?) LIMIT 1
    ''',
            <Object?>[countryId, org, division, division],
          )).first,
        );
    final Tournament league = await tour(t.orgLeague, division: 1);
    final Tournament cup = await tour(t.orgNationalCup);

    final SeasonGenerator generator = SeasonGenerator(db, random: Random(5));
    final CareerPlan plan = await generator.generateCareer(
      countryId: countryId,
      league: league,
      cup: cup,
    );
    final int seasonId = plan.season.seasonId;
    final ReferenceRepository refs = ReferenceRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final CareerService service = CareerService(
      db,
      refs: refs,
      seasons: SeasonRepository(db),
      squads: squads,
      matches: MatchRepository(db),
      messages: MessageRepository(db),
      engine: MatchEngine(random: Random(5)),
      generator: generator,
      random: Random(5),
      marketTickChance: 0,
    );
    final Team user = (await refs.teamsForDivision(countryId, 1)).first;
    await db.insert(t.careerHistory, <String, Object?>{
      'team_id': user.teamId,
      'season_id': seasonId,
      'country_id': countryId,
    });
    final Map<int, Team> teamCache = <int, Team>{
      for (final Team team in await refs.teamsForCountry(countryId))
        team.teamId: team,
    };
    while (!await service.seasonComplete(seasonId)) {
      await service.simulateMatchday(
        seasonId: seasonId,
        date: (await service.nextMatchDate(seasonId))!,
      );
      await service.maybeScheduleNextCupRound(
        seasonId: seasonId,
        cupTournamentId: cup.tournamentId,
        teamCache: teamCache,
      );
    }

    Future<String?> next() =>
        service.advanceOffseason(userTeamId: user.teamId, onProgress: (_) {});

    // 1. Summary: nothing is created yet, the old season is still current.
    OffseasonState state = await service.beginOffseason(
      userTeamId: user.teamId,
      onProgress: (_) {},
    );
    expect(state.current, OffseasonStep.summary);
    expect(state.reportLines.any((String l) => l.contains('Finished')), isTrue);
    expect(await db.query(t.seasons), hasLength(1));

    // 2. Contracts: AI deals roll over, user's expiring ones are listed.
    expect(await next(), isNull);
    state = (await service.offseasonState())!;
    expect(state.current, OffseasonStep.contracts);
    final int endYear = plan.season.endYear;
    final List<ExpiringContract> expiring = await service.expiringContracts(
      user.teamId,
      endYear,
    );
    expect(expiring, isNotEmpty);
    final int aiExpired = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM contracts WHERE status = 1 AND team_id != ? '
        'AND CAST(substr(end_date, 1, 4) AS INTEGER) <= ?',
        <Object?>[user.teamId, endYear],
      ),
    )!;
    expect(aiExpired, 0);
    final int keepId = expiring.first.player.playerId;
    expect(
      await squads.renewContract(
        playerId: keepId,
        teamId: user.teamId,
        currentYear: endYear,
      ),
      isNull,
    );
    final int leaveId = expiring.last.player.playerId;

    // 3. Development: the unrenewed player left, the renewed one stayed.
    expect(await next(), isNull);
    expect(
      (await service.offseasonState())!.current,
      OffseasonStep.development,
    );
    final List<Player> squad = await squads.squadForTeam(user.teamId);
    expect(squad.any((Player pl) => pl.playerId == keepId), isTrue);
    if (expiring.length > 1) {
      expect(squad.any((Player pl) => pl.playerId == leaveId), isFalse);
    }

    // 4. Transfer window: cannot leave while it is open.
    expect(await next(), isNull);
    expect(await next(), contains('transfer window'));
    await service.advanceTransferWindow(user.teamId);
    expect((await service.offseasonState())!.windowWeeks, 3);
    await service.advanceTransferWindow(user.teamId, toDeadline: true);
    expect((await service.offseasonState())!.windowWeeks, 0);

    // 5. Pre-season: a camp is required.
    expect(await next(), isNull);
    expect(await next(), contains('camp'));
    expect(
      await service.choosePreseasonCamp(user.teamId, PreseasonCamp.rest),
      isNull,
    );
    expect(
      await service.choosePreseasonCamp(user.teamId, PreseasonCamp.tour),
      contains('already'),
    );

    // 6. Board: an objective is required.
    expect(await next(), isNull);
    expect(await next(), contains('objective'));
    final List<BoardOption> options = await service.boardOptions(user.teamId);
    expect(options, hasLength(3));
    final BoardOption balancedOption = options.singleWhere(
      (BoardOption option) => option.ambition == BoardAmbition.balanced,
    );
    final List<StandingRow> finalTable = await SeasonRepository(db)
        .standings(seasonId, league.tournamentId);
    final int actualRank =
        finalTable.indexWhere((StandingRow row) => row.teamId == user.teamId) +
        1;
    final List<int> rankedByPower = finalTable
        .map((StandingRow row) => row.teamId)
        .toList();
    final List<Map<String, Object?>> powerRows = await db.query(
      t.teams,
      columns: <String>['team_id'],
      where:
          'team_id IN (${List<String>.filled(rankedByPower.length, '?').join(',')})',
      whereArgs: rankedByPower,
      orderBy: 'power DESC, team_id ASC',
    );
    final int expectedRank =
        powerRows.indexWhere(
          (Map<String, Object?> row) => row['team_id'] == user.teamId,
        ) +
        1;
    final Team boardTeam = (await refs.teamById(user.teamId))!;
    final double performanceMultiplier =
        (1 + (expectedRank - actualRank) / (finalTable.length - 1)).clamp(
          0.5,
          1.5,
        );
    expect(
      balancedOption.managementGrant,
      (max(300000, boardTeam.budget * 0.05) * performanceMultiplier).round(),
      reason:
          'budget=${boardTeam.budget}, actualRank=$actualRank, expectedRank=$expectedRank, '
          'tableSize=${finalTable.length}, grant=${balancedOption.managementGrant}',
    );
    final int budgetBeforeBoard = boardTeam.budget;
    expect(
      await service.chooseBoardAmbition(user.teamId, BoardAmbition.balanced),
      isNull,
    );
    final Team boardTeamAfter = (await refs.teamById(user.teamId))!;
    expect(
      boardTeamAfter.budget - budgetBeforeBoard,
      balancedOption.advance + balancedOption.managementGrant,
    );
    expect(
      (await service.offseasonState())!.report,
      contains('management grant'),
    );

    // 7. New season.
    expect(await next(), isNull);
    expect((await service.offseasonState())!.current, OffseasonStep.newSeason);
    final Season newSeason = await service.startNextSeason(
      userTeamId: user.teamId,
      onProgress: (_) {},
    );
    expect(newSeason.seasonId, isNot(seasonId));
    expect(newSeason.startYear, plan.season.startYear + 1);
    expect(await service.offseasonState(), isNull);
    final List<Map<String, Object?>> objective = await db.query(
      t.boardObjectives,
      where: 'start_year = ?',
      whereArgs: <Object?>[newSeason.startYear],
    );
    expect(objective, hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
