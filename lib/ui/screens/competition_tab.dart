import 'package:flutter/material.dart';

import '../theme.dart';
import 'fixtures_tab.dart';
import 'international_tab.dart';
import 'standings_tab.dart';

/// Combined competition screen integrating league standings/leaderboards,
/// matchday fixtures, and international football into a single cohesive tab.
class CompetitionTab extends StatefulWidget {
  const CompetitionTab({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<CompetitionTab> createState() => _CompetitionTabState();
}

class _CompetitionTabState extends State<CompetitionTab> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialIndex.clamp(0, 2),
      child: Column(
        children: <Widget>[
          Material(
            color: AppTheme.surfaceCard,
            elevation: 1,
            child: TabBar(
              dividerColor: Colors.transparent,
              labelColor: AppTheme.accent,
              unselectedLabelColor: AppTheme.textDim,
              indicatorColor: AppTheme.accent,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const <Widget>[
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.leaderboard_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Klasemen'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.calendar_month_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Jadwal'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.public_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Timnas'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: <Widget>[
                StandingsTab(),
                FixturesTab(),
                InternationalTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
