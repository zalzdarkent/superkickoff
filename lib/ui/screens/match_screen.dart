import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../game/match_engine.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'match_stats_sheet.dart';
import 'matchday_results_sheet.dart';
import 'team_detail_sheet.dart';

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
  bool _hapticTriggered = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void startClock() {
    _ticker?.cancel();
    _ticker = Timer.periodic(Duration(milliseconds: (400 / speed).round()), (
      Timer t,
    ) {
      final LiveMatchSession? session = context
          .read<CareerProvider>()
          .liveSession;
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

  void showStats(LiveMatchSession session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: MatchStatsSheet(session: session),
      ),
    );
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
    final List<MatchEvent> shown = session.result.events
        .where((MatchEvent e) => e.minute <= displayedMinute)
        .toList();
    final List<MatchEvent> kicks = displayedMinute >= 90
        ? session.shootoutEvents
        : <MatchEvent>[];
    final bool finished = displayedMinute >= 90;
    final bool isChampion = finished && session.isUserChampion(game.userTeamId);
    final bool isRunnerUp = finished && session.isUserRunnerUp(game.userTeamId);

    if (finished && !_hapticTriggered) {
      _hapticTriggered = true;
      if (isChampion) {
        HapticFeedback.heavyImpact();
      } else if (session.isHighStakes) {
        HapticFeedback.mediumImpact();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: session.isHighStakes
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.emoji_events, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(session.isCupFinal ? 'Final' : 'Title Decider'),
                ],
              )
            : const Text('Match Day'),
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              _scoreBoard(
                session,
                game.competitionLabel(session.match),
                homeGoals,
                awayGoals,
                isChampion: isChampion,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    if (isChampion) _celebrationBanner(session, game),
                    if (isRunnerUp) _runnerUpBanner(session),
                    for (final MatchEvent e in shown) _eventTile(e, session),
                    if (kicks.isNotEmpty) _shootoutSection(session, kicks),
                  ],
                ),
              ),
              _controls(finished, session, game, isChampion: isChampion),
            ],
          ),
          if (isChampion)
            const Positioned.fill(
              child: IgnorePointer(child: ConfettiOverlay()),
            ),
        ],
      ),
    );
  }

  int _goalsUpTo(LiveMatchSession session, bool home) {
    int goals = 0;
    for (final MatchEvent e in session.result.events) {
      if (e.minute > displayedMinute) break;
      if (e.type == MatchEvent.goal ||
          e.type == MatchEvent.ownGoal ||
          e.type == MatchEvent.penaltyScored) {
        final bool benefitsHome = e.type == MatchEvent.ownGoal
            ? !e.isHome
            : e.isHome;
        if (benefitsHome == home) goals++;
      }
    }
    return goals;
  }

  Widget _scoreBoard(
    LiveMatchSession session,
    String competitionLabel,
    int homeGoals,
    int awayGoals, {
    bool isChampion = false,
  }) {
    final bool highStakes = session.isHighStakes;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isChampion
              ? Colors.amber.shade400
              : (highStakes
                    ? Colors.amber.shade700.withValues(alpha: 0.5)
                    : Colors.grey.shade900),
          width: isChampion ? 2 : 1,
        ),
        boxShadow: isChampion
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        children: <Widget>[
          if (highStakes)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.amber.shade600.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.emoji_events, size: 12, color: Colors.amber),
                  const SizedBox(width: 5),
                  Text(
                    session.isCupFinal ? 'FINAL' : 'TITLE DECIDER',
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: .8,
                      color: Colors.amber,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            competitionLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: .7,
              color: highStakes ? Colors.amber.shade200 : AppTheme.textDim,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: () => showTeamDetail(context, session.homeTeam.teamId),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: <Widget>[
                        Text(
                          session.homeTeam.abbreviation,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.homeTeam.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                children: <Widget>[
                  Text(
                    '$homeGoals - $awayGoals',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (displayedMinute >= 90 && session.decidedOnPenalties)
                    Text(
                      'Pens ${_shootoutScore(session, true)}-'
                      '${_shootoutScore(session, false)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warn,
                      ),
                    ),
                  Text(
                    '$displayedMinute\'',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: InkWell(
                  onTap: () => showTeamDetail(context, session.awayTeam.teamId),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: <Widget>[
                        Text(
                          session.awayTeam.abbreviation,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.awayTeam.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (session.isLeg2) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Text(
                'AGG: ${homeGoals + session.leg1HomeGoals} - ${awayGoals + session.leg1AwayGoals}  ·  '
                '1st Leg: ${session.leg1HomeGoals}-${session.leg1AwayGoals}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: .4,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ] else if (session.isLeg1) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '1st Leg of 2',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDim,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _shootoutScore(LiveMatchSession session, bool home) {
    int score = 0;
    for (final MatchEvent e in session.shootoutEvents) {
      if (e.isHome == home && e.detail?.startsWith('scored') == true) score++;
    }
    return score;
  }

  /// Penalty shootout kicks listed after normal time.
  Widget _shootoutSection(LiveMatchSession session, List<MatchEvent> kicks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(
            'PENALTY SHOOTOUT',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: AppTheme.textDim,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final MatchEvent e in kicks)
          ListTile(
            dense: true,
            leading: Icon(
              e.detail?.startsWith('scored') == true
                  ? Icons.check_circle
                  : Icons.cancel,
              size: 18,
              color: e.detail?.startsWith('scored') == true
                  ? AppTheme.accent
                  : AppTheme.danger,
            ),
            title: Text(
              '${e.playerName ?? 'Taker'}  ·  '
              '${e.detail?.startsWith('scored') == true ? 'scored' : 'missed'}',
              style: const TextStyle(fontSize: 13),
            ),
            trailing: Text(
              (e.isHome ? session.homeTeam : session.awayTeam).abbreviation,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _eventTile(MatchEvent e, LiveMatchSession session) {
    final (String label, IconData icon, Color color) = switch (e.type) {
      MatchEvent.goal => ('Goal', Icons.sports_soccer, AppTheme.accent),
      MatchEvent.penaltyScored => (
        'Penalty scored',
        Icons.sports_handball,
        AppTheme.accent,
      ),
      MatchEvent.penaltyMissed => (
        'Penalty missed',
        Icons.sports_handball,
        AppTheme.warn,
      ),
      MatchEvent.ownGoal => ('Own goal', Icons.error_outline, AppTheme.danger),
      MatchEvent.save => ('Save', Icons.pan_tool, AppTheme.textDim),
      MatchEvent.yellow => ('Yellow card', Icons.square, AppTheme.warn),
      MatchEvent.red => ('Red card', Icons.square, AppTheme.danger),
      MatchEvent.injury => ('Injury', Icons.medical_services, AppTheme.danger),
      MatchEvent.subIn => (
        'Substitution in',
        Icons.swap_horiz,
        AppTheme.textDim,
      ),
      MatchEvent.subOut => (
        'Substitution out',
        Icons.swap_horiz,
        AppTheme.textDim,
      ),
      MatchEvent.varCheck => ('VAR check', Icons.monitor, AppTheme.textDim),
      MatchEvent.varGoalDisallowed => (
        'Goal disallowed',
        Icons.videocam_off,
        AppTheme.danger,
      ),
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
      trailing: Text(
        team.abbreviation,
        style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
      ),
    );
  }

  Widget _controls(
    bool finished,
    LiveMatchSession session,
    CareerProvider game, {
    bool isChampion = false,
  }) {
    final int homeGoals = _goalsUpTo(session, true);
    final int awayGoals = _goalsUpTo(session, false);
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
                      statChip(
                        session.isLeg2
                            ? 'Aggregate'
                            : (session.decidedOnPenalties
                                  ? 'Penalties'
                                  : 'Final score'),
                        session.isLeg2
                            ? '${homeGoals + session.leg1HomeGoals}-'
                                  '${awayGoals + session.leg1AwayGoals}'
                                  '${session.decidedOnPenalties ? ' (pens ${_shootoutScore(session, true)}-${_shootoutScore(session, false)})' : ''}'
                            : (session.decidedOnPenalties
                                  ? '${_shootoutScore(session, true)}-'
                                        '${_shootoutScore(session, false)}'
                                  : 'FT'),
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 16),
                      statChip(
                        'Revenue',
                        money(session.result.revenue),
                        icon: Icons.payments,
                      ),
                      const SizedBox(width: 16),
                      statChip(
                        'Attendance',
                        '${session.result.attendanceGeneral + session.result.attendanceStand + session.result.attendanceTerrace + session.result.attendanceBoxes}',
                        icon: Icons.groups,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: () => showStats(session),
                        icon: const Icon(Icons.bar_chart, size: 16),
                        label: const Text('Stats'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: isChampion
                            ? FilledButton.icon(
                                onPressed: () async {
                                  await game.finishLiveMatch();
                                  if (!mounted) return;
                                  await showMatchdayResults(
                                    context,
                                    matches: game.lastMatchday,
                                    teams: game.lastMatchdayTeams,
                                    userTeamId: game.userTeamId,
                                    competitionLabel: game.competitionLabel,
                                    aggregates: game.lastMatchdayAggregates,
                                    date: session.match.date,
                                  );
                                  if (mounted) Navigator.of(context).pop();
                                },
                                icon: const Icon(Icons.emoji_events, size: 16),
                                label: const Text('Continue'),
                              )
                            : FilledButton(
                                onPressed: () async {
                                  await game.finishLiveMatch();
                                  if (!mounted) return;
                                  await showMatchdayResults(
                                    context,
                                    matches: game.lastMatchday,
                                    teams: game.lastMatchdayTeams,
                                    userTeamId: game.userTeamId,
                                    competitionLabel: game.competitionLabel,
                                    aggregates: game.lastMatchdayAggregates,
                                    date: session.match.date,
                                  );
                                  if (mounted) Navigator.of(context).pop();
                                },
                                child: const Text('Continue'),
                              ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      speed = speed == 1 ? 2 : (speed == 2 ? 4 : 1);
                      startClock();
                    }),
                    icon: const Icon(Icons.speed, size: 16),
                    label: Text('${speed.toInt()}x'),
                  ),
                  const SizedBox(width: 8),
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

  Widget _celebrationBanner(LiveMatchSession session, CareerProvider game) {
    final Team team = game.teamCache[game.userTeamId] ?? session.homeTeam;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFF78350F),
            Color(0xFFB45309),
            Color(0xFFD97706),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amberAccent.withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.emoji_events, size: 30, color: Colors.amberAccent),
              SizedBox(width: 8),
              Text(
                '🏆 JUARA! CHAMPIONS! 🏆',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            team.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Selamat atas gelar juara ${session.trophyName ?? 'ini'}!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.amber.shade100,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _runnerUpBanner(LiveMatchSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.military_tech, size: 28, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '🥈 RUNNER-UP',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.white,
                ),
              ),
              Text(
                'Peringkat kedua di ${session.trophyName ?? 'Final'}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lightweight falling confetti animation overlay for championship celebrations.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key});

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_ConfettiParticle> _particles = <_ConfettiParticle>[];

  @override
  void initState() {
    super.initState();
    final Random rng = Random();
    const List<Color> colors = <Color>[
      Colors.amber,
      Colors.orange,
      Colors.yellowAccent,
      Colors.lightBlueAccent,
      Colors.redAccent,
      Colors.purpleAccent,
      Colors.white,
      Colors.greenAccent,
    ];
    for (int i = 0; i < 60; i++) {
      _particles.add(
        _ConfettiParticle(
          x: rng.nextDouble(),
          y: rng.nextDouble() * -1.0,
          speed: 0.15 + rng.nextDouble() * 0.35,
          size: 6.0 + rng.nextDouble() * 6.0,
          color: colors[rng.nextInt(colors.length)],
          rotationSpeed: (rng.nextDouble() - 0.5) * 8.0,
          swingSpeed: 1.0 + rng.nextDouble() * 3.0,
          isCircle: rng.nextBool(),
        ),
      );
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        return CustomPaint(
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.color,
    required this.rotationSpeed,
    required this.swingSpeed,
    required this.isCircle,
  });

  final double x;
  final double y;
  final double speed;
  final double size;
  final Color color;
  final double rotationSpeed;
  final double swingSpeed;
  final bool isCircle;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final _ConfettiParticle p in particles) {
      final double currentY = (p.y + progress * p.speed * 4) % 1.2;
      final double drawY = (currentY - 0.1) * size.height;
      final double swing =
          sin(progress * 2 * pi * p.swingSpeed + p.x * 10) * 15;
      final double drawX = p.x * size.width + swing;

      final Paint paint = Paint()..color = p.color;
      canvas.save();
      canvas.translate(drawX, drawY);
      canvas.rotate(progress * 2 * pi * p.rotationSpeed);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
