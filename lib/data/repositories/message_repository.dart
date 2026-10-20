import 'package:sqflite/sqflite.dart';

import '../db/schema.dart' as t;
import '../models/models.dart';

/// Inbox/notification messages (news about results, injuries, market moves...).
class MessageRepository {
  MessageRepository(this.db);

  final Database db;

  Future<void> insert({
    required String title,
    required String body,
    String? sender,
    int type = 0,
    String? date,
    int? playerId,
    int? teamId,
  }) {
    return db.insert(t.messages, <String, Object?>{
      'title': title,
      'body': body,
      'date': date ?? _todayIso(),
      'sender': sender ?? 'Club',
      'is_read': 0,
      'type': type,
      'player_id': playerId,
      'team_id': teamId,
    });
  }

  Future<List<Message>> latest({int teamId = 0, int limit = 30}) async {
    final rows = await db.query(
      t.messages,
      where: teamId > 0 ? 'team_id = ? OR team_id IS NULL' : null,
      whereArgs: teamId > 0 ? <Object?>[teamId] : null,
      orderBy: 'message_id DESC',
      limit: limit,
    );
    return rows.map(Message.fromMap).toList();
  }

  Future<void> markRead(int messageId) => db.update(
        t.messages,
        <String, Object?>{'is_read': 1},
        where: 'message_id = ?',
        whereArgs: <Object?>[messageId],
      );

  Future<int> unreadCount() async {
    final int? c = Sqflite.firstIntValue(await db.query(
      t.messages,
      columns: ['COUNT(*)'],
      where: 'is_read = 0',
    ));
    return c ?? 0;
  }

  static String _todayIso() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
