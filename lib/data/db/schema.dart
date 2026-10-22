/// Central schema constants (English identifiers) plus value conventions.
///
/// All table names are top-level constants so call sites can import this file
/// with a prefix (`import 'schema.dart' as t;`) and write `t.matches`.
library;

// ------------------------------------------------------------------ tables
const String countries = 'countries';
const String teams = 'teams';
const String coaches = 'coaches';
const String stadiums = 'stadiums';
const String teamPlayers = 'team_players';
const String teamTactics = 'team_tactics';
const String teamLineups = 'team_lineups';
const String teamTraining = 'team_training';
const String teamYouthAcademy = 'team_youth_academy';
const String academyProspects = 'academy_prospects';
const String competitionPrizeRules = 'competition_prize_rules';
const String competitionPrizeAwards = 'competition_prize_awards';
const String scouts = 'scouts';
const String scoutReports = 'scout_reports';
const String teamLoans = 'team_loans';
const String countryCoaches = 'country_coaches';
const String countryCallups = 'country_callups';
const String players = 'players';
const String playerSkills = 'player_skills';
const String skills = 'skills';
const String positions = 'positions';
const String positionSkills = 'position_skills';
const String playerStatuses = 'player_statuses';
const String playerSeasonStats = 'player_season_stats';
const String playerSeasonStatsCountries = 'player_season_stats_countries';
const String contracts = 'contracts';
const String playerAwards = 'player_awards';
const String tournaments = 'tournaments';
const String tournamentCountries = 'tournament_countries';
const String divisions = 'divisions';
const String groups = 'groups';
const String seasons = 'seasons';
const String seasonTournaments = 'season_tournaments';
const String seasonTeams = 'season_teams';
const String seasonCountries = 'season_countries';
const String matches = 'matches';
const String matchIncidents = 'match_incidents';
const String matchPlayers = 'match_players';
const String matchPlayersCountries = 'match_players_countries';
const String countryMatches = 'country_matches';
const String referees = 'referees';
const String refereeTypes = 'referee_types';
const String suspensions = 'suspensions';
const String internationalSlots = 'international_slots';
const String playerTransfers = 'player_transfers';
const String coachTransfers = 'coach_transfers';
const String sponsors = 'sponsors';
const String sponsorships = 'sponsorships';
const String messages = 'messages';
const String news = 'news';
const String transferOffers = 'transfer_offers';
const String worldRankingHistory = 'world_ranking_history';
const String careerHistory = 'career_history';
const String managerProfile = 'manager_profile';

// ------------------------------------------------------- match statuses
const int matchScheduled = 1;
const int matchFinished = 2;
const int matchCancelled = 3;

// ----------------------------------------------- tournament organization
const int orgLeague = 1;
const int orgInternational = 2;
const int orgNationalCup = 3;
const int orgFriendly = 4;

// ------------------------------------------------ season tournament state
const int seasonTournamentActive = 1;
const int seasonTournamentArchived = 0;

// ------------------------------------------- players.squad_status values
const int squadReserve = 0;
const int squadFirstTeam = 1;
const int squadLoanListed = 2;

// ------------------------------------------ players.market_status values
const int marketActive = 1;
const int marketForSale = 2;
const int marketOnLoan = 3;

// ----------------------------------------- players.status_id references
const int statusActive = 1;
const int statusRetired = 2;
const int statusDead = 3;

// ---------------------------------------------- player_awards.type values
const int awardTopScorer = 1;
const int awardMvp = 2;
const int awardYoungPlayer = 3;

// -------------------------------------------- transfer_offers.status values
const int offerPending = 1;
const int offerAccepted = 2;
const int offerRejected = 3;
const int offerCountered = 4;
const int offerContractNegotiation = 5;
const int offerPlayerAccepted = 6;
const int offerPlayerRejected = 7;
const int offerCompleted = 8;
