import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/db/schema.dart' as t;
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Squad management: list players with line-up status, captain pick and
/// transfer listing.
class SquadTab extends StatefulWidget {
  const SquadTab({super.key});

  @override
  State<SquadTab> createState() => _SquadTabState();
}

class _SquadTabState extends State<SquadTab> {
  List<Player>? squad;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final CareerProvider game = context.read<CareerProvider>();
    final List<Player> players = await game.squadForUser();
    if (!mounted) return;
    setState(() => squad = players);
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<Player> players = squad ?? const <Player>[];
    if (game.busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (players.isEmpty) {
      return const Center(child: Text('Squad not loaded'));
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: players.length,
        itemBuilder: (BuildContext context, int index) =>
            _playerTile(context, game, players[index]),
      ),
    );
  }

  Widget _playerTile(BuildContext context, CareerProvider game, Player p) {
    final String statusLabel = switch (p.squadStatus) {
      t.squadFirstTeam => 'XI',
      t.squadReserve => 'Res',
      _ => 'Loan',
    };
    final Color statusColor = switch (p.squadStatus) {
      t.squadFirstTeam => AppTheme.accent,
      t.squadReserve => AppTheme.textDim,
      _ => AppTheme.warn,
    };
    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              PositionBadge(positionId: p.positionId),
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
            if (p.isCaptain) const Icon(Icons.star, size: 14, color: AppTheme.accent),
            Flexible(
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            if (p.marketStatus == t.marketForSale) ...<Widget>[
              const SizedBox(width: 6),
              const Text('🛒', style: TextStyle(fontSize: 11)),
            ],
          ],
        ),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(statusLabel,
                style: TextStyle(fontSize: 10, color: statusColor)),
            Text('${p.age}y · ${money(p.value)} · ${money(p.salary)}/w',
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim)),
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
                }
                await _reload();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                    value: 'lineup',
                    child: Text('Toggle squad role (Reserve / First team)')),
                const PopupMenuItem<String>(
                    value: 'captain', child: Text('Make captain')),
                PopupMenuItem<String>(
                    value: 'market',
                    child: Text(p.marketStatus == t.marketForSale
                        ? 'Remove from market'
                        : 'List for sale')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
