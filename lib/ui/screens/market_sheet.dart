import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Transfer market sheet: search listed players and buy them.
class MarketSheet extends StatefulWidget {
  const MarketSheet({super.key});

  @override
  State<MarketSheet> createState() => _MarketSheetState();
}

class _MarketSheetState extends State<MarketSheet> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, Object?>> players = <Map<String, Object?>>[];
  int? positionFilter;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
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
    );
    if (!mounted) return;
    setState(() {
      players = list;
      loading = false;
    });
  }

  Future<void> _confirmBuy(Map<String, Object?> row) async {
    final CareerProvider game = context.read<CareerProvider>();
    final int value = (row['value'] as int?) ?? 0;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Sign ${row['name']}?'),
        content: Text(
          'Transfer fee: ${money(value)}\n'
          'Club: ${row['club_name'] ?? 'Free agent'}\n'
          'Power: ${row['power']} / Potential: ${row['potential']}\n'
          'Your budget: ${money(game.userTeam?.budget ?? 0)}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Buy'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final String? failure = await game.buyPlayer(row);
    if (!mounted) return;
    setState(() => error = failure);
    if (failure == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${row['name']} joined your squad!')));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollController) =>
          Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: <Widget>[
                  const Text(
                    'Transfer Market',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Text(
                    'Budget ${money(game.userTeam?.budget ?? 0)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.accent),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                child: Text(error!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
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
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: players.length,
                          itemBuilder: (BuildContext context, int index) {
                            final Map<String, Object?> row = players[index];
                            return Card(
                              child: ListTile(
                                leading: PositionBadge(
                                  positionId:
                                      (row['position_id'] as int?) ?? 1,
                                ),
                                title: Text(
                                  '${row['name']}  ${row['power']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '${row['age']}y · ${row['club_name']} · '
                                  '${money((row['value'] as int?) ?? 0)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.add_shopping_cart,
                                      color: AppTheme.accent),
                                  onPressed: () => _confirmBuy(row),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
