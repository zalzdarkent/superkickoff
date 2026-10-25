import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../game/match_engine.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';
import 'team_detail_sheet.dart';

/// Full-time match report: team statistics charts plus every player rating.
class MatchStatsSheet extends StatelessWidget {
  const MatchStatsSheet({super.key, required this.session});

  final LiveMatchSession session;

  static const Color _awayColor = Color(0xFF60A5FA);

  @override
  Widget build(BuildContext context) {
    final MatchResult result = session.result;
    final int userTeamId = context.watch<CareerProvider>().userTeamId;
    final List<MatchPlayerRow> played = result.playerRows
        .where((MatchPlayerRow row) => row.minutes > 0)
        .toList();

    final int homeYellows = played
        .where((MatchPlayerRow row) => row.teamId == session.homeTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.yellowCards);
    final int awayYellows = played
        .where((MatchPlayerRow row) => row.teamId == session.awayTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.yellowCards);
    final int homeReds = played
        .where((MatchPlayerRow row) => row.teamId == session.homeTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.redCards);
    final int awayReds = played
        .where((MatchPlayerRow row) => row.teamId == session.awayTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.redCards);
    final bool userIsHome = session.homeTeam.teamId == userTeamId;
    final List<Team> teamOrder = userIsHome
        ? <Team>[session.homeTeam, session.awayTeam]
        : <Team>[session.awayTeam, session.homeTeam];

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: <Widget>[
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'FULL-TIME STATISTICS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                color: AppTheme.textDim,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                InkWell(
                  onTap: () => showTeamDetail(context, session.homeTeam.teamId),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      session.homeTeam.abbreviation,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '${result.homeGoals} - ${result.awayGoals}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => showTeamDetail(context, session.awayTeam.teamId),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      session.awayTeam.abbreviation,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _teamLegend(context),
            const SizedBox(height: 8),
            _statBar(
              'Possession',
              result.homePossession,
              100 - result.homePossession,
              suffix: '%',
            ),
            _statBar('Shots', result.homeShots, result.awayShots),
            _statBar(
              'Shots on target',
              result.homeShotsOnTarget,
              result.awayShotsOnTarget,
            ),
            _statBar(
              'Shot accuracy',
              _percent(result.homeShotsOnTarget, result.homeShots),
              _percent(result.awayShotsOnTarget, result.awayShots),
              suffix: '%',
            ),
            _statBar('Saves', result.homeSaves, result.awaySaves),
            _statBar('Yellow cards', homeYellows, awayYellows),
            _statBar('Red cards', homeReds, awayReds),
            const SizedBox(height: 18),
            for (final Team team in teamOrder) ...<Widget>[
              _ratingsHeader(context, team, team.teamId == userTeamId),
              ..._ratings(context, played, team),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  static int _percent(int value, int total) =>
      total <= 0 ? 0 : ((value * 100) / total).round();

  Widget _teamLegend(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: InkWell(
            onTap: () => showTeamDetail(context, session.homeTeam.teamId),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: <Widget>[
                Container(width: 8, height: 8, color: AppTheme.accent),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    session.homeTeam.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () => showTeamDetail(context, session.awayTeam.teamId),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Flexible(
                  child: Text(
                    session.awayTeam.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                  ),
                ),
                const SizedBox(width: 5),
                Container(width: 8, height: 8, color: _awayColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statBar(String label, int home, int away, {String suffix = ''}) {
    final int total = home + away;
    final int homeFlex = total <= 0
        ? 50
        : ((home * 100) / total).round().clamp(1, 99);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 42,
                child: Text(
                  '$home$suffix',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '$away$suffix',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: homeFlex,
                  child: Container(height: 6, color: AppTheme.accent),
                ),
                Expanded(
                  flex: 100 - homeFlex,
                  child: Container(height: 6, color: _awayColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingsHeader(BuildContext context, Team team, bool mine) {
    return InkWell(
      onTap: () => showTeamDetail(context, team.teamId),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            CrestAvatar(team: team, radius: 12),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mine ? '${team.name} · YOUR TEAM' : team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: mine ? AppTheme.accent : Colors.white,
                ),
              ),
            ),
            const Text(
              'RATING',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                color: AppTheme.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _ratings(
    BuildContext context,
    List<MatchPlayerRow> played,
    Team team,
  ) {
    final List<MatchPlayerRow> rows =
        played.where((MatchPlayerRow row) => row.teamId == team.teamId).toList()
          ..sort(
            (MatchPlayerRow a, MatchPlayerRow b) =>
                b.rating.compareTo(a.rating),
          );
    if (rows.isEmpty) {
      return <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No players recorded.',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
        ),
      ];
    }
    return <Widget>[
      for (final MatchPlayerRow row in rows) _playerRow(context, row),
    ];
  }

  Widget _playerRow(BuildContext context, MatchPlayerRow row) {
    final double score = row.rating / 10;
    final Color ratingColor = score >= 7
        ? AppTheme.accent
        : score >= 6
        ? Colors.white
        : AppTheme.danger;
    final List<String> details = <String>[
      '${row.minutes}\'',
      if (row.goals > 0) '${row.goals}G',
      if (row.assists > 0) '${row.assists}A',
      if (row.yellowCards > 0) '${row.yellowCards}Y',
      if (row.redCards > 0) '${row.redCards}R',
    ];
    return InkWell(
      onTap: () => showPlayerDetail(context, row.playerId),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            child: row.mvp == 1
                ? const Icon(Icons.star, size: 13, color: AppTheme.warn)
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (row.rating / 100).clamp(0, 1),
                          minHeight: 3,
                          backgroundColor: Colors.grey.shade800,
                          color: ratingColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      details.join(' · '),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.textDim,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: ratingColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ratingColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              score.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: ratingColor,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}
