import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';

/// The kind of competition. Kept deliberately small: the scheduling system only
/// needs to know whether a tournament is a league, a cup, a continental
/// competition or a one-off super cup.
enum CompetitionType {
  league,
  domesticCup,
  continental,
  superCup,
  international,
  friendly,
}

/// The structural format of a competition.
enum CompetitionFormat {
  doubleRoundRobin,
  singleRoundRobin,
  leaguePhase,
  groupStage,
  knockout,
  singleMatch,
  multiStage,
}

/// Centralised rule-set for one competition (optionally for one season).
///
/// This is the single source of truth consumed by the fixture generators. New
/// competitions can be added by registering a config instead of adding another
/// `if (tournamentId == ...)` branch to the scheduling code.
class CompetitionConfig {
  CompetitionConfig({
    required this.tournamentId,
    required this.name,
    required this.type,
    required this.format,
    this.seasonStartYear,
    this.participantCount,
    this.doubleRoundRobin = true,
    this.matchdayIntervalDays = 7,
    this.minRestDays = 2,
    this.groupSize = 4,
    this.groupCount = 0,
    this.groupDoubleRoundRobin = true,
    this.groupQualifiersPerGroup = 2,
    this.leaguePhaseOpponents = 0,
    this.leaguePhaseHomeMatches = 0,
    this.leaguePhaseAwayMatches = 0,
    this.leaguePhaseQualifiers = 0,
    this.knockoutLegs = 1,
    this.finalSingleMatch = true,
    this.neutralFinal = false,
    this.extraTime = true,
    this.penalties = true,
    this.awayGoals = false,
    this.useByes = true,
    this.trimToPowerOfTwo = false,
    int? fieldSize,
    this.promotionSlots = 0,
    this.relegationSlots = 0,
    List<DateTime> unavailableDates = const <DateTime>[],
    List<int> allowedWeekdays = const <int>[],
  }) : fieldSize = fieldSize ?? participantCount,
       unavailableDates = List<DateTime>.unmodifiable(unavailableDates),
       allowedWeekdays = List<int>.unmodifiable(allowedWeekdays);

  final int tournamentId;
  final String name;
  final CompetitionType type;
  final CompetitionFormat format;

  /// When non-null this config only applies to that season.
  final int? seasonStartYear;

  /// Expected field size when the database does not expose one reliably.
  final int? participantCount;

  final bool doubleRoundRobin;
  final int matchdayIntervalDays;

  /// Minimum days between two matches of the same club.
  final int minRestDays;

  final int groupSize;

  /// Zero means "derive from the number of entrants".
  final int groupCount;

  final bool groupDoubleRoundRobin;
  final int groupQualifiersPerGroup;

  final int leaguePhaseOpponents;
  final int leaguePhaseHomeMatches;
  final int leaguePhaseAwayMatches;
  final int leaguePhaseQualifiers;

  /// Legs for knockout rounds before the final.
  final int knockoutLegs;

  final bool finalSingleMatch;
  final bool neutralFinal;
  final bool extraTime;
  final bool penalties;

  /// Away-goals rule. Disabled unless a competition explicitly enables it.
  final bool awayGoals;

  /// Whether a bracket should keep every entrant and use byes.
  final bool useByes;

  /// Some cup competitions pre-select a fixed power-of-two field. When true the
  /// strongest [fieldSize] clubs enter and no byes are required.
  final bool trimToPowerOfTwo;
  final int? fieldSize;

  final int promotionSlots;
  final int relegationSlots;

  /// Dates on which the competition must not schedule fixtures (international
  /// windows, winter breaks, ...).
  final List<DateTime> unavailableDates;
  final List<int> allowedWeekdays;

  bool get isLeagueLike =>
      format == CompetitionFormat.doubleRoundRobin ||
      format == CompetitionFormat.singleRoundRobin ||
      format == CompetitionFormat.leaguePhase;

  bool get isGrouped =>
      format == CompetitionFormat.groupStage ||
      format == CompetitionFormat.leaguePhase;

  CompetitionConfig copyWith({
    int? tournamentId,
    String? name,
    CompetitionType? type,
    CompetitionFormat? format,
    int? seasonStartYear,
    int? participantCount,
    bool? doubleRoundRobin,
    int? matchdayIntervalDays,
    int? minRestDays,
    int? groupSize,
    int? groupCount,
    bool? groupDoubleRoundRobin,
    int? groupQualifiersPerGroup,
    int? leaguePhaseOpponents,
    int? leaguePhaseHomeMatches,
    int? leaguePhaseAwayMatches,
    int? leaguePhaseQualifiers,
    int? knockoutLegs,
    bool? finalSingleMatch,
    bool? neutralFinal,
    bool? extraTime,
    bool? penalties,
    bool? awayGoals,
    bool? useByes,
    bool? trimToPowerOfTwo,
    int? fieldSize,
    int? promotionSlots,
    int? relegationSlots,
    List<DateTime>? unavailableDates,
    List<int>? allowedWeekdays,
  }) => CompetitionConfig(
    tournamentId: tournamentId ?? this.tournamentId,
    name: name ?? this.name,
    type: type ?? this.type,
    format: format ?? this.format,
    seasonStartYear: seasonStartYear ?? this.seasonStartYear,
    participantCount: participantCount ?? this.participantCount,
    doubleRoundRobin: doubleRoundRobin ?? this.doubleRoundRobin,
    matchdayIntervalDays: matchdayIntervalDays ?? this.matchdayIntervalDays,
    minRestDays: minRestDays ?? this.minRestDays,
    groupSize: groupSize ?? this.groupSize,
    groupCount: groupCount ?? this.groupCount,
    groupDoubleRoundRobin: groupDoubleRoundRobin ?? this.groupDoubleRoundRobin,
    groupQualifiersPerGroup:
        groupQualifiersPerGroup ?? this.groupQualifiersPerGroup,
    leaguePhaseOpponents: leaguePhaseOpponents ?? this.leaguePhaseOpponents,
    leaguePhaseHomeMatches:
        leaguePhaseHomeMatches ?? this.leaguePhaseHomeMatches,
    leaguePhaseAwayMatches:
        leaguePhaseAwayMatches ?? this.leaguePhaseAwayMatches,
    leaguePhaseQualifiers: leaguePhaseQualifiers ?? this.leaguePhaseQualifiers,
    knockoutLegs: knockoutLegs ?? this.knockoutLegs,
    finalSingleMatch: finalSingleMatch ?? this.finalSingleMatch,
    neutralFinal: neutralFinal ?? this.neutralFinal,
    extraTime: extraTime ?? this.extraTime,
    penalties: penalties ?? this.penalties,
    awayGoals: awayGoals ?? this.awayGoals,
    useByes: useByes ?? this.useByes,
    trimToPowerOfTwo: trimToPowerOfTwo ?? this.trimToPowerOfTwo,
    fieldSize: fieldSize ?? this.fieldSize,
    promotionSlots: promotionSlots ?? this.promotionSlots,
    relegationSlots: relegationSlots ?? this.relegationSlots,
    unavailableDates: unavailableDates ?? this.unavailableDates,
    allowedWeekdays: allowedWeekdays ?? this.allowedWeekdays,
  );

  /// Derives a config from the bundled tournament row, then applies the known
  /// competition-specific reference profiles. Unknown competitions receive a
  /// safe, explicit fallback based on their organisation and slot count.
  static CompetitionConfig forTournament(
    Tournament tournament, {
    int? seasonStartYear,
  }) {
    final CompetitionConfig? override =
        _overrides[_key(tournament.tournamentId, seasonStartYear)];
    if (override != null) return override;
    final CompetitionConfig base =
        _knownProfiles[tournament.tournamentId] != null
        ? _knownProfiles[tournament.tournamentId]!(tournament, seasonStartYear)
        : _fallback(tournament, seasonStartYear);
    return base;
  }

  /// Derives a config directly from the tournament ID by querying the database.
  static Future<CompetitionConfig> forTournamentId(
    Database db,
    int tournamentId, {
    int? seasonStartYear,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      t.tournaments,
      where: 'tournament_id = ?',
      whereArgs: <Object?>[tournamentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      final Tournament synthetic = Tournament(
        tournamentId: tournamentId,
        name: 'Tournament $tournamentId',
        organization: DbOrg.orgInternational,
        divisionId: 1,
        slots: 16,
        promotionSlots: 0,
        relegationSpots: 0,
        points: 3.0,
        prizeTeams: 0,
        prizeTopScorer: 0,
        prizeMvp: 0,
        playDays: '6,7',
        rounds: 1,
      );
      return forTournament(synthetic, seasonStartYear: seasonStartYear);
    }
    return forTournament(
      Tournament.fromMap(rows.first),
      seasonStartYear: seasonStartYear,
    );
  }

  static CompetitionConfig _fallback(
    Tournament tournament,
    int? seasonStartYear,
  ) {
    final bool league = tournament.organization == DbOrg.orgLeague;
    final bool cup = tournament.organization == DbOrg.orgNationalCup;
    final bool international =
        tournament.organization == DbOrg.orgInternational;
    final int slots = tournament.slots;
    if (league) {
      return CompetitionConfig(
        tournamentId: tournament.tournamentId,
        name: tournament.name,
        type: CompetitionType.league,
        format: CompetitionFormat.doubleRoundRobin,
        seasonStartYear: seasonStartYear,
        // The tournament.rounds column in this database is a historical
        // format flag, not a reliable league-format switch. Domestic leagues
        // are double round-robin unless an explicit season override says
        // otherwise.
        doubleRoundRobin: true,
        matchdayIntervalDays: 7,
        minRestDays: 2,
        allowedWeekdays: _parseWeekdays(tournament.playDays),
        promotionSlots: tournament.promotionSlots,
        relegationSlots: tournament.relegationSpots,
      );
    }
    if (cup) {
      return CompetitionConfig(
        tournamentId: tournament.tournamentId,
        name: tournament.name,
        type: CompetitionType.domesticCup,
        format: CompetitionFormat.knockout,
        seasonStartYear: seasonStartYear,
        knockoutLegs: tournament.rounds == 2 ? 2 : 1,
        finalSingleMatch: true,
        neutralFinal: true,
        extraTime: true,
        penalties: true,
        // Domestic cups in the bundled data expose a large pool of clubs. The
        // existing game selected the strongest power-of-two field; preserve
        // that behaviour explicitly instead of silently dropping clubs.
        trimToPowerOfTwo: true,
        // Field size is derived from the number of entrants (largest power of
        // two that fits), matching the game's existing domestic-cup field.
        fieldSize: null,
      );
    }
    if (international) {
      if (slots <= 2) {
        return CompetitionConfig(
          tournamentId: tournament.tournamentId,
          name: tournament.name,
          type: CompetitionType.superCup,
          format: CompetitionFormat.singleMatch,
          seasonStartYear: seasonStartYear,
          participantCount: slots > 0 ? slots : 2,
          finalSingleMatch: true,
          neutralFinal: true,
          extraTime: true,
          penalties: true,
          knockoutLegs: 1,
        );
      }
      if (slots <= 8) {
        return CompetitionConfig(
          tournamentId: tournament.tournamentId,
          name: tournament.name,
          type: CompetitionType.international,
          format: CompetitionFormat.knockout,
          seasonStartYear: seasonStartYear,
          participantCount: slots,
          knockoutLegs: 1,
          finalSingleMatch: true,
          neutralFinal: true,
          extraTime: true,
          penalties: true,
          useByes: true,
        );
      }
      return CompetitionConfig(
        tournamentId: tournament.tournamentId,
        name: tournament.name,
        type: CompetitionType.continental,
        format: CompetitionFormat.groupStage,
        seasonStartYear: seasonStartYear,
        participantCount: slots,
        groupSize: 4,
        groupDoubleRoundRobin: true,
        knockoutLegs: 2,
        finalSingleMatch: true,
        neutralFinal: true,
        extraTime: true,
        penalties: true,
        useByes: true,
      );
    }
    return CompetitionConfig(
      tournamentId: tournament.tournamentId,
      name: tournament.name,
      type: CompetitionType.friendly,
      format: CompetitionFormat.singleMatch,
      seasonStartYear: seasonStartYear,
      finalSingleMatch: true,
      knockoutLegs: 1,
      extraTime: false,
      penalties: false,
    );
  }

  // -------------------------------------------------------- known profiles
  //
  // These are the explicitly documented reference profiles for the competitions
  // whose rules are known from the bundled competition data. They are kept in
  // one place so the generator never has to special-case a tournament id.

  static final Map<int, CompetitionConfig Function(Tournament, int?)>
  _knownProfiles = <int, CompetitionConfig Function(Tournament, int?)>{
    49: (Tournament t, int? y) =>
        _leaguePhaseProfile(t, y, opponents: 8, home: 4, away: 4),
    51: (Tournament t, int? y) =>
        _leaguePhaseProfile(t, y, opponents: 8, home: 4, away: 4),
    135: (Tournament t, int? y) =>
        _leaguePhaseProfile(t, y, opponents: 6, home: 3, away: 3),
    99: (Tournament t, int? y) => _groupProfile(t, y, knockoutLegs: 2),
    164: (Tournament t, int? y) => _groupProfile(t, y, knockoutLegs: 2),
    1650: (Tournament t, int? y) => _groupProfile(t, y, knockoutLegs: 2),
    50: (Tournament t, int? y) => _groupProfile(t, y, knockoutLegs: 2),
    52: (Tournament t, int? y) => _groupProfile(t, y, knockoutLegs: 2),
    53: (Tournament t, int? y) => _groupProfile(t, y, knockoutLegs: 2),
    100: (Tournament t, int? y) => _groupProfile(t, y, knockoutLegs: 2),
    163: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 16,
      groupSize: 4,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    54: (Tournament t, int? y) => _singleMatchProfile(t, y),
    1651: (Tournament t, int? y) => _singleMatchProfile(t, y),
    56: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.knockout,
      seasonStartYear: y,
      participantCount: 8,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    // ---------------- International National-Team Competitions ----------------
    57: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: (y != null && y >= 2026) ? 48 : 32,
      fieldSize: (y != null && y >= 2026) ? 48 : 32,
      groupCount: (y != null && y >= 2026) ? 12 : 8,
      groupSize: 4,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    95: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 24,
      fieldSize: 24,
      groupSize: 4,
      groupCount: 6,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    98: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 24,
      fieldSize: 24,
      groupSize: 4,
      groupCount: 6,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    94: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 16,
      groupSize: 4,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    96: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 16,
      groupSize: 4,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    97: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 24,
      groupSize: 4,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      useByes: true,
    ),
    900: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.friendly,
      format: CompetitionFormat.singleMatch,
      seasonStartYear: y,
      finalSingleMatch: true,
      knockoutLegs: 1,
      extraTime: false,
      penalties: false,
    ),
    901: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 16,
      fieldSize: 16,
      doubleRoundRobin: true,
      groupSize: 4,
      groupDoubleRoundRobin: true,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
      promotionSlots: 4,
      relegationSlots: 4,
    ),
    902: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 10,
      fieldSize: 10,
      groupCount: 2,
      groupSize: 5,
      groupDoubleRoundRobin: false,
      knockoutLegs: 2,
      finalSingleMatch: false,
      extraTime: true,
      penalties: true,
    ),
    903: (Tournament t, int? y) => CompetitionConfig(
      tournamentId: t.tournamentId,
      name: t.name,
      type: CompetitionType.international,
      format: CompetitionFormat.groupStage,
      seasonStartYear: y,
      participantCount: 14,
      fieldSize: 14,
      groupCount: 3,
      groupSize: 4,
      groupDoubleRoundRobin: false,
      knockoutLegs: 1,
      finalSingleMatch: true,
      neutralFinal: true,
      extraTime: true,
      penalties: true,
    ),
  };

  static CompetitionConfig _leaguePhaseProfile(
    Tournament t,
    int? year, {
    required int opponents,
    required int home,
    required int away,
  }) => CompetitionConfig(
    tournamentId: t.tournamentId,
    name: t.name,
    type: CompetitionType.continental,
    format: CompetitionFormat.leaguePhase,
    seasonStartYear: year,
    participantCount: 36,
    leaguePhaseOpponents: opponents,
    leaguePhaseHomeMatches: home,
    leaguePhaseAwayMatches: away,
    // The bundled game does not model the play-off round. The top 16 of the
    // single league-phase table advance straight to a two-legged round of 16.
    leaguePhaseQualifiers: 16,
    knockoutLegs: 2,
    finalSingleMatch: true,
    neutralFinal: true,
    extraTime: true,
    penalties: true,
    awayGoals: false,
    matchdayIntervalDays: 7,
    minRestDays: 2,
  );

  static CompetitionConfig _groupProfile(
    Tournament t,
    int? year, {
    required int knockoutLegs,
  }) => CompetitionConfig(
    tournamentId: t.tournamentId,
    name: t.name,
    type: CompetitionType.continental,
    format: CompetitionFormat.groupStage,
    seasonStartYear: year,
    participantCount: t.slots,
    groupSize: 4,
    groupDoubleRoundRobin: true,
    knockoutLegs: knockoutLegs,
    finalSingleMatch: true,
    neutralFinal: true,
    extraTime: true,
    penalties: true,
    useByes: true,
    matchdayIntervalDays: 7,
    minRestDays: 2,
  );

  static CompetitionConfig _singleMatchProfile(Tournament t, int? year) =>
      CompetitionConfig(
        tournamentId: t.tournamentId,
        name: t.name,
        type: CompetitionType.superCup,
        format: CompetitionFormat.singleMatch,
        seasonStartYear: year,
        participantCount: 2,
        finalSingleMatch: true,
        neutralFinal: true,
        extraTime: true,
        penalties: true,
        knockoutLegs: 1,
      );

  static List<int> _parseWeekdays(String value) {
    final Set<int> weekdays = <int>{};
    for (final String token in value.split(',')) {
      final int? weekday = int.tryParse(token.trim());
      if (weekday != null && weekday >= DateTime.monday &&
          weekday <= DateTime.sunday) {
        weekdays.add(weekday);
      }
    }
    return weekdays.toList()..sort();
  }

  // ----------------------------------------------------- season overrides

  static final Map<String, CompetitionConfig> _overrides =
      <String, CompetitionConfig>{};

  static String _key(int tournamentId, int? year) =>
      '$tournamentId@${year ?? 0}';

  /// Registers a season-specific override. Returns the previous value, if any.
  static CompetitionConfig? override(CompetitionConfig config) {
    final String key = _key(config.tournamentId, config.seasonStartYear);
    final CompetitionConfig? previous = _overrides[key];
    _overrides[key] = config;
    return previous;
  }

  static void clearOverrides() => _overrides.clear();

  // --------------------------------------------------------- persistence

  Map<String, Object?> toDbMap() => <String, Object?>{
    'tournament_id': tournamentId,
    'season_start_year': seasonStartYear ?? 0,
    'name': name,
    'type': type.name,
    'format': format.name,
    'participant_count': participantCount,
    'double_round_robin': doubleRoundRobin ? 1 : 0,
    'matchday_interval_days': matchdayIntervalDays,
    'min_rest_days': minRestDays,
    'group_size': groupSize,
    'group_count': groupCount,
    'group_double_round_robin': groupDoubleRoundRobin ? 1 : 0,
    'group_qualifiers_per_group': groupQualifiersPerGroup,
    'league_phase_opponents': leaguePhaseOpponents,
    'league_phase_home_matches': leaguePhaseHomeMatches,
    'league_phase_away_matches': leaguePhaseAwayMatches,
    'league_phase_qualifiers': leaguePhaseQualifiers,
    'knockout_legs': knockoutLegs,
    'final_single_match': finalSingleMatch ? 1 : 0,
    'neutral_final': neutralFinal ? 1 : 0,
    'extra_time': extraTime ? 1 : 0,
    'penalties': penalties ? 1 : 0,
    'away_goals': awayGoals ? 1 : 0,
    'use_byes': useByes ? 1 : 0,
    'trim_to_power_of_two': trimToPowerOfTwo ? 1 : 0,
    'field_size': fieldSize,
    'promotion_slots': promotionSlots,
    'relegation_slots': relegationSlots,
    'unavailable_dates': jsonEncode(
      unavailableDates.map((DateTime date) => date.toIso8601String()).toList(),
    ),
    'allowed_weekdays': jsonEncode(allowedWeekdays),
  };

  static CompetitionConfig fromDbMap(Map<String, Object?> m) {
    final Object? rawDates = m['unavailable_dates'];
    final Object? rawWeekdays = m['allowed_weekdays'];
    final List<DateTime> unavailableDates = rawDates == null
        ? <DateTime>[]
        : (jsonDecode(rawDates as String) as List<dynamic>)
              .map((dynamic value) => DateTime.parse(value as String))
              .toList();
    final List<int> allowedWeekdays = rawWeekdays == null
        ? <int>[]
        : (jsonDecode(rawWeekdays as String) as List<dynamic>)
              .map((dynamic value) => value as int)
              .toList();
    return CompetitionConfig(
      tournamentId: m['tournament_id'] as int,
      seasonStartYear: (m['season_start_year'] as int?) == 0
          ? null
          : m['season_start_year'] as int?,
      name: (m['name'] as String?) ?? '',
      type: _enumByName(
        CompetitionType.values,
        m['type'] as String?,
        CompetitionType.league,
      ),
      format: _enumByName(
        CompetitionFormat.values,
        m['format'] as String?,
        CompetitionFormat.doubleRoundRobin,
      ),
      participantCount: m['participant_count'] as int?,
      doubleRoundRobin: ((m['double_round_robin'] as int?) ?? 1) == 1,
      matchdayIntervalDays: (m['matchday_interval_days'] as int?) ?? 7,
      minRestDays: (m['min_rest_days'] as int?) ?? 2,
      groupSize: (m['group_size'] as int?) ?? 4,
      groupCount: (m['group_count'] as int?) ?? 0,
      groupDoubleRoundRobin:
          ((m['group_double_round_robin'] as int?) ?? 1) == 1,
      groupQualifiersPerGroup:
          (m['group_qualifiers_per_group'] as int?) ?? 2,
      leaguePhaseOpponents: (m['league_phase_opponents'] as int?) ?? 0,
      leaguePhaseHomeMatches: (m['league_phase_home_matches'] as int?) ?? 0,
      leaguePhaseAwayMatches: (m['league_phase_away_matches'] as int?) ?? 0,
      leaguePhaseQualifiers: (m['league_phase_qualifiers'] as int?) ?? 0,
      knockoutLegs: (m['knockout_legs'] as int?) ?? 1,
      finalSingleMatch: ((m['final_single_match'] as int?) ?? 1) == 1,
      neutralFinal: ((m['neutral_final'] as int?) ?? 0) == 1,
      extraTime: ((m['extra_time'] as int?) ?? 1) == 1,
      penalties: ((m['penalties'] as int?) ?? 1) == 1,
      awayGoals: ((m['away_goals'] as int?) ?? 0) == 1,
      useByes: ((m['use_byes'] as int?) ?? 1) == 1,
      trimToPowerOfTwo: ((m['trim_to_power_of_two'] as int?) ?? 0) == 1,
      fieldSize: m['field_size'] as int?,
      promotionSlots: (m['promotion_slots'] as int?) ?? 0,
      relegationSlots: (m['relegation_slots'] as int?) ?? 0,
      unavailableDates: unavailableDates,
      allowedWeekdays: allowedWeekdays,
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final T value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
