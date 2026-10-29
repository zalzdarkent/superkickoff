import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

void main() {
  test('Simulate 5 seasons and inspect international fixtures and Persib callups', () async {
    sqfliteFfiInit();
    final tempDir = await Directory.systemTemp.createTemp('superkickoff_5s_');
    final dbPath = '${tempDir.path}/sim_5s.db';
    await File('assets/data/superkickoff_2025.db').copy(dbPath);

    final db = await AppDatabase.openFile(dbPath);
    final refRepo = ReferenceRepository(db);
    final seasonRepo = SeasonRepository(db);
    final squadRepo = SquadRepository(db);
    final matchRepo = MatchRepository(db);
    final msgRepo = MessageRepository(db);
    final engine = MatchEngine();
    final gen = SeasonGenerator(db);

    await squadRepo.refreshAllTeamPowers();

    final userTeamId = 42; // Persib
    final intlCups = await refRepo.internationalCups(94);
    final domesticLeagues = await refRepo.domesticLeagues(94);
    final league = domesticLeagues.first;
    final cupRow = await refRepo.nationalCup(94);
    final cup = Tournament.fromMap(cupRow!);

    final plan = await gen.generateCareer(
      countryId: 94,
      league: league,
      cup: cup,
      internationals: intlCups,
      otherLeagues: domesticLeagues.where((l) => l.tournamentId != league.tournamentId).toList(),
      startYear: 2025,
      userTeamId: userTeamId,
    );

    int currentSeasonId = plan.season.seasonId;
    print('Initial Season ID: $currentSeasonId (2025)');

    final careerService = CareerService(
      db,
      refs: refRepo,
      seasons: seasonRepo,
      squads: squadRepo,
      matches: matchRepo,
      messages: msgRepo,
      engine: engine,
      generator: gen,
    );

    for (int seasonCount = 1; seasonCount <= 5; seasonCount++) {
      print('\n================== SIMULASI MUSIM $seasonCount (Season ID $currentSeasonId) ==================');

      // Check scheduled country matches for this season
      final intlMatches = await db.rawQuery('''
        SELECT cm.tournament_id, tu.name as tournament_name, count(*) as count
        FROM country_matches cm
        LEFT JOIN tournaments tu ON tu.tournament_id = cm.tournament_id
        WHERE cm.season_id = ?
        GROUP BY cm.tournament_id
      ''', [currentSeasonId]);
      print('Jadwal Pertandingan Timnas di Season ID $currentSeasonId: $intlMatches');

      final indoMatches = await db.rawQuery('''
        SELECT cm.match_id, cm.date, cm.tournament_id, hc.name as home, ac.name as away, cm.status
        FROM country_matches cm
        JOIN countries hc ON hc.country_id = cm.home_country_id
        JOIN countries ac ON ac.country_id = cm.away_country_id
        WHERE cm.season_id = ? AND (cm.home_country_id = 94 OR cm.away_country_id = 94)
      ''', [currentSeasonId]);
      print('Pertandingan Timnas Indonesia terdaftar: ${indoMatches.length} laga');
      for (final m in indoMatches.take(5)) {
        print('  - ${m['date']} [Tour ${m['tournament_id']}]: ${m['home']} vs ${m['away']} (Status: ${m['status']})');
      }

      // Check Persib callups
      final persibCallups = await db.rawQuery('''
        SELECT cc.season_id, cc.window_id, p.name as player_name, c.name as country_name
        FROM country_callups cc
        JOIN players p ON p.player_id = cc.player_id
        JOIN team_players tp ON tp.player_id = p.player_id
        JOIN countries c ON c.country_id = cc.country_id
        WHERE tp.team_id = 42 AND cc.season_id = ?
      ''', [currentSeasonId]);
      print('Pemain Persib yang dipanggil ke Timnas: ${persibCallups.length}');
      for (final pc in persibCallups) {
        print('  - ${pc['player_name']} -> ${pc['country_name']} (${pc['window_id']})');
      }

      // If season < 5, generate next season
      if (seasonCount < 5) {
        final nextSeason = await careerService.finishSeason(
          currentSeason: Season(seasonId: currentSeasonId, startYear: 2024 + seasonCount, status: 1),
          userTeamId: userTeamId,
          onProgress: (p) {},
        );
        currentSeasonId = nextSeason.seasonId;
      }
    }

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
