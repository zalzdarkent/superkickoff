import '../db/schema.dart' as t;

/// Kind of international calendar window.
enum InternationalWindowType {
  fifaWindow,
  qualifiers,
  finalTournament,
  friendly,
}

/// A calendar window dedicated to national-team football.
class InternationalWindow {
  const InternationalWindow({
    required this.windowId,
    required this.seasonId,
    required this.name,
    required this.windowType,
    required this.startDate,
    required this.endDate,
    required this.releaseStartDate,
    required this.returnDate,
    this.isMandatoryRelease = true,
    this.maxMatches = 2,
    this.clubFixturesAllowed = false,
  });

  final String windowId;
  final int seasonId;
  final String name;
  final InternationalWindowType windowType;
  final String startDate;
  final String endDate;
  final String releaseStartDate;
  final String returnDate;
  final bool isMandatoryRelease;
  final int maxMatches;
  final bool clubFixturesAllowed;

  bool containsDate(String date) {
    final String clean = date.length >= 10 ? date.substring(0, 10) : date;
    final String s = startDate.length >= 10 ? startDate.substring(0, 10) : startDate;
    final String e = endDate.length >= 10 ? endDate.substring(0, 10) : endDate;
    return clean.compareTo(s) >= 0 && clean.compareTo(e) <= 0;
  }

  bool isPlayerReleased(String date) {
    final String clean = date.length >= 10 ? date.substring(0, 10) : date;
    final String s = releaseStartDate.length >= 10 ? releaseStartDate.substring(0, 10) : releaseStartDate;
    final String e = returnDate.length >= 10 ? returnDate.substring(0, 10) : returnDate;
    return clean.compareTo(s) >= 0 && clean.compareTo(e) <= 0;
  }

  factory InternationalWindow.fromMap(Map<String, Object?> m) {
    final String typeStr = (m['window_type'] as String?) ?? 'fifaWindow';
    final InternationalWindowType type = InternationalWindowType.values.firstWhere(
      (InternationalWindowType w) => w.name == typeStr,
      orElse: () => InternationalWindowType.fifaWindow,
    );
    return InternationalWindow(
      windowId: m['window_id'] as String,
      seasonId: (m['season_id'] as int?) ?? 1,
      name: (m['name'] as String?) ?? 'FIFA International Window',
      windowType: type,
      startDate: m['start_date'] as String,
      endDate: m['end_date'] as String,
      releaseStartDate: m['release_start_date'] as String,
      returnDate: m['return_date'] as String,
      isMandatoryRelease: ((m['is_mandatory'] as int?) ?? 1) == 1,
      maxMatches: (m['max_matches'] as int?) ?? 2,
      clubFixturesAllowed: ((m['club_fixtures_allowed'] as int?) ?? 0) == 1,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'window_id': windowId,
    'season_id': seasonId,
    'name': name,
    'window_type': windowType.name,
    'start_date': startDate,
    'end_date': endDate,
    'release_start_date': releaseStartDate,
    'return_date': returnDate,
    'is_mandatory': isMandatoryRelease ? 1 : 0,
    'max_matches': maxMatches,
    'club_fixtures_allowed': clubFixturesAllowed ? 1 : 0,
  };
}

/// Active national-team duty record for a player during an international window.
class InternationalDuty {
  const InternationalDuty({
    this.dutyId = 0,
    required this.seasonId,
    required this.countryId,
    required this.playerId,
    required this.windowId,
    required this.releaseDate,
    required this.returnDate,
    this.squadNumber = 0,
    this.isCaptain = false,
    this.status = 'active',
  });

  final int dutyId;
  final int seasonId;
  final int countryId;
  final int playerId;
  final String windowId;
  final String releaseDate;
  final String returnDate;
  final int squadNumber;
  final bool isCaptain;
  final String status;

  String get releaseStartDate => releaseDate;

  bool isActiveOn(String date) {
    if (status != 'active') return false;
    final String clean = date.length >= 10 ? date.substring(0, 10) : date;
    final String s = releaseDate.length >= 10 ? releaseDate.substring(0, 10) : releaseDate;
    final String e = returnDate.length >= 10 ? returnDate.substring(0, 10) : returnDate;
    return clean.compareTo(s) >= 0 && clean.compareTo(e) <= 0;
  }

  factory InternationalDuty.fromMap(Map<String, Object?> m) => InternationalDuty(
    dutyId: (m['duty_id'] as int?) ?? 0,
    seasonId: (m['season_id'] as int?) ?? 1,
    countryId: m['country_id'] as int,
    playerId: m['player_id'] as int,
    windowId: (m['window_id'] as String?) ?? '',
    releaseDate: (m['release_date'] as String?) ?? '',
    returnDate: (m['return_date'] as String?) ?? '',
    squadNumber: (m['squad_number'] as int?) ?? 0,
    isCaptain: ((m['is_captain'] as int?) ?? 0) == 1,
    status: (m['status'] as String?) ?? 'active',
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (dutyId > 0) 'duty_id': dutyId,
    'season_id': seasonId,
    'country_id': countryId,
    'player_id': playerId,
    'window_id': windowId,
    'release_date': releaseDate,
    'return_date': returnDate,
    'squad_number': squadNumber,
    'is_captain': isCaptain ? 1 : 0,
    'status': status,
  };
}

/// A national-team fixture.
class CountryMatch {
  const CountryMatch({
    required this.matchId,
    required this.tournamentId,
    required this.seasonId,
    this.refereeId = 0,
    this.stadiumId = 0,
    required this.homeCountryId,
    required this.awayCountryId,
    this.homeGoals,
    this.awayGoals,
    this.winnerId,
    this.phase = 0,
    this.round = 0,
    this.status = t.matchScheduled,
    this.leg = 1,
    this.date,
    this.penaltyHomeGoals,
    this.penaltyAwayGoals,
    this.groupId,
    this.windowId,
    this.originalDate,
    this.rescheduleReason,
  });

  final int matchId;
  final int tournamentId;
  final int seasonId;
  final int refereeId;
  final int stadiumId;
  final int homeCountryId;
  final int awayCountryId;
  final int? homeGoals;
  final int? awayGoals;
  final int? winnerId;
  final int phase;
  final int round;
  final int status;
  final int leg;
  final String? date;
  final int? penaltyHomeGoals;
  final int? penaltyAwayGoals;
  final int? groupId;
  final String? windowId;
  final String? originalDate;
  final String? rescheduleReason;

  bool get isPlayed => status == t.matchFinished;
  bool get isDraw => (homeGoals ?? 0) == (awayGoals ?? 0);

  int? get homeScore => homeGoals;
  int? get awayScore => awayGoals;

  String get scoreText => isPlayed ? '$homeGoals - $awayGoals' : 'vs';

  factory CountryMatch.fromMap(Map<String, Object?> m) => CountryMatch(
    matchId: m['match_id'] as int,
    tournamentId: (m['tournament_id'] as int?) ?? 0,
    seasonId: (m['season_id'] as int?) ?? 1,
    refereeId: (m['referee_id'] as int?) ?? 0,
    stadiumId: (m['stadium_id'] as int?) ?? 0,
    homeCountryId: (m['home_country_id'] as int?) ?? 0,
    awayCountryId: (m['away_country_id'] as int?) ?? 0,
    homeGoals: m['home_goals'] as int?,
    awayGoals: m['away_goals'] as int?,
    winnerId: m['winner_id'] as int?,
    phase: (m['phase'] as int?) ?? 0,
    round: (m['round'] as int?) ?? 0,
    status: (m['status'] as int?) ?? t.matchScheduled,
    leg: (m['leg'] as int?) ?? 1,
    date: m['date'] as String?,
    penaltyHomeGoals: m['penalty_home_goals'] as int?,
    penaltyAwayGoals: m['penalty_away_goals'] as int?,
    groupId: m['group_id'] as int?,
    windowId: m['window_id'] as String?,
    originalDate: m['original_date'] as String?,
    rescheduleReason: m['reschedule_reason'] as String?,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'match_id': matchId,
    'tournament_id': tournamentId,
    'season_id': seasonId,
    'referee_id': refereeId,
    'stadium_id': stadiumId,
    'home_country_id': homeCountryId,
    'away_country_id': awayCountryId,
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'winner_id': winnerId,
    'phase': phase,
    'round': round,
    'status': status,
    'leg': leg,
    'date': date,
    'penalty_home_goals': penaltyHomeGoals,
    'penalty_away_goals': penaltyAwayGoals,
    'group_id': groupId,
    'window_id': windowId,
    'original_date': originalDate,
    'reschedule_reason': rescheduleReason,
  };
}

/// Player international representation eligibility.
class PlayerNationalEligibility {
  const PlayerNationalEligibility({
    required this.playerId,
    required this.countryId,
    this.isPrimary = true,
    this.isLocked = false,
    this.notes,
  });

  final int playerId;
  final int countryId;
  final bool isPrimary;
  final bool isLocked;
  final String? notes;

  factory PlayerNationalEligibility.fromMap(Map<String, Object?> m) =>
      PlayerNationalEligibility(
        playerId: m['player_id'] as int,
        countryId: m['country_id'] as int,
        isPrimary: ((m['is_primary'] as int?) ?? 1) == 1,
        isLocked: ((m['is_locked'] as int?) ?? 0) == 1,
        notes: m['notes'] as String?,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    'player_id': playerId,
    'country_id': countryId,
    'is_primary': isPrimary ? 1 : 0,
    'is_locked': isLocked ? 1 : 0,
    'notes': notes,
  };
}

/// Aggregate international stats for a player (career or season).
class PlayerNationalStats {
  const PlayerNationalStats({
    required this.playerId,
    required this.countryId,
    this.playerName = '',
    this.positionId = 1,
    this.power = 50,
    this.shirtNumber,
    this.clubName,
    this.clubId = 0,
    this.isCaptain = false,
    this.seasonId,
    this.matchesPlayed = 0,
    this.minutes = 0,
    this.starts = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    this.mvps = 0,
    this.rating = 6.0,
  });

  final int playerId;
  final int countryId;
  final String playerName;
  final int positionId;
  final int power;
  final int? shirtNumber;
  final String? clubName;
  final int clubId;
  final bool isCaptain;
  final int? seasonId;
  final int matchesPlayed;
  final int minutes;
  final int starts;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final int mvps;
  final double rating;

  int get caps => matchesPlayed;

  PlayerNationalStats copyWith({
    String? playerName,
    int? positionId,
    int? power,
    int? shirtNumber,
    String? clubName,
    int? clubId,
    bool? isCaptain,
    int? seasonId,
    int? matchesPlayed,
    int? minutes,
    int? starts,
    int? goals,
    int? assists,
    int? yellowCards,
    int? redCards,
    int? mvps,
    double? rating,
  }) =>
      PlayerNationalStats(
        playerId: playerId,
        countryId: countryId,
        playerName: playerName ?? this.playerName,
        positionId: positionId ?? this.positionId,
        power: power ?? this.power,
        shirtNumber: shirtNumber ?? this.shirtNumber,
        clubName: clubName ?? this.clubName,
        clubId: clubId ?? this.clubId,
        isCaptain: isCaptain ?? this.isCaptain,
        seasonId: seasonId ?? this.seasonId,
        matchesPlayed: matchesPlayed ?? this.matchesPlayed,
        minutes: minutes ?? this.minutes,
        starts: starts ?? this.starts,
        goals: goals ?? this.goals,
        assists: assists ?? this.assists,
        yellowCards: yellowCards ?? this.yellowCards,
        redCards: redCards ?? this.redCards,
        mvps: mvps ?? this.mvps,
        rating: rating ?? this.rating,
      );

  factory PlayerNationalStats.fromMap(Map<String, Object?> m) =>
      PlayerNationalStats(
        playerId: m['player_id'] as int,
        countryId: m['country_id'] as int,
        seasonId: m['season_id'] as int?,
        clubId: (m['club_id'] as int?) ?? 0,
        isCaptain: ((m['is_captain'] as int?) ?? 0) == 1,
        matchesPlayed: (m['matches_played'] as int?) ?? 0,
        minutes: (m['minutes'] as int?) ?? 0,
        starts: (m['starts'] as int?) ?? 0,
        goals: (m['goals'] as int?) ?? 0,
        assists: (m['assists'] as int?) ?? 0,
        yellowCards: (m['yellow_cards'] as int?) ?? 0,
        redCards: (m['red_cards'] as int?) ?? 0,
        mvps: (m['mvps'] as int?) ?? 0,
        rating: ((m['rating'] as num?) ?? 60).toDouble() / 10.0,
      );
}
