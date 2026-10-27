import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'competition_tab.dart';
import 'inbox_tab.dart';
import 'knockout_bracket_sheet.dart';
import 'club_hub_sheet.dart';
import 'market_tab.dart';
import 'news_tab.dart';
import 'offseason_screen.dart';
import 'match_screen.dart';
import 'matchday_results_sheet.dart';
import 'squad_tab.dart';
import 'annual_awards_gala_sheet.dart';
import 'tactical_analysis_sheet.dart';
import 'team_detail_sheet.dart';

/// Main game hub with bottom navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  int _competitionSubIndex = 0;

  void _navigateToTab(int tabIndex, [int subIndex = 0]) {
    setState(() {
      _index = tabIndex;
      if (tabIndex == 2) {
        _competitionSubIndex = subIndex;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final Team? team = game.userTeam;
    if (team == null) {
      return const Scaffold(
        body: Center(child: Text('No career found — restart the app.')),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _leaveCareer(context);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Keluar karir',
            onPressed: () => _leaveCareer(context),
          ),
          title: InkWell(
            onTap: () => showTeamDetail(context, team.teamId),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CrestAvatar(team: team, radius: 15),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          team.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.calendar_month,
                              size: 11,
                              color: AppTheme.accent,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                game.season?.name ?? 'Season ?',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Inbox',
              icon: Badge(
                isLabelVisible: game.unreadCount > 0,
                label: Text('${game.unreadCount}'),
                child: const Icon(Icons.mail_outline),
              ),
              onPressed: () => _openInbox(context),
            ),
            if (game.cups.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Bagan Turnamen',
                icon: const Icon(Icons.account_tree_outlined),
                onPressed: () => _openBrackets(context, game),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Keluar Karir',
              icon: const Icon(Icons.exit_to_app),
              onPressed: () => _leaveCareer(context),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Stack(
          children: <Widget>[
            if (game.offseason != null)
              const OffseasonView()
            else
              RefreshIndicator(onRefresh: game.refreshWorld, child: _body(game)),
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
        bottomNavigationBar: game.offseason != null
            ? null
            : NavigationBar(
          selectedIndex: _index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 64,
          onDestinationSelected: (int i) {
            setState(() {
              _index = i;
              if (i == 2) {
                _competitionSubIndex = 0;
              }
            });
          },
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Squad',
            ),
            NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events),
              label: 'Kompetisi',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Market',
            ),
          ],
        ),
      ),
    );
  }

  void _openInbox(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const InboxScreen()));

  Future<void> _openBrackets(BuildContext context, CareerProvider game) async {
    final Tournament? tournament = await showModalBottomSheet<Tournament>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const ListTile(title: Text('Knockout brackets')),
            for (final Tournament cup in game.cups)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(cup.name),
                onTap: () => Navigator.pop(context, cup),
              ),
          ],
        ),
      ),
    );
    if (tournament == null || !context.mounted) return;
    final List<FixtureMatch> fixtures = await game.seasonFixtures();
    if (!context.mounted) return;
    showKnockoutBracket(
      context,
      tournament: tournament,
      matches: fixtures
          .where(
            (FixtureMatch match) =>
                match.tournamentId == tournament.tournamentId &&
                match.groupId == null,
          )
          .toList(),
      teams: game.teamCache,
    );
  }

  Future<void> _leaveCareer(BuildContext context) async {
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Leave career?'),
        content: const Text('Do you want to save this session?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Don't save"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == null || !context.mounted) return;
    await context.read<CareerProvider>().leaveCareer(save: save);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Widget _body(CareerProvider game) {
    switch (_index) {
      case 1:
        return const SquadTab();
      case 2:
        return CompetitionTab(
          key: ValueKey<int>(_competitionSubIndex),
          initialIndex: _competitionSubIndex,
        );
      case 3:
        return const MarketTab();
      default:
        return OverviewTab(
          onPlayPressed: () => _playNext(context, game),
          onOpenInbox: () => _openInbox(context),
          onNavigateTab: _navigateToTab,
        );
    }
  }

  Future<void> _playNext(BuildContext context, CareerProvider game) async {
    if (game.busy) return;
    if (game.nextUserMatch != null) {
      await game.startLiveMatch();
      if (context.mounted && game.liveSession != null) {
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const MatchScreen()));
      }
      return;
    }
    await game.playAiMatchday();
    if (context.mounted) {
      await showMatchdayResults(
        context,
        matches: game.lastMatchday,
        teams: game.lastMatchdayTeams,
        userTeamId: game.userTeamId,
        competitionLabel: game.competitionLabel,
        aggregates: game.lastMatchdayAggregates,
        date: game.lastMatchday.isEmpty ? null : game.lastMatchday.first.date,
      );
    }
  }
}

/// Overview: next match card, quick stats, mini table, recent news and inbox preview.
class OverviewTab extends StatefulWidget {
  const OverviewTab({
    super.key,
    required this.onPlayPressed,
    this.onOpenInbox,
    this.onNavigateTab,
    this.initialSubTab = 0,
  });

  final Future<void> Function() onPlayPressed;
  final VoidCallback? onOpenInbox;
  final void Function(int tabIndex, [int subIndex])? onNavigateTab;
  final int initialSubTab;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialSubTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _simulateWeek() async {
    final CareerProvider provider = context.read<CareerProvider>();
    await provider.playAiMatchday();
    if (!mounted) return;
    await showMatchdayResults(
      context,
      matches: provider.lastMatchday,
      teams: provider.lastMatchdayTeams,
      userTeamId: provider.userTeamId,
      competitionLabel: provider.competitionLabel,
      aggregates: provider.lastMatchdayAggregates,
      date: provider.lastMatchday.isEmpty
          ? null
          : provider.lastMatchday.first.date,
    );
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final Team? team = game.userTeam;
    if (team == null) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        Material(
          color: AppTheme.surfaceCard,
          elevation: 1,
          child: TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textDim,
            indicatorColor: AppTheme.accent,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const <Widget>[
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.dashboard_outlined, size: 16),
                    SizedBox(width: 6),
                    Text('Ringkasan'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.newspaper_outlined, size: 16),
                    SizedBox(width: 6),
                    Text('Berita'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              _buildSummary(context, game, team),
              const NewsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, CareerProvider game, Team team) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        if (game.pendingGala != null) _pendingGalaCard(context, game),
        if (game.isPreSeasonOrientation)
          _preSeasonOrientationCard(context, game, team)
        else
          _nextMatchCard(context, game, team),
        SectionCard(
          title: 'Club',
          trailing: TextButton.icon(
            onPressed: () => showClubHub(context),
            icon: const Icon(Icons.info_outline, size: 15),
            label: const Text('Club info'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          child: StatChips(
            items: <Widget>[
              statChip(
                'Budget',
                money(team.budget),
                icon: Icons.account_balance_wallet,
                color: AppTheme.accent,
              ),
              statChip('Power', '${team.power}', icon: Icons.bolt),
              statChip('Position', _position(game)),
              statChip(
                game.isPreSeasonOrientation ? 'Fase' : 'Week',
                game.isPreSeasonOrientation ? 'Pra-Musim' : '${game.week + 1}',
                icon: Icons.date_range,
              ),
            ],
          ),
        ),
        MiniStandingsCard(
          game: game,
          team: team,
          onViewAll: () => widget.onNavigateTab?.call(2, 0),
        ),
        _unreadInboxCard(context, game, onOpenInbox: widget.onOpenInbox),
        _recentNewsCard(context, game),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _recentNewsCard(BuildContext context, CareerProvider game) {
    return FutureBuilder<List<NewsItem>>(
      future: game.newsFeed('world'),
      builder: (BuildContext context, AsyncSnapshot<List<NewsItem>> snapshot) {
        final List<NewsItem> items = snapshot.data ?? const <NewsItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        final NewsItem latest = items.first;
        return SectionCard(
          title: 'Berita Terkini',
          trailing: TextButton.icon(
            onPressed: () => _tabController.animateTo(1),
            icon: const Icon(Icons.arrow_forward, size: 14),
            label: const Text('Baca Berita'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
          child: InkWell(
            onTap: () => _tabController.animateTo(1),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.newspaper,
                    size: 18,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      latest.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppTheme.textDim,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pendingGalaCard(BuildContext context, CareerProvider game) {
    final SeasonGalaSummary gala = game.pendingGala!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF2E2002), Color(0xFF1E1B4B)],
        ),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD700),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    size: 18,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ANNUAL AWARDS GALA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                      Text(
                        'Malam Penghargaan Musim ${gala.year}!',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                  onPressed: game.dismissPendingGala,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Pemenang Ballon d\'Or, Golden Boot, dan Team of the Year (Once Ideal) telah diumumkan.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black87,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                icon: const Icon(Icons.celebration, size: 18),
                label: const Text('Buka Gala Penghargaan'),
                onPressed: () => showAnnualAwardsGala(context, gala: gala),
              ),
            ),
          ],
        ),
      ),
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
      final int opponentId = mine.homeTeamId == game.userTeamId
          ? mine.awayTeamId
          : mine.homeTeamId;
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
            if (game.nextUserMatch != null)
              Text(
                game.competitionLabel(game.nextUserMatch!).toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: .7,
                  color: AppTheme.textDim,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (game.nextUserMatch != null && opponent != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    Expanded(
                      child: _teamColumn(
                        context,
                        team,
                        isHome: game.nextUserMatch!.homeTeamId == team.teamId,
                      ),
                    ),
                    Text(
                      'VS',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accent,
                      ),
                    ),
                    Expanded(
                      child: _teamColumn(
                        context,
                        opponent,
                        isHome: game.nextUserMatch!.awayTeamId == team.teamId,
                      ),
                    ),
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
                      icon: _actionLoading || game.busy
                          ? const ButtonLoadingIndicator()
                          : Icon(
                              game.nextUserMatch != null
                                  ? Icons.play_circle
                                  : Icons.fast_forward,
                            ),
                      label: Text(
                        game.nextUserMatch != null
                            ? 'Play Match'
                            : 'Advance Week',
                      ),
                      onPressed: game.nextDate == null ||
                              _actionLoading ||
                              game.busy
                          ? null
                          : () => _runAction(widget.onPlayPressed),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: game.nextDate == null ||
                          _actionLoading ||
                          game.busy
                      ? null
                      : () => _runAction(_simulateWeek),
                  child: LoadingButtonContent(
                    isLoading: _actionLoading || game.busy,
                    child: const Text('Simulate week'),
                  ),
                ),
              ],
            ),
            if (game.nextUserMatch != null) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.psychology_outlined, size: 18),
                  label: const Text('Analisis Taktis Lawan'),
                  onPressed: () => showTacticalAnalysisSheet(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _teamColumn(BuildContext context, Team t, {required bool isHome}) =>
      InkWell(
        onTap: () => showTeamDetail(context, t.teamId),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
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
              Text(
                'PWR ${t.power}',
                style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
              ),
            ],
          ),
        ),
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
        game.inbox.isEmpty ? 'No messages yet' : game.inbox.first.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpenInbox,
    ),
  );

  Widget _preSeasonOrientationCard(
    BuildContext context,
    CareerProvider game,
    Team team,
  ) {
    final TransferWindow? win = game.currentTransferWindow;
    final String currentDate = game.nextDate ?? '2025-07-01';
    final int daysRemaining =
        win != null ? win.daysUntilDeadline(currentDate) : 62;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppTheme.accent.withValues(alpha: 0.12),
              Theme.of(context).cardColor,
            ],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header badge & date
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.workspace_premium,
                        size: 14,
                        color: AppTheme.accent,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'ERA BARU DIMULAI • PRA-MUSIM',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  shortDate(game.nextDate),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Club banner & Welcome
            Row(
              children: <Widget>[
                CrestAvatar(team: team, radius: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Selamat Datang di ${team.name}!',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${game.league?.name ?? 'Divisi ${team.division}'} • Berdiri sejak ${team.foundedYear}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Anda telah resmi ditunjuk sebagai manajer baru! '
              'Sebelum melakoni pertandingan pra-musim dan kompetisi resmi perdana, '
              'manfaatkan periode awal ini untuk meninjau komposisi skuad, merancang taktik, '
              'dan aktif berbelanja di bursa transfer pemain.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),

            // Summer Transfer Window Live Status Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_open_rounded,
                          color: Colors.green,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Jendela Transfer Musim Panas: DIBUKA',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Klub di seluruh dunia aktif bernegosiasi & merekrut pemain',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Sisa Waktu Jendela',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textDim,
                            ),
                          ),
                          Text(
                            '$daysRemaining Hari (Hingga ${shortDate(win?.endDate)})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          const Text(
                            'Anggaran Belanja',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textDim,
                            ),
                          ),
                          Text(
                            money(team.budget),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.storefront, size: 16),
                      label: const Text(
                        'Jelajahi Bursa Transfer Sekarang',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () => widget.onNavigateTab?.call(3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Board Expectations Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.flag_outlined,
                        size: 15,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Target & Ekspektasi Musim Ini',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _targetItem(
                    Icons.emoji_events_outlined,
                    'Target Kompetisi',
                    'Bersaing di papan atas ${game.league?.name ?? 'liga'} dan lolos ke turnamen kontinental.',
                  ),
                  const SizedBox(height: 6),
                  _targetItem(
                    Icons.groups_outlined,
                    'Kekuatan & Taktik Skuad',
                    'Kekuatan saat ini: ${team.power} OVR. Atur formasi, eksekutor bola mati, dan chemistry tim.',
                  ),
                  const SizedBox(height: 6),
                  _targetItem(
                    Icons.account_balance_outlined,
                    'Kesehatan Finansial',
                    'Gunakan anggaran transfer secara bijak untuk memperkuat posisi yang kurang.',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text(
                        'Atur Skuad & Taktik Tim',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () => widget.onNavigateTab?.call(1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // First Upcoming Match Preview
            FutureBuilder<FixtureMatch?>(
              future: game.firstUpcomingUserMatch(),
              builder: (
                BuildContext context,
                AsyncSnapshot<FixtureMatch?> snapshot,
              ) {
                final FixtureMatch? firstMatch = snapshot.data;
                if (firstMatch == null) return const SizedBox.shrink();
                final int oppId = firstMatch.homeTeamId == team.teamId
                    ? firstMatch.awayTeamId
                    : firstMatch.homeTeamId;
                final Team? opponent = game.teamCache[oppId];

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.event_available,
                            size: 15,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Laga Perdana Mendatang',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            shortDate(firstMatch.date),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textDim,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          CrestAvatar(team: team, radius: 14),
                          const SizedBox(width: 6),
                          Text(
                            team.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'VS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                          if (opponent != null) ...<Widget>[
                            CrestAvatar(team: opponent, radius: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                opponent.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '(${game.competitionLabel(firstMatch)}) Pertandingan perdana baru akan bergulir setelah Anda menyelesaikan persiapan orientasi di bawah.',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Conclude Orientation & Start Pre-Season Action Button
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text(
                  'Selesai Persiapan & Mulai Pra-Musim',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () => _confirmStartPreSeason(context, game),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetItem(IconData icon, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 14, color: AppTheme.accent),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11, color: null),
              children: <TextSpan>[
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: description,
                  style: const TextStyle(color: AppTheme.textDim),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmStartPreSeason(
    BuildContext context,
    CareerProvider game,
  ) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Mulai Agenda Pertandingan?'),
        content: const Text(
          'Anda akan menyelesaikan masa orientasi manajer dan melangkah ke jadwal pertandingan pra-musim perdana.\n\n'
          'Catatan: Jendela transfer musim panas akan tetap TERBUKA penuh sepanjang rangkaian pertandingan pra-musim dan awal musim.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjut Persiapan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai Pertandingan'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await game.completePreSeasonOrientation();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Orientasi selesai! Selamat berjuang mengarungi musim baru.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

/// Small standings snippet on the overview.
class MiniStandingsCard extends StatelessWidget {
  const MiniStandingsCard({
    super.key,
    required this.game,
    required this.team,
    this.onViewAll,
  });

  final CareerProvider game;
  final Team team;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final List<StandingRow> rows = game.standings.take(5).toList();
    final int userIndex = game.standings.indexWhere(
      (StandingRow r) => r.teamId == game.userTeamId,
    );
    late final List<StandingRow> display;
    if (userIndex >= 5) {
      display = <StandingRow>[...rows, game.standings[userIndex]];
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
        trailing: onViewAll == null
            ? null
            : TextButton.icon(
                onPressed: onViewAll,
                icon: const Icon(Icons.arrow_forward, size: 14),
                label: const Text('Klasemen'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
        child: Text(
          'Season underway — results will appear here.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      );
    }
    return SectionCard(
      title: game.league?.name ?? 'Top of the table',
      trailing: onViewAll == null
          ? null
          : TextButton.icon(
              onPressed: onViewAll,
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: const Text('Klasemen'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
      child: Column(
        children: <Widget>[
          for (final StandingRow row in display)
            InkWell(
              onTap: () => showTeamDetail(context, row.teamId),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
                      child: Row(
                        children: <Widget>[
                          CrestAvatar.raw(
                            teamId: row.teamId,
                            name: row.name,
                            abbreviation: row.abbreviation,
                            logoBase64: row.logoBase64 ??
                                game.teamCache[row.teamId]?.logoBase64,
                            radius: 8,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
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
                        ],
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
            ),
        ],
      ),
    );
  }
}
