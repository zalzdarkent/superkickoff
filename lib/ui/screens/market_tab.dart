import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../data/repositories/scouting_repository.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';

/// Full-page transfer market: listed players plus the club's transfer history.
class MarketTab extends StatefulWidget {
  const MarketTab({super.key});

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, Object?>> players = <Map<String, Object?>>[];
  List<Map<String, Object?>> allPlayers = <Map<String, Object?>>[];
  int? positionFilter;
  int? minAge;
  int? maxAge;
  int? minPrice;
  int? maxPrice;
  bool loading = true;
  bool loadingAll = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAllPlayers();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final CareerProvider game = context.read<CareerProvider>();
    final List<Map<String, Object?>> list = await game.marketPlayers(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      positionType: positionFilter,
      minAge: minAge,
      maxAge: maxAge,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
    if (!mounted) return;
    setState(() {
      players = list;
      loading = false;
    });
  }

  Future<void> _loadAllPlayers() async {
    setState(() => loadingAll = true);
    final CareerProvider game = context.read<CareerProvider>();
    final List<Map<String, Object?>> list = await game.allMarketPlayers(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      positionType: positionFilter,
      minAge: minAge,
      maxAge: maxAge,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
    if (!mounted) return;
    setState(() {
      allPlayers = list;
      loadingAll = false;
    });
  }

  void _showFilterDrawer() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => _FilterDrawer(
        minAge: minAge,
        maxAge: maxAge,
        minPrice: minPrice,
        maxPrice: maxPrice,
        onApply:
            (
              int? newMinAge,
              int? newMaxAge,
              int? newMinPrice,
              int? newMaxPrice,
            ) {
              setState(() {
                minAge = newMinAge;
                maxAge = newMaxAge;
                minPrice = newMinPrice;
                maxPrice = newMaxPrice;
              });
              _load();
              _loadAllPlayers();
            },
        onClear: () {
          setState(() {
            minAge = null;
            maxAge = null;
            minPrice = null;
            maxPrice = null;
          });
          _load();
          _loadAllPlayers();
        },
      ),
    );
  }

  Future<void> _makeOffer(Map<String, Object?> row) async {
    final CareerProvider game = context.read<CareerProvider>();
    final int value = (row['value'] as int?) ?? 0;
    final TextEditingController offer = TextEditingController(
      text: value.toString(),
    );
    final int? amount = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Offer for ${row['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Club: ${row['club_name'] ?? 'Free agent'}'),
            Text('Player value: ${money(value)}'),
            Text('Your budget: ${money(game.userTeam?.budget ?? 0)}'),
            const SizedBox(height: 14),
            TextField(
              controller: offer,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Your offer',
                prefixText: '\$',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(int.tryParse(offer.text.trim())),
            child: const Text('Send Offer'),
          ),
        ],
      ),
    );
    offer.dispose();
    if (amount == null || amount <= 0) return;
    final String? failure = await game.makeTransferOffer(row, amount);
    if (!mounted) return;
    setState(() => error = failure);
    if (failure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offer sent for ${row['name']}. Check Inbox.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    return DefaultTabController(
      length: 4,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Row(
              children: <Widget>[
                const Text(
                  'Transfer Market',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 20),
                  onPressed: _showFilterDrawer,
                  tooltip: 'Filter',
                ),
                const SizedBox(width: 8),
                Text(
                  'Budget ${money(game.userTeam?.budget ?? 0)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.accent),
                ),
              ],
            ),
          ),
          const TabBar(
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textDim,
            indicatorColor: AppTheme.accent,
            dividerColor: Colors.white10,
            tabs: <Widget>[
              Tab(text: 'Listed players'),
              Tab(text: 'All Players'),
              Tab(text: 'Scouting'),
              Tab(text: 'Transfer history'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _listedTab(),
                _allPlayersTab(),
                _scoutingTab(),
                const _TransferHistory(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listedTab() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search players...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  _load();
                },
              ),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: <Widget>[
              for (final (String label, int? type) in <(String, int?)>[
                ('All', null),
                ('GK', 1),
                ('DEF', 2),
                ('MID', 3),
                ('ATT', 4),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: positionFilter == type,
                    onSelected: (_) {
                      setState(() => positionFilter = type);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              error!,
              style: const TextStyle(color: AppTheme.danger, fontSize: 11),
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : players.isEmpty
              ? const Center(
                  child: Text(
                    'No players listed for sale right now.\n'
                    'Clubs relist players as the season advances.',
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: players.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, Object?> row = players[index];
                      return _PlayerMarketCard(
                        row: row,
                        onBuy: () => _makeOffer(row),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _allPlayersTab() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _loadAllPlayers(),
            decoration: InputDecoration(
              hintText: 'Search players...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  _loadAllPlayers();
                },
              ),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: <Widget>[
              for (final (String label, int? type) in <(String, int?)>[
                ('All', null),
                ('GK', 1),
                ('DEF', 2),
                ('MID', 3),
                ('ATT', 4),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: positionFilter == type,
                    onSelected: (_) {
                      setState(() => positionFilter = type);
                      _loadAllPlayers();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              error!,
              style: const TextStyle(color: AppTheme.danger, fontSize: 11),
            ),
          ),
        Expanded(
          child: loadingAll
              ? const Center(child: CircularProgressIndicator())
              : allPlayers.isEmpty
              ? const Center(
                  child: Text('No players found.', textAlign: TextAlign.center),
                )
              : RefreshIndicator(
                  onRefresh: _loadAllPlayers,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: allPlayers.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, Object?> row = allPlayers[index];
                      return _PlayerMarketCard(
                        row: row,
                        onBuy: () => _makeOffer(row),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _scoutingTab() {
    final CareerProvider game = context.watch<CareerProvider>();
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                'Scouting Department',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => _showHireScoutSheet(context),
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Recruit Scout'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Scout>>(
            future: game.hiredScouts(),
            builder: (BuildContext context, AsyncSnapshot<List<Scout>> snap) {
              final List<Scout> scouts = snap.data ?? <Scout>[];
              if (scouts.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'No scouts hired yet. Recruit scouts with high star ratings to uncover elite wonderkids worldwide!',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (final Scout scout in scouts)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.accent.withValues(
                            alpha: 0.15,
                          ),
                          child: const Icon(
                            Icons.radar,
                            color: AppTheme.accent,
                          ),
                        ),
                        title: Row(
                          children: <Widget>[
                            Text(
                              scout.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Stars(value: scout.stars, size: 10),
                          ],
                        ),
                        subtitle: Text(
                          scout.isScouting
                              ? 'Scouting in ${scout.region} · ${money(scout.salary)}/w'
                              : 'Ready for assignment · ${money(scout.salary)}/w',
                          style: TextStyle(
                            fontSize: 11,
                            color: scout.isScouting
                                ? AppTheme.accent
                                : AppTheme.textDim,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            FilledButton(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () =>
                                  _deployScoutDialog(context, scout),
                              child: Text(
                                scout.isScouting ? 'Re-deploy' : 'Deploy',
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: AppTheme.textDim,
                              ),
                              tooltip: 'Release scout',
                              onPressed: () async {
                                await game.fireScout(scout.scoutId);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 32),
          const Text(
            'Discovered Wonderkids',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<ScoutWonderkid>>(
            future: game.pendingWonderkids(),
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<ScoutWonderkid>> snap,
                ) {
                  final List<ScoutWonderkid> list =
                      snap.data ?? <ScoutWonderkid>[];
                  if (list.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'No wonderkids scouted yet. Deploy your scouts to South America, Europe, Africa, or Asia to discover talent!',
                        style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                      ),
                    );
                  }
                  return Column(
                    children: <Widget>[
                      for (final ScoutWonderkid w in list)
                        Card(
                          child: ListTile(
                            onTap: () => showProspectDetail(
                              context,
                              name: w.playerName,
                              age: w.age,
                              positionId: w.positionId,
                              power: w.power,
                              potential: w.potential,
                              value: w.value,
                              countryId: w.countryId,
                              profile: 'D',
                              source: '${w.region} · ${w.scoutName}',
                              signingFee: (w.value * 0.75).round(),
                            ),
                            leading: PositionBadge(positionId: w.positionId),
                            title: Row(
                              children: <Widget>[
                                Text(
                                  w.playerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'OVR ${w.power}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${w.age}y · Potential ${w.potential}+ · ${w.region} (${w.scoutName})\nValue ${money(w.value)} · Fee ${money((w.value * 0.75).round())}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            isThreeLine: true,
                            trailing: FilledButton(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final String? err = await game.signWonderkid(
                                  w.reportId,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        err ??
                                            '${w.playerName} joined your squad!',
                                      ),
                                    ),
                                  );
                                  setState(() {});
                                }
                              },
                              child: const Text('Sign'),
                            ),
                          ),
                        ),
                    ],
                  );
                },
          ),
        ],
      ),
    );
  }

  void _showHireScoutSheet(BuildContext context) {
    final CareerProvider game = context.read<CareerProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final List<Scout> candidates = game.availableScoutsToHire();
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.70,
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Recruit Scouts',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Hire scouts with higher star ratings to discover higher-potential wonderkids worldwide.',
                style: TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (BuildContext _, int i) {
                    final Scout c = candidates[i];
                    final int fee = ScoutingRepository.hiringCostForStars(
                      c.stars,
                    );
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.accent.withValues(
                            alpha: 0.15,
                          ),
                          child: Text(
                            '${c.stars}★',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                        title: Row(
                          children: <Widget>[
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Stars(value: c.stars, size: 10),
                          ],
                        ),
                        subtitle: Text(
                          'Region: ${c.region} · Wage: ${money(c.salary)}/w\nRecruitment fee: ${money(fee)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        isThreeLine: true,
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            final String? err = await game.hireScout(c);
                            if (context.mounted) {
                              Navigator.pop(sheetContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    err ?? '${c.name} hired as scout!',
                                  ),
                                ),
                              );
                              setState(() {});
                            }
                          },
                          child: const Text('Hire'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _deployScoutDialog(BuildContext context, Scout scout) {
    final CareerProvider game = context.read<CareerProvider>();
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Deploy ${scout.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Stars: ${scout.stars}★ · Wage: ${money(scout.salary)}/week'),
            const SizedBox(height: 12),
            const Text(
              'Select target scouting region:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final String region in ScoutingRepository.regions)
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.travel_explore,
                  size: 20,
                  color: AppTheme.accent,
                ),
                title: Text(region, style: const TextStyle(fontSize: 13)),
                onTap: () async {
                  Navigator.pop(dialogContext);
                  final List<ScoutWonderkid> found = await game.deployScout(
                    scout,
                    region,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${scout.name} scouted $region and discovered ${found.length} wonderkids!',
                        ),
                      ),
                    );
                    setState(() {});
                  }
                },
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _PlayerMarketCard extends StatelessWidget {
  const _PlayerMarketCard({required this.row, required this.onBuy});

  final Map<String, Object?> row;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => showPlayerDetail(context, row['player_id'] as int),
        leading: PositionBadge(
          positionId: (row['position_id'] as int?) ?? 1,
          profile: row['profile'] as String?,
        ),
        title: Text(
          '${row['name']}  ${row['power']}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${row['age']}y · ${row['club_name']} · '
          '${money((row['value'] as int?) ?? 0)}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_shopping_cart, color: AppTheme.accent),
          onPressed: onBuy,
        ),
      ),
    );
  }
}

class _TransferHistory extends StatefulWidget {
  const _TransferHistory();

  @override
  State<_TransferHistory> createState() => _TransferHistoryState();
}

class _TransferHistoryState extends State<_TransferHistory> {
  late Future<List<TransferRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().transferHistory();
  }

  Future<void> _reload() async {
    setState(() {
      _future = context.read<CareerProvider>().transferHistory();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    return FutureBuilder<List<TransferRecord>>(
      future: _future,
      builder:
          (BuildContext context, AsyncSnapshot<List<TransferRecord>> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<TransferRecord> records =
                snap.data ?? const <TransferRecord>[];
            if (records.isEmpty) {
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  children: const <Widget>[
                    SizedBox(height: 90),
                    Icon(Icons.swap_horiz, size: 42, color: AppTheme.textDim),
                    SizedBox(height: 10),
                    Center(
                      child: Text(
                        'No transfers yet.\n'
                        'Players you buy or sell will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textDim),
                      ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
                itemCount: records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 0),
                itemBuilder: (BuildContext context, int index) {
                  final TransferRecord r = records[index];
                  final bool incoming = r.toTeamId == game.userTeamId;
                  return Card(
                    child: ListTile(
                      onTap: () => showPlayerDetail(context, r.playerId),
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor:
                            (incoming ? AppTheme.accent : AppTheme.warn)
                                .withValues(alpha: 0.18),
                        child: Icon(
                          incoming ? Icons.south_west : Icons.north_east,
                          size: 18,
                          color: incoming ? AppTheme.accent : AppTheme.warn,
                        ),
                      ),
                      title: Text(
                        r.playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${incoming ? 'From' : 'To'} '
                        '${incoming ? r.fromTeamName : r.toTeamName} · '
                        '${shortDate(r.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        r.value <= 0
                            ? 'Free'
                            : '${incoming ? '-' : '+'}${money(r.value)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: incoming ? AppTheme.warn : AppTheme.accent,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
    );
  }
}

class _FilterDrawer extends StatefulWidget {
  const _FilterDrawer({
    required this.minAge,
    required this.maxAge,
    required this.minPrice,
    required this.maxPrice,
    required this.onApply,
    required this.onClear,
  });

  final int? minAge;
  final int? maxAge;
  final int? minPrice;
  final int? maxPrice;
  final void Function(int?, int?, int?, int?) onApply;
  final VoidCallback onClear;

  @override
  State<_FilterDrawer> createState() => _FilterDrawerState();
}

class _FilterDrawerState extends State<_FilterDrawer> {
  late TextEditingController _minAgeCtrl;
  late TextEditingController _maxAgeCtrl;
  late TextEditingController _minPriceCtrl;
  late TextEditingController _maxPriceCtrl;

  @override
  void initState() {
    super.initState();
    _minAgeCtrl = TextEditingController(text: widget.minAge?.toString());
    _maxAgeCtrl = TextEditingController(text: widget.maxAge?.toString());
    _minPriceCtrl = TextEditingController(text: widget.minPrice?.toString());
    _maxPriceCtrl = TextEditingController(text: widget.maxPrice?.toString());
  }

  @override
  void dispose() {
    _minAgeCtrl.dispose();
    _maxAgeCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Filter Players',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Age',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _minAgeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Min',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _maxAgeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Price (\$)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _minPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Min',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _maxPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    widget.onClear();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final int? minAge = int.tryParse(_minAgeCtrl.text);
                    final int? maxAge = int.tryParse(_maxAgeCtrl.text);
                    final int? minPrice = int.tryParse(_minPriceCtrl.text);
                    final int? maxPrice = int.tryParse(_maxPriceCtrl.text);
                    widget.onApply(minAge, maxAge, minPrice, maxPrice);
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
