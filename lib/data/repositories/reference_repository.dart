import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';
import '../../core/country_names.dart';

/// Read-mostly reference data: countries, tournaments, teams, stadiums.
class ReferenceRepository {
  ReferenceRepository(this.db);

  final Database db;

  /// Countries that have at least one domestic league available, ranked by
  /// how many clubs can play there (best first).
  Future<List<Map<String, Object?>>> playableCountries() async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
    SELECT c.country_id, c.name, c.iso2, c.power,
           COUNT(DISTINCT tu.tournament_id) AS league_count,
           COUNT(DISTINCT tm.team_id) AS team_count
    FROM countries c
    JOIN tournament_countries tc ON tc.country_id = c.country_id
    JOIN tournaments tu ON tu.tournament_id = tc.tournament_id AND tu.organization = ?
    JOIN teams tm ON tm.country_id = c.country_id
    GROUP BY c.country_id
    ORDER BY c.name COLLATE NOCASE ASC
  ''',
      <Object?>[t.orgLeague],
    );
    return rows
        .map(
          (Map<String, Object?> row) => <String, Object?>{
            ...row,
            'name': displayCountryName(
              row['name'] as String? ?? '',
              row['iso2'] as String? ?? '',
              countryId: row['country_id'] as int?,
            ),
          },
        )
        .toList();
  }

  /// Domestic leagues (organization = 1) of a country, with squad counts.
  Future<List<Map<String, Object?>>> leaguesForCountry(int countryId) =>
      db.rawQuery(
        '''
    SELECT tu.tournament_id, tu.name, tu.division_id, tu.play_days, tu.slots, tu.logo_base64,
           (SELECT COUNT(*) FROM teams tm
             WHERE tm.country_id = ? AND tm.division = tu.division_id)
           AS team_count
    FROM tournaments tu
    JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
    WHERE tc.country_id = ? AND tu.organization = ?
    GROUP BY tu.tournament_id
    ORDER BY tu.division_id, tu.name
  ''',
        <Object?>[countryId, countryId, t.orgLeague],
      );

  /// Returns all domestic league tournaments for a country, ordered by division.
  Future<List<Tournament>> domesticLeagues(int countryId) async {
    final rows = await db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ? AND tu.organization = ?
      GROUP BY tu.tournament_id
      ORDER BY tu.division_id ASC, tu.name ASC
    ''',
      <Object?>[countryId, t.orgLeague],
    );
    return rows.map(Tournament.fromMap).toList();
  }

  /// Continental zone of a league, taken from the continental cup its country plays in.
  Future<String> leagueRegion(int tournamentId) async {
    final rows = await db.rawQuery(
      '''
      SELECT isl.tournament_id FROM tournament_countries tc
      JOIN international_slots isl ON isl.country_id = tc.country_id
      WHERE tc.tournament_id = ? AND isl.tournament_id IN (49, 50, 52, 99, 100)
    ''',
      <Object?>[tournamentId],
    );
    final Set<Object?> ids = rows.map((r) => r['tournament_id']).toSet();
    const Map<int, String> zones = <int, String>{
      49: 'europe',
      50: 'northAmerica',
      52: 'southAmerica',
      99: 'asia',
      100: 'africa',
    };
    for (final MapEntry<int, String> z in zones.entries) {
      if (ids.contains(z.key)) return z.value;
    }
    return '';
  }

  /// Every country, for the manager's nationality picker.
  Future<List<Map<String, Object?>>> allCountries() async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT country_id, name, iso2 FROM countries WHERE name IS NOT NULL '
      'ORDER BY name COLLATE NOCASE',
    );
    return rows
        .map(
          (Map<String, Object?> row) => <String, Object?>{
            ...row,
            'name': displayCountryName(
              row['name'] as String? ?? '',
              row['iso2'] as String? ?? '',
              countryId: row['country_id'] as int?,
            ),
          },
        )
        .toList();
  }

  /// Continental club competitions this country's clubs qualify for.
  Future<List<Tournament>> internationalCups(int countryId) async {
    final rows = await db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN international_slots isl ON isl.tournament_id = tu.tournament_id
      WHERE isl.country_id = ? AND tu.organization = ?
      GROUP BY tu.tournament_id
      ORDER BY tu.tournament_id
    ''',
      <Object?>[countryId, t.orgInternational],
    );
    return rows.map(Tournament.fromMap).toList();
  }

  /// The national cup (organization = 3) of a country, if any.
  Future<Map<String, Object?>?> nationalCup(int countryId) async {
    final rows = await db.rawQuery(
      '''
      SELECT tu.tournament_id, tu.name, tu.logo_base64
      FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tu.organization = ? AND tc.country_id = ?
      ORDER BY tu.tournament_id LIMIT 1
    ''',
      <Object?>[t.orgNationalCup, countryId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Tournament?> tournamentById(int id) async {
    final rows = await db.query(
      t.tournaments,
      where: 'tournament_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Tournament.fromMap(rows.first);
  }

  /// Teams of a country in a specific division (league participants).
  Future<List<Team>> teamsForDivision(int countryId, int divisionId) async {
    final rows = await db.query(
      t.teams,
      where: 'country_id = ? AND division = ?',
      whereArgs: <Object?>[countryId, divisionId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Team.fromMap).toList();
  }

  Future<List<Team>> teamsForCountry(int countryId) => db
      .query(
        t.teams,
        where: 'country_id = ?',
        whereArgs: <Object?>[countryId],
        orderBy: 'name COLLATE NOCASE ASC',
      )
      .then((rows) => rows.map(Team.fromMap).toList());

  Future<Team?> teamById(int teamId) async {
    final rows = await db.query(
      t.teams,
      where: 'team_id = ?',
      whereArgs: <Object?>[teamId],
      limit: 1,
    );
    return rows.isEmpty ? null : Team.fromMap(rows.first);
  }

  Future<Stadium?> stadiumById(int stadiumId) async {
    final rows = await db.query(
      t.stadiums,
      where: 'stadium_id = ?',
      whereArgs: <Object?>[stadiumId],
      limit: 1,
    );
    return rows.isEmpty ? null : Stadium.fromMap(rows.first);
  }

  Future<Country?> countryById(int countryId) async {
    final rows = await db.query(
      t.countries,
      where: 'country_id = ?',
      whereArgs: <Object?>[countryId],
      limit: 1,
    );
    return rows.isEmpty ? null : Country.fromMap(rows.first);
  }
}
