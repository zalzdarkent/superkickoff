import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';

void main() {
  test('academy graduates 5-9 players every three months', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final Directory dir = await Directory.systemTemp.createTemp('academy_test_');
    final String path = p.join(dir.path, 'game.db');
    await File(p.join('assets', 'data', 'superkickoff_2025.db')).copy(path);
    final Database db = await databaseFactory.openDatabase(path);
    await AppDatabase.ensureLocalTables(db);
    final SquadRepository squads = SquadRepository(db);

    expect((await squads.youthAcademyState(42)).level, 1);
    expect(await squads.upgradeYouthAcademy(42), isNull);
    expect((await squads.youthAcademyState(42)).level, 2);

    expect(
      await squads.graduateYouthPlayersIfDue(teamId: 42, date: '2026-01-01'),
      isEmpty,
    );
    expect(
      await squads.graduateYouthPlayersIfDue(teamId: 42, date: '2026-02-15'),
      isEmpty,
    );

    final List<YouthProspect> graduates = await squads.graduateYouthPlayersIfDue(
      teamId: 42,
      date: '2026-04-05',
    );
    expect(graduates.length, inInclusiveRange(5, 9));
    for (final YouthProspect player in graduates) {
      expect(player.age, 17);
      expect(player.name, isNot(startsWith('Academy Prospect')));
      expect(player.power, inInclusiveRange(46, 49));
    }
    // Sign one prospect and verify they join the squad
    final Player? signed = await squads.signProspect(graduates.first.prospectId);
    expect(signed, isNotNull);
    expect(signed!.name, graduates.first.name);

    final List<Player> squad = await squads.squadForTeam(42);
    expect(squad.any((Player p) => p.playerId == signed.playerId), isTrue);

    final YouthProspect rejectedProspect = graduates[1];
    expect(
      await squads.rejectProspect(
        prospectId: rejectedProspect.prospectId,
        teamId: 551,
      ),
      isFalse,
    );
    expect(
      await squads.rejectProspect(
        prospectId: rejectedProspect.prospectId,
        teamId: 42,
      ),
      isTrue,
    );
    final List<YouthProspect> pending = await squads.pendingProspects(42);
    expect(
      pending.any(
        (YouthProspect prospect) =>
            prospect.prospectId == rejectedProspect.prospectId,
      ),
      isFalse,
    );

    expect(
      await squads.graduateYouthPlayersIfDue(teamId: 42, date: '2026-05-01'),
      isEmpty,
    );

    await db.close();
    await dir.delete(recursive: true);
  });
}
