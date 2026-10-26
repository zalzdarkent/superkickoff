import 'dart:math';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';

enum FixtureViolationSeverity { warning, error }

/// Actionable validation result. Every violation names the competition, season,
/// fixture, clubs and round so it can be reported to the user instead of
/// returning a generic boolean.
class FixtureViolation {
  FixtureViolation({
    required this.code,
    required this.message,
    required this.competitionId,
    required this.seasonId,
    this.matchId,
    this.clubId,
    this.round,
    this.phase,
    this.severity = FixtureViolationSeverity.error,
  });

  final String code;
  final String message;
  final int competitionId;
  final int seasonId;
  final int? matchId;
  final int? clubId;
  final int? round;
  final int? phase;
  final FixtureViolationSeverity severity;

  bool get isError => severity == FixtureViolationSeverity.error;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer()
      ..write('[${severity.name.toUpperCase()}] ')
      ..write('competition=$competitionId season=$seasonId ');
    if (matchId != null) buffer.write('fixture=$matchId ');
    if (clubId != null) buffer.write('club=$clubId ');
    if (round != null) buffer.write('round=$round ');
    if (phase != null) buffer.write('phase=$phase ');
    buffer.write('$code: $message');
    return buffer.toString();
  }
}

class FixtureValidationReport {
  FixtureValidationReport(this.violations);

  final List<FixtureViolation> violations;

  bool get isValid => violations.every((FixtureViolation v) => !v.isError);
  int get errorCount =>
      violations.where((FixtureViolation v) => v.isError).length;
  int get warningCount => violations.length - errorCount;

  String describe() {
    if (violations.isEmpty) return 'Fixture list is valid.';
    return <String>[
      '$errorCount error(s), $warningCount warning(s):',
      ...violations.map((FixtureViolation v) => ' - $v'),
    ].join('\n');
  }
}

/// Pure fixture-list validator. It never mutates the database; callers can run
/// it on generated fixtures before saving, and on existing saves for auditing.
class FixtureValidator {
  const FixtureValidator._();

  // ------------------------------------------------------------- leagues

  static FixtureValidationReport validateLeague({
    required int competitionId,
    required int seasonId,
    required List<FixtureMatch> fixtures,
    required List<int> clubIds,
    bool doubleRound = true,
    String codePrefix = 'league',
  }) {
    final List<FixtureViolation> out = <FixtureViolation>[];
    final List<int> clubs = _unique(clubIds)..sort();
    final Set<int> valid = clubs.toSet();
    final int n = clubs.length;
    final int expectedMeetings = doubleRound ? 2 : 1;
    final int expectedFixtures = doubleRound
        ? n * (n - 1)
        : n * (n - 1) ~/ 2;
    // With an odd number of clubs one club rests every round, so a full cycle
    // needs n rounds instead of n - 1. A double round-robin repeats it.
    final int singleCycleRounds = n.isEven ? n - 1 : n;
    final int expectedRounds = doubleRound
        ? singleCycleRounds * 2
        : singleCycleRounds;

    if (fixtures.length != expectedFixtures) {
      out.add(
        FixtureViolation(
          code: '${codePrefix}_fixture_count',
          message:
              'Expected $expectedFixtures fixtures for $n clubs, found '
              '${fixtures.length}.',
          competitionId: competitionId,
          seasonId: seasonId,
        ),
      );
    }

    final Map<String, int> pairCounts = <String, int>{};
    final Map<String, int> homeCounts = <String, int>{};
    final Map<int, int> clubHomes = <int, int>{for (final int id in clubs) id: 0};
    final Map<int, int> clubAways = <int, int>{for (final int id in clubs) id: 0};
    final Map<int, List<FixtureMatch>> byRound = <int, List<FixtureMatch>>{};
    final Set<String> identities = <String>{};

    for (final FixtureMatch m in fixtures) {
      if (m.homeTeamId == m.awayTeamId) {
        out.add(
          _violation(
            'league_self_fixture',
            'A club was scheduled against itself.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      if (!valid.contains(m.homeTeamId) || !valid.contains(m.awayTeamId)) {
        out.add(
          _violation(
            'league_invalid_club',
            'Fixture references a club that is not registered in the league.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      final String identity =
          '${m.phase}:${m.leg}:${m.round}:${m.homeTeamId}:${m.awayTeamId}';
      if (!identities.add(identity)) {
        out.add(
          _violation(
            'league_duplicate_fixture',
            'The same fixture appears more than once.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      final String pair = _pairKey(m.homeTeamId, m.awayTeamId);
      pairCounts[pair] = (pairCounts[pair] ?? 0) + 1;
      final String directed = '${m.homeTeamId}-${m.awayTeamId}';
      homeCounts[directed] = (homeCounts[directed] ?? 0) + 1;
      clubHomes[m.homeTeamId] = (clubHomes[m.homeTeamId] ?? 0) + 1;
      clubAways[m.awayTeamId] = (clubAways[m.awayTeamId] ?? 0) + 1;
      byRound.putIfAbsent(m.round, () => <FixtureMatch>[]).add(m);
    }

    for (final MapEntry<String, int> entry in pairCounts.entries) {
      if (entry.value != expectedMeetings) {
        out.add(
          FixtureViolation(
            code: '${codePrefix}_pair_coverage',
            message:
                'Pairing ${entry.key} occurs ${entry.value} time(s); expected '
                '$expectedMeetings.',
            competitionId: competitionId,
            seasonId: seasonId,
          ),
        );
      }
    }
    if (n >= 2) {
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          final String key = _pairKey(clubs[i], clubs[j]);
          if (!pairCounts.containsKey(key)) {
            out.add(
              FixtureViolation(
                code: '${codePrefix}_missing_pair',
                message: 'Clubs ${clubs[i]} and ${clubs[j]} never meet.',
                competitionId: competitionId,
                seasonId: seasonId,
                clubId: clubs[i],
              ),
            );
          }
        }
      }
    }

    if (doubleRound) {
      for (final MapEntry<String, int> entry in pairCounts.entries) {
        final List<String> parts = entry.key.split('-');
        final int a = int.parse(parts[0]);
        final int b = int.parse(parts[1]);
        final int ab = homeCounts['$a-$b'] ?? 0;
        final int ba = homeCounts['$b-$a'] ?? 0;
        if (ab != 1 || ba != 1) {
          out.add(
            FixtureViolation(
              code: '${codePrefix}_home_away_reversal',
              message:
                  'Pairing $a/$b must have one home fixture each; found '
                  '$a home=$ab, $b home=$ba.',
              competitionId: competitionId,
              seasonId: seasonId,
              clubId: a,
            ),
          );
        }
      }
    }

    final int expectedHome = doubleRound
        ? n - 1
        : (n - 1) ~/ 2 + ((n - 1).isOdd ? 1 : 0);
    final int expectedAway = doubleRound
        ? n - 1
        : (n - 1) ~/ 2;
    for (final int club in clubs) {
      final int homes = clubHomes[club] ?? 0;
      final int aways = clubAways[club] ?? 0;
      if (homes + aways != expectedMeetings * (n - 1)) {
        out.add(
          FixtureViolation(
            code: '${codePrefix}_appearance_count',
            message:
                'Club $club plays ${homes + aways} matches; expected '
                '${expectedMeetings * (n - 1)}.',
            competitionId: competitionId,
            seasonId: seasonId,
            clubId: club,
          ),
        );
      }
      if (doubleRound && (homes != expectedHome || aways != expectedAway)) {
        out.add(
          FixtureViolation(
            code: '${codePrefix}_home_away_totals',
            message:
                'Club $club has $homes home / $aways away; expected '
                '$expectedHome / $expectedAway.',
            competitionId: competitionId,
            seasonId: seasonId,
            clubId: club,
          ),
        );
      }
      if (!doubleRound && (homes - aways).abs() > 1) {
        out.add(
          FixtureViolation(
            code: '${codePrefix}_home_away_balance',
            message:
                'Club $club has $homes home / $aways away; single round-robin '
                'may differ by at most one.',
            competitionId: competitionId,
            seasonId: seasonId,
            clubId: club,
          ),
        );
      }
    }

    if (byRound.length != expectedRounds) {
      out.add(
        FixtureViolation(
          code: '${codePrefix}_round_count',
          message:
              'Expected $expectedRounds rounds, found ${byRound.length}.',
          competitionId: competitionId,
          seasonId: seasonId,
        ),
      );
    }
    for (final MapEntry<int, List<FixtureMatch>> entry in byRound.entries) {
      final Set<int> playing = <int>{};
      for (final FixtureMatch m in entry.value) {
        if (!playing.add(m.homeTeamId)) {
          out.add(
            _violation(
              '${codePrefix}_double_booked',
              'Club ${m.homeTeamId} appears twice in round ${entry.key}.',
              competitionId,
              seasonId,
              m,
            ),
          );
        }
        if (!playing.add(m.awayTeamId)) {
          out.add(
            _violation(
              '${codePrefix}_double_booked',
              'Club ${m.awayTeamId} appears twice in round ${entry.key}.',
              competitionId,
              seasonId,
              m,
            ),
          );
        }
      }
    }

    return FixtureValidationReport(out);
  }

  // --------------------------------------------------------- league phase

  static FixtureValidationReport validateLeaguePhase({
    required int competitionId,
    required int seasonId,
    required List<FixtureMatch> fixtures,
    required List<int> clubIds,
    required int opponentsPerClub,
    required int homeMatches,
    required int awayMatches,
  }) {
    final List<FixtureViolation> out = <FixtureViolation>[];
    final List<int> clubs = _unique(clubIds);
    final Set<int> valid = clubs.toSet();
    final Map<int, Set<int>> opponents = <int, Set<int>>{
      for (final int id in clubs) id: <int>{},
    };
    final Map<int, int> homes = <int, int>{for (final int id in clubs) id: 0};
    final Map<int, int> aways = <int, int>{for (final int id in clubs) id: 0};
    final Map<int, List<FixtureMatch>> byRound = <int, List<FixtureMatch>>{};
    final Set<String> pairs = <String>{};

    final int expectedFixtures = clubs.length * opponentsPerClub ~/ 2;
    if (fixtures.length != expectedFixtures) {
      out.add(
        FixtureViolation(
          code: 'league_phase_fixture_count',
          message:
              'Expected $expectedFixtures fixtures, found ${fixtures.length}.',
          competitionId: competitionId,
          seasonId: seasonId,
        ),
      );
    }

    for (final FixtureMatch m in fixtures) {
      if (!valid.contains(m.homeTeamId) || !valid.contains(m.awayTeamId)) {
        out.add(
          _violation(
            'league_phase_invalid_club',
            'Fixture references a club outside the league phase.',
            competitionId,
            seasonId,
            m,
          ),
        );
        continue;
      }
      if (m.homeTeamId == m.awayTeamId) {
        out.add(
          _violation(
            'league_phase_self_fixture',
            'A club was scheduled against itself.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      final String pair = _pairKey(m.homeTeamId, m.awayTeamId);
      if (!pairs.add(pair)) {
        out.add(
          _violation(
            'league_phase_repeated_opponent',
            'The same pair meets more than once in the league phase.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      opponents[m.homeTeamId]!.add(m.awayTeamId);
      opponents[m.awayTeamId]!.add(m.homeTeamId);
      homes[m.homeTeamId] = (homes[m.homeTeamId] ?? 0) + 1;
      aways[m.awayTeamId] = (aways[m.awayTeamId] ?? 0) + 1;
      byRound.putIfAbsent(m.round, () => <FixtureMatch>[]).add(m);
    }

    for (final int club in clubs) {
      if (opponents[club]!.length != opponentsPerClub) {
        out.add(
          FixtureViolation(
            code: 'league_phase_opponent_count',
            message:
                'Club $club has ${opponents[club]!.length} distinct opponents; '
                'expected $opponentsPerClub.',
            competitionId: competitionId,
            seasonId: seasonId,
            clubId: club,
          ),
        );
      }
      if ((homes[club] ?? 0) != homeMatches ||
          (aways[club] ?? 0) != awayMatches) {
        out.add(
          FixtureViolation(
            code: 'league_phase_home_away',
            message:
                'Club $club has ${homes[club]} home / ${aways[club]} away; '
                'expected $homeMatches / $awayMatches.',
            competitionId: competitionId,
            seasonId: seasonId,
            clubId: club,
          ),
        );
      }
    }

    for (final MapEntry<int, List<FixtureMatch>> entry in byRound.entries) {
      final Set<int> playing = <int>{};
      for (final FixtureMatch m in entry.value) {
        if (!playing.add(m.homeTeamId) || !playing.add(m.awayTeamId)) {
          out.add(
            _violation(
              'league_phase_double_booked',
              'A club appears twice in matchday ${entry.key}.',
              competitionId,
              seasonId,
              m,
            ),
          );
        }
      }
    }
    return FixtureValidationReport(out);
  }

  // ---------------------------------------------------------- knockouts

  static FixtureValidationReport validateKnockout({
    required int competitionId,
    required int seasonId,
    required List<FixtureMatch> fixtures,
    int? expectedLegs,
    bool finalSingleMatch = false,
    bool allowByes = true,
  }) {
    final List<FixtureViolation> out = <FixtureViolation>[];
    final Map<int, List<FixtureMatch>> byPhase = <int, List<FixtureMatch>>{};
    for (final FixtureMatch m in fixtures) {
      byPhase.putIfAbsent(m.phase, () => <FixtureMatch>[]).add(m);
    }
    final int lastPhase = byPhase.keys.fold<int>(
      0,
      (int current, int phase) => phase > current ? phase : current,
    );

    for (final MapEntry<int, List<FixtureMatch>> phase in byPhase.entries) {
      final Map<String, List<FixtureMatch>> ties = <String, List<FixtureMatch>>{};
      for (final FixtureMatch m in phase.value) {
        final String key = _pairKey(m.homeTeamId, m.awayTeamId);
        ties.putIfAbsent(key, () => <FixtureMatch>[]).add(m);
      }

      // A tie is identified by its two clubs. A two-legged tie therefore does
      // not count as a duplicate: the same clubs legitimately appear twice.
      final Set<int> playing = <int>{};
      for (final List<FixtureMatch> tie in ties.values) {
        final FixtureMatch reference = tie.first;
        for (final int club in <int>[
          reference.homeTeamId,
          reference.awayTeamId,
        ]) {
          if (!playing.add(club)) {
            out.add(
              _violation(
                'knockout_duplicate_club',
                'Club $club appears in two ties in phase ${phase.key}.',
                competitionId,
                seasonId,
                reference,
              ),
            );
          }
        }
      }

      // A single tie is only a one-match final when the caller says the final
      // is played over one match AND this is the last phase. A one-tie
      // two-legged round (or a standalone test fixture) is still a two-leg tie.
      final bool isFinal =
          finalSingleMatch && phase.key == lastPhase && ties.length == 1;
      final int expected = isFinal
          ? 1
          : (expectedLegs ?? (phase.value.length > ties.length ? 2 : 1));
      for (final MapEntry<String, List<FixtureMatch>> entry in ties.entries) {
        final List<FixtureMatch> legs = entry.value
          ..sort((FixtureMatch a, FixtureMatch b) => a.leg.compareTo(b.leg));
        if (legs.length != expected) {
          out.add(
            FixtureViolation(
              code: 'knockout_leg_count',
              message:
                  'Tie ${entry.key} has ${legs.length} leg(s); expected '
                  '$expected.${allowByes ? '' : ' Byes are disabled.'}',
              competitionId: competitionId,
              seasonId: seasonId,
              round: phase.key,
              phase: phase.key,
            ),
          );
        }
        if (legs.length == 2) {
          final FixtureMatch first = legs.first;
          final FixtureMatch second = legs.last;
          if (first.homeTeamId != second.awayTeamId ||
              first.awayTeamId != second.homeTeamId) {
            out.add(
              _violation(
                'knockout_no_reversal',
                'The second leg does not reverse the first-leg venues.',
                competitionId,
                seasonId,
                second,
              ),
            );
          }
        }
        for (final FixtureMatch m in legs) {
          if (m.isPlayed) {
            if (m.winnerId == null || m.winnerId == 0) {
              out.add(
                _violation(
                  'knockout_missing_winner',
                  'Completed knockout fixture has no winner.',
                  competitionId,
                  seasonId,
                  m,
                ),
              );
            } else if (m.winnerId != m.homeTeamId &&
                m.winnerId != m.awayTeamId) {
              out.add(
                _violation(
                  'knockout_invalid_winner',
                  'Winner is not one of the two clubs.',
                  competitionId,
                  seasonId,
                  m,
                ),
              );
            }
          }
        }
      }
    }
    return FixtureValidationReport(out);
  }

  // ---------------------------------------------------------- calendar

  static FixtureValidationReport validateCalendar({
    required List<FixtureMatch> fixtures,
    int minRestDays = 2,
    Map<int, int>? minRestDaysByCompetition,
    Map<int, int>? seasonOfCompetition,
  }) {
    final List<FixtureViolation> out = <FixtureViolation>[];
    final Set<int> matchIds = <int>{};
    final Map<int, List<FixtureMatch>> byClub = <int, List<FixtureMatch>>{};
    final Map<int, List<FixtureMatch>> byStadium =
        <int, List<FixtureMatch>>{};
    final Map<String, FixtureMatch> identities = <String, FixtureMatch>{};
    final Map<String, Map<int, List<String>>> datesByRound =
        <String, Map<int, List<String>>>{};
    final Map<String, List<FixtureMatch>> legsByTie =
        <String, List<FixtureMatch>>{};

    for (final FixtureMatch m in fixtures) {
      final int competitionId = m.tournamentId;
      final int seasonId = m.seasonId;
      if (!matchIds.add(m.matchId)) {
        out.add(
          _violation(
            'calendar_duplicate_id',
            'Duplicate fixture id.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      if (m.homeTeamId == 0 || m.awayTeamId == 0) {
        out.add(
          _violation(
            'calendar_invalid_club',
            'Fixture has an invalid club reference.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      final String identity =
          '${m.seasonId}:${m.tournamentId}:${m.phase}:${m.leg}:${m.round}:'
          '${m.homeTeamId}:${m.awayTeamId}:${m.groupId}';
      final FixtureMatch? previous = identities[identity];
      if (previous != null) {
        out.add(
          _violation(
            'calendar_duplicate_fixture',
            'The same fixture identity appears twice '
                '(fixtures ${previous.matchId} and ${m.matchId}).',
            competitionId,
            seasonId,
            m,
          ),
        );
      } else {
        identities[identity] = m;
      }
      if (m.status == t.matchCancelled) continue;
      final DateTime? date = DateTime.tryParse(m.date ?? '');
      if (date == null) {
        out.add(
          _violation(
            'calendar_invalid_date',
            'Fixture has no valid calendar date.',
            competitionId,
            seasonId,
            m,
          ),
        );
      }
      byClub.putIfAbsent(m.homeTeamId, () => <FixtureMatch>[]).add(m);
      byClub.putIfAbsent(m.awayTeamId, () => <FixtureMatch>[]).add(m);
      if (m.stadiumId > 0) {
        byStadium.putIfAbsent(m.stadiumId, () => <FixtureMatch>[]).add(m);
      }
      final String roundKey =
          '${m.tournamentId}:${m.phase}:${m.groupId ?? -1}:${m.leg}';
      datesByRound
          .putIfAbsent(roundKey, () => <int, List<String>>{})
          .putIfAbsent(m.round, () => <String>[])
          .add(m.date ?? '');
      if (m.phase > 0 && m.groupId == null) {
        final String pair = _pairKey(m.homeTeamId, m.awayTeamId);
        legsByTie
            .putIfAbsent(
              '${m.tournamentId}:${m.phase}:$pair',
              () => <FixtureMatch>[],
            )
            .add(m);
      }
    }

    for (final MapEntry<int, List<FixtureMatch>> entry in byClub.entries) {
      final List<FixtureMatch> list = entry.value
        ..sort((FixtureMatch a, FixtureMatch b) {
          final String ad = a.date ?? '';
          final String bd = b.date ?? '';
          return ad.compareTo(bd);
        });
      for (int i = 1; i < list.length; i++) {
        final DateTime? previous = DateTime.tryParse(list[i - 1].date ?? '');
        final DateTime? current = DateTime.tryParse(list[i].date ?? '');
        if (previous == null || current == null) continue;
        final int days = current.difference(previous).inDays;
        if (days == 0) {
          out.add(
            _violation(
              'calendar_overlap',
              'Club ${entry.key} has two fixtures on ${list[i].date}.',
              list[i].tournamentId,
              list[i].seasonId,
              list[i],
            ),
          );
        } else if (days <
            max(
              minRestDays,
              minRestDaysByCompetition?[list[i].tournamentId] ?? minRestDays,
            )) {
          final int requiredRest = max(
            minRestDays,
            minRestDaysByCompetition?[list[i].tournamentId] ?? minRestDays,
          );
          out.add(
            FixtureViolation(
              code: 'calendar_rest',
              message:
                  'Club ${entry.key} has only $days day(s) between fixtures '
                  '${list[i - 1].date} and ${list[i].date}; minimum is '
                  '$requiredRest.',
              competitionId: list[i].tournamentId,
              seasonId: list[i].seasonId,
              matchId: list[i].matchId,
              clubId: entry.key,
              severity: FixtureViolationSeverity.warning,
            ),
          );
        }
      }
    }

    for (final MapEntry<int, List<FixtureMatch>> entry in byStadium.entries) {
      final List<FixtureMatch> fixtures = entry.value
        ..sort((FixtureMatch a, FixtureMatch b) {
          final int date = (a.date ?? '').compareTo(b.date ?? '');
          return date != 0 ? date : a.matchId.compareTo(b.matchId);
        });
      for (int i = 1; i < fixtures.length; i++) {
        if (fixtures[i].date != null &&
            fixtures[i].date == fixtures[i - 1].date) {
          out.add(
            _violation(
              'calendar_stadium_overlap',
              'Stadium ${entry.key} hosts multiple fixtures on '
                  '${fixtures[i].date}.',
              fixtures[i].tournamentId,
              fixtures[i].seasonId,
              fixtures[i],
            ),
          );
        }
      }
    }

    for (final MapEntry<String, Map<int, List<String>>> entry
        in datesByRound.entries) {
      final List<int> rounds = entry.value.keys.toList()..sort();
      for (int i = 1; i < rounds.length; i++) {
        final List<String> previous = entry.value[rounds[i - 1]]!..sort();
        final List<String> current = entry.value[rounds[i]]!..sort();
        if (previous.last.isNotEmpty &&
            current.first.isNotEmpty &&
            current.first.compareTo(previous.last) < 0) {
          final FixtureMatch fixture = fixtures.firstWhere(
            (FixtureMatch m) =>
                '${m.tournamentId}:${m.phase}:${m.groupId ?? -1}:${m.leg}' ==
                    entry.key &&
                m.round == rounds[i],
          );
          out.add(
            _violation(
              'calendar_round_order',
              'Round ${rounds[i]} starts before round ${rounds[i - 1]} is '
                  'complete in this phase.',
              fixture.tournamentId,
              fixture.seasonId,
              fixture,
            ),
          );
        }
      }
    }

    for (final MapEntry<String, List<FixtureMatch>> entry
        in legsByTie.entries) {
      final List<FixtureMatch> legs = entry.value
        ..sort((FixtureMatch a, FixtureMatch b) => a.leg.compareTo(b.leg));
      if (legs.length > 1 &&
          legs.first.date != null &&
          legs.last.date != null &&
          legs.last.date!.compareTo(legs.first.date!) <= 0) {
        out.add(
          _violation(
            'calendar_knockout_leg_order',
            'The return leg must be scheduled after the first leg.',
            legs.last.tournamentId,
            legs.last.seasonId,
            legs.last,
          ),
        );
      }
    }
    return FixtureValidationReport(out);
  }

  // ------------------------------------------------------------ helpers

  static FixtureViolation _violation(
    String code,
    String message,
    int competitionId,
    int seasonId,
    FixtureMatch m,
  ) => FixtureViolation(
    code: code,
    message: message,
    competitionId: competitionId,
    seasonId: seasonId,
    matchId: m.matchId,
    clubId: m.homeTeamId,
    round: m.round,
    phase: m.phase,
  );

  static String _pairKey(int a, int b) => a < b ? '$a-$b' : '$b-$a';

  static List<int> _unique(List<int> values) {
    final List<int> result = <int>[];
    final Set<int> seen = <int>{};
    for (final int value in values) {
      if (seen.add(value)) result.add(value);
    }
    return result;
  }
}
