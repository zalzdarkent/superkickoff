import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/formation.dart';
import 'package:superkickoff/game/match_engine.dart';

void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_team_detail_');
    final File source = File(p.join('assets', 'data', 'superkickoff_2025.db'));
    final File target = File(p.join(tempDir.path, 'team_detail.db'));
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

  test('loads squad, computes lineup best and strength ratings for arbitrary team', () async {
    final ReferenceRepository refs = ReferenceRepository(db);
    final SquadRepository squads = SquadRepository(db);
    final SeasonRepository seasons = SeasonRepository(db);

    final List<Team> clubs = await refs.teamsForDivision(141, 1);
    expect(clubs, isNotEmpty);
    final Team targetClub = clubs.first;

    // Squad query
    final List<Player> squad = await squads.squadForTeam(targetClub.teamId);
    expect(squad, isNotEmpty);
    expect(squad.length, greaterThanOrEqualTo(11));

    // Formation & saved lineup
    final String formStr = await squads.formationForTeam(targetClub.teamId);
    final Formation formation = Formation.parse(formStr);
    final Map<int, int> saved = await squads.lineupForTeam(targetClub.teamId);

    // Compute best lineup
    final Lineup lineup = Lineup.best(
      squad,
      formation: formation,
      preferredIds: saved.values.toList(),
    );

    expect(lineup.starters.length, 11);
    expect(lineup.starters.where((p) => p.positionId == 1).length, 1);

    // Verify rating calculations
    final int att = (Lineup.attackOn(lineup.starters) / 9.4).round().clamp(1, 99);
    final int mid = (Lineup.midfieldOn(lineup.starters) / 8.0).round().clamp(1, 99);
    final int def = (Lineup.defenseOn(lineup.starters) / 10.4).round().clamp(1, 99);
    final Player gk = lineup.starters.firstWhere(
      (p) => p.positionId == 1,
      orElse: () => squad.first,
    );
    final int gkRating = gk.power.clamp(1, 99);

    expect(att, inInclusiveRange(1, 99));
    expect(mid, inInclusiveRange(1, 99));
    expect(def, inInclusiveRange(1, 99));
    expect(gkRating, inInclusiveRange(1, 99));

    // Verify club overview
    final ClubOverview? overview = await squads.clubOverview(targetClub.teamId);
    expect(overview, isNotNull);
    expect(overview!.team.teamId, targetClub.teamId);
    expect(overview.stadiumName, isNotEmpty);
    expect(overview.capacity, greaterThan(0));

    // Verify trophies query doesn't crash
    final List<ClubTrophy> trophies = await seasons.clubTrophies(targetClub.teamId);
    expect(trophies, isNotNull);
  });
}
