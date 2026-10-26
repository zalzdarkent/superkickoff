/// Typed models for the core game entities. Only the entities the game
/// actively manipulates get classes; the rest are read as raw maps.
library;

import '../db/schema.dart' as t;
import '../../core/country_names.dart';

class Country {
  Country({
    required this.countryId,
    required this.name,
    required this.iso2,
    required this.power,
    required this.confederation,
  });

  final int countryId;
  final String name;
  final String iso2;
  final int power;
  final int confederation;

  factory Country.fromMap(Map<String, Object?> m) => Country(
    countryId: m['country_id'] as int,
    name: displayCountryName(
      m['name'] as String? ?? '',
      m['iso2'] as String? ?? '',
      countryId: m['country_id'] as int?,
    ),
    iso2: m['iso2'] as String? ?? '',
    power: (m['power'] as int?) ?? 0,
    confederation: (m['confederation'] as int?) ?? 0,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'country_id': countryId,
    'name': name,
    'iso2': iso2,
    'power': power,
    'confederation': confederation,
  };
}

/// The local manager identity used for the active career. This is deliberately
/// separate from the real-world coach record in the reference database.
class ManagerProfile {
  const ManagerProfile({required this.name, required this.countryId});

  final String name;
  final int countryId;
}

class Team {
  Team({
    required this.teamId,
    required this.name,
    required this.abbreviation,
    required this.countryId,
    required this.power,
    required this.value,
    required this.budget,
    required this.division,
    required this.stadiumId,
    required this.coachId,
    required this.foundedYear,
    this.logoBase64,
  });

  final int teamId;
  final String name;
  final String abbreviation;
  final int countryId;
  final int power;
  final int value;
  final int budget;
  final int division;
  final int stadiumId;
  final int coachId;
  final int foundedYear;
  final String? logoBase64;

  factory Team.fromMap(Map<String, Object?> m) => Team(
    teamId: m['team_id'] as int,
    name: m['name'] as String,
    abbreviation: m['abbreviation'] as String? ?? '',
    countryId: m['country_id'] as int,
    power: (m['power'] as int?) ?? 0,
    value: (m['value'] as int?) ?? 0,
    budget: (m['budget'] as int?) ?? 0,
    division: (m['division'] as int?) ?? 1,
    stadiumId: m['stadium_id'] as int,
    coachId: m['coach_id'] as int,
    foundedYear: (m['founded_year'] as int?) ?? 1900,
    logoBase64: m['logo_base64'] as String?,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'team_id': teamId,
    'name': name,
    'abbreviation': abbreviation,
    'country_id': countryId,
    'power': power,
    'value': value,
    'budget': budget,
    'division': division,
    'stadium_id': stadiumId,
    'coach_id': coachId,
    'founded_year': foundedYear,
    'logo_base64': logoBase64,
  };
}

class Player {
  Player({
    required this.playerId,
    required this.name,
    required this.age,
    required this.positionId,
    this.profile = 'D',
    required this.power,
    required this.potential,
    required this.fitness,
    required this.value,
    required this.salary,
    required this.countryId,
    required this.squadStatus,
    required this.marketStatus,
    required this.statusId,
    required this.isCaptain,
    required this.shirtNumber,
    required this.stars,
    required this.skillA,
    required this.skillB,
    required this.height,
    required this.championships,
  });

  final int playerId;
  final String name;
  final int age;
  final int positionId;

  /// Preferred foot: 'D' for right, 'I' for left.
  final String profile;
  final int power;
  final int potential;
  final int fitness;
  final int value;
  final int salary;
  final int countryId;
  final int squadStatus;
  final int marketStatus;
  final int statusId;
  final bool isCaptain;
  final int shirtNumber;
  final int stars;
  final int skillA;
  final int skillB;
  final int height;
  final String? championships;

  factory Player.fromMap(Map<String, Object?> m) => Player(
    playerId: m['player_id'] as int,
    name: m['name'] as String,
    age: (m['age'] as int?) ?? 17,
    positionId: m['position_id'] as int,
    profile: (m['profile'] as String?) ?? 'D',
    power: (m['power'] as int?) ?? 0,
    potential: (m['potential'] as int?) ?? 0,
    fitness: (m['fitness'] as int?) ?? 100,
    value: (m['value'] as int?) ?? 0,
    salary: (m['salary'] as int?) ?? 0,
    countryId: m['country_id'] as int,
    squadStatus: (m['squad_status'] as int?) ?? 1,
    marketStatus: (m['market_status'] as int?) ?? 1,
    statusId: (m['status_id'] as int?) ?? 1,
    isCaptain: (m['is_captain'] as int? ?? 0) == 1,
    shirtNumber: (m['shirt_number'] as int?) ?? 0,
    stars: (m['stars'] as int?) ?? 0,
    skillA: m['skill_a'] as int? ?? 0,
    skillB: m['skill_b'] as int? ?? 0,
    height: (m['height'] as int?) ?? 175,
    championships: m['championships'] as String?,
  );
}

class Tournament {
  Tournament({
    required this.tournamentId,
    required this.name,
    required this.organization,
    required this.divisionId,
    required this.slots,
    required this.promotionSlots,
    required this.relegationSpots,
    required this.points,
    required this.prizeTeams,
    required this.prizeTopScorer,
    required this.prizeMvp,
    required this.playDays,
    required this.rounds,
  });

  final int tournamentId;
  final String name;
  final int organization;
  final int divisionId;
  final int slots;
  final int promotionSlots;
  final int relegationSpots;
  final double points;
  final int prizeTeams;
  final int prizeTopScorer;
  final int prizeMvp;
  final String playDays;
  final int rounds;

  bool get isLeague => organization == DbOrg.orgLeague;
  bool get isInternational => organization == DbOrg.orgInternational;
  bool get isNationalCup => organization == DbOrg.orgNationalCup;

  factory Tournament.fromMap(Map<String, Object?> m) => Tournament(
    tournamentId: m['tournament_id'] as int,
    name: m['name'] as String,
    organization: (m['organization'] as int?) ?? 1,
    divisionId: (m['division_id'] as int?) ?? 1,
    slots: int.tryParse('${m['slots']}') ?? 16,
    promotionSlots: (m['promotion_slots'] as int?) ?? 0,
    relegationSpots: (m['relegation_spots'] as int?) ?? 0,
    points: (m['points'] as num?)?.toDouble() ?? 0,
    prizeTeams: (m['prize_teams'] as int?) ?? 0,
    prizeTopScorer: (m['prize_top_scorer'] as int?) ?? 0,
    prizeMvp: (m['prize_mvp'] as int?) ?? 0,
    playDays: m['play_days'] as String? ?? '6,7',
    rounds: (m['rounds'] as int?) ?? 1,
  );
}

/// Alias so model files do not each import the DB constants.
class DbOrg {
  DbOrg._();
  static const int orgLeague = 1;
  static const int orgInternational = 2;
  static const int orgNationalCup = 3;
}

class FixtureMatch {
  FixtureMatch({
    required this.matchId,
    required this.tournamentId,
    required this.round,
    required this.phase,
    required this.status,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.stadiumId,
    required this.date,
    required this.homeGoals,
    required this.awayGoals,
    required this.winnerId,
    this.groupId,
    this.penaltyHomeGoals,
    this.penaltyAwayGoals,
    this.leg = 1,
    this.seasonId = 0,
  });

  final int matchId;
  final int tournamentId;
  final int seasonId;
  final int round;
  final int phase;

  /// Set for group-stage matches; knockout rounds leave it null.
  final int? groupId;
  final int status;
  final int homeTeamId;
  final int awayTeamId;
  final int stadiumId;
  final String? date;
  final int? homeGoals;
  final int? awayGoals;
  final int? winnerId;

  /// Shootout score when a knockout tie was level after 90 minutes.
  final int? penaltyHomeGoals;
  final int? penaltyAwayGoals;

  /// Leg of the tie (1 or 2). Defaults to 1 for single-leg matches.
  final int leg;

  bool get isPlayed => status == DbMatch.matchFinished;
  bool get isScheduled => status == DbMatch.matchScheduled;

  factory FixtureMatch.fromMap(Map<String, Object?> m) => FixtureMatch(
    matchId: m['match_id'] as int,
    tournamentId: m['tournament_id'] as int,
    seasonId: (m['season_id'] as int?) ?? 0,
    round: (m['round'] as int?) ?? 0,
    phase: (m['phase'] as int?) ?? 0,
    groupId: m['group_id'] as int?,
    penaltyHomeGoals: (m['penalty_home_goals'] as int?) ?? 0,
    penaltyAwayGoals: (m['penalty_away_goals'] as int?) ?? 0,
    leg: (m['leg'] as int?) ?? 1,
    status: (m['status'] as int?) ?? 1,
    homeTeamId: m['home_team_id'] as int,
    awayTeamId: m['away_team_id'] as int,
    stadiumId: m['stadium_id'] as int,
    date: m['date'] as String?,
    homeGoals: m['home_goals'] as int?,
    awayGoals: m['away_goals'] as int?,
    winnerId: m['winner_id'] as int?,
  );
}

/// One knockout tie: a single match, or leg 1 + leg 2 of a two-legged tie.
class KnockoutTie {
  KnockoutTie(this.first, [this.second]);

  final FixtureMatch first;
  final FixtureMatch? second;

  bool get twoLegged => second != null;
  bool get complete => first.isPlayed && (second?.isPlayed ?? true);

  /// Aggregate from the point of view of leg 1's home / away club.
  int get homeAgg => (first.homeGoals ?? 0) + (second?.awayGoals ?? 0);
  int get awayAgg => (first.awayGoals ?? 0) + (second?.homeGoals ?? 0);

  /// Club that went through, once every leg is played.
  int? get winnerId => complete ? (second ?? first).winnerId : null;

  /// Aggregate oriented to [m]'s home / away club (leg 2 flips the venues).
  (int, int) aggregateFor(FixtureMatch m) =>
      m.matchId == first.matchId ? (homeAgg, awayAgg) : (awayAgg, homeAgg);

  /// Shootout of the deciding leg oriented to leg 1 home - leg 1 away, or null.
  (int, int)? get penalties {
    final FixtureMatch last = second ?? first;
    final int home = last.penaltyHomeGoals ?? 0;
    final int away = last.penaltyAwayGoals ?? 0;
    if (home == 0 && away == 0) return null;
    return second == null ? (home, away) : (away, home);
  }
}

/// Pairs the legs of knockout [matches] into ties. Pass knockout matches only:
/// league rounds also use leg 2 for their second half-season.
List<KnockoutTie> groupTies(List<FixtureMatch> matches) {
  final Map<String, FixtureMatch> open = <String, FixtureMatch>{};
  final List<KnockoutTie> ties = <KnockoutTie>[];
  for (final FixtureMatch m in matches) {
    final List<int> ids = <int>[m.homeTeamId, m.awayTeamId]..sort();
    final String key = '${m.tournamentId}:${m.phase}:${ids.join('-')}';
    final FixtureMatch? other = open[key];
    if (other != null && other.leg != m.leg) {
      open.remove(key);
      ties.add(
        other.leg < m.leg ? KnockoutTie(other, m) : KnockoutTie(m, other),
      );
    } else {
      open[key] = m;
    }
  }
  ties.addAll(open.values.map(KnockoutTie.new));
  return ties..sort(
    (KnockoutTie a, KnockoutTie b) =>
        a.first.matchId.compareTo(b.first.matchId),
  );
}

class DbMatch {
  DbMatch._();
  static const int matchScheduled = 1;
  static const int matchFinished = 2;
  static const int matchCancelled = 3;
}

class Position {
  Position({
    required this.positionId,
    required this.abbreviation,
    required this.name,
    required this.type,
  });

  final int positionId;
  final String abbreviation;
  final String name;
  final int type;

  factory Position.fromMap(Map<String, Object?> m) => Position(
    positionId: m['position_id'] as int,
    abbreviation: m['abbreviation'] as String,
    name: m['name'] as String,
    type: (m['type'] as int?) ?? 0,
  );
}

class Stadium {
  Stadium({
    required this.stadiumId,
    required this.name,
    required this.city,
    required this.capacityTotal,
  });

  final int stadiumId;
  final String name;
  final String? city;
  final int capacityTotal;

  factory Stadium.fromMap(Map<String, Object?> m) => Stadium(
    stadiumId: m['stadium_id'] as int,
    name: m['name'] as String? ?? '',
    city: m['city'] as String?,
    capacityTotal:
        ((m['capacity_general'] as int?) ?? 0) +
        ((m['capacity_stand'] as int?) ?? 0) +
        ((m['capacity_terrace'] as int?) ?? 0) +
        ((m['capacity_boxes'] as int?) ?? 0),
  );
}

class Message {
  Message({
    required this.messageId,
    required this.title,
    required this.body,
    required this.date,
    required this.sender,
    required this.isRead,
    required this.type,
    this.playerId,
    this.transferOfferId,
  });

  final int messageId;
  final String title;
  final String body;
  final String? date;
  final String? sender;
  final bool isRead;
  final int type;
  final int? playerId;
  final int? transferOfferId;

  factory Message.fromMap(Map<String, Object?> m) => Message(
    messageId: m['message_id'] as int,
    title: m['title'] as String? ?? '',
    body: m['body'] as String? ?? '',
    date: m['date'] as String?,
    sender: m['sender'] as String?,
    isRead: (m['is_read'] as int? ?? 0) == 1,
    type: (m['type'] as int?) ?? 0,
    playerId: m['player_id'] as int?,
    transferOfferId: m['transfer_offer_id'] as int?,
  );
}

class Season {
  Season({
    required this.seasonId,
    required this.name,
    required this.startYear,
    required this.endYear,
  });

  final int seasonId;
  final String name;
  final int startYear;
  final int endYear;

  factory Season.fromMap(Map<String, Object?> m) => Season(
    seasonId: m['season_id'] as int,
    name: m['name'] as String,
    startYear: (m['start_year'] as int?) ?? 2025,
    endYear: (m['end_year'] as int?) ?? 2026,
  );
}

/// A single standings-table row, computed on the fly from results.
class StandingRow {
  StandingRow({
    required this.teamId,
    required this.name,
    required this.abbreviation,
    this.logoBase64,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
  });

  final int teamId;
  final String name;
  final String abbreviation;
  final String? logoBase64;
  int played, wins, draws, losses, goalsFor, goalsAgainst, points;

  int get goalDifference => goalsFor - goalsAgainst;
}

/// Standings of one group in a tournament with a group stage.
class GroupTable {
  GroupTable({required this.groupId, required this.rows});

  final int groupId;
  final List<StandingRow> rows;
}

/// Standings and leaderboards for one competition in one season.
class CompetitionStats {
  const CompetitionStats({
    required this.standings,
    required this.groups,
    required this.scorers,
    required this.assists,
    required this.cleanSheets,
    required this.rated,
    this.region = '',
  });

  /// Continental zone of the league's country (europe, asia, ...), '' if none.
  final String region;
  final List<StandingRow> standings;
  final List<GroupTable> groups;
  final List<LeaderRow> scorers;
  final List<LeaderRow> assists;
  final List<LeaderRow> cleanSheets;
  final List<LeaderRow> rated;
}

/// One row of a statistical leaderboard (scorers, assists, clean sheets...).
class LeaderRow {
  LeaderRow({
    required this.playerId,
    required this.playerName,
    required this.clubName,
    required this.positionId,
    required this.teamId,
    this.profile = 'D',
    required this.value,
  });

  final int playerId;
  final String playerName;
  final String clubName;
  final int positionId;

  /// Team the player represented for these statistics.
  final int teamId;
  final String profile;
  final double value;

  /// Counts are whole numbers; ratings keep one decimal.
  String get display => value == value.roundToDouble()
      ? '${value.toInt()}'
      : value.toStringAsFixed(1);
}

/// One row of the squad statistics table for the current season.
class SquadStatRow {
  SquadStatRow({
    required this.playerId,
    required this.name,
    required this.positionId,
    required this.profile,
    required this.age,
    required this.power,
    required this.appearances,
    required this.minutes,
    required this.goals,
    required this.assists,
    required this.mvps,
    required this.yellowCards,
    required this.redCards,
    required this.rating,
  });

  final int playerId;
  final String name;
  final int positionId;
  final String profile;
  final int age;
  final int power;
  final int appearances;
  final int minutes;
  final int goals;
  final int assists;
  final int mvps;
  final int yellowCards;
  final int redCards;
  final double rating;
}

/// Active contract details shown in the player profile.
class ContractInfo {
  ContractInfo({
    required this.startDate,
    required this.endDate,
    required this.salary,
    this.goalBonus,
    this.assistBonus,
    this.mvpBonus,
    this.titleBonus,
    this.appearanceBonus,
  });

  final String startDate;
  final String endDate;
  final int salary;
  final int? goalBonus;
  final int? assistBonus;
  final int? mvpBonus;
  final int? titleBonus;
  final int? appearanceBonus;
}

/// Aggregated current-season numbers for one player.
class PlayerSeasonSummary {
  const PlayerSeasonSummary({
    required this.matches,
    required this.minutes,
    required this.goals,
    required this.assists,
    required this.mvps,
    required this.yellowCards,
    required this.redCards,
    required this.rating,
  });

  final int matches;
  final int minutes;
  final int goals;
  final int assists;
  final int mvps;
  final int yellowCards;
  final int redCards;
  final double rating;

  bool get isEmpty => matches == 0;

  static const PlayerSeasonSummary empty = PlayerSeasonSummary(
    matches: 0,
    minutes: 0,
    goals: 0,
    assists: 0,
    mvps: 0,
    yellowCards: 0,
    redCards: 0,
    rating: 0,
  );
}

/// One line of a player's transfer history.
class TransferRecord {
  TransferRecord({
    required this.playerId,
    required this.playerName,
    required this.date,
    required this.fromTeamId,
    required this.toTeamId,
    required this.fromTeamName,
    required this.toTeamName,
    required this.value,
    required this.type,
  });

  final int playerId;
  final String playerName;
  final String date;
  final int? fromTeamId;
  final int? toTeamId;
  final String fromTeamName;
  final String toTeamName;
  final int value;
  final int type;
}

/// Everything needed by the player profile sheet.
class PlayerDetail {
  PlayerDetail({
    required this.player,
    required this.clubId,
    required this.clubName,
    required this.countryName,
    required this.contract,
    required this.stats,
    required this.transfers,
    required this.suspensionMatches,
    required this.career,
    required this.awards,
  });

  final Player player;
  final int? clubId;
  final String clubName;
  final String countryName;
  final ContractInfo? contract;
  final PlayerSeasonSummary stats;
  final List<TransferRecord> transfers;
  final int suspensionMatches;
  final List<PlayerCareerRow> career;
  final List<PlayerAward> awards;
}

/// Club overview used by the club hub sheet (finances, coach, stadium).
class ClubOverview {
  ClubOverview({
    required this.team,
    required this.countryName,
    required this.stadiumName,
    required this.stadiumCity,
    required this.general,
    required this.stand,
    required this.terrace,
    required this.boxes,
    required this.maxGeneral,
    required this.maxStand,
    required this.maxTerrace,
    required this.maxBoxes,
    required this.coachName,
    required this.coachAge,
    required this.coachPoints,
    required this.coachCountry,
    required this.squadValue,
    required this.wageBill,
    required this.expiringContracts,
    required this.transferSpend,
    required this.transferIncome,
  });

  final Team team;
  final String countryName;
  final String stadiumName;
  final String stadiumCity;
  final int general;
  final int stand;
  final int terrace;
  final int boxes;
  final int maxGeneral;
  final int maxStand;
  final int maxTerrace;
  final int maxBoxes;
  final String coachName;
  final int coachAge;
  final int coachPoints;
  final String coachCountry;
  final int squadValue;
  final int wageBill;
  final int expiringContracts;
  final int transferSpend;
  final int transferIncome;

  int get capacity => general + stand + terrace + boxes;

  static int nextTier(int current, int max) {
    if (current >= max) return current;
    final int step = current ~/ 10 < 100 ? 100 : current ~/ 10;
    final int next = current + step;
    return next > max ? max : next;
  }

  int get upgradeSeats =>
      (nextTier(general, maxGeneral) - general) +
      (nextTier(stand, maxStand) - stand) +
      (nextTier(terrace, maxTerrace) - terrace) +
      (nextTier(boxes, maxBoxes) - boxes);

  bool get atMaxCapacity => upgradeSeats <= 0;

  int get expansionCost => upgradeSeats * 1200;

  int get netTransfers => transferIncome - transferSpend;
}

class FinanceSummary {
  const FinanceSummary({
    required this.ticketIncome,
    required this.sponsorIncome,
    required this.playerSaleIncome,
    required this.prizeIncome,
    required this.salaryExpense,
    required this.playerPurchaseExpense,
    required this.otherExpense,
  });

  final int ticketIncome;
  final int sponsorIncome;
  final int playerSaleIncome;
  final int prizeIncome;
  final int salaryExpense;
  final int playerPurchaseExpense;
  final int otherExpense;

  int get totalIncome =>
      ticketIncome + sponsorIncome + playerSaleIncome + prizeIncome;
  int get totalExpense => salaryExpense + playerPurchaseExpense + otherExpense;
  int get net => totalIncome - totalExpense;
}

/// Weekly training availability and eligible-player counts per focus.
class YouthAcademyState {
  const YouthAcademyState({
    required this.level,
    required this.upgradeCost,
    this.lastGraduatedDate,
  });

  final int level;
  final int upgradeCost;
  final String? lastGraduatedDate;

  bool get isMaxLevel => level >= 10;
}

class TrainingState {
  const TrainingState({
    required this.doneFocuses,
    required this.sessions,
    required this.matchesPlayed,
    required this.cost,
    required this.eligible,
  });

  /// Focus keys already trained on this matchday; each can run once.
  final Set<String> doneFocuses;
  final int sessions;
  final int matchesPlayed;
  final int cost;

  /// Focus key (see [TrainingFocus.name]) -> number of eligible players.
  final Map<String, int> eligible;
}

/// Result of one training session.
class TrainingOutcome {
  const TrainingOutcome({
    this.error,
    this.improved = const <String>[],
    this.cost = 0,
  });

  final String? error;
  final List<String> improved;
  final int cost;

  bool get ok => error == null;
}

/// One archived season in a player's career (from player_season_stats).
class PlayerCareerRow {
  PlayerCareerRow({
    required this.seasonId,
    required this.seasonName,
    required this.teamName,
    required this.matches,
    required this.minutes,
    required this.starts,
    required this.goals,
    required this.assists,
    required this.mvps,
    required this.yellowCards,
    required this.redCards,
    required this.ratingSum,
  });

  final int seasonId;
  final String seasonName;
  final String teamName;
  final int matches;
  final int minutes;
  final int starts;
  final int goals;
  final int assists;
  final int mvps;
  final int yellowCards;
  final int redCards;

  /// The archive stores the sum of match ratings; the UI shows the average.
  final int ratingSum;

  double get rating => matches == 0 ? 0 : ratingSum / matches;
}

/// A player award stored in player_awards.
class PlayerAward {
  const PlayerAward({
    required this.awardId,
    required this.playerId,
    required this.playerName,
    required this.teamName,
    required this.type,
    required this.year,
    required this.seasonId,
    this.goals,
    this.rating,
    this.statSubtitle,
    this.positionId,
    this.teamId,
  });

  final int awardId;
  final int playerId;
  final String playerName;
  final String teamName;
  final int type;
  final int year;
  final int seasonId;
  final int? goals;
  final double? rating;
  final String? statSubtitle;
  final int? positionId;
  final int? teamId;

  String get label => switch (type) {
    t.awardBallonDor => "Ballon d'Or",
    t.awardTopScorer => 'Golden Boot',
    t.awardGoldenGlove => 'Golden Glove',
    t.awardYoungPlayer => 'Best Young Player',
    t.awardMvp => 'Player of the Season (MVP)',
    t.awardManagerOfTheYear => 'Manager of the Year',
    t.awardTeamOfTheYear => 'Team of the Year',
    _ => 'Award',
  };

  String get shortLabel => switch (type) {
    t.awardBallonDor => "Ballon d'Or",
    t.awardTopScorer => 'Golden Boot',
    t.awardGoldenGlove => 'Golden Glove',
    t.awardYoungPlayer => 'Best Young',
    t.awardMvp => 'MVP',
    t.awardManagerOfTheYear => 'Manager of Year',
    t.awardTeamOfTheYear => 'Team of Year',
    _ => 'Award',
  };
}

/// Aggregated gala summary for a season: individual award winners,
/// Team of the Year (Once Ideal), and club honours.
class SeasonGalaSummary {
  const SeasonGalaSummary({
    required this.seasonId,
    required this.year,
    required this.seasonName,
    this.ballonDor,
    this.goldenBoot,
    this.goldenGlove,
    this.youngPlayer,
    this.mvp,
    this.managerOfTheYear,
    this.teamOfTheYear = const <PlayerAward>[],
    this.clubTrophies = const <ClubTrophy>[],
    this.userClubAwards = const <PlayerAward>[],
  });

  final int seasonId;
  final int year;
  final String seasonName;
  final PlayerAward? ballonDor;
  final PlayerAward? goldenBoot;
  final PlayerAward? goldenGlove;
  final PlayerAward? youngPlayer;
  final PlayerAward? mvp;
  final PlayerAward? managerOfTheYear;
  final List<PlayerAward> teamOfTheYear;
  final List<ClubTrophy> clubTrophies;
  final List<PlayerAward> userClubAwards;

  bool get isEmpty =>
      ballonDor == null &&
      goldenBoot == null &&
      goldenGlove == null &&
      youngPlayer == null &&
      teamOfTheYear.isEmpty;
}

/// A transfer offer in negotiation.
class TransferOffer {
  TransferOffer({
    required this.offerId,
    required this.playerId,
    required this.playerName,
    required this.fromTeamId,
    required this.fromTeamName,
    required this.toTeamId,
    required this.toTeamName,
    required this.offerAmount,
    required this.playerValue,
    required this.playerSalary,
    required this.status,
    this.counterAmount,
    this.proposedSalary,
    this.proposedDurationYears,
    required this.createdDate,
    this.updatedDate,
    this.messageId,
    this.isLoan = false,
    this.loanSeasons = 1,
    this.agreementDate,
    this.effectiveDate,
    this.eligibleDate,
    this.transferType = 'permanent',
    this.loanMonths,
    this.wageSplitRatio = 1.0,
    this.loanStartDate,
    this.loanEndDate,
    this.cancellationReason,
  });

  final int offerId;
  final int playerId;
  final String playerName;
  final int fromTeamId;
  final String fromTeamName;
  final int toTeamId;
  final String toTeamName;
  final int offerAmount;
  final int playerValue;
  final int playerSalary;
  final int status;
  final int? counterAmount;
  final int? proposedSalary;
  final int? proposedDurationYears;
  final String createdDate;
  final String? updatedDate;
  final int? messageId;
  final bool isLoan;

  /// Seasons the borrower keeps the player (1 or 2); loans only.
  final int loanSeasons;

  final String? agreementDate;
  final String? effectiveDate;
  final String? eligibleDate;
  final String transferType;
  final int? loanMonths;
  final double wageSplitRatio;
  final String? loanStartDate;
  final String? loanEndDate;
  final String? cancellationReason;

  bool get isScheduled => status == t.offerAwaitingWindow;
  bool get isCompleted => status == t.offerCompleted;
  bool get isRejected =>
      status == t.offerRejected || status == t.offerPlayerRejected;
  bool get isCancelled => status == t.offerCancelled;
  bool get isFailed => status == t.offerFailed;
  bool get isNegotiating =>
      status == t.offerPending ||
      status == t.offerCountered ||
      status == t.offerContractNegotiation;

  String get statusLabel {
    switch (status) {
      case t.offerPending:
        return 'Offer Submitted';
      case t.offerAccepted:
        return 'Offer Accepted';
      case t.offerRejected:
        return 'Rejected';
      case t.offerCountered:
        return 'Negotiating (Countered)';
      case t.offerContractNegotiation:
        return 'Negotiating Contract';
      case t.offerPlayerAccepted:
        return 'Agreement Reached';
      case t.offerPlayerRejected:
        return 'Rejected by Player';
      case t.offerCompleted:
        return 'Completed';
      case t.offerAwaitingWindow:
        return 'Awaiting Transfer Window (Scheduled)';
      case t.offerCancelled:
        return 'Cancelled';
      case t.offerFailed:
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  factory TransferOffer.fromMap(Map<String, Object?> m) => TransferOffer(
    offerId: m['offer_id'] as int,
    playerId: m['player_id'] as int,
    playerName: m['player_name'] as String? ?? '',
    fromTeamId: m['from_team_id'] as int,
    fromTeamName: m['from_team_name'] as String? ?? '',
    toTeamId: m['to_team_id'] as int,
    toTeamName: m['to_team_name'] as String? ?? '',
    offerAmount: (m['offer_amount'] as int?) ?? 0,
    playerValue: (m['player_value'] as int?) ?? 0,
    playerSalary: (m['player_salary'] as int?) ?? 0,
    status: (m['status'] as int?) ?? 1,
    counterAmount: m['counter_amount'] as int?,
    proposedSalary: m['proposed_salary'] as int?,
    proposedDurationYears: m['proposed_duration_years'] as int?,
    createdDate: m['created_date'] as String? ?? '',
    updatedDate: m['updated_date'] as String?,
    messageId: m['message_id'] as int?,
    isLoan: (m['is_loan'] as int? ?? 0) == 1,
    loanSeasons: (m['loan_seasons'] as int?) ?? 1,
    agreementDate: m['agreement_date'] as String?,
    effectiveDate: m['effective_date'] as String?,
    eligibleDate: m['eligible_date'] as String?,
    transferType: (m['transfer_type'] as String?) ?? 'permanent',
    loanMonths: m['loan_months'] as int?,
    wageSplitRatio: (m['wage_split_ratio'] as num?)?.toDouble() ?? 1.0,
    loanStartDate: m['loan_start_date'] as String?,
    loanEndDate: m['loan_end_date'] as String?,
    cancellationReason: m['cancellation_reason'] as String?,
  );
}

/// Transfer Window configuration and status for a league/country in a season.
class TransferWindow {
  TransferWindow({
    required this.windowId,
    required this.seasonId,
    required this.countryId,
    this.tournamentId = 0,
    required this.windowType,
    required this.startDate,
    required this.endDate,
    this.isOpen = false,
    this.allowFreeAgentsOutside = true,
  });

  final int windowId;
  final int seasonId;
  final int countryId;
  final int tournamentId;

  /// 'summer' or 'winter'
  final String windowType;
  final String startDate;
  final String endDate;
  final bool isOpen;
  final bool allowFreeAgentsOutside;

  bool get isSummer => windowType.toLowerCase() == 'summer';
  bool get isWinter => windowType.toLowerCase() == 'winter';

  String get displayName =>
      isSummer ? 'Summer Transfer Window' : 'Winter Transfer Window';

  bool isWindowOpen(String currentDate) {
    return currentDate.compareTo(startDate) >= 0 &&
        currentDate.compareTo(endDate) <= 0;
  }

  bool isDeadlineDay(String currentDate) {
    if (!isWindowOpen(currentDate)) return false;
    final DateTime? current = DateTime.tryParse(currentDate);
    final DateTime? end = DateTime.tryParse(endDate);
    if (current == null || end == null) return currentDate == endDate;
    return end.difference(current).inDays <= 0;
  }

  int daysUntilOpen(String currentDate) {
    final DateTime? current = DateTime.tryParse(currentDate);
    final DateTime? start = DateTime.tryParse(startDate);
    if (current == null || start == null) return 0;
    final int diff = start.difference(current).inDays;
    return diff > 0 ? diff : 0;
  }

  int daysUntilDeadline(String currentDate) {
    final DateTime? current = DateTime.tryParse(currentDate);
    final DateTime? end = DateTime.tryParse(endDate);
    if (current == null || end == null) return 0;
    final int diff = end.difference(current).inDays;
    return diff >= 0 ? diff : 0;
  }

  int get durationDays {
    final DateTime? start = DateTime.tryParse(startDate);
    final DateTime? end = DateTime.tryParse(endDate);
    if (start == null || end == null) return 0;
    return end.difference(start).inDays;
  }

  String statusBadgeText(String currentDate) {
    if (isDeadlineDay(currentDate)) {
      return 'DEADLINE DAY';
    } else if (isWindowOpen(currentDate)) {
      final int left = daysUntilDeadline(currentDate);
      return 'TERBUKA (${left}d tersisa)';
    } else if (currentDate.compareTo(startDate) < 0) {
      final int until = daysUntilOpen(currentDate);
      return 'Membuka dlm ${until}d';
    } else {
      return 'DITUTUP';
    }
  }

  factory TransferWindow.fromMap(Map<String, Object?> m) => TransferWindow(
    windowId: (m['window_id'] as int?) ?? 0,
    seasonId: (m['season_id'] as int?) ?? 0,
    countryId: (m['country_id'] as int?) ?? 0,
    tournamentId: (m['tournament_id'] as int?) ?? 0,
    windowType: (m['window_type'] as String?) ?? 'summer',
    startDate: (m['start_date'] as String?) ?? '',
    endDate: (m['end_date'] as String?) ?? '',
    isOpen: ((m['is_open'] as int?) ?? 0) == 1,
    allowFreeAgentsOutside:
        ((m['allow_free_agents_outside'] as int?) ?? 1) == 1,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (windowId > 0) 'window_id': windowId,
    'season_id': seasonId,
    'country_id': countryId,
    'tournament_id': tournamentId,
    'window_type': windowType,
    'start_date': startDate,
    'end_date': endDate,
    'is_open': isOpen ? 1 : 0,
    'allow_free_agents_outside': allowFreeAgentsOutside ? 1 : 0,
  };
}

/// An unassigned prospect graduated from the youth academy.
class YouthProspect {
  YouthProspect({
    required this.prospectId,
    required this.teamId,
    required this.name,
    required this.age,
    required this.positionId,
    required this.power,
    required this.potential,
    required this.stars,
    required this.profile,
    required this.height,
    required this.countryId,
    required this.createdDate,
    required this.signed,
  });

  final int prospectId;
  final int teamId;
  final String name;
  final int age;
  final int positionId;
  final int power;
  final int potential;
  final int stars;
  final String profile;
  final int height;
  final int countryId;
  final String createdDate;
  final bool signed;

  factory YouthProspect.fromMap(Map<String, Object?> m) => YouthProspect(
    prospectId: m['prospect_id'] as int,
    teamId: m['team_id'] as int,
    name: m['name'] as String? ?? 'Prospect',
    age: (m['age'] as int?) ?? 17,
    positionId: (m['position_id'] as int?) ?? 1,
    power: (m['power'] as int?) ?? 50,
    potential: (m['potential'] as int?) ?? 60,
    stars: (m['stars'] as int?) ?? 0,
    profile: (m['profile'] as String?) ?? 'D',
    height: (m['height'] as int?) ?? 178,
    countryId: (m['country_id'] as int?) ?? 141,
    createdDate: (m['created_date'] as String?) ?? '',
    signed: (m['signed'] as int? ?? 0) == 1,
  );
}

/// An active or proposed sponsorship deal.
class ClubSponsorship {
  ClubSponsorship({
    required this.sponsorshipId,
    required this.type,
    required this.teamId,
    required this.sponsorId,
    required this.sponsorName,
    required this.seasonId,
    required this.baseReward,
    required this.weeklyReward,
    required this.target,
    required this.bonusPrize,
    required this.status,
    required this.extraData,
  });

  final int sponsorshipId;
  final int type; // 1 = Main Kit, 2 = Stadium, 3 = Sleeve
  final int teamId;
  final int sponsorId;
  final String sponsorName;
  final int seasonId;
  final int baseReward; // Upfront signing bonus
  final int weeklyReward;
  final int target; // League position target (e.g. 1 = Champion, 4 = Top 4)
  final int bonusPrize;
  final int status; // 1 = active, 0 = expired
  final String extraData;

  String get typeLabel => switch (type) {
    1 => 'Main Shirt Sponsor',
    2 => 'Stadium Sponsor',
    3 => 'Sleeve Sponsor',
    _ => 'Official Partner',
  };

  factory ClubSponsorship.fromMap(Map<String, Object?> m) => ClubSponsorship(
    sponsorshipId: (m['sponsorship_id'] as int?) ?? 0,
    type: (m['type'] as int?) ?? 1,
    teamId: (m['team_id'] as int?) ?? 0,
    sponsorId: (m['sponsor_id'] as int?) ?? 1,
    sponsorName:
        (m['sponsor_name'] as String?) ??
        (m['extra_data'] as String?) ??
        'Sponsor',
    seasonId: (m['season_id'] as int?) ?? 0,
    baseReward: (m['base_reward'] as int?) ?? 0,
    weeklyReward: (m['progress'] as int?) ?? 0,
    target: (m['target'] as int?) ?? 4,
    bonusPrize: (m['is_unique_prize'] as int?) ?? 0,
    status: (m['status'] as int?) ?? 1,
    extraData: (m['extra_data'] as String?) ?? '',
  );
}

/// A hired scout that can be deployed to uncover wonderkids.
class Scout {
  Scout({
    required this.scoutId,
    required this.teamId,
    required this.name,
    required this.stars,
    required this.region,
    required this.salary,
    required this.status,
    this.returnDate,
    this.lastReport,
  });

  final int scoutId;
  final int teamId;
  final String name;
  final int stars; // 1 to 5 stars
  final String? region;
  final int salary;
  final String status; // 'idle', 'scouting'
  final String? returnDate;
  final String? lastReport;

  bool get isScouting => status == 'scouting';

  factory Scout.fromMap(Map<String, Object?> m) => Scout(
    scoutId: m['scout_id'] as int,
    teamId: m['team_id'] as int,
    name: m['name'] as String? ?? 'Scout',
    stars: (m['stars'] as int?) ?? 1,
    region: m['region'] as String?,
    salary: (m['salary'] as int?) ?? 5000,
    status: (m['status'] as String?) ?? 'idle',
    returnDate: m['return_date'] as String?,
    lastReport: m['last_report'] as String?,
  );
}

/// A scouted wonderkid prospect waiting to be signed.
class ScoutWonderkid {
  ScoutWonderkid({
    required this.reportId,
    required this.teamId,
    required this.scoutId,
    required this.scoutName,
    required this.region,
    required this.date,
    required this.playerName,
    required this.age,
    required this.positionId,
    required this.power,
    required this.potential,
    required this.value,
    required this.countryId,
    required this.signed,
  });

  final int reportId;
  final int teamId;
  final int scoutId;
  final String scoutName;
  final String region;
  final String date;
  final String playerName;
  final int age;
  final int positionId;
  final int power;
  final int potential;
  final int value;
  final int countryId;
  final bool signed;

  factory ScoutWonderkid.fromMap(Map<String, Object?> m) => ScoutWonderkid(
    reportId: m['report_id'] as int,
    teamId: m['team_id'] as int,
    scoutId: m['scout_id'] as int,
    scoutName: m['scout_name'] as String? ?? 'Scout',
    region: m['region'] as String? ?? '',
    date: m['date'] as String? ?? '',
    playerName: m['player_name'] as String? ?? 'Wonderkid',
    age: (m['age'] as int?) ?? 17,
    positionId: (m['position_id'] as int?) ?? 1,
    power: (m['power'] as int?) ?? 65,
    potential: (m['potential'] as int?) ?? 85,
    value: (m['value'] as int?) ?? 1000000,
    countryId: (m['country_id'] as int?) ?? 141,
    signed: (m['signed'] as int? ?? 0) == 1,
  );
}

/// One season in the manager's career history.
class CareerSeason {
  CareerSeason({
    required this.seasonId,
    required this.seasonName,
    required this.teamName,
    required this.matches,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.championships,
  });

  final int seasonId;
  final String seasonName;
  final String teamName;
  final int matches;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final String championships;

  String get record => '$wins-$draws-$losses';
}

/// One trophy won by a club, derived from a completed competition.
class ClubTrophy {
  const ClubTrophy({
    required this.tournamentId,
    required this.tournamentName,
    required this.organization,
    required this.seasonId,
    required this.seasonName,
    required this.year,
  });

  final int tournamentId;
  final String tournamentName;
  final int organization;
  final int seasonId;
  final String seasonName;
  final int year;

  bool get isLeague => organization == DbOrg.orgLeague;
  bool get isInternational => organization == DbOrg.orgInternational;
}

/// Combined club history payload for the club hub.
class ClubHistory {
  const ClubHistory({required this.seasons, required this.awards});

  final List<CareerSeason> seasons;
  final List<PlayerAward> awards;

  bool get isEmpty => seasons.isEmpty && awards.isEmpty;
}

/// One story in the News menu. [scope] is 'world', 'region' or 'league';
/// [importance] runs 1 (filler) to 5 (front page).
class NewsItem {
  const NewsItem({
    required this.ref,
    required this.seasonId,
    required this.date,
    required this.scope,
    required this.category,
    required this.headline,
    required this.body,
    this.importance = 1,
    this.teamId,
    this.playerId,
    this.newsId = 0,
  });

  final int newsId;
  final String ref;
  final int seasonId;
  final String date;
  final String scope;
  final String category;
  final String headline;
  final String body;
  final int importance;
  final int? teamId;
  final int? playerId;

  factory NewsItem.fromMap(Map<String, Object?> m) => NewsItem(
    newsId: m['news_id'] as int,
    ref: m['ref'] as String,
    seasonId: m['season_id'] as int,
    date: m['date'] as String,
    scope: m['scope'] as String,
    category: m['category'] as String,
    headline: m['headline'] as String,
    body: m['body'] as String,
    importance: (m['importance'] as int?) ?? 1,
    teamId: m['team_id'] as int?,
    playerId: m['player_id'] as int?,
  );
}
