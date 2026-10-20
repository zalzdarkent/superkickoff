import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';

/// Season calendar grouped by match week with results and upcoming games.
class FixturesTab extends StatefulWidget {
  const FixturesTab({super.key});

  @override
  State<FixturesTab> createState() => _FixturesTabState();
}

class _FixturesTabState extends State<FixturesTab> {
  List<FixtureMatch>? fixtures;
  int? cupTournamentId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final CareerProvider game = context.read<CareerProvider>();
    if (game.season == null) return;
    final List<FixtureMatch> list = await game.seasonFixtures();
    if (!mounted) return;
    setState(() {
      fixtures = list;
      cupTournamentId = game.cup?.tournamentId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<FixtureMatch> list = fixtures ?? const <FixtureMatch>[];
    if (list.isEmpty) {
      return const Center(child: Text('No fixtures yet'));
    }
    // Group by tournament + round.
    final Map<String, List<FixtureMatch>> groups = <String, List<FixtureMatch>>{};
    for (final FixtureMatch m in list) {
      final bool isCup = m.tournamentId == cupTournamentId;
      final String key = isCup
          ? 'Cup · ${_phaseName(m.phase)}'
          : 'League · Round ${m.round}';
      groups.putIfAbsent(key, () => <FixtureMatch>[]).add(m);
    }
    final List<String> keys = groups.keys.toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: keys.length,
        itemBuilder: (BuildContext context, int index) {
          final String key = keys[index];
          final List<FixtureMatch> group = groups[key]!
            ..sort((FixtureMatch a, FixtureMatch b) =>
                (a.date ?? '').compareTo(b.date ?? ''));
          final DateTime? date = DateTime.tryParse(group.first.date ?? '');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 4),
                child: Text(
                  '$key  ·  ${date == null ? '' : _formatDate(date)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: key.startsWith('League')
                        ? AppTheme.accent
                        : AppTheme.warn,
                  ),
                ),
              ),
              for (final FixtureMatch m in group) _fixtureRow(game, m),
            ],
          );
        },
      ),
    );
  }

  Widget _fixtureRow(CareerProvider game, FixtureMatch m) {
    final Team? home = game.teamCache[m.homeTeamId];
    final Team? away = game.teamCache[m.awayTeamId];
    final bool involvesUser =
        m.homeTeamId == game.userTeamId || m.awayTeamId == game.userTeamId;
    final bool played = m.isPlayed;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: involvesUser ? AppTheme.accentDim.withAlpha(70) : AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              home?.name ?? '?',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: involvesUser ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Container(
            width: 62,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              played ? '${m.homeGoals ?? 0} - ${m.awayGoals ?? 0}' : 'vs',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: played ? 14 : 11,
                color: played ? Colors.white : AppTheme.textDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              away?.name ?? '?',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: involvesUser ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  static String _phaseName(int phase) => switch (phase) {
        1 => 'Round of 32',
        2 => 'Round of 16',
        3 => 'Quarter-finals',
        4 => 'Semi-finals',
        _ => 'Final',
      };
}
