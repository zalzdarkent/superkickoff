/// Typed models for the core game entities. Only the entities the game
/// actively manipulates get classes; the rest are read as raw maps.
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
        name: m['name'] as String? ?? '',
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
      };
}

class Player {
  Player({
    required this.playerId,
    required this.name,
    required this.age,
    required this.positionId,
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
  });

  final int matchId;
  final int tournamentId;
  final int round;
  final int phase;
  final int status;
  final int homeTeamId;
  final int awayTeamId;
  final int stadiumId;
  final String? date;
  final int? homeGoals;
  final int? awayGoals;
  final int? winnerId;

  bool get isPlayed => status == DbMatch.matchFinished;
  bool get isScheduled => status == DbMatch.matchScheduled;

  factory FixtureMatch.fromMap(Map<String, Object?> m) => FixtureMatch(
        matchId: m['match_id'] as int,
        tournamentId: m['tournament_id'] as int,
        round: (m['round'] as int?) ?? 0,
        phase: (m['phase'] as int?) ?? 0,
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
  });

  final int messageId;
  final String title;
  final String body;
  final String? date;
  final String? sender;
  final bool isRead;
  final int type;

  factory Message.fromMap(Map<String, Object?> m) => Message(
        messageId: m['message_id'] as int,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        date: m['date'] as String?,
        sender: m['sender'] as String?,
        isRead: (m['is_read'] as int? ?? 0) == 1,
        type: (m['type'] as int?) ?? 0,
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
  int played, wins, draws, losses, goalsFor, goalsAgainst, points;

  int get goalDifference => goalsFor - goalsAgainst;
}
