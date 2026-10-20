import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Seasons, fixtures, standings and season lifecycle.
class SeasonRepository {
  SeasonRepository(this.db);

  final Database db;

  Future<bool> hasCareer() async {
    final int? count = Sqflite.firstIntValue(
      await db.query(t.seasons, columns: ['COUNT(*)']),
    );
    return (count ?? 0) > 0;
  }

  /// Current (newest) season.
  Future<Season?> currentSeason() async {
    final rows = await db.query(t.seasons, orderBy: 'season_id DESC', limit: 1);
    return rows.isEmpty ? null : Season.fromMap(rows.first);
  }

  Future<Season> insertSeason({
    required int startYear,
    required int endYear,
    required String name,
  }) async {
    return Season.fromMap(await db.insert(
      t.seasons,
      <String, Object?>{
        'name': name,
        'start_year': startYear,
        'end_year': endYear,
      },
      // sqflite returns only the row id, so read the row back.
    ).then((id) async {
      final rows = await db.query(t.seasons,
          where: 'season_id = ?', whereArgs: <Object?>[id], limit: 1);
      return rows.first;
    }));
  }

  Future<void> linkSeasonTournament(int seasonId, int tournamentId) =>
      db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': seasonId,
        'tournament_id': tournamentId,
        'status': t.seasonTournamentActive,
      });

  /// Players linked to a season: one row per team participating in ANY
  /// competition of the season (league + cup share one membership table).
  Future<void> addSeasonTeams(int seasonId, List<int> teamIds, int coachId) async {
    await db.transaction((Transaction txn) async {
      for (final int teamId in teamIds) {
        await txn.insert(t.seasonTeams, <String, Object?>{
          'team_id': teamId,
          'season_id': seasonId,
          'coach_id': coachId,
        });
      }
    });
  }

  Future<void> addMatches(List<Map<String, Object?>> rows) =>
      db.transaction((Transaction txn) async {
        for (final Map<String, Object?> row in rows) {
          await txn.insert(t.matches, row);
        }
      });

  /// All fixtures of a season, ordered by date then round.
  Future<List<FixtureMatch>> fixturesForSeason(int seasonId,
      {int? tournamentId}) async {
    final rows = await db.query(
      t.matches,
      where: tournamentId == null
          ? 'season_id = ?'
          : 'season_id = ? AND tournament_id = ?',
      whereArgs: tournamentId == null
          ? <Object?>[seasonId]
          : <Object?>[seasonId, tournamentId],
      orderBy: 'date ASC, match_id ASC',
    );
    return rows.map(FixtureMatch.fromMap).toList();
  }

  Future<FixtureMatch?> matchById(int matchId) async {
    final rows = await db
        .query(t.matches, where: 'match_id = ?', whereArgs: <Object?>[matchId], limit: 1);
    return rows.isEmpty ? null : FixtureMatch.fromMap(rows.first);
  }

  /// Count of scheduled matches left for a tournament.
  Future<int> remainingMatches(int seasonId, int tournamentId) async {
    final int? c = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
    ''', <Object?>[seasonId, tournamentId, t.matchScheduled]));
    return c ?? 0;
  }

  /// League standings computed from played matches of [tournamentId].
  Future<List<StandingRow>> standings(int seasonId, int tournamentId) async {
    final List<StandingRow> rows = <StandingRow>[];
    final Map<int, StandingRow> byTeam = <int, StandingRow>{};
    final teamRows = await db.rawQuery('''
      SELECT tm.team_id, tm.name, tm.abbreviation
      FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ? AND st.team_id IN (
        SELECT home_team_id FROM matches
        WHERE season_id = ? AND tournament_id = ?
        UNION SELECT away_team_id FROM matches
        WHERE season_id = ? AND tournament_id = ?
      )
    ''', <Object?>[seasonId, seasonId, tournamentId, seasonId, tournamentId]);
    for (final Map<String, Object?> r in teamRows) {
      final StandingRow row = StandingRow(
        teamId: r['team_id'] as int,
        name: r['name'] as String,
        abbreviation: r['abbreviation'] as String? ?? '',
        played: 0, wins: 0, draws: 0, losses: 0,
        goalsFor: 0, goalsAgainst: 0, points: 0,
      );
      byTeam[row.teamId] = row;
      rows.add(row);
    }
    final matches = await db.rawQuery('''
      SELECT home_team_id, away_team_id, home_goals, away_goals
      FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
        AND home_goals IS NOT NULL AND away_goals IS NOT NULL
    ''', <Object?>[seasonId, tournamentId, t.matchFinished]);
    for (final Map<String, Object?> m in matches) {
      final int home = m['home_team_id'] as int;
      final int away = m['away_team_id'] as int;
      final int hg = (m['home_goals'] as int?) ?? 0;
      final int ag = (m['away_goals'] as int?) ?? 0;
      final homeRow = byTeam[home];
      final awayRow = byTeam[away];
      if (homeRow == null || awayRow == null) continue;
      homeRow.played++; homeRow.goalsFor += hg; homeRow.goalsAgainst += ag;
      awayRow.played++; awayRow.goalsFor += ag; awayRow.goalsAgainst += hg;
      if (hg > ag) {
        homeRow.wins++; homeRow.points += 3;
        awayRow.losses++;
      } else if (hg < ag) {
        awayRow.wins++; awayRow.points += 3;
        homeRow.losses++;
      } else {
        homeRow.draws++; awayRow.draws++;
        homeRow.points++; awayRow.points++;
      }
    }
    rows.sort((StandingRow a, StandingRow b) {
      if (b.points != a.points) return b.points.compareTo(a.points);
      if (b.goalDifference != a.goalDifference) {
        return b.goalDifference.compareTo(a.goalDifference);
      }
      return b.goalsFor.compareTo(a.goalsFor);
    });
    return rows;
  }

  /// Marks a league/cup season table as archived, firing the clear triggers.
  Future<void> archiveSeasonTournament(int seasonId, int tournamentId) async {
    final updated = await db.update(
      t.seasonTournaments,
      <String, Object?>{'status': t.seasonTournamentArchived},
      where: 'season_id = ? AND tournament_id = ? AND status = ?',
      whereArgs: <Object?>[seasonId, tournamentId, t.seasonTournamentActive],
    );
    if (updated == 0) return;
  }

  /// Ages every active player by one year, retiring the oldest ones.
  Future<void> ageSquad() => db.execute('''
        UPDATE players SET age = age + 1 WHERE status_id = ?
      ''', <Object?>[t.statusActive]);
}
