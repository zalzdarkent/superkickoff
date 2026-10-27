import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../game/offseason.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'market_tab.dart';
import 'squad_tab.dart';

/// The break between two seasons: seven stages, worked through in order.
class OffseasonView extends StatelessWidget {
  const OffseasonView({super.key});

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final OffseasonState? state = game.offseason;
    if (state == null) return const SizedBox.shrink();
    final OffseasonStep step = state.current;
    final int total = OffseasonStep.values.length;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'OFF-SEASON · STEP ${state.step + 1} OF $total',
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: .8,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDim,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                step.subtitle,
                style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  for (int i = 0; i < total; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i <= state.step
                              ? AppTheme.accent
                              : Colors.white12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _body(context, game, state)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: game.busy ? null : () => _next(context, game, state),
                child: LoadingButtonContent(
                  isLoading: game.busy,
                  child: Text(_nextLabel(state, game)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _nextLabel(OffseasonState state, CareerProvider game) {
    final int next = state.step + 1;
    if (state.current == OffseasonStep.newSeason) return 'Start new season';
    return 'Continue to: ${OffseasonStep.values[next].title}';
  }

  Widget _body(BuildContext context, CareerProvider game, OffseasonState s) {
    switch (s.current) {
      case OffseasonStep.contracts:
        return ListView(
          children: <Widget>[
            _ReportCard(lines: s.reportLines),
            const _ContractsList(),
          ],
        );
      case OffseasonStep.transfers:
        return _TransferStage(state: s);
      case OffseasonStep.preseason:
        return ListView(
          children: <Widget>[
            _ReportCard(lines: s.reportLines),
            for (final PreseasonCamp camp in PreseasonCamp.values)
              _ChoiceCard(
                title: camp.label,
                description: camp.description,
                selected: s.camp == camp.name,
                locked: s.camp != null,
                onTap: () => _report(context, game.choosePreseasonCamp(camp)),
              ),
          ],
        );
      case OffseasonStep.board:
        return ListView(
          children: <Widget>[
            _ReportCard(lines: s.reportLines),
            if (s.ambition == null) const _BoardOptions(),
          ],
        );
      default:
        return ListView(children: <Widget>[_ReportCard(lines: s.reportLines)]);
    }
  }

  Future<void> _report(BuildContext context, Future<String?> result) async {
    final String? error = await result;
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _next(
    BuildContext context,
    CareerProvider game,
    OffseasonState state,
  ) async {
    if (state.current == OffseasonStep.newSeason) {
      await game.startNextSeason();
      return;
    }
    if (state.current == OffseasonStep.contracts) {
      final int leaving = (await game.expiringContracts()).length;
      if (leaving > 0 && context.mounted) {
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Let players go?'),
            content: Text(
              '$leaving player${leaving == 1 ? '' : 's'} without a new '
              'contract will leave the club on a free transfer.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Let them go'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }
    if (!context.mounted) return;
    await _report(context, game.advanceOffseason());
  }
}

/// Lines of a stage report. "+ " / "- " prefixes mark gains and losses.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final String line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _line(line),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(String line) {
    final bool up = line.startsWith('+ ');
    final bool down = line.startsWith('- ');
    if (!up && !down) {
      return Text(line, style: const TextStyle(fontSize: 13));
    }
    return Row(
      children: <Widget>[
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: up ? AppTheme.accent : AppTheme.danger,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(line.substring(2), style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: selected ? AppTheme.accent : Colors.transparent),
    ),
    child: ListTile(
      enabled: !locked || selected,
      onTap: locked ? null : onTap,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(description, style: const TextStyle(fontSize: 12)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppTheme.accent)
          : null,
    ),
  );
}

class _ContractsList extends StatefulWidget {
  const _ContractsList();

  @override
  State<_ContractsList> createState() => _ContractsListState();
}

class _ContractsListState extends State<_ContractsList> {
  late Future<List<ExpiringContract>> _future;
  int? _renewingPlayerId;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().expiringContracts();
  }

  Future<void> _renew(ExpiringContract c) async {
    if (_renewingPlayerId != null) return;
    setState(() => _renewingPlayerId = c.player.playerId);
    final CareerProvider game = context.read<CareerProvider>();
    try {
      final String? error = await game.renewContract(c.player.playerId);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      setState(() => _future = game.expiringContracts());
    } finally {
      if (mounted) setState(() => _renewingPlayerId = null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ExpiringContract>>(
    future: _future,
    builder:
        (BuildContext context, AsyncSnapshot<List<ExpiringContract>> snap) {
          final List<ExpiringContract> items =
              snap.data ?? <ExpiringContract>[];
          if (items.isEmpty) return const SizedBox.shrink();
          return SectionCard(
            title: 'Expiring contracts',
            child: Column(
              children: <Widget>[
                for (final ExpiringContract c in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PositionBadge(
                      positionId: c.player.positionId,
                      profile: c.player.profile,
                    ),
                    title: Text(
                      '${c.player.name}  ${c.player.power}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${c.player.age}y · new wage ${money(c.newSalary)} · '
                      'bonus ${money(c.signingBonus)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _renewingPlayerId == null
                          ? () => _renew(c)
                          : null,
                      child: LoadingButtonContent(
                        isLoading: _renewingPlayerId == c.player.playerId,
                        child: const Text('Renew'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
  );
}

class _TransferStage extends StatefulWidget {
  const _TransferStage({required this.state});

  final OffseasonState state;

  @override
  State<_TransferStage> createState() => _TransferStageState();
}

class _TransferStageState extends State<_TransferStage> {
  bool _showSquad = false;

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final int weeks = widget.state.windowWeeks;
    return Column(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  weeks > 0
                      ? 'Window open: $weeks week${weeks == 1 ? '' : 's'} left'
                      : 'The window has closed. You can continue.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (weeks > 0) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: game.busy
                              ? null
                              : game.advanceTransferWindow,
                          child: LoadingButtonContent(
                            isLoading: game.busy,
                            child: const Text('Advance 1 week'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: game.busy
                              ? null
                              : () => game.advanceTransferWindow(
                                  toDeadline: true,
                                ),
                          child: LoadingButtonContent(
                            isLoading: game.busy,
                            child: const Text('Skip to deadline'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(value: false, label: Text('Market')),
              ButtonSegment<bool>(value: true, label: Text('My squad')),
            ],
            selected: <bool>{_showSquad},
            onSelectionChanged: (Set<bool> v) =>
                setState(() => _showSquad = v.first),
          ),
        ),
        Expanded(child: _showSquad ? const SquadTab() : const MarketTab()),
      ],
    );
  }
}

class _BoardOptions extends StatefulWidget {
  const _BoardOptions();

  @override
  State<_BoardOptions> createState() => _BoardOptionsState();
}

class _BoardOptionsState extends State<_BoardOptions> {
  late final Future<List<BoardOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().boardOptions();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<BoardOption>>(
    future: _future,
    builder: (BuildContext context, AsyncSnapshot<List<BoardOption>> snap) =>
        Column(
          children: <Widget>[
            for (final BoardOption o in snap.data ?? <BoardOption>[])
              _ChoiceCard(
                title: '${o.ambition.label}: finish top ${o.targetRank}',
                description:
                    '${o.ambition.description} Advance ${money(o.advance)} '
                    'now, bonus ${money(o.bonus)} if we deliver.',
                selected: false,
                locked: false,
                onTap: () async {
                  final String? error = await context
                      .read<CareerProvider>()
                      .chooseBoardAmbition(o.ambition);
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(error)));
                  }
                },
              ),
          ],
        ),
  );
}
