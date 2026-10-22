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

  /// Every season of the save, newest first, including archived ones.
  Future<List<Season>> allSeasons() async {
    final rows = await db.query(t.seasons, orderBy: 'season_id DESC');
    return rows.map(Season.fromMap).toList();
  }

  /// Competitions played in a season, active or archived.
  Future<List<Tournament>> tournamentsForSeason(int seasonId) async {
    final rows = await db.rawQuery(
      '''
      SELECT tu.* FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      WHERE st.season_id = ?
      ORDER BY tu.organization ASC, tu.tournament_id ASC
    ''',
      <Object?>[seasonId],
    );
    return rows.map(Tournament.fromMap).toList();
  }

  Future<Season> insertSeason({
    required int startYear,
    required int endYear,
    required String name,
  }) async {
    return Season.fromMap(
      await db
          .insert(
            t.seasons,
            <String, Object?>{
              'name': name,
              'start_year': startYear,
              'end_year': endYear,
            },
            // sqflite returns only the row id, so read the row back.
          )
          .then((id) async {
            final rows = await db.query(
              t.seasons,
              where: 'season_id = ?',
              whereArgs: <Object?>[id],
              limit: 1,
            );
            return rows.first;
          }),
    );
  }

  Future<void> linkSeasonTournament(int seasonId, int tournamentId) =>
      db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': seasonId,
        'tournament_id': tournamentId,
        'status': t.seasonTournamentActive,
      });

  /// Players linked to a season: one row per team participating in ANY
  /// competition of the season (league + cup share one membership table).
  Future<void> addSeasonTeams(
    int seasonId,
    List<int> teamIds,
    int coachId,
  ) async {
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
  Future<List<FixtureMatch>> fixturesForSeason(
    int seasonId, {
    int? tournamentId,
  }) async {
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
    final rows = await db.query(
      t.matches,
      where: 'match_id = ?',
      whereArgs: <Object?>[matchId],
      limit: 1,
    );
    return rows.isEmpty ? null : FixtureMatch.fromMap(rows.first);
  }

  /// Count of scheduled matches left for a tournament.
  Future<int> remainingMatches(int seasonId, int tournamentId) async {
    final int? c = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
      SELECT COUNT(*) FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
    ''',
        <Object?>[seasonId, tournamentId, t.matchScheduled],
      ),
    );
    return c ?? 0;
  }

  /// League standings computed from played matches of [tournamentId].
  /// Pass [groupId] to read a single group of a cup group stage.
  Future<List<StandingRow>> standings(
    int seasonId,
    int tournamentId, {
    int? groupId,
  }) async {
    final String groupFilter = groupId == null ? '' : ' AND group_id = ?';
    final List<Object?> groupArgs = groupId == null
        ? <Object?>[]
        : <Object?>[groupId];
    final List<StandingRow> rows = <StandingRow>[];
    final Map<int, StandingRow> byTeam = <int, StandingRow>{};
    final teamRows = await db.rawQuery(
      '''
      SELECT tm.team_id, tm.name, tm.abbreviation
      FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ? AND st.team_id IN (
        SELECT home_team_id FROM matches
        WHERE season_id = ? AND tournament_id = ?$groupFilter
        UNION SELECT away_team_id FROM matches
        WHERE season_id = ? AND tournament_id = ?$groupFilter
      )
    ''',
      <Object?>[
        seasonId,
        seasonId,
        tournamentId,
        ...groupArgs,
        seasonId,
        tournamentId,
        ...groupArgs,
      ],
    );
    for (final Map<String, Object?> r in teamRows) {
      final StandingRow row = StandingRow(
        teamId: r['team_id'] as int,
        name: r['name'] as String,
        abbreviation: r['abbreviation'] as String? ?? '',
        played: 0,
        wins: 0,
        draws: 0,
        losses: 0,
        goalsFor: 0,
        goalsAgainst: 0,
        points: 0,
      );
      byTeam[row.teamId] = row;
      rows.add(row);
    }
    final matches = await db.rawQuery(
      '''
      SELECT home_team_id, away_team_id, home_goals, away_goals
      FROM matches
      WHERE season_id = ? AND tournament_id = ? AND status = ?
        AND home_goals IS NOT NULL AND away_goals IS NOT NULL$groupFilter
    ''',
      <Object?>[seasonId, tournamentId, t.matchFinished, ...groupArgs],
    );
    for (final Map<String, Object?> m in matches) {
      final int home = m['home_team_id'] as int;
      final int away = m['away_team_id'] as int;
      final int hg = (m['home_goals'] as int?) ?? 0;
      final int ag = (m['away_goals'] as int?) ?? 0;
      final homeRow = byTeam[home];
      final awayRow = byTeam[away];
      if (homeRow == null || awayRow == null) continue;
      homeRow.played++;
      homeRow.goalsFor += hg;
      homeRow.goalsAgainst += ag;
      awayRow.played++;
      awayRow.goalsFor += ag;
      awayRow.goalsAgainst += hg;
      if (hg > ag) {
        homeRow.wins++;
        homeRow.points += 3;
        awayRow.losses++;
      } else if (hg < ag) {
        awayRow.wins++;
        awayRow.points += 3;
        homeRow.losses++;
      } else {
        homeRow.draws++;
        awayRow.draws++;
        homeRow.points++;
        awayRow.points++;
      }
    }
    rows.sort((StandingRow a, StandingRow b) {
      if (b.points != a.points) return b.points.compareTo(a.points);
      if (b.goalDifference != a.goalDifference) {
        return b.goalDifference.compareTo(a.goalDifference);
      }
      if (b.goalsFor != a.goalsFor) return b.goalsFor.compareTo(a.goalsFor);
      // Level on everything (e.g. before kick-off): alphabetical.
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return rows;
  }

  /// Every group table of a tournament, ordered by group id.
  Future<List<GroupTable>> groupTables(int seasonId, int tournamentId) async {
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT group_id FROM matches
      WHERE season_id = ? AND tournament_id = ? AND group_id IS NOT NULL
      ORDER BY group_id
    ''',
      <Object?>[seasonId, tournamentId],
    );
    final List<GroupTable> tables = <GroupTable>[];
    for (final Map<String, Object?> row in rows) {
      final int groupId = row['group_id'] as int;
      tables.add(
        GroupTable(
          groupId: groupId,
          rows: await standings(seasonId, tournamentId, groupId: groupId),
        ),
      );
    }
    return tables;
  }

  // ------------------------------------------------------------ leaderboards

  /// Top scorers of a tournament in a season. Pass [teamId] to restrict the
  /// list to a single club.
  Future<List<LeaderRow>> topScorers(
    int seasonId,
    int tournamentId, {
    int limit = 20,
    int? teamId,
  }) => _leaders(
    seasonId: seasonId,
    tournamentId: tournamentId,
    teamId: teamId,
    aggregate: 'SUM(mp.goals)',
    having: 'SUM(mp.goals) > 0',
    limit: limit,
  );

  /// Top assist providers of a tournament in a season.
  Future<List<LeaderRow>> topAssists(
    int seasonId,
    int tournamentId, {
    int limit = 20,
    int? teamId,
  }) => _leaders(
    seasonId: seasonId,
    tournamentId: tournamentId,
    teamId: teamId,
    aggregate: 'SUM(mp.assists)',
    having: 'SUM(mp.assists) > 0',
    limit: limit,
  );

  /// Best average match rating, requiring at least one full match played.
  Future<List<LeaderRow>> topRated(
    int seasonId,
    int tournamentId, {
    int limit = 20,
    int? teamId,
  }) => _leaders(
    seasonId: seasonId,
    tournamentId: tournamentId,
    teamId: teamId,
    aggregate: 'AVG(mp.rating) / 10.0',
    having: 'SUM(mp.minutes) >= 90',
    limit: limit,
    orderBy: 'total DESC, SUM(mp.minutes) DESC',
  );

  /// Goalkeepers with the most clean sheets.
  Future<List<LeaderRow>> topCleanSheets(
    int seasonId,
    int tournamentId, {
    int limit = 20,
    int? teamId,
  }) async {
    final String teamClause = teamId == null ? '' : ' AND mp.team_id = ?';
    final List<Object?> args = <Object?>[
      seasonId,
      tournamentId,
      t.matchFinished,
    ];
    if (teamId != null) args.add(teamId);
    args.add(limit);
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT p.player_id,
             p.name AS player_name,
             p.position_id,
             MAX(p.profile) AS profile,
             MAX(tm.name) AS club_name,
             MAX(mp.team_id) AS team_id,
             COUNT(*) AS total
      FROM match_players mp
      JOIN matches m ON m.match_id = mp.match_id
      JOIN players p ON p.player_id = mp.player_id
      JOIN teams tm ON tm.team_id = mp.team_id
      WHERE m.season_id = ? AND m.tournament_id = ? AND m.status = ?
        AND mp.minutes > 0
        AND p.position_id = 1
        AND ((mp.team_id = m.home_team_id AND m.away_goals = 0)
          OR (mp.team_id = m.away_team_id AND m.home_goals = 0))$teamClause
      GROUP BY p.player_id
      ORDER BY total DESC, p.name ASC
      LIMIT ?
    ''', args);
    return <LeaderRow>[
      for (final Map<String, Object?> row in rows)
        LeaderRow(
          playerId: row['player_id'] as int,
          playerName: row['player_name'] as String,
          clubName: (row['club_name'] as String?) ?? '',
          positionId: (row['position_id'] as int?) ?? 1,
          teamId: (row['team_id'] as int?) ?? 0,
          profile: (row['profile'] as String?) ?? 'D',
          value: ((row['total'] as num?) ?? 0).toDouble(),
        ),
    ];
  }

  Future<List<LeaderRow>> _leaders({
    required int seasonId,
    required int tournamentId,
    required String aggregate,
    required String having,
    required int limit,
    int? teamId,
    String orderBy = 'total DESC, p.name ASC',
  }) async {
    final String teamClause = teamId == null ? '' : ' AND mp.team_id = ?';
    final List<Object?> args = <Object?>[
      seasonId,
      tournamentId,
      t.matchFinished,
    ];
    if (teamId != null) args.add(teamId);
    args.add(limit);
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT p.player_id,
             p.name AS player_name,
             p.position_id,
             MAX(p.profile) AS profile,
             MAX(tm.name) AS club_name,
             MAX(mp.team_id) AS team_id,
             $aggregate AS total
      FROM match_players mp
      JOIN matches m ON m.match_id = mp.match_id
      JOIN players p ON p.player_id = mp.player_id
      JOIN teams tm ON tm.team_id = mp.team_id
      WHERE m.season_id = ? AND m.tournament_id = ? AND m.status = ?$teamClause
      GROUP BY p.player_id
      HAVING $having
      ORDER BY $orderBy
      LIMIT ?
    ''', args);
    return <LeaderRow>[
      for (final Map<String, Object?> row in rows)
        LeaderRow(
          playerId: row['player_id'] as int,
          playerName: row['player_name'] as String,
          clubName: (row['club_name'] as String?) ?? '',
          positionId: (row['position_id'] as int?) ?? 1,
          teamId: (row['team_id'] as int?) ?? 0,
          profile: (row['profile'] as String?) ?? 'D',
          value: ((row['total'] as num?) ?? 0).toDouble(),
        ),
    ];
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
  Future<void> ageSquad() => db.execute(
    '''
        UPDATE players SET age = age + 1 WHERE status_id = ?
      ''',
    <Object?>[t.statusActive],
  );

  // --------------------------------------------------------------- history

  /// Creates the season awards from the still-present per-match statistics.
  /// Must run before the season archive trigger deletes match_players.
  Future<void> recordSeasonAwards({
    required int seasonId,
    required int year,
  }) async {
    await db.delete(
      t.playerAwards,
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
    );

    final List<Map<String, Object?>> topScorer = await db.rawQuery(
      '''
      SELECT mp.player_id, mp.team_id, SUM(mp.goals) AS goals
      FROM match_players mp
      JOIN matches m ON m.match_id = mp.match_id
      WHERE m.season_id = ? AND m.status = ?
      GROUP BY mp.player_id, mp.team_id
      HAVING SUM(mp.goals) > 0
      ORDER BY goals DESC, SUM(mp.assists) DESC, AVG(mp.rating) DESC
      LIMIT 1
    ''',
      <Object?>[seasonId, t.matchFinished],
    );
    if (topScorer.isNotEmpty) {
      final Map<String, Object?> row = topScorer.first;
      await db.insert(t.playerAwards, <String, Object?>{
        'player_id': row['player_id'],
        'team_id': row['team_id'],
        'type': t.awardTopScorer,
        'year': year,
        'season_id': seasonId,
        'goals': (row['goals'] as int?) ?? 0,
      });
    }

    final List<Map<String, Object?>> mvp = await db.rawQuery(
      '''
      SELECT mp.player_id, mp.team_id
      FROM match_players mp
      JOIN matches m ON m.match_id = mp.match_id
      WHERE m.season_id = ? AND m.status = ? AND mp.minutes > 0
      GROUP BY mp.player_id, mp.team_id
      ORDER BY SUM(mp.mvp) DESC, AVG(mp.rating) DESC,
               SUM(mp.goals) + SUM(mp.assists) DESC
      LIMIT 1
    ''',
      <Object?>[seasonId, t.matchFinished],
    );
    if (mvp.isNotEmpty) {
      final Map<String, Object?> row = mvp.first;
      await db.insert(t.playerAwards, <String, Object?>{
        'player_id': row['player_id'],
        'team_id': row['team_id'],
        'type': t.awardMvp,
        'year': year,
        'season_id': seasonId,
        'goals': 0,
      });
    }

    final List<Map<String, Object?>> young = await db.rawQuery(
      '''
      SELECT mp.player_id, mp.team_id
      FROM match_players mp
      JOIN matches m ON m.match_id = mp.match_id
      JOIN players p ON p.player_id = mp.player_id
      WHERE m.season_id = ? AND m.status = ? AND p.age <= 21
      GROUP BY mp.player_id, mp.team_id
      HAVING SUM(mp.minutes) >= 90
      ORDER BY AVG(mp.rating) DESC, SUM(mp.goals) + SUM(mp.assists) DESC
      LIMIT 1
    ''',
      <Object?>[seasonId, t.matchFinished],
    );
    if (young.isNotEmpty) {
      final Map<String, Object?> row = young.first;
      await db.insert(t.playerAwards, <String, Object?>{
        'player_id': row['player_id'],
        'team_id': row['team_id'],
        'type': t.awardYoungPlayer,
        'year': year,
        'season_id': seasonId,
        'goals': 0,
      });
    }
  }

  /// Writes (or updates) the manager's record for one season.
  Future<void> recordCareerSeason({
    required int seasonId,
    required int teamId,
    required int startYear,
    required int endYear,
    required String championships,
  }) async {
    final List<Map<String, Object?>> stats = await db.rawQuery(
      '''
      SELECT COUNT(*) AS played,
             COALESCE(SUM(CASE WHEN winner_id = ? THEN 1 ELSE 0 END), 0)
               AS wins,
             COALESCE(SUM(CASE WHEN winner_id IS NULL THEN 1 ELSE 0 END), 0)
               AS draws,
             COALESCE(SUM(CASE WHEN winner_id IS NOT NULL AND winner_id != ?
               THEN 1 ELSE 0 END), 0) AS losses,
             COALESCE(SUM(CASE WHEN home_team_id = ? THEN home_goals
               ELSE away_goals END), 0) AS goals_for,
             COALESCE(SUM(CASE WHEN home_team_id = ? THEN away_goals
               ELSE home_goals END), 0) AS goals_against
      FROM matches
      WHERE season_id = ? AND status = ?
        AND (home_team_id = ? OR away_team_id = ?)
    ''',
      <Object?>[
        teamId,
        teamId,
        teamId,
        teamId,
        seasonId,
        t.matchFinished,
        teamId,
        teamId,
      ],
    );
    final Map<String, Object?> s = stats.first;
    final List<Map<String, Object?>> teamRows = await db.query(
      t.teams,
      columns: <String>['coach_id', 'country_id'],
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    final int coachId = teamRows.isEmpty
        ? 0
        : ((teamRows.first['coach_id'] as int?) ?? 0);
    final int countryId = teamRows.isEmpty
        ? 0
        : ((teamRows.first['country_id'] as int?) ?? 0);
    final Map<String, Object?> values = <String, Object?>{
      'season_id': seasonId,
      'coach_id': coachId,
      'team_id': teamId,
      'country_id': countryId,
      'matches_played': (s['played'] as int?) ?? 0,
      'wins': (s['wins'] as int?) ?? 0,
      'draws': (s['draws'] as int?) ?? 0,
      'losses': (s['losses'] as int?) ?? 0,
      'goals_for': (s['goals_for'] as int?) ?? 0,
      'goals_against': (s['goals_against'] as int?) ?? 0,
      'start_year': startYear,
      'end_year': endYear,
      'championships': championships.isEmpty ? null : championships,
    };
    final int updated = await db.update(
      t.careerHistory,
      values,
      where: 'season_id = ? AND team_id = ?',
      whereArgs: <Object?>[seasonId, teamId],
    );
    if (updated == 0) await db.insert(t.careerHistory, values);
  }

  /// Manager career seasons for a club, newest first.
  Future<List<CareerSeason>> careerHistory(int teamId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT ch.*, s.name AS season_name, tm.name AS team_name
      FROM career_history ch
      LEFT JOIN seasons s ON s.season_id = ch.season_id
      LEFT JOIN teams tm ON tm.team_id = ch.team_id
      WHERE ch.team_id = ?
      ORDER BY ch.season_id DESC
    ''',
      <Object?>[teamId],
    );
    return <CareerSeason>[
      for (final Map<String, Object?> r in rows)
        CareerSeason(
          seasonId: (r['season_id'] as int?) ?? 0,
          seasonName: (r['season_name'] as String?) ?? 'Season',
          teamName: (r['team_name'] as String?) ?? '',
          matches: (r['matches_played'] as int?) ?? 0,
          wins: (r['wins'] as int?) ?? 0,
          draws: (r['draws'] as int?) ?? 0,
          losses: (r['losses'] as int?) ?? 0,
          goalsFor: (r['goals_for'] as int?) ?? 0,
          goalsAgainst: (r['goals_against'] as int?) ?? 0,
          championships: (r['championships'] as String?) ?? '',
        ),
    ];
  }

  /// Trophies won by a club, derived from completed competitions.
  ///
  /// Nothing is duplicated into a history table: league titles come from the
  /// final standings and knockout titles from the final match, both of which
  /// stay in the database after a season is archived.
  Future<List<ClubTrophy>> clubTrophies(int teamId) async {
    final List<Map<String, Object?>> competitions = await db.rawQuery('''
      SELECT st.season_id, st.tournament_id, s.name AS season_name,
             s.end_year, tu.name AS tournament_name, tu.organization
      FROM season_tournaments st
      JOIN seasons s ON s.season_id = st.season_id
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      ORDER BY st.season_id DESC, tu.tournament_id ASC
    ''');
    final List<ClubTrophy> trophies = <ClubTrophy>[];
    for (final Map<String, Object?> row in competitions) {
      final int seasonId = row['season_id'] as int;
      final int tournamentId = row['tournament_id'] as int;
      final int organization = (row['organization'] as int?) ?? 0;
      if ((await remainingMatches(seasonId, tournamentId)) > 0) continue;

      int? champion;
      if (organization == t.orgLeague) {
        final List<StandingRow> table = await standings(seasonId, tournamentId);
        if (table.isNotEmpty) champion = table.first.teamId;
      } else {
        final List<Map<String, Object?>> rows = await db.rawQuery(
          '''
          SELECT winner_id FROM matches
          WHERE season_id = ? AND tournament_id = ? AND status = ?
            AND phase = (SELECT MAX(phase) FROM matches
                         WHERE season_id = ? AND tournament_id = ?)
            AND winner_id IS NOT NULL
          LIMIT 1
        ''',
          <Object?>[
            seasonId,
            tournamentId,
            t.matchFinished,
            seasonId,
            tournamentId,
          ],
        );
        if (rows.isNotEmpty) champion = rows.first['winner_id'] as int?;
      }
      if (champion != teamId) continue;
      trophies.add(
        ClubTrophy(
          tournamentId: tournamentId,
          tournamentName: (row['tournament_name'] as String?) ?? 'Trophy',
          organization: organization,
          seasonId: seasonId,
          seasonName: (row['season_name'] as String?) ?? 'Season',
          year: (row['end_year'] as int?) ?? 0,
        ),
      );
    }
    return trophies;
  }

  /// Awards won by players of [teamId], newest first.
  Future<List<PlayerAward>> clubAwards(int teamId, {int limit = 20}) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT pa.*, p.name AS player_name, tm.name AS team_name
      FROM player_awards pa
      LEFT JOIN players p ON p.player_id = pa.player_id
      LEFT JOIN teams tm ON tm.team_id = pa.team_id
      WHERE pa.team_id = ?
      ORDER BY pa.year DESC, pa.type ASC
      LIMIT ?
    ''',
      <Object?>[teamId, limit],
    );
    return _awardsFromRows(rows);
  }

  /// Awards won by one player, newest first.
  Future<List<PlayerAward>> playerAwards(int playerId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT pa.*, p.name AS player_name, tm.name AS team_name
      FROM player_awards pa
      LEFT JOIN players p ON p.player_id = pa.player_id
      LEFT JOIN teams tm ON tm.team_id = pa.team_id
      WHERE pa.player_id = ?
      ORDER BY pa.year DESC, pa.type ASC
    ''',
      <Object?>[playerId],
    );
    return _awardsFromRows(rows);
  }

  List<PlayerAward> _awardsFromRows(List<Map<String, Object?>> rows) {
    return <PlayerAward>[
      for (final Map<String, Object?> r in rows)
        PlayerAward(
          awardId: (r['award_id'] as int?) ?? 0,
          playerId: (r['player_id'] as int?) ?? 0,
          playerName: (r['player_name'] as String?) ?? '',
          teamName: (r['team_name'] as String?) ?? '',
          type: (r['type'] as int?) ?? 0,
          year: (r['year'] as int?) ?? 0,
          seasonId: (r['season_id'] as int?) ?? 0,
          goals: r['goals'] as int?,
        ),
    ];
  }

  /// Archived season-by-season stats for a player, newest first.
  Future<List<PlayerCareerRow>> playerCareer(int playerId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT pss.*, s.name AS season_name, tm.name AS team_name
      FROM player_season_stats pss
      LEFT JOIN seasons s ON s.season_id = pss.season_id
      LEFT JOIN teams tm ON tm.team_id = pss.team_id
      WHERE pss.player_id = ?
      ORDER BY pss.season_id DESC
    ''',
      <Object?>[playerId],
    );
    return <PlayerCareerRow>[
      for (final Map<String, Object?> r in rows)
        PlayerCareerRow(
          seasonId: (r['season_id'] as int?) ?? 0,
          seasonName: (r['season_name'] as String?) ?? 'Season',
          teamName: (r['team_name'] as String?) ?? '',
          matches: (r['matches_played'] as int?) ?? 0,
          minutes: (r['minutes'] as int?) ?? 0,
          starts: (r['starts'] as int?) ?? 0,
          goals: (r['goals'] as int?) ?? 0,
          assists: (r['assists'] as int?) ?? 0,
          mvps: (r['mvps'] as int?) ?? 0,
          yellowCards: (r['yellow_cards'] as int?) ?? 0,
          redCards: (r['red_cards'] as int?) ?? 0,
          ratingSum: (r['rating'] as int?) ?? 0,
        ),
    ];
  }
}
