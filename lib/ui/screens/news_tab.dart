import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';

/// News menu: world, the user's region and the user's league.
class NewsTab extends StatefulWidget {
  const NewsTab({super.key});

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  static const List<(String, String)> _scopes = <(String, String)>[
    ('world', 'Dunia'),
    ('region', 'Region'),
    ('league', 'Liga'),
  ];

  final Map<String, Future<List<NewsItem>>> _feeds =
      <String, Future<List<NewsItem>>>{};
  int _loadedWeek = -1;
  int? _loadedSeason;

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    if (_loadedWeek != game.week || _loadedSeason != game.season?.seasonId) {
      _loadedWeek = game.week;
      _loadedSeason = game.season?.seasonId;
      _feeds.clear();
    }
    return DefaultTabController(
      length: _scopes.length,
      child: Column(
        children: <Widget>[
          TabBar(
            dividerColor: Colors.transparent,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textDim,
            indicatorColor: AppTheme.accent,
            tabs: <Widget>[for (final (String, String) s in _scopes) Tab(text: s.$2)],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final (String, String) s in _scopes)
                  _feed(game, s.$1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feed(CareerProvider game, String scope) {
    final Future<List<NewsItem>> future = _feeds.putIfAbsent(
      scope,
      () => game.newsFeed(scope),
    );
    return FutureBuilder<List<NewsItem>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<NewsItem>> snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<NewsItem> items = snap.data!;
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Belum ada berita. Mainkan satu pekan pertandingan dan headline akan berdatangan.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int i) =>
              _StoryCard(item: items[i], game: game, lead: i == 0),
        );
      },
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.item, required this.game, required this.lead});

  final NewsItem item;
  final CareerProvider game;
  final bool lead;

  static (IconData, Color, String) _style(String category) =>
      switch (category) {
        'trophy' => (Icons.emoji_events, const Color(0xFFF59E0B), 'TROFI'),
        'upset' => (Icons.bolt, const Color(0xFFEF4444), 'KEJUTAN'),
        'rout' => (Icons.local_fire_department, const Color(0xFFEF4444), 'PESTA GOL'),
        'thriller' => (Icons.sports_soccer, const Color(0xFF3B82F6), 'LAGA SERU'),
        'player' => (Icons.person, AppTheme.accent, 'PEMAIN'),
        'form' => (Icons.trending_up, const Color(0xFF22D3EE), 'PERFORMA'),
        'table' => (Icons.leaderboard, const Color(0xFFA78BFA), 'KLASEMEN'),
        'transfer' => (Icons.swap_horiz, const Color(0xFFF472B6), 'TRANSFER'),
        'preview' => (Icons.visibility, AppTheme.textDim, 'PRATINJAU'),
        _ => (Icons.article_outlined, AppTheme.textDim, 'BERITA'),
      };

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = _style(item.category);
    final bool top = item.importance >= 5 || lead && item.importance >= 4;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: top ? color.withValues(alpha: 0.6) : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 5),
                  Text(
                    top ? 'BERITA UTAMA · $label' : label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    shortDate(item.date),
                    style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.headline,
                style: TextStyle(
                  fontSize: top ? 17 : 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.body,
                maxLines: top ? 5 : 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppTheme.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                shortDate(item.date),
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
              const SizedBox(height: 8),
              Text(
                item.headline,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(item.body, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}
