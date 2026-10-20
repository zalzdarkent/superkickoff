import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'inbox_tab.dart';
import 'market_sheet.dart';
import 'match_screen.dart';
import 'squad_tab.dart';
import 'standings_tab.dart';
import 'fixtures_tab.dart';

/// Main game hub with bottom navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final Team? team = game.userTeam;
    if (team == null) {
      return const Scaffold(
        body: Center(child: Text('No career found — restart the app.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            CrestAvatar(team: team, radius: 14),
            const SizedBox(width: 8),
            Text(team.name, style: const TextStyle(fontSize: 16)),
          ],
        ),
        actions: <Widget>[
          Chip(
            avatar: const Icon(Icons.calendar_month, size: 14),
            label: Text(
              game.season?.name ?? 'Season ?',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: <Widget>[
          RefreshIndicator(
            onRefresh: game.refreshWorld,
            child: _body(game),
          ),
          if (game.busy)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(game.busyStatus),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) {
          if (i == 5) {
            _openMarket(context);
            return;
          }
          setState(() => _index = i);
        },
        destinations: <Widget>[
          const NavigationDestination(
            icon: Icon(Icons.outlined_flag),
            label: 'Overview',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups),
            label: 'Squad',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event),
            label: 'Fixtures',
          ),
          const NavigationDestination(
            icon: Icon(Icons.table_chart),
            label: 'Table',
          ),
          const NavigationDestination(
            icon: Icon(Icons.mail_outline),
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront),
            label: 'Market',
          ),
        ],
      ),
    );
  }

  Widget _body(CareerProvider game) {
    switch (_index) {
      case 1:
        return const SquadTab();
      case 2:
        return const FixturesTab();
      case 3:
        return const StandingsTab();
      case 4:
        return const InboxTab();
      default:
        return OverviewTab(
          onPlayPressed: () => _playNext(context, game),
          onOpenInbox: () => setState(() => _index = 4),
        );
    }
  }

  void _openMarket(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const MarketSheet(),
    );
  }

  Future<void> _playNext(BuildContext context, CareerProvider game) async {
    if (game.busy) return;
    if (game.nextUserMatch != null) {
      await game.startLiveMatch();
      if (context.mounted && game.liveSession != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MatchScreen()),
        );
      }
      return;
    }
    await game.playAiMatchday();
  }
}

/// Overview: next match card, quick stats, mini table and inbox preview.
class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.onPlayPressed,
    this.onOpenInbox,
  });

  final VoidCallback onPlayPressed;
  final VoidCallback? onOpenInbox;

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final Team? team = game.userTeam;
    if (team == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        _nextMatchCard(context, game, team),
        SectionCard(
          title: 'Club',
          trailing: Text(
            game.season?.name ?? '',
            style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
          child: StatChips(
            items: <Widget>[
              statChip('Budget', money(team.budget),
                  icon: Icons.account_balance_wallet, color: AppTheme.accent),
              statChip('Power', '${team.power}', icon: Icons.bolt),
              statChip('Position', _position(game)),
              statChip('Week', '${game.week + 1}', icon: Icons.date_range),
            ],
          ),
        ),
        MiniStandingsCard(game: game, team: team),
        _unreadInboxCard(context, game, onOpenInbox: onOpenInbox),
        const SizedBox(height: 24),
      ],
    );
  }

  String _position(CareerProvider game) {
    for (int i = 0; i < game.standings.length; i++) {
      if (game.standings[i].teamId == game.userTeamId) return '${i + 1}';
    }
    return '-';
  }

  Widget _nextMatchCard(BuildContext context, CareerProvider game, Team team) {
    FixtureMatch? mine = game.nextUserMatch;
    Team? opponent;
    if (mine != null) {
      final int opponentId =
          mine.homeTeamId == game.userTeamId ? mine.awayTeamId : mine.homeTeamId;
      opponent = game.teamCache[opponentId];
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  'Next match',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  shortDate(game.nextDate),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
            const Divider(height: 20),
            if (game.nextUserMatch != null && opponent != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    Expanded(
                        child: _teamColumn(team,
                            isHome: game.nextUserMatch!.homeTeamId ==
                                team.teamId)),
                    Text(
                      'VS',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, color: AppTheme.accent),
                    ),
                    Expanded(
                        child: _teamColumn(opponent,
                            isHome: game.nextUserMatch!.awayTeamId ==
                                team.teamId)),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  game.nextDate == null
                      ? 'Season finished — no more fixtures.'
                      : 'Rest week. Advance to continue the season.',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      icon: Icon(game.nextUserMatch != null
                          ? Icons.play_circle
                          : Icons.fast_forward),
                      label: Text(
                        game.nextUserMatch != null
                            ? 'Play Match'
                            : 'Advance Week',
                      ),
                      onPressed: game.nextDate == null ? null : onPlayPressed,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: game.nextDate == null
                      ? null
                      : () async {
                          await context.read<CareerProvider>().playAiMatchday();
                        },
                  child: const Text('Simulate week'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamColumn(Team t, {required bool isHome}) => Column(
        children: <Widget>[
          CrestAvatar(team: t, radius: 22),
          const SizedBox(height: 6),
          Text(
            t.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          Text('#${t.power}',
              style: const TextStyle(fontSize: 10, color: AppTheme.textDim)),
        ],
      );

  Widget _unreadInboxCard(
    BuildContext context,
    CareerProvider game, {
    VoidCallback? onOpenInbox,
  }) => Card(
        child: ListTile(
          leading: Badge(
            isLabelVisible: game.unreadCount > 0,
            label: Text('${game.unreadCount}'),
            child: const Icon(Icons.mail_outline),
          ),
          title: const Text(
            'Inbox',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: Text(
            game.inbox.isEmpty
                ? 'No messages yet'
                : game.inbox.first.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenInbox,
        ),
      );
}

/// Small standings snippet on the overview.
class MiniStandingsCard extends StatelessWidget {
  const MiniStandingsCard({
    super.key,
    required this.game,
    required this.team,
  });

  final CareerProvider game;
  final Team team;

  @override
  Widget build(BuildContext context) {
    final List<StandingRow> rows = game.standings.take(5).toList();
    final int userIndex = game.standings
        .indexWhere((StandingRow r) => r.teamId == game.userTeamId);
    late final List<StandingRow> display;
    if (userIndex >= 5) {
      display = <StandingRow>[
        ...rows,
        game.standings[userIndex],
      ];
    } else {
      if (userIndex < 0) {
        display = rows;
      } else {
        display = rows;
      }
    }
    if (display.isEmpty) {
      return SectionCard(
        title: 'Standings',
        child: Text(
          'Season underway — results will appear here.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      );
    }
    return SectionCard(
      title: 'Top of the table',
      child: Column(
        children: <Widget>[
          for (final StandingRow row in display)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${game.standings.indexOf(row) + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: row.teamId == game.userTeamId
                            ? AppTheme.accent
                            : AppTheme.textDim,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: row.teamId == game.userTeamId
                            ? AppTheme.accent
                            : Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    '${row.points} pts',
                    style: TextStyle(
                      fontSize: 11,
                      color: row.teamId == game.userTeamId
                          ? AppTheme.accent
                          : AppTheme.textDim,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
