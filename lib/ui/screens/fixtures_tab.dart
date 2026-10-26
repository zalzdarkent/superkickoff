import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'knockout_bracket_sheet.dart';
import 'team_detail_sheet.dart';

/// Season calendar grouped by match week with results and upcoming games.
class FixturesTab extends StatefulWidget {
  const FixturesTab({super.key});

  @override
  State<FixturesTab> createState() => _FixturesTabState();
}

class _FixturesTabState extends State<FixturesTab> {
  List<FixtureMatch>? fixtures;
  Map<int, String> tournamentNames = <int, String>{};
  Map<int, int> _cupTotalRounds = <int, int>{};
  final GlobalKey _currentWeekKey = GlobalKey();
  String? _scrolledToDate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final CareerProvider game = context.read<CareerProvider>();
    if (game.season == null) return;
    final List<FixtureMatch> list = game.userTeamId > 0
        ? await game.fixturesForTeam(game.userTeamId)
        : await game.seasonFixtures();
    final Map<int, int> cupRounds = await game.cupTotalRounds();
    if (!mounted) return;
    setState(() {
      fixtures = list;
      _cupTotalRounds = cupRounds;
      tournamentNames = <int, String>{
        for (final Tournament tour in game.cups) tour.tournamentId: tour.name,
      };
    });
  }

  Widget _headerBanner(CareerProvider game, int count) {
    final Team? userTeam = game.userTeam;
    if (userTeam == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: <Widget>[
          CrestAvatar(team: userTeam, radius: 11),
          const SizedBox(width: 8),
          Text(
            'Jadwal ${userTeam.name}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.accent.withAlpha(35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withAlpha(80)),
            ),
            child: Text(
              '$count Laga',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<FixtureMatch> list = fixtures ?? const <FixtureMatch>[];
    if (list.isEmpty) {
      return Center(
        child: Text(
          game.userTeam != null
              ? 'Belum ada jadwal pertandingan untuk ${game.userTeam!.name}'
              : 'Belum ada jadwal pertandingan',
          style: const TextStyle(color: AppTheme.textDim),
        ),
      );
    }

    final int leagueId = game.league?.tournamentId ?? 0;
    final Map<int, List<FixtureMatch>> knockoutMatches =
        <int, List<FixtureMatch>>{};
    for (final FixtureMatch match in list) {
      if (match.tournamentId == leagueId ||
          match.groupId != null ||
          match.phase == 0) {
        continue;
      }
      knockoutMatches
          .putIfAbsent(match.tournamentId, () => <FixtureMatch>[])
          .add(match);
    }
    final Map<int, int> totalRounds = <int, int>{
      for (final MapEntry<int, List<FixtureMatch>> entry
          in knockoutMatches.entries)
        entry.key:
            _cupTotalRounds[entry.key] ?? knockoutTotalRounds(entry.value),
    };

    // Group by tournament + round. Knockout legs are merged into one tie so
    // a two-legged round reads as one card instead of two scattered matches.
    final Map<String, List<KnockoutTie>> groups = <String, List<KnockoutTie>>{};
    // League / group / friendly games stay single; leg 2 there is just the
    // reverse fixture of the season.
    bool isCupTie(FixtureMatch m) =>
        m.tournamentId != leagueId &&
        m.groupId == null &&
        m.phase > 0 &&
        m.tournamentId != 9999;
    final List<KnockoutTie> allTies = <KnockoutTie>[
      for (final FixtureMatch m in list)
        if (!isCupTie(m)) KnockoutTie(m),
      ...groupTies(list.where(isCupTie).toList()),
    ]..sort((KnockoutTie a, KnockoutTie b) =>
        (a.first.date ?? '').compareTo(b.first.date ?? ''));

    for (final KnockoutTie tie in allTies) {
      final FixtureMatch m = tie.first;
      final bool isLeague = m.tournamentId == leagueId;
      final String stage = m.groupId != null
          ? 'Group ${String.fromCharCode(64 + m.groupId!)} · '
                'Matchday ${m.round}'
          : m.phase == 0
          ? 'League Phase · Matchday ${m.round}'
          : knockoutRoundName(m.phase, totalRounds[m.tournamentId] ?? 1);
      final String key = m.tournamentId == 9999
          ? 'Pre-Season Friendly · Match ${m.round}'
          : isLeague
          ? '${game.league?.name ?? 'League'} · Round ${m.round}'
          : '${tournamentNames[m.tournamentId] ?? 'Cup'} · $stage';
      groups.putIfAbsent(key, () => <KnockoutTie>[]).add(tie);
    }
    final List<String> keys = groups.keys.toList();
    final String? currentKey = game.nextDate == null
        ? null
        : keys.cast<String?>().firstWhere(
            (String? key) => groups[key]!.any(
              (KnockoutTie tie) =>
                  tie.first.date == game.nextDate ||
                  tie.second?.date == game.nextDate,
            ),
            orElse: () => null,
          );
    if (currentKey != null && _scrolledToDate != game.nextDate) {
      _scrolledToDate = game.nextDate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? target = _currentWeekKey.currentContext;
        if (target != null && mounted) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 250),
            alignment: 0.08,
          );
        }
      });
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _headerBanner(game, list.length),
            for (final String key in keys)
              _groupColumn(
                key,
                groups[key]!,
                key == currentKey,
                leagueId,
                game,
              ),
          ],
        ),
      ),
    );
  }

  Widget _groupColumn(
    String key,
    List<KnockoutTie> ties,
    bool isCurrent,
    int leagueId,
    CareerProvider game,
  ) {
    final List<KnockoutTie> group = List<KnockoutTie>.of(ties)
      ..sort(
        (KnockoutTie a, KnockoutTie b) =>
            (a.first.date ?? '').compareTo(b.first.date ?? ''),
      );
    final DateTime? date = DateTime.tryParse(
      group.first.first.date ?? '',
    );
    return Column(
      key: isCurrent ? _currentWeekKey : null,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$key  ·  ${date == null ? '' : _formatDate(date)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: group.first.first.tournamentId == leagueId
                        ? AppTheme.accent
                        : AppTheme.warn,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final KnockoutTie tie in group) _fixtureRow(game, tie),
      ],
    );
  }

  Widget _fixtureRow(CareerProvider game, KnockoutTie tie) {
    final FixtureMatch m = tie.first;
    final FixtureMatch? second = tie.second;
    final bool involvesUser =
        m.homeTeamId == game.userTeamId || m.awayTeamId == game.userTeamId;
    final (int, int)? pens = tie.penalties;
    final bool showAgg = second != null && tie.complete;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: involvesUser
            ? AppTheme.accentDim.withAlpha(70)
            : AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            game.competitionLabel(m).toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              letterSpacing: .6,
              color: AppTheme.textDim,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          _legRow(
            game,
            m,
            involvesUser,
            legLabel: second == null ? null : 'Leg 1',
          ),
          if (second != null) ...<Widget>[
            const SizedBox(height: 4),
            _legRow(game, second, involvesUser, legLabel: 'Leg 2'),
          ],
          if (showAgg)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  'Aggregate ${game.teamCache[m.homeTeamId]?.abbreviation ?? ''} '
                  '${tie.homeAgg}-${tie.awayAgg} '
                  '${game.teamCache[m.awayTeamId]?.abbreviation ?? ''}'
                  '${pens == null ? '' : '  ·  pens ${pens.$1}-${pens.$2}'}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            )
          else if (second == null && pens != null)
            Center(
              child: Text(
                'pens ${pens.$1}-${pens.$2}',
                style: const TextStyle(fontSize: 9, color: AppTheme.warn),
              ),
            ),
        ],
      ),
    );
  }

  Widget _legRow(
    CareerProvider game,
    FixtureMatch m,
    bool involvesUser, {
    String? legLabel,
  }) {
    final Team? home = game.teamCache[m.homeTeamId];
    final Team? away = game.teamCache[m.awayTeamId];
    final DateTime? date = DateTime.tryParse(m.date ?? '');
    final bool played = m.isPlayed;
    final TextStyle nameStyle = TextStyle(
      fontSize: 12,
      fontWeight: involvesUser ? FontWeight.w700 : FontWeight.w400,
    );
    return Row(
      children: <Widget>[
        if (legLabel != null)
          SizedBox(
            width: 38,
            child: Text(
              '$legLabel${date == null ? '' : '\n${_formatDate(date)}'}',
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: AppTheme.warn,
              ),
            ),
          ),
        Expanded(
          child: InkWell(
            onTap: home == null
                ? null
                : () => showTeamDetail(context, m.homeTeamId),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      home?.name ?? '?',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle,
                    ),
                  ),
                  if (home != null) ...<Widget>[
                    const SizedBox(width: 6),
                    CrestAvatar(team: home, radius: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
        Container(
          width: 56,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            played ? '${m.homeGoals ?? 0} - ${m.awayGoals ?? 0}' : 'vs',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: played ? 14 : 11,
              color: played ? Colors.white : AppTheme.textDim,
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: away == null
                ? null
                : () => showTeamDetail(context, m.awayTeamId),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  if (away != null) ...<Widget>[
                    CrestAvatar(team: away, radius: 10),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      away?.name ?? '?',
                      textAlign: TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (legLabel != null) const SizedBox(width: 38),
      ],
    );
  }

  static String _formatDate(DateTime d) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
