import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../game/training.dart';
import '../../state/career_provider.dart';
import '../theme.dart';

/// Weekly training session: one focus per matchday, paid from the club budget.
Future<void> showTrainingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) =>
        const FractionallySizedBox(heightFactor: 0.78, child: TrainingSheet()),
  );
}

class TrainingSheet extends StatefulWidget {
  const TrainingSheet({super.key});

  @override
  State<TrainingSheet> createState() => _TrainingSheetState();
}

class _TrainingSheetState extends State<TrainingSheet> {
  late Future<TrainingState> _future;
  TrainingFocus _focus = TrainingFocus.attack;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().trainingState();
  }

  void _reload() {
    setState(() {
      _future = context.read<CareerProvider>().trainingState();
    });
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    final TrainingOutcome outcome = await context
        .read<CareerProvider>()
        .runTraining(_focus);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!outcome.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.error!),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    _reload();
    final List<String> names = outcome.improved;
    final String detail = names.isEmpty
        ? 'Training session completed.'
        : names.length <= 3
        ? '${names.join(', ')} improved.'
        : '${names.length} players improved.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: FutureBuilder<TrainingState>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<TrainingState> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final TrainingState? state = snap.data;
          if (state == null) {
            return const Center(child: Text('Training data not available.'));
          }
          return _content(state);
        },
      ),
    );
  }

  Widget _content(TrainingState state) {
    final CareerProvider game = context.watch<CareerProvider>();
    final int eligible = state.eligible[_focus.name] ?? 0;
    final bool focusDone = state.doneFocuses.contains(_focus.name);
    final bool canTrain = !focusDone && eligible > 0 && !_busy;
    return Column(
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
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.accentDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fitness_center,
                  color: AppTheme.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Weekly training',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'One session per focus each matchday',
                      style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final TrainingFocus focus in TrainingFocus.values)
                      ChoiceChip(
                        label: Text(
                          state.doneFocuses.contains(focus.name)
                              ? '${focus.label} \u2713'
                              : focus.label,
                        ),
                        selected: _focus == focus,
                        onSelected: (_) => setState(() => _focus = focus),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _focus.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppTheme.textDim,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _focus.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          _pill(
                            '$eligible eligible',
                            eligible > 0 ? AppTheme.accent : AppTheme.warn,
                          ),
                          const SizedBox(width: 8),
                          _pill(
                            _focus.isFitness
                                ? 'Whole squad +${TrainingRules.fitnessGain} fitness'
                                : 'Up to ${TrainingRules.maxPlayers} players '
                                      '+${TrainingRules.powerGain} power',
                            AppTheme.textDim,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _row('Session cost', money(state.cost)),
                _row('Club budget', money(game.userTeam?.budget ?? 0)),
                _row('Sessions completed', '${state.sessions}'),
                if (focusDone) ...<Widget>[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warn.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.warn.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.schedule,
                          size: 18,
                          color: AppTheme.warn,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_focus.label} training is done for this matchday. '
                            'Pick another focus, or play your next match to '
                            'unlock it again.',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canTrain ? _start : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(
                  focusDone
                      ? 'Already trained today'
                      : eligible <= 0
                      ? 'No eligible players'
                      : 'Start session \u00b7 ${money(state.cost)}',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color == AppTheme.textDim ? AppTheme.textDim : color,
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
