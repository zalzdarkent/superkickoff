import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../game/match_engine.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Live match viewer: the result is pre-simulated by the engine and revealed
/// minute by minute, exactly like Superkickoff's timeline games.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  Timer? _ticker;
  int displayedMinute = 0;
  double speed = 1;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void startClock() {
    _ticker?.cancel();
    _ticker = Timer.periodic(Duration(milliseconds: (400 / speed).round()),
        (Timer t) {
      final LiveMatchSession? session =
          context.read<CareerProvider>().liveSession;
      if (session == null) return;
      if (displayedMinute < 90) {
        setState(() => displayedMinute++);
      } else {
        t.cancel();
      }
    });
  }

  void finishInstantly() {
    setState(() => displayedMinute = 90);
    _ticker?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final LiveMatchSession? session = game.liveSession;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (displayedMinute == 0) {
      // First build after session set: kick-off.
      scheduleMicrotask(startClock);
    }
    final int homeGoals = _goalsUpTo(session, true);
    final int awayGoals = _goalsUpTo(session, false);
    final List<MatchEvent> shown =
        session.result.events.where((MatchEvent e) => e.minute <= displayedMinute).toList();
    final bool finished = displayedMinute >= 90;

    return Scaffold(
      appBar: AppBar(title: const Text('Match Day')),
      body: Column(
        children: <Widget>[
          _scoreBoard(session, homeGoals, awayGoals),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: shown.length,
              itemBuilder: (BuildContext context, int index) =>
                  _eventTile(shown[index], session),
            ),
          ),
          _controls(finished, session, game),
        ],
      ),
    );
  }

  int _goalsUpTo(LiveMatchSession session, bool home) {
    int goals = 0;
    for (final MatchEvent e in session.result.events) {
      if (e.minute > displayedMinute) break;
      if (e.type == MatchEvent.goal || e.type == MatchEvent.ownGoal ||
          e.type == MatchEvent.penaltyScored) {
        final bool benefitsHome =
            e.type == MatchEvent.ownGoal ? !e.isHome : e.isHome;
        if (benefitsHome == home) goals++;
      }
    }
    return goals;
  }

  Widget _scoreBoard(LiveMatchSession session, int homeGoals, int awayGoals) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade900),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  session.homeTeam.abbreviation,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  session.homeTeam.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          Column(
            children: <Widget>[
              Text(
                '$homeGoals - $awayGoals',
                style: const TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w900),
              ),
              Text('$displayedMinute\'',
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  session.awayTeam.abbreviation,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  session.awayTeam.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventTile(MatchEvent e, LiveMatchSession session) {
    final (String label, IconData icon, Color color) = switch (e.type) {
      MatchEvent.goal => ('Goal', Icons.sports_soccer, AppTheme.accent),
      MatchEvent.penaltyScored =>
        ('Penalty scored', Icons.sports_handball, AppTheme.accent),
      MatchEvent.penaltyMissed =>
        ('Penalty missed', Icons.sports_handball, AppTheme.warn),
      MatchEvent.ownGoal => ('Own goal', Icons.error_outline, AppTheme.danger),
      MatchEvent.save => ('Save', Icons.pan_tool, AppTheme.textDim),
      MatchEvent.yellow => ('Yellow card', Icons.square, AppTheme.warn),
      MatchEvent.red => ('Red card', Icons.square, AppTheme.danger),
      MatchEvent.injury => ('Injury', Icons.medical_services, AppTheme.danger),
      MatchEvent.subIn => ('Substitution in', Icons.swap_horiz, AppTheme.textDim),
      MatchEvent.subOut => ('Substitution out', Icons.swap_horiz, AppTheme.textDim),
      MatchEvent.varCheck => ('VAR check', Icons.monitor, AppTheme.textDim),
      MatchEvent.varGoalDisallowed =>
        ('Goal disallowed', Icons.videocam_off, AppTheme.danger),
      _ => (e.type, Icons.info, AppTheme.textDim),
    };
    final Team team = e.isHome ? session.homeTeam : session.awayTeam;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        '${e.minute}\'  $label${e.playerName != null ? '  ·  ${e.playerName}' : ''}',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Text(team.abbreviation,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
    );
  }

  Widget _controls(
      bool finished, LiveMatchSession session, CareerProvider game) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: finished
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      statChip('Final score',
                          'FT', color: AppTheme.accent),
                      const SizedBox(width: 16),
                      statChip(
                          'Revenue',
                          money(session.result.revenue),
                          icon: Icons.payments),
                      const SizedBox(width: 16),
                      statChip(
                          'Attendance',
                          '${session.result.attendanceGeneral + session.result.attendanceStand + session.result.attendanceTerrace + session.result.attendanceBoxes}',
                          icon: Icons.groups),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await game.finishLiveMatch();
                        if (mounted) Navigator.of(context).pop();
                      },
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  for (final double s in <double>[1, 2, 4])
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          speed = s;
                          startClock();
                        }),
                        icon: Icon(speed == s ? Icons.check : Icons.speed, size: 14),
                        label: Text('${s}x'),
                      ),
                    ),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: finishInstantly,
                      icon: const Icon(Icons.skip_next, size: 16),
                      label: const Text('To end'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
