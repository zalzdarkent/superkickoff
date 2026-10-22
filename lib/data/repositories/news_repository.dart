import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Stories written by the news engine. Each story has a unique `ref`, so
/// regenerating a matchday never duplicates it.
class NewsRepository {
  NewsRepository(this.db);

  final Database db;

  Future<void> insertAll(List<NewsItem> items) async {
    final Batch batch = db.batch();
    for (final NewsItem n in items) {
      batch.insert(t.news, <String, Object?>{
        'ref': n.ref,
        'season_id': n.seasonId,
        'date': n.date,
        'scope': n.scope,
        'category': n.category,
        'headline': n.headline,
        'body': n.body,
        'importance': n.importance,
        'team_id': n.teamId,
        'player_id': n.playerId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<bool> hasRef(String ref) async =>
      (Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM ${t.news} WHERE ref = ?',
              <Object?>[ref],
            ),
          ) ??
          0) >
      0;

  /// Newest first; bigger stories first within a day. Region and world also
  /// pick up the biggest stories of the narrower feeds below them.
  Future<List<NewsItem>> feed(String scope, {int limit = 80}) async {
    final String where = switch (scope) {
      'world' => "scope = 'world' OR importance >= 5",
      'region' => "scope = 'region' OR (scope = 'league' AND importance >= 3)",
      _ => "scope = 'league'",
    };
    final List<Map<String, Object?>> rows = await db.query(
      t.news,
      where: "($where) AND category != 'meta'",
      orderBy: 'date DESC, importance DESC, news_id DESC',
      limit: limit,
    );
    return rows.map(NewsItem.fromMap).toList();
  }
}
