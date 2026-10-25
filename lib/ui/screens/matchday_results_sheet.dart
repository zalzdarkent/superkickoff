import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../theme.dart';
import 'team_detail_sheet.dart';

/// Shows every result from the matchday that just finished.
Future<void> showMatchdayResults(
  BuildContext context, {
  required List<FixtureMatch> matches,
  required Map<int, Team> teams,
  required int userTeamId,
  required String Function(FixtureMatch) competitionLabel,
  Map<int, (int, int)> aggregates = const <int, (int, int)>{},
  String? date,
}) {
  if (matches.isEmpty) return Future<void>.value();
  final List<FixtureMatch> sorted = List<FixtureMatch>.of(matches)
    ..sort((FixtureMatch a, FixtureMatch b) {
      final bool aUser =
          a.homeTeamId == userTeamId || a.awayTeamId == userTeamId;
      final bool bUser =
          b.homeTeamId == userTeamId || b.awayTeamId == userTeamId;
      if (aUser != bUser) return aUser ? -1 : 1;
      return a.matchId.compareTo(b.matchId);
    });
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.82,
      child: _MatchdayResultsSheet(
        matches: sorted,
        teams: teams,
        userTeamId: userTeamId,
        competitionLabel: competitionLabel,
        aggregates: aggregates,
        date: date,
      ),
    ),
  );
}

class _MatchdayResultsSheet extends StatelessWidget {
  const _MatchdayResultsSheet({
    required this.matches,
    required this.teams,
    required this.userTeamId,
    required this.competitionLabel,
    required this.aggregates,
    required this.date,
  });

  final List<FixtureMatch> matches;
  final Map<int, Team> teams;
  final int userTeamId;
  final String Function(FixtureMatch) competitionLabel;
  final Map<int, (int, int)> aggregates;
  final String? date;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade700,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.sports_soccer,
                  color: AppTheme.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Matchday results',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        shortDate(date),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${matches.length} matches',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              itemCount: matches.length,
              itemBuilder: (BuildContext context, int index) =>
                  _row(context, matches[index]),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, FixtureMatch match) {
    final Team? home = teams[match.homeTeamId];
    final Team? away = teams[match.awayTeamId];
    final bool mine =
        match.homeTeamId == userTeamId || match.awayTeamId == userTeamId;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? AppTheme.accentDim.withAlpha(70) : AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                competitionLabel(match).toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: .6,
                  color: AppTheme.textDim,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (aggregates.containsKey(match.matchId))
                Text(
                  'LEG 2',
                  style: const TextStyle(
                    fontSize: 8,
                    letterSpacing: .5,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: () => showTeamDetail(context, match.homeTeamId),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: Text(
                      home?.name ?? '?',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: mine ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 62,
                alignment: Alignment.center,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: <Widget>[
                    Text(
                      '${match.homeGoals ?? 0} - ${match.awayGoals ?? 0}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (aggregates[match.matchId] case (int h, int a))
                      Text(
                        'Agg $h-$a',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                    if ((match.penaltyHomeGoals ?? 0) > 0 ||
                        (match.penaltyAwayGoals ?? 0) > 0)
                      Text(
                        'pens ${match.penaltyHomeGoals}-${match.penaltyAwayGoals}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.warn,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => showTeamDetail(context, match.awayTeamId),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: Text(
                      away?.name ?? '?',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: mine ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
