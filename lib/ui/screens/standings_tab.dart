import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'knockout_bracket_sheet.dart';
import 'player_detail_sheet.dart';
import 'season_history_sheet.dart';
import 'team_detail_sheet.dart';

/// Competition table plus leaderboards. Every domestic and continental
/// competition generated for this career can be selected here.
class StandingsTab extends StatefulWidget {
  const StandingsTab({super.key});

  @override
  State<StandingsTab> createState() => _StandingsTabState();
}

class _StandingsTabState extends State<StandingsTab> {
  int? _selectedId;
  int? _loadedTournamentId;
  int? _loadedSeasonId;
  Future<CompetitionStats>? _stats;

  void _select(CareerProvider game, int id) {
    setState(() {
      _selectedId = id;
      _loadedTournamentId = id;
      _loadedSeasonId = game.season?.seasonId;
      _stats = game.competitionStats(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<Tournament> options = <Tournament>[
      if (game.domesticLeagues.isNotEmpty)
        ...game.domesticLeagues
      else if (game.league != null)
        game.league!,
      ...game.cups,
    ];
    if (options.isEmpty) {
      return const Center(child: Text('No competition available.'));
    }
    final int selectedId =
        options.any(
          (Tournament tournament) => tournament.tournamentId == _selectedId,
        )
        ? _selectedId!
        : options.first.tournamentId;
    final Tournament selected = options.firstWhere(
      (Tournament tournament) => tournament.tournamentId == selectedId,
    );
    if (_stats == null ||
        _loadedTournamentId != selectedId ||
        _loadedSeasonId != game.season?.seasonId) {
      _loadedTournamentId = selectedId;
      _loadedSeasonId = game.season?.seasonId;
      _stats = game.competitionStats(selectedId);
    }
    return FutureBuilder<CompetitionStats>(
      future: _stats,
      builder:
          (BuildContext context, AsyncSnapshot<CompetitionStats> snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final CompetitionStats stats = snapshot.data!;
            return DefaultTabController(
              length: 5,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: selectedId,
                              isExpanded: true,
                              dropdownColor: AppTheme.surfaceCard,
                              items: <DropdownMenuItem<int>>[
                                for (final Tournament tournament in options)
                                  DropdownMenuItem<int>(
                                    value: tournament.tournamentId,
                                    child: Row(
                                      children: <Widget>[
                                        TournamentAvatar(
                                          tournament: tournament,
                                          radius: 12,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            tournament.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (tournament.isLeague &&
                                            game.domesticLeagues.length > 1) ...<Widget>[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surface,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: tournament.divisionId == 1
                                                    ? AppTheme.accent
                                                    : AppTheme.textDim
                                                        .withValues(alpha: 0.4),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Text(
                                              'Div ${tournament.divisionId}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: tournament.divisionId == 1
                                                    ? AppTheme.accent
                                                    : AppTheme.textDim,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (int? id) {
                                if (id != null) _select(game, id);
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Season history',
                          icon: const Icon(Icons.history, size: 20),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SeasonHistoryScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    labelColor: AppTheme.accent,
                    unselectedLabelColor: AppTheme.textDim,
                    indicatorColor: AppTheme.accent,
                    tabs: <Widget>[
                      Tab(text: selected.isNationalCup ? 'Bracket' : 'Table'),
                      const Tab(text: 'Scorers'),
                      const Tab(text: 'Assists'),
                      const Tab(text: 'Clean sheets'),
                      const Tab(text: 'Rating'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        _LeagueTable(
                          game: game,
                          tournament: selected,
                          stats: stats,
                        ),
                        _LeaderList(
                          rows: stats.scorers,
                          metric: 'Goals',
                          userTeamId: game.userTeamId,
                          emptyHint: 'No goals scored yet this season.',
                        ),
                        _LeaderList(
                          rows: stats.assists,
                          metric: 'Assists',
                          userTeamId: game.userTeamId,
                          emptyHint: 'No assists recorded yet this season.',
                        ),
                        _LeaderList(
                          rows: stats.cleanSheets,
                          metric: 'Clean sheets',
                          userTeamId: game.userTeamId,
                          emptyHint:
                              'No clean sheets recorded yet this season.',
                        ),
                        _LeaderList(
                          rows: stats.rated,
                          metric: 'Avg rating',
                          userTeamId: game.userTeamId,
                          emptyHint:
                              'Ratings appear after players complete a match.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}

class _LeagueTable extends StatefulWidget {
  const _LeagueTable({
    required this.game,
    required this.tournament,
    required this.stats,
  });

  final CareerProvider game;
  final Tournament tournament;
  final CompetitionStats stats;

  @override
  State<_LeagueTable> createState() => _LeagueTableState();
}

class _LeagueTableState extends State<_LeagueTable> {
  CareerProvider get game => widget.game;

  static const double _rankWidth = 44;
  static const double _statWidth = 22;
  static const double _gdWidth = 26;
  static const double _ptsWidth = 30;

  static const TextStyle _headStyle = TextStyle(
    fontSize: 11,
    color: AppTheme.textDim,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    if (widget.tournament.isNationalCup) {
      return FutureBuilder<List<FixtureMatch>>(
        future: game.seasonFixtures(),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<FixtureMatch>> snap,
        ) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<FixtureMatch> matches =
              snap.data!
                  .where(
                    (FixtureMatch m) =>
                        m.tournamentId == widget.tournament.tournamentId &&
                        m.groupId == null,
                  )
                  .toList();
          return FutureBuilder<Map<int, int>>(
            future: game.cupTotalRounds(),
            builder: (
              BuildContext context,
              AsyncSnapshot<Map<int, int>> roundsSnap,
            ) {
              final int? totalRounds =
                  roundsSnap.data?[widget.tournament.tournamentId];
              return KnockoutBracketView(
                tournament: widget.tournament,
                matches: matches,
                teams: game.teamCache,
                totalRounds: totalRounds,
              );
            },
          );
        },
      );
    }
    return widget.stats.groups.isNotEmpty
        ? _groupBody(widget.stats.groups)
        : _leagueBody(widget.stats.standings);
  }

  Widget _leagueBody(List<StandingRow> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Text('No results yet — play a match to build the table.'),
      );
    }
    final List<_QualRule> legend = _buildLegend(rows.length);
    return Column(
      children: <Widget>[
        _header(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) =>
                _row(game, rows[index], index),
          ),
        ),
        if (legend.isNotEmpty) _legendWidget(legend),
      ],
    );
  }

  Widget _legendWidget(List<_QualRule> legend) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: AppTheme.surfaceCard,
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: <Widget>[
          for (final _QualRule rule in legend)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: rule.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  rule.label,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<_QualRule> _buildLegend(int total) {
    final List<_QualRule> list = <_QualRule>[];
    final Set<String> seen = <String>{};
    for (int i = 0; i < total; i++) {
      final _QualRule? q = _getQualification(i, total);
      if (q != null && !seen.contains(q.label)) {
        seen.add(q.label);
        list.add(q);
      }
    }
    return list;
  }

  _QualRule? _getQualification(int index, int total) {
    if (!widget.tournament.isLeague) return null;

    final bool hasLowerDiv = widget.game.domesticLeagues.any(
      (Tournament t) => t.divisionId == widget.tournament.divisionId + 1,
    );

    // Lower divisions
    if (widget.tournament.divisionId > 1) {
      if (index < widget.tournament.promotionSlots) {
        return const _QualRule('Promotion', 'PRO', AppTheme.accent);
      }
      if (hasLowerDiv &&
          widget.tournament.relegationSpots > 0 &&
          index >= total - widget.tournament.relegationSpots) {
        return const _QualRule('Relegation', 'REL', AppTheme.danger);
      }
      return null;
    }

    // Top Division Relegation
    if (hasLowerDiv &&
        widget.tournament.relegationSpots > 0 &&
        index >= total - widget.tournament.relegationSpots) {
      return const _QualRule('Relegation', 'REL', AppTheme.danger);
    }

    final String name = widget.tournament.name.toLowerCase();
    final String region = widget.stats.region;

    // Asia (Indonesia, Saudi, Japan, Korea, etc.)
    final bool isAsia = region == 'asia';

    if (isAsia) {
      if (index == 0) {
        return const _QualRule(
          'ACL Elite (Direct)',
          'ACL Elite',
          Color(0xFF2196F3),
        );
      } else if (index == 1) {
        return const _QualRule(
          'ACL Two (Direct)',
          'ACL Two',
          Color(0xFFFF9800),
        );
      } else if (index == 2) {
        return const _QualRule(
          'Challenge League (Playoff)',
          'ACGL PO',
          Color(0xFF4CAF50),
        );
      }
      return null;
    }

    // South America
    final bool isSouthAmerica = region == 'southAmerica';

    if (isSouthAmerica) {
      if (index < 4) {
        return const _QualRule(
          'Libertadores (Direct)',
          'Libertadores',
          Color(0xFF2196F3),
        );
      } else if (index < 6) {
        return const _QualRule(
          'Libertadores (Playoff)',
          'Libertadores PO',
          Color(0xFF00BCD4),
        );
      } else if (index < 10) {
        return const _QualRule(
          'Sudamericana',
          'Sudamericana',
          Color(0xFFFF9800),
        );
      }
      return null;
    }

    // North America (Liga MX, MLS)
    final bool isNorthAmerica = region == 'northAmerica';

    if (isNorthAmerica) {
      if (index < 4) {
        return const _QualRule('Champions Cup', 'CCC', Color(0xFF2196F3));
      }
      return null;
    }

    // Europe (Premier League, La Liga, Serie A, Bundesliga, etc.)
    final bool isTopEuro =
        name.contains('premier league') ||
        name.contains('la liga') ||
        name.contains('serie a') ||
        name.contains('bundesliga') ||
        name.contains('ligue 1');

    if (isTopEuro) {
      if (index < 4) {
        return const _QualRule(
          'Champions League (Direct)',
          'UCL',
          Color(0xFF2196F3),
        );
      } else if (index == 4) {
        return const _QualRule(
          'Europa League (Direct)',
          'UEL',
          Color(0xFFFF9800),
        );
      } else if (index == 5) {
        return const _QualRule(
          'Conference League (Playoff)',
          'UECL PO',
          Color(0xFF4CAF50),
        );
      }
    } else if (region == 'europe') {
      // General European League
      if (index < 2) {
        return const _QualRule(
          'Champions League (Direct)',
          'UCL',
          Color(0xFF2196F3),
        );
      } else if (index == 2) {
        return const _QualRule(
          'Europa League (Direct)',
          'UEL',
          Color(0xFFFF9800),
        );
      } else if (index == 3) {
        return const _QualRule(
          'Conference League (Playoff)',
          'UECL PO',
          Color(0xFF4CAF50),
        );
      }
    }

    return null;
  }

  Widget _groupBody(List<GroupTable> groups) {
    if (groups.isEmpty) {
      return const Center(child: Text('No group stage for this cup.'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: <Widget>[
        for (int i = 0; i < groups.length; i++) ...<Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            color: AppTheme.surfaceCard,
            child: Text(
              'Group ${String.fromCharCode(65 + i)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          _header(),
          for (int r = 0; r < groups[i].rows.length; r++)
            _row(game, groups[i].rows[r], r, groupStage: true),
        ],
      ],
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    color: AppTheme.surfaceCard,
    child: Row(
      children: <Widget>[
        const SizedBox(
          width: _rankWidth,
          child: Text('#', style: _headStyle),
        ),
        const Expanded(child: Text('Club', style: _headStyle)),
        _headCell('P'),
        _headCell('W'),
        _headCell('D'),
        _headCell('L'),
        _headCell('GF', width: _gdWidth),
        _headCell('GA', width: _gdWidth),
        _headCell('GD', width: _gdWidth),
        _headCell('Pts', width: _ptsWidth),
      ],
    ),
  );

  Widget _headCell(String text, {double width = _statWidth}) => SizedBox(
    width: width,
    child: Text(text, textAlign: TextAlign.center, style: _headStyle),
  );

  Widget _cell(String value, {double width = _statWidth, bool bold = false}) =>
      SizedBox(
        width: width,
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.w400,
            color: bold ? Colors.white : null,
          ),
        ),
      );

  Widget _row(
    CareerProvider game,
    StandingRow row,
    int index, {
    bool groupStage = false,
  }) {
    final bool isUser = row.teamId == game.userTeamId;
    final _QualRule? qual = groupStage
        ? (index < 2
              ? const _QualRule('Knockout Stage', 'Q', AppTheme.accent)
              : null)
        : _getQualification(index, widget.stats.standings.length);
    final Color barColor = qual?.color ?? Colors.transparent;
    return InkWell(
      onTap: () => showTeamDetail(context, row.teamId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.5),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.accentDim.withAlpha(60) : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade900, width: 0.5),
          ),
        ),
        child: Row(
        children: <Widget>[
          SizedBox(
            width: _rankWidth,
            child: Row(
              children: <Widget>[
                Container(
                  width: 3.5,
                  height: 14,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 3),
                SizedBox(
                  width: 15,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDim,
                    ),
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: _movementIndicator(row.positionChange(index + 1)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: <Widget>[
                  CrestAvatar.raw(
                    teamId: row.teamId,
                    name: row.name,
                    abbreviation: row.abbreviation,
                    logoBase64: row.logoBase64 ??
                        game.teamCache[row.teamId]?.logoBase64,
                    radius: 9,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isUser ? FontWeight.w700 : FontWeight.w400,
                        color: isUser ? AppTheme.accent : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _cell('${row.played}'),
          _cell('${row.wins}'),
          _cell('${row.draws}'),
          _cell('${row.losses}'),
          _cell('${row.goalsFor}', width: _gdWidth),
          _cell('${row.goalsAgainst}', width: _gdWidth),
          _cell('${row.goalDifference}', width: _gdWidth),
          _cell('${row.points}', width: _ptsWidth, bold: true),
        ],
      ),
    ),
  );
}

  Widget _movementIndicator(int? delta) {
    if (delta == null || delta == 0) {
      return const SizedBox.shrink();
    }
    final bool isUp = delta > 0;
    final Color color = isUp ? AppTheme.accent : AppTheme.danger;
    final int change = delta.abs();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 14,
            color: color,
          ),
          Text(
            '$change',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared leaderboard list for the four statistical tabs.
class _LeaderList extends StatelessWidget {
  const _LeaderList({
    required this.rows,
    required this.metric,
    required this.userTeamId,
    required this.emptyHint,
  });

  final List<LeaderRow> rows;
  final String metric;
  final int userTeamId;
  final String emptyHint;

  static const double _rankWidth = 28;
  static const double _positionWidth = 38;
  static const double _metricWidth = 72;

  static const TextStyle _headStyle = TextStyle(
    fontSize: 11,
    color: AppTheme.textDim,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyHint, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          color: AppTheme.surfaceCard,
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: _rankWidth,
                child: Text('#', style: _headStyle),
              ),
              const SizedBox(
                width: _positionWidth,
                child: Text('POS', style: _headStyle),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Player', style: _headStyle)),
              SizedBox(
                width: _metricWidth,
                child: Text(
                  metric.toUpperCase(),
                  textAlign: TextAlign.right,
                  style: _headStyle.copyWith(fontSize: 9),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) {
              final LeaderRow row = rows[index];
              final bool isUser = userTeamId != 0 && row.teamId == userTeamId;
              return InkWell(
                onTap: () => showPlayerDetail(context, row.playerId),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? AppTheme.accentDim.withAlpha(60) : null,
                    border: Border(
                      left: BorderSide(
                        color: isUser ? AppTheme.accent : Colors.transparent,
                        width: 3,
                      ),
                      bottom: BorderSide(
                        color: Colors.grey.shade900,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: _rankWidth,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: index < 3
                                ? FontWeight.bold
                                : FontWeight.w400,
                            color: index < 3
                                ? AppTheme.accent
                                : AppTheme.textDim,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _positionWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PositionBadge(
                            positionId: row.positionId,
                            profile: row.profile,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    row.playerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUser
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: isUser ? AppTheme.accent : null,
                                    ),
                                  ),
                                ),
                                if (isUser) ...<Widget>[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.star,
                                    size: 12,
                                    color: AppTheme.accent,
                                  ),
                                ],
                              ],
                            ),
                            GestureDetector(
                              onTap: () => showTeamDetail(context, row.teamId),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  CrestAvatar.raw(
                                    teamId: row.teamId,
                                    name: row.clubName,
                                    abbreviation: row.clubName.length >= 3
                                        ? row.clubName.substring(0, 3)
                                        : row.clubName,
                                    logoBase64: context
                                        .read<CareerProvider>()
                                        .teamCache[row.teamId]
                                        ?.logoBase64,
                                    radius: 6,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      row.clubName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textDim,
                                        decoration: TextDecoration.underline,
                                        decorationColor: Colors.white24,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: _metricWidth,
                        child: Text(
                          metric == 'Avg rating'
                              ? row.value.toStringAsFixed(1)
                              : row.display,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QualRule {
  const _QualRule(this.label, this.shortTag, this.color);

  final String label;
  final String shortTag;
  final Color color;
}
