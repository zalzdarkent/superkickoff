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
import 'package:superkickoff/data/repositories/prize_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/scouting_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/data/repositories/sponsorship_repository.dart';
import 'package:superkickoff/data/repositories/transfer_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  late Directory tempDir;
  late Database db;
  late CareerService service;
  late int seasonId;
  late int userTeamId;
  late int aiTeamId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_ai_train_');
    final File source = File(p.join('assets', 'data', 'superkickoff_2025.db'));
    final File target = File(p.join(tempDir.path, 'ai_train.db'));
    await source.copy(target.path);
    db = await databaseFactory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await AppDatabase.ensureLocalTables(db);

    final ReferenceRepository refs = ReferenceRepository(db);
    final SeasonRepository seasons = SeasonRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final MatchRepository matchRepo = MatchRepository(db);
    final MessageRepository messages = MessageRepository(db);
    final PrizeRepository prizes = PrizeRepository(db);
    final TransferRepository transfers = TransferRepository(db);
    final SponsorshipRepository sponsorships = SponsorshipRepository(db);
    final ScoutingRepository scouting = ScoutingRepository(db);

    final SeasonGenerator generator = SeasonGenerator(db, random: Random(42));
    const int countryId = 141;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ? AND tu.organization = ? AND tu.division_id = ?
      LIMIT 1
    ''',
      <Object?>[countryId, t.orgLeague, 1],
    );
    final Tournament league = Tournament.fromMap(rows.first);

    final CareerPlan plan = await generator.generateCareer(
      countryId: countryId,
      league: league,
      cup: null,
      startYear: 2025,
    );
    seasonId = plan.season.seasonId;

    final List<Team> teams = await refs.teamsForDivision(countryId, 1);
    userTeamId = teams[0].teamId;
    aiTeamId = teams[1].teamId;

    service = CareerService(
      db,
      refs: refs,
      seasons: seasons,
      squads: squads,
      matches: matchRepo,
      messages: messages,
      prizes: prizes,
      transfers: transfers,
      sponsorships: sponsorships,
      scouting: scouting,
      engine: MatchEngine(),
      generator: generator,
      random: Random(42),
    );
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('AI clubs run automated weekly training with player development', () async {
    // 1. Give an AI player headroom to grow: potential > power
    final List<Map<String, Object?>> aiPlayers = await db.rawQuery(
      '''
      SELECT p.player_id, p.power, p.potential, p.value
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
      LIMIT 3
    ''',
      <Object?>[aiTeamId, t.statusActive],
    );
    expect(aiPlayers, isNotEmpty);

    final int targetPlayerId = aiPlayers.first['player_id'] as int;
    final int initialPower = 60;
    final int initialPotential = 78;
    final int initialValue = 500000;

    await db.update(
      t.players,
      <String, Object?>{
        'power': initialPower,
        'potential': initialPotential,
        'value': initialValue,
      },
      where: 'player_id = ?',
      whereArgs: <Object?>[targetPlayerId],
    );

    // 2. Also record a user player to ensure user players are untouched by AI training
    final List<Map<String, Object?>> userPlayers = await db.rawQuery(
      '''
      SELECT p.player_id, p.power
      FROM players p
      JOIN team_players tp ON tp.player_id = p.player_id
      WHERE tp.team_id = ? AND p.status_id = ?
      LIMIT 1
    ''',
      <Object?>[userTeamId, t.statusActive],
    );
    final int userPlayerId = userPlayers.first['player_id'] as int;
    final int userPowerBefore = (userPlayers.first['power'] as int?) ?? 65;

    // 3. Run AI training session
    final int improvedCount = await service.runAiTraining(
      userTeamId: userTeamId,
      seasonId: seasonId,
    );

    expect(improvedCount, greaterThan(0));

    // 4. Verify AI target player gained power and value
    final List<Map<String, Object?>> afterRows = await db.query(
      t.players,
      columns: <String>['power', 'value'],
      where: 'player_id = ?',
      whereArgs: <Object?>[targetPlayerId],
    );
    final int powerAfter = afterRows.first['power'] as int;
    final int valueAfter = afterRows.first['value'] as int;

    expect(powerAfter, greaterThanOrEqualTo(initialPower));
    expect(powerAfter, lessThanOrEqualTo(initialPotential));
    expect(valueAfter, greaterThanOrEqualTo(initialValue));

    // 5. User player was NOT modified by AI training
    final List<Map<String, Object?>> userAfterRows = await db.query(
      t.players,
      columns: <String>['power'],
      where: 'player_id = ?',
      whereArgs: <Object?>[userPlayerId],
    );
    expect(userAfterRows.first['power'], userPowerBefore);
  });
}
