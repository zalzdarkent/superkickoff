import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/db/schema.dart' as t;
import '../../data/models/models.dart';
import '../../game/formation.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';
import 'training_sheet.dart';

/// Squad management: list players with line-up status, captain pick and
/// transfer listing.
class SquadTab extends StatefulWidget {
  const SquadTab({super.key});

  @override
  State<SquadTab> createState() => _SquadTabState();
}

class _SquadTabState extends State<SquadTab> {
  List<Player>? squad;
  List<SquadStatRow>? stats;
  Map<int, int> suspensions = <int, int>{};
  int _loadedWeek = -1;
  String _sortBy = 'power';
  bool _sortDescending = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final CareerProvider game = context.read<CareerProvider>();
    final List<Player> players = await game.squadForUser();
    final List<SquadStatRow> rows = await game.squadStatistics();
    final Map<int, int> banned = await game.suspensionsForUser();
    if (!mounted) return;
    setState(() {
      squad = players;
      stats = rows;
      suspensions = banned;
      _loadedWeek = game.week;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<Player> players = squad ?? const <Player>[];
    if (game.busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (squad != null && _loadedWeek != game.week) {
      _loadedWeek = game.week;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    if (players.isEmpty) {
      return const Center(child: Text('Squad not loaded'));
    }
    return DefaultTabController(
      length: 3,
      child: Column(
        children: <Widget>[
          const Material(
            color: AppTheme.surfaceCard,
            child: TabBar(
              labelColor: AppTheme.accent,
              unselectedLabelColor: AppTheme.textDim,
              indicatorColor: AppTheme.accent,
              dividerColor: Colors.transparent,
              labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              unselectedLabelStyle: TextStyle(fontSize: 12),
              tabs: <Widget>[
                Tab(text: 'Squad'),
                Tab(text: 'Statistics'),
                Tab(text: 'Formation'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _squadList(game, players),
                _statisticsTab(game, players),
                _formationTab(game, players),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Player> _getSortedPlayers(List<Player> source) {
    final List<Player> list = List<Player>.from(source);
    list.sort((Player a, Player b) {
      int cmp = 0;
      switch (_sortBy) {
        case 'power':
          cmp = a.power.compareTo(b.power);
          break;
        case 'value':
          cmp = a.value.compareTo(b.value);
          break;
        case 'age':
          cmp = a.age.compareTo(b.age);
          break;
        case 'position':
          cmp = a.positionId.compareTo(b.positionId);
          break;
      }
      return _sortDescending ? -cmp : cmp;
    });
    return list;
  }

  Widget _squadList(CareerProvider game, List<Player> players) {
    final List<Player> sorted = _getSortedPlayers(players);
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          color: AppTheme.surfaceCard,
          child: Row(
            children: <Widget>[
              Text(
                '${sorted.length} players',
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
              const Spacer(),
              const Text(
                'Sort: ',
                style: TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
              DropdownButton<String>(
                value: _sortBy,
                isDense: true,
                underline: const SizedBox.shrink(),
                dropdownColor: AppTheme.surfaceCard,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: 'power',
                    child: Text('Overall'),
                  ),
                  DropdownMenuItem<String>(value: 'value', child: Text('MV')),
                  DropdownMenuItem<String>(value: 'age', child: Text('Age')),
                  DropdownMenuItem<String>(
                    value: 'position',
                    child: Text('Position'),
                  ),
                ],
                onChanged: (String? val) {
                  if (val != null) setState(() => _sortBy = val);
                },
              ),
              IconButton(
                icon: Icon(
                  _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 16,
                  color: AppTheme.accent,
                ),
                tooltip: _sortDescending ? 'Highest first' : 'Lowest first',
                onPressed: () =>
                    setState(() => _sortDescending = !_sortDescending),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sorted.length,
              itemBuilder: (BuildContext context, int index) =>
                  _playerTile(context, game, sorted[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statisticsTab(CareerProvider game, List<Player> players) {
    final int power = players.isEmpty
        ? 0
        : (players.fold<int>(0, (int sum, Player p) => sum + p.power) /
                  players.length)
              .round();
    final int age = players.isEmpty
        ? 0
        : (players.fold<int>(0, (int sum, Player p) => sum + p.age) /
                  players.length)
              .round();
    final int value = players.fold<int>(
      0,
      (int sum, Player p) => sum + p.value,
    );
    final int fit = players.isEmpty
        ? 0
        : (players.fold<int>(0, (int sum, Player p) => sum + p.fitness) /
                  players.length)
              .round();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: <Widget>[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.insights, size: 16, color: AppTheme.accent),
                      SizedBox(width: 6),
                      Text(
                        'Squad profile',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StatChips(
                    items: <Widget>[
                      statChip('Players', '${players.length}'),
                      statChip(
                        'Avg power',
                        '$power',
                        icon: Icons.bolt,
                        color: AppTheme.accent,
                      ),
                      statChip('Avg age', '$age'),
                      statChip('Fitness', '$fit%'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Squad value ${money(value)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          _playerStatsCard(),
          const SizedBox(height: 4),
          _leadersCard(game),
        ],
      ),
    );
  }

  Widget _playerStatsCard() {
    final List<SquadStatRow> rows = stats ?? const <SquadStatRow>[];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.table_chart, size: 16, color: AppTheme.accent),
                SizedBox(width: 6),
                Text(
                  'Player statistics',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Current season · all competitions',
              style: TextStyle(fontSize: 10, color: AppTheme.textDim),
            ),
            const SizedBox(height: 6),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No stats loaded.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 30,
                  dataRowMinHeight: 38,
                  dataRowMaxHeight: 44,
                  horizontalMargin: 4,
                  columnSpacing: 14,
                  headingTextStyle: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDim,
                  ),
                  dataTextStyle: const TextStyle(fontSize: 11),
                  columns: const <DataColumn>[
                    DataColumn(label: Text('PLAYER')),
                    DataColumn(label: Text('POS')),
                    DataColumn(label: Text('AGE'), numeric: true),
                    DataColumn(label: Text('APP'), numeric: true),
                    DataColumn(label: Text('MIN'), numeric: true),
                    DataColumn(label: Text('G'), numeric: true),
                    DataColumn(label: Text('A'), numeric: true),
                    DataColumn(label: Text('MVP'), numeric: true),
                    DataColumn(label: Text('YC'), numeric: true),
                    DataColumn(label: Text('RC'), numeric: true),
                    DataColumn(label: Text('RTG'), numeric: true),
                  ],
                  rows: <DataRow>[
                    for (final SquadStatRow row in rows)
                      DataRow(
                        onSelectChanged: (_) =>
                            showPlayerDetail(context, row.playerId),
                        cells: <DataCell>[
                          DataCell(
                            Text(
                              row.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(
                            PositionBadge(
                              positionId: row.positionId,
                              profile: row.profile,
                            ),
                          ),
                          DataCell(Text('${row.age}')),
                          DataCell(Text('${row.appearances}')),
                          DataCell(Text('${row.minutes}')),
                          DataCell(Text('${row.goals}')),
                          DataCell(Text('${row.assists}')),
                          DataCell(Text('${row.mvps}')),
                          DataCell(Text('${row.yellowCards}')),
                          DataCell(Text('${row.redCards}')),
                          DataCell(
                            Text(
                              row.rating <= 0
                                  ? '—'
                                  : row.rating.toStringAsFixed(1),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: row.rating >= 7
                                    ? AppTheme.accent
                                    : row.rating > 0 && row.rating < 6
                                    ? AppTheme.danger
                                    : null,
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
    );
  }

  Widget _formationTab(CareerProvider game, List<Player> players) {
    final Formation formation = game.formation;
    final List<_SlotSpec> slots = _slotsFor(formation);
    final Map<int, Player> byId = <int, Player>{
      for (final Player p in players) p.playerId: p,
    };
    final Set<int> assigned = game.lineup.values.toSet();
    final List<Player> bench = players
        .where((Player p) => !assigned.contains(p.playerId))
        .toList();
    final int filled = slots
        .where((_SlotSpec slot) => byId.containsKey(game.lineup[slot.index]))
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.dashboard_customize,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Formation',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    DropdownButton<Formation>(
                      value: formation,
                      isDense: true,
                      dropdownColor: AppTheme.surfaceCard,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                      ),
                      items: <DropdownMenuItem<Formation>>[
                        for (final Formation f in Formation.all)
                          DropdownMenuItem<Formation>(
                            value: f,
                            child: Text(f.name),
                          ),
                      ],
                      onChanged: (Formation? f) {
                        if (f != null && f != formation) {
                          game.setFormation(f);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Text(
                      '$filled / 11 picked',
                      style: TextStyle(
                        fontSize: 11,
                        color: filled == 11
                            ? AppTheme.accent
                            : AppTheme.textDim,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => game.autoFillLineup(),
                      icon: const Icon(Icons.auto_fix_high, size: 15),
                      label: const Text('Auto XI'),
                    ),
                    TextButton(
                      onPressed: game.lineup.isEmpty
                          ? null
                          : () => game.clearLineup(),
                      child: const Text('Clear'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await showTrainingSheet(context);
                        if (mounted) await _reload();
                      },
                      icon: const Icon(Icons.fitness_center, size: 15),
                      label: const Text('Train'),
                    ),
                  ],
                ),
                const Text(
                  'Auto XI picks the best player for every slot. To adjust, hold a '
                  'player and drag onto a pitch slot; drag a starter to the '
                  'bench to remove him.',
                  style: TextStyle(fontSize: 10, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _pitch(game, slots, byId),
        const SizedBox(height: 8),
        _bench(game, bench),
      ],
    );
  }

  Widget _pitch(
    CareerProvider game,
    List<_SlotSpec> slots,
    Map<int, Player> byId,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF166534), Color(0xFF14532D)],
          ),
        ),
        child: AspectRatio(
          aspectRatio: 0.74,
          child: Stack(
            children: <Widget>[
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 1,
                    child: ColoredBox(color: Colors.white24),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: <Widget>[
                    for (final int group in <int>[4, 3, 2, 1])
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            for (final _SlotSpec slot in slots)
                              if (slot.group == group) _slot(game, slot, byId),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slot(CareerProvider game, _SlotSpec slot, Map<int, Player> byId) {
    final Player? player = byId[game.lineup[slot.index]];
    final Color color = _groupColor(slot.group);
    return DragTarget<int>(
      onWillAcceptWithDetails: (DragTargetDetails<int> details) => true,
      onAcceptWithDetails: (DragTargetDetails<int> details) =>
          game.assignLineupSlot(slot.index, details.data),
      builder:
          (
            BuildContext context,
            List<int?> candidates,
            List<dynamic> rejected,
          ) {
            final bool hot = candidates.isNotEmpty;
            return SizedBox(
              width: 58,
              height: 58,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: hot
                      ? AppTheme.accent.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: hot ? AppTheme.accent : color.withValues(alpha: 0.7),
                    width: hot ? 2 : 1,
                  ),
                ),
                child: player == null
                    ? Center(
                        child: Text(
                          slot.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      )
                    : LongPressDraggable<int>(
                        data: player.playerId,
                        feedback: Material(
                          color: Colors.transparent,
                          child: _playerChip(player, color, width: 96),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: _playerChip(player, color),
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              showPlayerDetail(context, player.playerId),
                          child: _playerChip(player, color),
                        ),
                      ),
              ),
            );
          },
    );
  }

  Widget _bench(CareerProvider game, List<Player> bench) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (DragTargetDetails<int> details) => true,
      onAcceptWithDetails: (DragTargetDetails<int> details) {
        int? slot;
        for (final MapEntry<int, int> entry in game.lineup.entries) {
          if (entry.value == details.data) {
            slot = entry.key;
            break;
          }
        }
        if (slot != null) game.clearLineupSlot(slot);
      },
      builder:
          (
            BuildContext context,
            List<int?> candidates,
            List<dynamic> rejected,
          ) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: candidates.isNotEmpty
                    ? AppTheme.danger.withValues(alpha: 0.10)
                    : AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: candidates.isNotEmpty
                      ? AppTheme.danger
                      : Colors.white10,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'BENCH · drop a starter here to remove',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDim,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (bench.isEmpty)
                    const Text(
                      'Every squad player is in the XI.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final Player p in bench)
                          LongPressDraggable<int>(
                            data: p.playerId,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: 96,
                                child: _playerChip(p, _groupColor(_groupOf(p))),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: _benchChip(p),
                            ),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  showPlayerDetail(context, p.playerId),
                              child: _benchChip(p),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            );
          },
    );
  }

  Widget _benchChip(Player p) {
    final Color color = _groupColor(_groupOf(p));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        p.name,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _playerChip(Player p, Color color, {double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600),
          ),
          Text(
            '${p.power}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static int _groupOf(Player p) {
    if (p.positionId == 1) return 1;
    if (p.positionId <= 4) return 2;
    if (p.positionId <= 8) return 3;
    return 4;
  }

  static Color _groupColor(int group) => switch (group) {
    1 => const Color(0xFFF59E0B),
    2 => const Color(0xFF3B82F6),
    3 => AppTheme.accent,
    _ => AppTheme.danger,
  };

  static List<_SlotSpec> _slotsFor(Formation f) {
    final List<_SlotSpec> slots = <_SlotSpec>[];
    int index = 0;
    slots.add(_SlotSpec(index++, 1, 'GK'));
    for (int i = 0; i < f.defenders; i++) {
      slots.add(_SlotSpec(index++, 2, 'DEF'));
    }
    for (int i = 0; i < f.midfielders; i++) {
      slots.add(_SlotSpec(index++, 3, 'MID'));
    }
    for (int i = 0; i < f.forwards; i++) {
      slots.add(_SlotSpec(index++, 4, 'ATT'));
    }
    return slots;
  }

  Widget _leadersCard(CareerProvider game) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.leaderboard, size: 16, color: AppTheme.accent),
                SizedBox(width: 6),
                Text(
                  'Club leaders',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _leaderBlock('Best rating', game.clubTopRated, rating: true),
            const Divider(height: 18),
            _leaderBlock('Top scorer', game.clubTopScorers),
            const Divider(height: 18),
            _leaderBlock('Top assists', game.clubTopAssists),
          ],
        ),
      ),
    );
  }

  Widget _leaderBlock(
    String title,
    List<LeaderRow> rows, {
    bool rating = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDim,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          const Text(
            'No matches played yet.',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          )
        else
          for (int i = 0; i < rows.length && i < 3; i++)
            InkWell(
              onTap: () => showPlayerDetail(context, rows[i].playerId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      child: Text(
                        '${i + 1}.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ),
                    PositionBadge(
                      positionId: rows[i].positionId,
                      profile: rows[i].profile,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rows[i].playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      rating
                          ? rows[i].value.toStringAsFixed(1)
                          : rows[i].display,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _playerTile(BuildContext context, CareerProvider game, Player p) {
    final int? injuryDaysRemaining = p.injuryDaysRemaining(
      game.squadInjuryReferenceDate,
    );
    final bool inStartingLineup = game.lineup.values.contains(p.playerId);
    final String roleLabel = p.squadStatus == t.squadFirstTeam
        ? (inStartingLineup ? 'Pemain Inti (XI)' : 'Pemain Inti')
        : p.squadStatus == t.squadLoanListed
        ? 'Daftar Pinjaman'
        : 'Cadangan';
    final Color roleColor = p.squadStatus == t.squadFirstTeam
        ? AppTheme.accent
        : p.squadStatus == t.squadLoanListed
        ? AppTheme.warn
        : AppTheme.textDim;
    return Card(
      child: ListTile(
        onTap: () async {
          await showPlayerDetail(context, p.playerId);
          if (mounted) await _reload();
        },
        leading: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              PositionBadge(positionId: p.positionId, profile: p.profile),
              const SizedBox(height: 2),
              Text(
                '${p.power}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: <Widget>[
            if (p.isCaptain)
              const Icon(Icons.star, size: 14, color: AppTheme.accent),
            Flexible(
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (p.marketStatus == t.marketForSale) ...<Widget>[
              const SizedBox(width: 6),
              const Text('🛒', style: TextStyle(fontSize: 11)),
            ],
            if (p.squadStatus == t.squadLoanListed) ...<Widget>[
              const SizedBox(width: 6),
              const Text('📋', style: TextStyle(fontSize: 11)),
            ],
            if (p.marketStatus == t.marketOnLoan) ...<Widget>[
              const SizedBox(width: 6),
              const Text('✈️', style: TextStyle(fontSize: 11)),
            ],
          ],
        ),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: roleColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: roleColor,
                ),
              ),
            ),
            if ((suspensions[p.playerId] ?? 0) > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'SUSP ${suspensions[p.playerId]}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            if (injuryDaysRemaining != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'CEDERA · $injuryDaysRemaining hari lagi',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            if (game.isPlayerOnInternationalDuty(p.playerId))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFF1E88E5).withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.public, size: 9, color: Color(0xFF64B5F6)),
                    SizedBox(width: 3),
                    Text(
                      'TIMNAS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64B5F6),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              '${p.age}y · ${money(p.value)} · ${money(p.salary)}/w',
              style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
            ),
            Stars(value: p.stars, size: 10),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FitnessBar(value: p.fitness),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (String action) async {
                switch (action) {
                  case 'lineup':
                    await game.toggleSquadStatus(p);
                    break;
                  case 'captain':
                    await game.makeCaptain(p);
                    break;
                  case 'market':
                    await game.toggleListedForSale(p);
                    break;
                  case 'loan':
                    await game.toggleListedForLoan(p);
                    break;
                }
                await _reload();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'lineup',
                  child: Text('Toggle squad role (Reserve / First team)'),
                ),
                const PopupMenuItem<String>(
                  value: 'captain',
                  child: Text('Make captain'),
                ),
                PopupMenuItem<String>(
                  value: 'market',
                  child: Text(
                    p.marketStatus == t.marketForSale
                        ? 'Remove from transfer list'
                        : 'List for sale',
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'loan',
                  child: Text(
                    p.squadStatus == t.squadLoanListed
                        ? 'Remove from loan list'
                        : 'List for loan',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotSpec {
  const _SlotSpec(this.index, this.group, this.label);

  final int index;
  final int group;
  final String label;
}
