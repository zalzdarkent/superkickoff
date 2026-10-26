import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import 'competition_config.dart';
import 'fixture_validator.dart';

/// Result of postponing or moving one fixture.
class FixtureRescheduleResult {
  FixtureRescheduleResult({
    required this.success,
    required this.matchId,
    this.oldDate,
    this.newDate,
    this.reason,
    this.message,
  });

  final bool success;
  final int matchId;
  final String? oldDate;
  final String? newDate;
  final String? reason;
  final String? message;

  @override
  String toString() =>
      '${success ? 'moved' : 'failed'} fixture $matchId '
      '${oldDate ?? '-'} -> ${newDate ?? '-'}${message == null ? '' : ': $message'}';
}

/// Central calendar service. It owns every database write that touches fixture
/// dates, so season generation, cup progression and manual postponements all
/// obey the same conflict and rest-period rules.
class FixtureSchedulingService {
  FixtureSchedulingService(this.db);

  final Database db;

  /// Minimum practical gap between two matches of the same club.
  static const int preferredRestDays = 3;

  /// Moves conflicting scheduled fixtures to the nearest valid date and records
  /// the reason. Completed fixtures are never moved. Returns the number of
  /// fixtures whose date changed.
  Future<int> resolveSeasonConflicts(
    int seasonId, {
    int minRestDays = 2,
    bool recordChanges = true,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT match_id, tournament_id, home_team_id, away_team_id,
             stadium_id, date,
             status, phase, round, group_id, original_date
      FROM matches
      WHERE season_id = ? AND date IS NOT NULL AND status != ?
      ORDER BY date ASC, match_id ASC
    ''',
      <Object?>[seasonId, t.matchCancelled],
    );
    if (rows.isEmpty) return 0;

    final DateTime seasonStart = await _seasonStart(seasonId);
    final DateTime seasonEnd = await _seasonEnd(seasonId, seasonStart);
    final Map<int, Future<CompetitionConfig>> configs =
        <int, Future<CompetitionConfig>>{};
    Future<CompetitionConfig> configFor(int tournamentId) =>
        configs.putIfAbsent(
          tournamentId,
          () => _configForTournament(tournamentId, seasonStart.year),
        );

    // Finished fixtures are fixed points; scheduled fixtures are placed in
    // chronological order. The result is deterministic and idempotent.
    final Map<int, List<DateTime>> clubDates = <int, List<DateTime>>{};
    final Map<int, List<DateTime>> stadiumDates = <int, List<DateTime>>{};
    final List<Map<String, Object?>> ordered =
        List<Map<String, Object?>>.of(rows)
          ..sort((Map<String, Object?> a, Map<String, Object?> b) {
            final int date = '${a['date']}'.compareTo('${b['date']}');
            if (date != 0) return date;
            return (a['match_id'] as int).compareTo(b['match_id'] as int);
          });

    for (final Map<String, Object?> row in ordered) {
      if ((row['status'] as int?) == t.matchFinished) {
        _addClubDate(
          clubDates,
          row['home_team_id'] as int,
          row['date'] as String,
        );
        _addClubDate(
          clubDates,
          row['away_team_id'] as int,
          row['date'] as String,
        );
        _addStadiumDate(
          stadiumDates,
          row['stadium_id'] as int? ?? 0,
          row['date'] as String,
        );
      }
    }

    int moved = 0;
    for (final Map<String, Object?> row in ordered) {
      if ((row['status'] as int?) == t.matchFinished) continue;
      final int matchId = row['match_id'] as int;
      final int home = row['home_team_id'] as int;
      final int away = row['away_team_id'] as int;
      final int stadiumId = row['stadium_id'] as int? ?? 0;
      final CompetitionConfig config = await configFor(
        row['tournament_id'] as int,
      );
      final String oldDate = row['date'] as String;
      final DateTime? parsed = DateTime.tryParse(oldDate);
      if (parsed == null) continue;

      final int restDays = max(minRestDays, config.minRestDays);
      final bool unavailable = _isUnavailable(parsed, config.unavailableDates);
      final bool clash = _hasClash(clubDates, home, away, parsed, 0);
      final bool restIssue = _hasClash(clubDates, home, away, parsed, restDays);
      final bool stadiumIssue = _hasStadiumClash(
        stadiumDates,
        stadiumId,
        parsed,
      );

      if (!clash && !restIssue && !stadiumIssue && !unavailable) {
        _addClubDate(clubDates, home, oldDate);
        _addClubDate(clubDates, away, oldDate);
        _addStadiumDate(stadiumDates, stadiumId, oldDate);
        continue;
      }

      final bool cupLike =
          (row['group_id'] == null) && ((row['phase'] as int?) ?? 0) > 0;
      final DateTime? candidate = findAvailableDate(
        preferred: parsed,
        homeTeamId: home,
        awayTeamId: away,
        clubDates: clubDates,
        seasonStart: seasonStart,
        seasonEnd: seasonEnd,
        minRestDays: restDays,
        preferredRestDays: preferredRestDays,
        unavailableDates: config.unavailableDates,
        stadiumId: stadiumId,
        stadiumDates: stadiumDates,
        forwardOnly: true,
        allowedWeekdays: config.allowedWeekdays.isNotEmpty
            ? config.allowedWeekdays
            : cupLike
            ? const <int>[
                DateTime.tuesday,
                DateTime.wednesday,
                DateTime.thursday,
              ]
            : null,
      );
      if (candidate == null) {
        // Record the unresolved conflict rather than silently discarding it.
        await _recordReschedule(
          matchId: matchId,
          oldDate: oldDate,
          newDate: oldDate,
          reason: 'Unresolved calendar conflict: no valid alternative date.',
        );
        _addClubDate(clubDates, home, oldDate);
        _addClubDate(clubDates, away, oldDate);
        _addStadiumDate(stadiumDates, stadiumId, oldDate);
        continue;
      }

      final String newDate = iso(candidate);
      if (recordChanges) {
        await db.transaction((Transaction txn) async {
          await txn.update(
            t.matches,
            <String, Object?>{
              'date': newDate,
              'original_date': row['original_date'] ?? oldDate,
              'reschedule_reason': 'Calendar conflict / rest-period rule',
            },
            where: 'match_id = ?',
            whereArgs: <Object?>[matchId],
          );
          await _insertReschedule(
            txn,
            matchId: matchId,
            oldDate: oldDate,
            newDate: newDate,
            reason: 'Calendar conflict / rest-period rule',
          );
        });
      } else {
        await _recordReschedule(
          matchId: matchId,
          oldDate: oldDate,
          newDate: newDate,
          reason: 'Calendar conflict / rest-period rule',
        );
      }
      _addClubDate(clubDates, home, newDate);
      _addClubDate(clubDates, away, newDate);
      _addStadiumDate(stadiumDates, stadiumId, newDate);
      moved++;
    }
    return moved;
  }

  /// Postpones [matchId] without changing its identity. The fixture keeps its
  /// competition, season, round and clubs; only the date moves. Original dates
  /// and the reason are preserved for the audit trail.
  Future<FixtureRescheduleResult> postponeMatch(
    int matchId, {
    String reason = 'Match postponed',
    DateTime? newDate,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.matches,
      where: 'match_id = ?',
      whereArgs: <Object?>[matchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return FixtureRescheduleResult(
        success: false,
        matchId: matchId,
        message: 'Fixture not found.',
      );
    }
    final Map<String, Object?> match = rows.first;
    if ((match['status'] as int?) == t.matchFinished) {
      return FixtureRescheduleResult(
        success: false,
        matchId: matchId,
        oldDate: match['date'] as String?,
        message: 'Completed fixtures cannot be postponed.',
      );
    }
    final int seasonId = (match['season_id'] as int?) ?? 0;
    final int tournamentId = (match['tournament_id'] as int?) ?? 0;
    final int home = match['home_team_id'] as int;
    final int away = match['away_team_id'] as int;
    final int stadiumId = match['stadium_id'] as int? ?? 0;
    final String? oldDate = match['date'] as String?;

    final Map<int, List<DateTime>> clubDates = await _clubDates(
      seasonId,
      excludingMatchId: matchId,
    );
    final Map<int, List<DateTime>> stadiumDates = await _stadiumDates(
      seasonId,
      excludingMatchId: matchId,
    );
    final DateTime start = await _seasonStart(seasonId);
    final DateTime end = await _seasonEnd(seasonId, start);
    final CompetitionConfig config = await _configForTournament(
      tournamentId,
      start.year,
    );
    final int minRestDays = max(2, config.minRestDays);
    final DateTime preferred =
        newDate ?? DateTime.tryParse(oldDate ?? '') ?? start;

    DateTime? target = newDate;
    if (target == null) {
      target = findAvailableDate(
        preferred: preferred.add(const Duration(days: 7)),
        homeTeamId: home,
        awayTeamId: away,
        clubDates: clubDates,
        seasonStart: start,
        seasonEnd: end,
        minRestDays: minRestDays,
        preferredRestDays: preferredRestDays,
        unavailableDates: config.unavailableDates,
        stadiumId: stadiumId,
        stadiumDates: stadiumDates,
        forwardOnly: true,
        allowedWeekdays: config.allowedWeekdays.isNotEmpty
            ? config.allowedWeekdays
            : const <int>[
                DateTime.tuesday,
                DateTime.wednesday,
                DateTime.thursday,
              ],
      );
    } else {
      // An explicitly requested date must still be conflict-free.
      final bool valid = _dateIsAvailable(
        target,
        home,
        away,
        clubDates,
        minRestDays,
        start,
        end,
        config.unavailableDates,
        stadiumId,
        stadiumDates,
      );
      if (!valid) {
        final DateTime? fallback = findAvailableDate(
          preferred: target,
          homeTeamId: home,
          awayTeamId: away,
          clubDates: clubDates,
          seasonStart: start,
          seasonEnd: end,
          minRestDays: minRestDays,
          preferredRestDays: preferredRestDays,
          unavailableDates: config.unavailableDates,
          stadiumId: stadiumId,
          stadiumDates: stadiumDates,
          forwardOnly: true,
          allowedWeekdays: config.allowedWeekdays.isNotEmpty
              ? config.allowedWeekdays
              : const <int>[
                  DateTime.tuesday,
                  DateTime.wednesday,
                  DateTime.thursday,
                ],
        );
        if (fallback == null) {
          return FixtureRescheduleResult(
            success: false,
            matchId: matchId,
            oldDate: oldDate,
            reason: reason,
            message: 'Requested date conflicts and no alternative was found.',
          );
        }
        target = fallback;
      }
    }

    if (target == null) {
      return FixtureRescheduleResult(
        success: false,
        matchId: matchId,
        oldDate: oldDate,
        reason: reason,
        message: 'No valid alternative date was found.',
      );
    }

    final String newIso = iso(target);
    await db.transaction((Transaction txn) async {
      await txn.update(
        t.matches,
        <String, Object?>{
          'date': newIso,
          'original_date': match['original_date'] ?? oldDate,
          'reschedule_reason': reason,
          // A postponed fixture is still a scheduled fixture; it is simply on
          // a later date. It must never be marked as played.
          'status': t.matchScheduled,
        },
        where: 'match_id = ?',
        whereArgs: <Object?>[matchId],
      );
      await _insertReschedule(
        txn,
        matchId: matchId,
        oldDate: oldDate,
        newDate: newIso,
        reason: reason,
      );
    });

    return FixtureRescheduleResult(
      success: true,
      matchId: matchId,
      oldDate: oldDate,
      newDate: newIso,
      reason: reason,
    );
  }

  Future<FixtureRescheduleResult> rescheduleMatch(
    int matchId,
    DateTime newDate, {
    String reason = 'Rescheduled',
  }) => postponeMatch(matchId, reason: reason, newDate: newDate);

  /// Finds the nearest date that satisfies the club calendars and rest rules.
  /// The search first tries the 72-hour preference, then falls back to the hard
  /// minimum. It never returns a date outside the season window.
  DateTime? findAvailableDate({
    required DateTime preferred,
    required int homeTeamId,
    required int awayTeamId,
    required Map<int, List<DateTime>> clubDates,
    required DateTime seasonStart,
    required DateTime seasonEnd,
    required int minRestDays,
    int preferredRestDays = 3,
    List<DateTime> unavailableDates = const <DateTime>[],
    int stadiumId = 0,
    Map<int, List<DateTime>>? stadiumDates,
    bool forwardOnly = false,
    List<int>? allowedWeekdays,
  }) {
    final Set<String> unavailable = unavailableDates.map(iso).toSet();
    bool fits(DateTime date, int rest) {
      if (date.isBefore(seasonStart) || date.isAfter(seasonEnd)) return false;
      if (unavailable.contains(iso(date))) return false;
      if (allowedWeekdays != null && !allowedWeekdays.contains(date.weekday)) {
        return false;
      }
      return !_hasClash(clubDates, homeTeamId, awayTeamId, date, rest) &&
          !_hasStadiumClash(
            stadiumDates ?? const <int, List<DateTime>>{},
            stadiumId,
            date,
          );
    }

    for (int pass = 0; pass < 2; pass++) {
      final int rest = pass == 0
          ? max(minRestDays, preferredRestDays)
          : minRestDays;
      for (int offset = 0; offset <= 180; offset++) {
        final DateTime forward = preferred.add(Duration(days: offset));
        if (fits(forward, rest)) return forward;
        if (forwardOnly) continue;
        if (offset == 0) continue;
        final DateTime backward = preferred.subtract(Duration(days: offset));
        if (fits(backward, rest)) return backward;
      }
    }
    return null;
  }

  /// Persists one competition configuration (season-specific when a year is
  /// supplied). Safe to call repeatedly.
  Future<void> persistConfig(CompetitionConfig config) async {
    await db.insert(
      'competition_configs',
      config.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CompetitionConfig?> loadConfig(
    int tournamentId, {
    int? seasonStartYear,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'competition_configs',
      where: seasonStartYear == null
          ? 'tournament_id = ? AND season_start_year = 0'
          : 'tournament_id = ? AND season_start_year IN (?, 0)',
      whereArgs: seasonStartYear == null
          ? <Object?>[tournamentId]
          : <Object?>[tournamentId, seasonStartYear, seasonStartYear],
      orderBy: seasonStartYear == null
          ? null
          : 'CASE WHEN season_start_year = ? THEN 0 ELSE 1 END',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CompetitionConfig.fromDbMap(rows.first);
  }

  Future<CompetitionConfig> resolveConfig(
    Tournament tournament, {
    int? seasonStartYear,
  }) async =>
      await loadConfig(
        tournament.tournamentId,
        seasonStartYear: seasonStartYear,
      ) ??
      CompetitionConfig.forTournament(
        tournament,
        seasonStartYear: seasonStartYear,
      );

  Future<CompetitionConfig> _configForTournament(
    int tournamentId,
    int seasonStartYear,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.tournaments,
      where: 'tournament_id = ?',
      whereArgs: <Object?>[tournamentId],
      limit: 1,
    );
    final CompetitionConfig? saved = await loadConfig(
      tournamentId,
      seasonStartYear: seasonStartYear,
    );
    if (saved != null) return saved;
    if (rows.isEmpty) {
      return CompetitionConfig(
        tournamentId: tournamentId,
        name: 'Tournament $tournamentId',
        type: CompetitionType.international,
        format: CompetitionFormat.knockout,
        seasonStartYear: seasonStartYear,
      );
    }
    return CompetitionConfig.forTournament(
      Tournament.fromMap(rows.first),
      seasonStartYear: seasonStartYear,
    );
  }

  /// Validates every competition in a season and returns one report.
  Future<FixtureValidationReport> validateSeason(int seasonId) async {
    final List<Map<String, Object?>> matchRows = await db.query(
      t.matches,
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
    );
    final List<FixtureMatch> fixtures = matchRows
        .map(FixtureMatch.fromMap)
        .toList();
    final List<FixtureViolation> violations = <FixtureViolation>[];
    final List<Map<String, Object?>> seasonRows = await db.query(
      t.seasons,
      columns: <String>['start_year'],
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
      limit: 1,
    );
    final int? seasonStartYear = seasonRows.isEmpty
        ? null
        : seasonRows.first['start_year'] as int?;
    final Map<int, int> restDaysByCompetition = <int, int>{};
    final Set<int> tournamentIds = <int>{
      for (final FixtureMatch m in fixtures) m.tournamentId,
    };

    for (final int tournamentId in tournamentIds) {
      final List<FixtureMatch> tournamentFixtures = fixtures
          .where((FixtureMatch m) => m.tournamentId == tournamentId)
          .toList();
      final List<Map<String, Object?>> tourRows = await db.query(
        t.tournaments,
        where: 'tournament_id = ?',
        whereArgs: <Object?>[tournamentId],
        limit: 1,
      );
      if (tourRows.isEmpty) continue;
      final Tournament tournament = Tournament.fromMap(tourRows.first);
      final CompetitionConfig config = await resolveConfig(
        tournament,
        seasonStartYear: seasonStartYear,
      );
      restDaysByCompetition[tournamentId] = config.minRestDays;
      final List<int> clubs = <int>[
        for (final FixtureMatch m in tournamentFixtures) ...<int>[
          m.homeTeamId,
          m.awayTeamId,
        ],
      ];
      final List<int> uniqueClubs = clubs.toSet().toList();

      if (config.format == CompetitionFormat.leaguePhase) {
        // Only phase 0 belongs to the league-phase table. Any later phase is
        // the knockout bracket and must be validated as such.
        final List<FixtureMatch> phaseFixtures = tournamentFixtures
            .where((FixtureMatch m) => m.phase == 0)
            .toList();
        if (phaseFixtures.isNotEmpty) {
          final List<int> phaseClubs = <int>[
            for (final FixtureMatch m in phaseFixtures) ...<int>[
              m.homeTeamId,
              m.awayTeamId,
            ],
          ];
          violations.addAll(
            FixtureValidator.validateLeaguePhase(
              competitionId: tournamentId,
              seasonId: seasonId,
              fixtures: phaseFixtures,
              clubIds: phaseClubs.toSet().toList(),
              opponentsPerClub: config.leaguePhaseOpponents,
              homeMatches: config.leaguePhaseHomeMatches,
              awayMatches: config.leaguePhaseAwayMatches,
            ).violations,
          );
        }
        final List<FixtureMatch> knockoutFixtures = tournamentFixtures
            .where((FixtureMatch m) => m.phase > 0 && m.groupId == null)
            .toList();
        if (knockoutFixtures.isNotEmpty) {
          violations.addAll(
            FixtureValidator.validateKnockout(
              competitionId: tournamentId,
              seasonId: seasonId,
              fixtures: knockoutFixtures,
              expectedLegs: config.knockoutLegs,
              finalSingleMatch: config.finalSingleMatch,
            ).violations,
          );
        }
      } else if (config.isLeagueLike) {
        violations.addAll(
          FixtureValidator.validateLeague(
            competitionId: tournamentId,
            seasonId: seasonId,
            fixtures: tournamentFixtures,
            clubIds: uniqueClubs,
            doubleRound: config.doubleRoundRobin,
          ).violations,
        );
      } else if (config.format == CompetitionFormat.groupStage) {
        final Map<int, List<FixtureMatch>> groups =
            <int, List<FixtureMatch>>{};
        for (final FixtureMatch fixture in tournamentFixtures) {
          if (fixture.groupId == null) continue;
          groups
              .putIfAbsent(fixture.groupId!, () => <FixtureMatch>[])
              .add(fixture);
        }
        for (final MapEntry<int, List<FixtureMatch>> group in groups.entries) {
          final List<int> groupClubs = <int>{
            for (final FixtureMatch fixture in group.value)
              fixture.homeTeamId,
            for (final FixtureMatch fixture in group.value)
              fixture.awayTeamId,
          }.toList();
          violations.addAll(
            FixtureValidator.validateLeague(
              competitionId: tournamentId,
              seasonId: seasonId,
              fixtures: group.value,
              clubIds: groupClubs,
              doubleRound: config.groupDoubleRoundRobin,
              codePrefix: 'group_${group.key}',
            ).violations,
          );
        }
        final List<FixtureMatch> knockoutFixtures = tournamentFixtures
            .where((FixtureMatch fixture) => fixture.groupId == null)
            .toList();
        if (knockoutFixtures.isNotEmpty) {
          violations.addAll(
            FixtureValidator.validateKnockout(
              competitionId: tournamentId,
              seasonId: seasonId,
              fixtures: knockoutFixtures,
              expectedLegs: config.knockoutLegs,
              finalSingleMatch: config.finalSingleMatch,
            ).violations,
          );
        }
      } else {
        final List<FixtureMatch> knockoutFixtures = tournamentFixtures
            .where((FixtureMatch m) => m.groupId == null)
            .toList();
        if (knockoutFixtures.isNotEmpty) {
          violations.addAll(
            FixtureValidator.validateKnockout(
              competitionId: tournamentId,
              seasonId: seasonId,
              fixtures: knockoutFixtures,
              expectedLegs: config.knockoutLegs,
              finalSingleMatch: config.finalSingleMatch,
            ).violations,
          );
        }
      }
    }

    violations.addAll(
      FixtureValidator.validateCalendar(
        fixtures: fixtures,
        minRestDays: 2,
        minRestDaysByCompetition: restDaysByCompetition,
      ).violations,
    );
    return FixtureValidationReport(violations);
  }

  // ------------------------------------------------------------ internals

  Future<Map<int, List<DateTime>>> _clubDates(
    int seasonId, {
    int? excludingMatchId,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.matches,
      columns: <String>['match_id', 'home_team_id', 'away_team_id', 'date'],
      where: seasonId == 0
          ? 'date IS NOT NULL AND status != ?'
          : 'season_id = ? AND date IS NOT NULL AND status != ?',
      whereArgs: seasonId == 0
          ? <Object?>[t.matchCancelled]
          : <Object?>[seasonId, t.matchCancelled],
    );
    final Map<int, List<DateTime>> result = <int, List<DateTime>>{};
    for (final Map<String, Object?> row in rows) {
      if (excludingMatchId != null && row['match_id'] == excludingMatchId) {
        continue;
      }
      final DateTime? date = DateTime.tryParse('${row['date']}');
      if (date == null) continue;
      _addClubDate(result, row['home_team_id'] as int, date);
      _addClubDate(result, row['away_team_id'] as int, date);
    }
    return result;
  }

  Future<Map<int, List<DateTime>>> _stadiumDates(
    int seasonId, {
    int? excludingMatchId,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.matches,
      columns: <String>['match_id', 'stadium_id', 'date'],
      where: seasonId == 0
          ? 'date IS NOT NULL AND status != ?'
          : 'season_id = ? AND date IS NOT NULL AND status != ?',
      whereArgs: seasonId == 0
          ? <Object?>[t.matchCancelled]
          : <Object?>[seasonId, t.matchCancelled],
    );
    final Map<int, List<DateTime>> result = <int, List<DateTime>>{};
    for (final Map<String, Object?> row in rows) {
      if (excludingMatchId != null && row['match_id'] == excludingMatchId) {
        continue;
      }
      final DateTime? date = DateTime.tryParse('${row['date']}');
      if (date == null) continue;
      _addStadiumDate(result, row['stadium_id'] as int? ?? 0, date);
    }
    return result;
  }

  Future<DateTime> _seasonStart(int seasonId) async {
    if (seasonId == 0) return DateTime(2025, 8, 1);
    final List<Map<String, Object?>> rows = await db.query(
      t.seasons,
      columns: <String>['start_year'],
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
      limit: 1,
    );
    final int year = rows.isEmpty
        ? 2025
        : (rows.first['start_year'] as int? ?? 2025);
    return DateTime(year, 7, 1);
  }

  Future<DateTime> _seasonEnd(int seasonId, DateTime seasonStart) async {
    if (seasonId == 0) return seasonStart.add(const Duration(days: 330));
    final List<Map<String, Object?>> rows = await db.query(
      t.seasons,
      columns: <String>['end_year'],
      where: 'season_id = ?',
      whereArgs: <Object?>[seasonId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['end_year'] == null) {
      return seasonStart.add(const Duration(days: 330));
    }
    return DateTime(rows.first['end_year'] as int, 6, 30);
  }

  void _addClubDate(
    Map<int, List<DateTime>> clubDates,
    int clubId,
    Object? date,
  ) {
    final DateTime? parsed = date is DateTime
        ? date
        : DateTime.tryParse('${date ?? ''}');
    if (parsed == null) return;
    clubDates.putIfAbsent(clubId, () => <DateTime>[]).add(parsed);
  }

  void _addStadiumDate(
    Map<int, List<DateTime>> stadiumDates,
    int stadiumId,
    Object? date,
  ) {
    if (stadiumId <= 0) return;
    _addClubDate(stadiumDates, stadiumId, date);
  }

  bool _hasStadiumClash(
    Map<int, List<DateTime>> stadiumDates,
    int stadiumId,
    DateTime date,
  ) {
    if (stadiumId <= 0) return false;
    return stadiumDates[stadiumId]?.any(
          (DateTime existing) =>
              existing.year == date.year &&
              existing.month == date.month &&
              existing.day == date.day,
        ) ??
        false;
  }

  bool _hasClash(
    Map<int, List<DateTime>> clubDates,
    int home,
    int away,
    DateTime date,
    int minRestDays,
  ) {
    for (final int club in <int>[home, away]) {
      final List<DateTime>? dates = clubDates[club];
      if (dates == null) continue;
      for (final DateTime existing in dates) {
        final int gap = existing.difference(date).inDays.abs();
        if (minRestDays == 0) {
          if (gap == 0) return true;
        } else if (gap < minRestDays) {
          return true;
        }
      }
    }
    return false;
  }

  bool _dateIsAvailable(
    DateTime date,
    int home,
    int away,
    Map<int, List<DateTime>> clubDates,
    int minRestDays,
    DateTime seasonStart,
    DateTime seasonEnd,
    List<DateTime> unavailableDates,
    int stadiumId,
    Map<int, List<DateTime>> stadiumDates,
  ) {
    if (date.isBefore(seasonStart) || date.isAfter(seasonEnd)) return false;
    if (_isUnavailable(date, unavailableDates)) return false;
    return !_hasClash(clubDates, home, away, date, minRestDays) &&
        !_hasStadiumClash(stadiumDates, stadiumId, date);
  }

  bool _isUnavailable(DateTime date, List<DateTime> unavailableDates) {
    final String key = iso(date);
    return unavailableDates.any(
      (DateTime unavailable) => iso(unavailable) == key,
    );
  }

  Future<void> _recordReschedule({
    required int matchId,
    required String? oldDate,
    required String newDate,
    required String reason,
  }) => _insertReschedule(
    db,
    matchId: matchId,
    oldDate: oldDate,
    newDate: newDate,
    reason: reason,
  );

  Future<void> _insertReschedule(
    DatabaseExecutor executor, {
    required int matchId,
    required String? oldDate,
    required String newDate,
    required String reason,
  }) async {
    await executor.insert('fixture_reschedules', <String, Object?>{
      'match_id': matchId,
      'old_date': oldDate,
      'new_date': newDate,
      'reason': reason,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static String iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
