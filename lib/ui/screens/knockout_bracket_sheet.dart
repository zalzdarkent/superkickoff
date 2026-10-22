import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme.dart';

/// Displays the played and upcoming rounds of one cup's knockout bracket.
Future<void> showKnockoutBracket(
  BuildContext context, {
  required Tournament tournament,
  required List<FixtureMatch> matches,
  required Map<int, Team> teams,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.82,
      child: _KnockoutBracketSheet(
        tournament: tournament,
        matches: matches,
        teams: teams,
      ),
    ),
  );
}

class _KnockoutBracketSheet extends StatelessWidget {
  const _KnockoutBracketSheet({
    required this.tournament,
    required this.matches,
    required this.teams,
  });

  final Tournament tournament;
  final List<FixtureMatch> matches;
  final Map<int, Team> teams;

  @override
  Widget build(BuildContext context) {
    final int totalRounds = knockoutTotalRounds(matches);
    final Map<int, List<FixtureMatch>> rounds = <int, List<FixtureMatch>>{};
    for (final FixtureMatch match in matches) {
      rounds.putIfAbsent(match.phase, () => <FixtureMatch>[]).add(match);
    }
    final List<FixtureMatch>? finalRound = rounds[totalRounds];
    final FixtureMatch? finalMatch = finalRound == null || finalRound.isEmpty
        ? null
        : finalRound.first;
    final Team? champion = finalMatch?.winnerId == null
        ? null
        : teams[finalMatch!.winnerId!];

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              '${tournament.name} · Knockout bracket',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int phase = 1; phase <= totalRounds; phase++)
                    _RoundColumn(
                      title: knockoutRoundName(phase, totalRounds),
                      ties: groupTies(rounds[phase] ?? const <FixtureMatch>[]),
                      teams: teams,
                    ),
                  _ChampionColumn(champion: champion),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundColumn extends StatelessWidget {
  const _RoundColumn({
    required this.title,
    required this.ties,
    required this.teams,
  });

  final String title;
  final List<KnockoutTie> ties;
  final Map<int, Team> teams;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ties.isEmpty
                  ? const Center(
                      child: Text(
                        'Awaiting results',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: <Widget>[
                        for (final KnockoutTie tie in ties)
                          _MatchCard(tie, teams),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard(this.tie, this.teams);

  final KnockoutTie tie;
  final Map<int, Team> teams;

  @override
  Widget build(BuildContext context) {
    final FixtureMatch first = tie.first;
    final FixtureMatch? second = tie.second;
    final (int, int)? pens = tie.penalties;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (second != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text(
                'TWO LEGS',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                  letterSpacing: .5,
                ),
              ),
            ),
          _teamRow(
            first.homeTeamId,
            first.homeGoals,
            second?.awayGoals,
            tie.homeAgg,
          ),
          const Divider(height: 7),
          _teamRow(
            first.awayTeamId,
            first.awayGoals,
            second?.homeGoals,
            tie.awayAgg,
          ),
          if (pens != null)
            Text(
              'Pens ${pens.$1}-${pens.$2}',
              style: const TextStyle(fontSize: 9, color: AppTheme.warn),
            ),
        ],
      ),
    );
  }

  Widget _teamRow(int teamId, int? leg1Goals, int? leg2Goals, int agg) {
    final bool winner = tie.winnerId == teamId;
    final bool two = tie.twoLegged;
    String score(int? goals, bool played) => played ? '${goals ?? 0}' : '-';
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            teams[teamId]?.name ?? '?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: winner ? FontWeight.bold : FontWeight.normal,
              color: winner ? AppTheme.accent : null,
            ),
          ),
        ),
        Text(
          two
              ? '${score(leg1Goals, tie.first.isPlayed)}  '
                    '${score(leg2Goals, tie.second!.isPlayed)}'
              : score(leg1Goals, tie.first.isPlayed),
          style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
        ),
        if (two)
          SizedBox(
            width: 22,
            child: Text(
              tie.complete ? '$agg' : '-',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: winner ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChampionColumn extends StatelessWidget {
  const _ChampionColumn({required this.champion});

  final Team? champion;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        children: <Widget>[
          const Text(
            'Champion',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.warn,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.warn.withAlpha(30),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              champion?.name ?? 'TBD',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

int knockoutTotalRounds(List<FixtureMatch> matches) {
  if (matches.isEmpty) return 1;
  final int firstPhase = matches
      .map((FixtureMatch match) => match.phase)
      .reduce((int a, int b) => a < b ? a : b);
  // Count ties, not matches: a two-legged round has two matches per tie.
  final int firstRoundMatches = matches
      .where(
        (FixtureMatch match) => match.phase == firstPhase && match.leg == 1,
      )
      .length;
  return (firstRoundMatches * 2).bitLength - 1;
}

String knockoutRoundName(int phase, int totalRounds) {
  final int teamsLeft = 1 << (totalRounds - phase + 1);
  if (teamsLeft <= 2) return 'Final';
  if (teamsLeft == 4) return 'Semi-finals';
  return 'Round of $teamsLeft';
}
