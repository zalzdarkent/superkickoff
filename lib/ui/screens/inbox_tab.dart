import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';

/// Club inbox: news about results, transfers, injuries and season events.
class InboxTab extends StatelessWidget {
  const InboxTab({super.key});

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<Message> messages = game.inbox;
    if (messages.isEmpty) {
      return const Center(child: Text('Your inbox is empty.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (BuildContext context, int index) {
        final Message m = messages[index];
        return Card(
          child: ListTile(
            leading: Icon(
              m.isRead ? Icons.mail_outline : Icons.mark_email_unread,
              color: m.isRead ? AppTheme.textDim : AppTheme.accent,
            ),
            title: Text(
              m.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: m.isRead ? FontWeight.w400 : FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${m.sender ?? ''} · ${shortDate(m.date)}\n${m.body}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (BuildContext dialogContext) => AlertDialog(
                  title: Text(m.title),
                  content: SingleChildScrollView(
                    child: Text(
                      '${m.body}\n\n— ${m.sender ?? ''}\n${shortDate(m.date)}',
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
              game.markMessageRead(m);
            },
          ),
        );
      },
    );
  }
}
