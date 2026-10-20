import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';

/// League table computed live from played matches.
class StandingsTab extends StatelessWidget {
  const StandingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<StandingRow> rows = game.standings;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  game.league?.name ?? 'League',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (game.cup != null)
                Text(
                  game.cup!.name,
                  style: const TextStyle(fontSize: 11, color: AppTheme.warn),
                ),
            ],
          ),
        ),
        _header(),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No results yet — play a match to build the table.'),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _row(game, rows[index], index),
                ),
        ),
      ],
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: AppTheme.surfaceCard,
        child: const Row(
          children: <Widget>[
            SizedBox(width: 24, child: Text('#', style: _headStyle)),
            Expanded(child: Text('Club', style: _headStyle)),
            SizedBox(
                width: 26,
                child: Text('P', textAlign: TextAlign.center, style: _headStyle)),
            SizedBox(
                width: 26,
                child: Text('W', textAlign: TextAlign.center, style: _headStyle)),
            SizedBox(
                width: 26,
                child: Text('D', textAlign: TextAlign.center, style: _headStyle)),
            SizedBox(
                width: 26,
                child: Text('L', textAlign: TextAlign.center, style: _headStyle)),
            SizedBox(
                width: 34,
                child: Text('GD', textAlign: TextAlign.center, style: _headStyle)),
            SizedBox(
                width: 34,
                child: Text('Pts', textAlign: TextAlign.center, style: _headStyle)),
          ],
        ),
      );

  static const TextStyle _headStyle =
      TextStyle(fontSize: 10, color: AppTheme.textDim, fontWeight: FontWeight.bold);

  Widget _row(CareerProvider game, StandingRow row, int index) {
    final bool isUser = row.teamId == game.userTeamId;
    final bool promotion = game.league != null &&
        index < game.league!.promotionSlots;
    final bool relegation = game.league != null &&
        game.league!.relegationSpots > 0 &&
        index >= game.standings.length - game.league!.relegationSpots;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isUser ? AppTheme.accentDim.withAlpha(60) : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade900, width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
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
                Text('${index + 1}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textDim)),
              ],
            ),
          ),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isUser ? FontWeight.bold : FontWeight.w400,
                color: isUser ? AppTheme.accent : Colors.white,
              ),
            ),
          ),
          _cell('${row.played}'),
          _cell('${row.wins}'),
          _cell('${row.draws}'),
          _cell('${row.losses}'),
          _cell('${row.goalDifference}'),
          _cell('${row.points}', bold: true),
        ],
      ),
    );
  }

  Widget _cell(String value, {bool bold = false}) => SizedBox(
        width: value.length > 2 ? 34 : 26,
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.bold : FontWeight.w400,
          ),
        ),
      );
}
