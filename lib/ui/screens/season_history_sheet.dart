import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import 'annual_awards_gala_sheet.dart';
import 'team_detail_sheet.dart';

/// Browses the final league tables and continental group tables of past
/// seasons. Archived matches stay in the database, so tables are rebuilt from
/// them on demand.
class SeasonHistoryScreen extends StatefulWidget {
  const SeasonHistoryScreen({super.key});

  @override
  State<SeasonHistoryScreen> createState() => _SeasonHistoryScreenState();
}

class _SeasonHistoryScreenState extends State<SeasonHistoryScreen> {
  List<Season> _seasons = <Season>[];
  List<Tournament> _competitions = <Tournament>[];
  final Map<int, List<StandingRow>> _leagueTables = <int, List<StandingRow>>{};
  final Map<int, List<GroupTable>> _groupTables = <int, List<GroupTable>>{};
  int? _seasonId;
  int? _leagueId;
  int? _competitionId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSeasons();
  }

  Future<void> _loadSeasons() async {
    final CareerProvider game = context.read<CareerProvider>();
    final List<Season> seasons = await game.allSeasons();
    if (!mounted) return;
    if (seasons.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No seasons played yet.';
      });
      return;
    }
    setState(() {
      _seasons = seasons;
      _seasonId = game.season?.seasonId ?? seasons.first.seasonId;
    });
    await _loadSeason(_seasonId!);
  }

  Future<void> _loadSeason(int seasonId) async {
    final CareerProvider game = context.read<CareerProvider>();
    setState(() {
      _loading = true;
      _error = null;
      _leagueTables.clear();
      _groupTables.clear();
    });
    final List<Tournament> comps = (await game.competitionsForSeason(seasonId))
        .where((Tournament tour) => tour.isLeague || tour.isInternational)
        .toList();
    Tournament? league;
    final List<Tournament> selectable = <Tournament>[];
    for (final Tournament tour in comps) {
      if (tour.isLeague) {
        league ??= tour;
        selectable.add(tour);
        _leagueTables[tour.tournamentId] = await game.standingsForSeason(
          seasonId,
          tour.tournamentId,
        );
      } else {
        final List<GroupTable> groups = await game.groupsForSeason(
          seasonId,
          tour.tournamentId,
        );
        if (groups.isEmpty) continue;
        _groupTables[tour.tournamentId] = groups;
        selectable.add(tour);
      }
    }
    if (!mounted) return;
    if (selectable.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No competitions recorded for this season.';
      });
      return;
    }
    setState(() {
      _loading = false;
      _competitions = selectable;
      _leagueId = league?.tournamentId;
      _competitionId = league?.tournamentId ?? selectable.first.tournamentId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Season history'),
        actions: <Widget>[
          if (_seasonId != null)
            IconButton(
              icon: const Icon(Icons.workspace_premium, color: Color(0xFFFFD700)),
              tooltip: 'Awards Gala',
              onPressed: () async {
                final CareerProvider game = context.read<CareerProvider>();
                final SeasonGalaSummary gala = await game.seasonGalaAwards(_seasonId!);
                if (!context.mounted) return;
                showAnnualAwardsGala(context, gala: gala);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: _seasonSelector()),
                      const SizedBox(width: 8),
                      if (_competitions.length > 1)
                        Flexible(child: _competitionSelector()),
                    ],
                  ),
                ),
                Expanded(child: _body()),
              ],
            ),
    );
  }

  Widget _body() {
    if (_competitionId == _leagueId) {
      return _standingsTable(
        _leagueTables[_leagueId] ?? const <StandingRow>[],
        league: _competition(_leagueId),
      );
    }
    final List<GroupTable> groups =
        _groupTables[_competitionId] ?? const <GroupTable>[];
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
            _row(
              groups[i].rows[r],
              r,
              groupStage: true,
              rowCount: groups[i].rows.length,
            ),
        ],
      ],
    );
  }

  Widget _standingsTable(List<StandingRow> rows, {Tournament? league}) {
    if (rows.isEmpty) {
      return const Center(child: Text('No results recorded for this season.'));
    }
    return Column(
      children: <Widget>[
        _header(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) =>
                _row(rows[index], index, league: league, rowCount: rows.length),
          ),
        ),
      ],
    );
  }

  Widget _seasonSelector() => DropdownButtonHideUnderline(
    child: DropdownButton<int>(
      value: _seasonId,
      isExpanded: true,
      dropdownColor: AppTheme.surfaceCard,
      style: const TextStyle(fontSize: 13, color: Colors.white),
      items: <DropdownMenuItem<int>>[
        for (final Season season in _seasons)
          DropdownMenuItem<int>(
            value: season.seasonId,
            child: Text(season.name),
          ),
      ],
      onChanged: (int? id) {
        if (id == null || id == _seasonId) return;
        setState(() => _seasonId = id);
        _loadSeason(id);
      },
    ),
  );

  Widget _competitionSelector() => DropdownButtonHideUnderline(
    child: DropdownButton<int>(
      value: _competitionId,
      isExpanded: true,
      dropdownColor: AppTheme.surfaceCard,
      style: const TextStyle(fontSize: 12, color: Colors.white),
      items: <DropdownMenuItem<int>>[
        for (final Tournament tour in _competitions)
          DropdownMenuItem<int>(
            value: tour.tournamentId,
            child: Text(tour.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (int? id) {
        if (id == null) return;
        setState(() => _competitionId = id);
      },
    ),
  );

  Tournament? _competition(int? id) {
    for (final Tournament tour in _competitions) {
      if (tour.tournamentId == id) return tour;
    }
    return null;
  }

  // ------------------------------------------------------------- table rows

  static const double _rankWidth = 30;
  static const double _statWidth = 26;
  static const double _gdWidth = 34;
  static const double _ptsWidth = 38;

  static const TextStyle _headStyle = TextStyle(
    fontSize: 11,
    color: AppTheme.textDim,
    fontWeight: FontWeight.bold,
  );

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
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
    StandingRow row,
    int index, {
    bool groupStage = false,
    Tournament? league,
    int rowCount = 0,
  }) {
    final CareerProvider game = context.read<CareerProvider>();
    final bool isUser = row.teamId == game.userTeamId;
    final bool promotion = groupStage
        ? index < 2
        : league != null && index < league.promotionSlots;
    final bool relegation =
        !groupStage &&
        league != null &&
        league.relegationSpots > 0 &&
        index >= rowCount - league.relegationSpots;
    return InkWell(
      onTap: () => showTeamDetail(context, row.teamId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
                  width: 3,
                  height: 14,
                  color: promotion
                      ? AppTheme.accent
                      : relegation
                      ? AppTheme.danger
                      : Colors.transparent,
                ),
                const SizedBox(width: 4),
                Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
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
          ),
          _cell('${row.played}'),
          _cell('${row.wins}'),
          _cell('${row.draws}'),
          _cell('${row.losses}'),
          _cell('${row.goalDifference}', width: _gdWidth),
          _cell('${row.points}', width: _ptsWidth, bold: true),
        ],
      ),
    ),
  );
}
}
