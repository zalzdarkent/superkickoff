import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/db/schema.dart' as t;
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';

/// Full-screen wrapper so the inbox can open from the app bar.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inbox')),
    body: const InboxTab(),
  );
}

/// Club inbox: offers, contracts, injuries and season events.
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
        final Message message = messages[index];
        return Card(
          child: ListTile(
            leading: Icon(
              message.isRead ? Icons.mail_outline : Icons.mark_email_unread,
              color: message.isRead ? AppTheme.textDim : AppTheme.accent,
            ),
            title: Text(
              message.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: message.isRead ? FontWeight.w400 : FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${message.sender ?? ''} · ${shortDate(message.date)}\n${message.body}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _openMessage(context, game, message),
          ),
        );
      },
    );
  }

  Future<void> _openMessage(
    BuildContext context,
    CareerProvider game,
    Message message,
  ) async {
    game.markMessageRead(message);
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final int? offerId = message.transferOfferId;
        if (offerId == null) {
          final List<Widget> actions = <Widget>[];
          if (message.title.startsWith('Youth Academy Intake')) {
            actions.add(
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showAcademyIntakeSheet(context, game);
                },
                child: const Text('Review Prospects'),
              ),
            );
          }
          if (message.playerId != null &&
              message.title.startsWith('Wage Increase Request')) {
            actions.add(
              FilledButton(
                onPressed: () async {
                  final String? err = await game.renewContract(
                    message.playerId!,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          err ?? 'Contract extended with wage increase!',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Grant Wage Increase'),
              ),
            );
          }
          return _messageDialog(dialogContext, message, actions);
        }
        return FutureBuilder<TransferOffer?>(
          future: game.transferOffer(offerId),
          builder: (BuildContext _, AsyncSnapshot<TransferOffer?> snapshot) {
            if (!snapshot.hasData) {
              return const AlertDialog(
                content: SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final TransferOffer offer = snapshot.data!;
            return _messageDialog(
              dialogContext,
              message,
              _offerActions(dialogContext, context, game, offer),
            );
          },
        );
      },
    );
  }

  AlertDialog _messageDialog(
    BuildContext dialogContext,
    Message message,
    List<Widget> offerActions,
  ) {
    return AlertDialog(
      title: Text(message.title),
      content: SingleChildScrollView(
        child: Text(
          '${message.body}\n\n— ${message.sender ?? ''}\n${shortDate(message.date)}',
        ),
      ),
      actions: <Widget>[
        ...offerActions,
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<Widget> _offerActions(
    BuildContext dialogContext,
    BuildContext pageContext,
    CareerProvider game,
    TransferOffer offer,
  ) {
    if (offer.fromTeamId == game.userTeamId && offer.status == t.offerPending) {
      if (offer.isLoan) {
        return <Widget>[
          TextButton(
            onPressed: () async {
              await game.rejectSaleOffer(offer.offerId);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Reject Loan'),
          ),
          FilledButton(
            onPressed: () async {
              final String? error = await game.acceptLoanOffer(offer.offerId);
              if (!pageContext.mounted) return;
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(pageContext).showSnackBar(
                SnackBar(
                  content: Text(
                    error ??
                        '${offer.playerName} loaned to ${offer.toTeamName}.',
                  ),
                ),
              );
            },
            child: Text(
              'Accept Loan · ${offer.loanSeasons}y (${money(offer.offerAmount)})',
            ),
          ),
        ];
      }
      return <Widget>[
        TextButton(
          onPressed: () async {
            await game.rejectSaleOffer(offer.offerId);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          child: const Text('Reject'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            _showSaleCounterDialog(pageContext, game, offer);
          },
          child: const Text('Counter'),
        ),
        FilledButton(
          onPressed: () async {
            final String? error = await game.acceptSaleOffer(offer.offerId);
            if (!pageContext.mounted) return;
            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(pageContext).showSnackBar(
              SnackBar(content: Text(error ?? '${offer.playerName} sold.')),
            );
          },
          child: Text('Accept ${money(offer.offerAmount)}'),
        ),
      ];
    }
    if (offer.status == t.offerAccepted) {
      return <Widget>[
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            _showContractDialog(pageContext, game, offer);
          },
          child: const Text('Negotiate Contract'),
        ),
      ];
    }
    if (offer.status == t.offerCountered) {
      return <Widget>[
        FilledButton(
          onPressed: () async {
            final String? error = await game.acceptCounterOffer(offer.offerId);
            if (!pageContext.mounted) return;
            Navigator.of(dialogContext).pop();
            if (error != null) {
              ScaffoldMessenger.of(pageContext)
                  .showSnackBar(SnackBar(content: Text(error)));
              return;
            }
            final TransferOffer? accepted = await game.transferOffer(
              offer.offerId,
            );
            if (accepted != null && pageContext.mounted) {
              await _showContractDialog(pageContext, game, accepted);
            }
          },
          child: Text('Accept ${money(offer.counterAmount ?? 0)}'),
        ),
      ];
    }
    return const <Widget>[];
  }

  Future<void> _showSaleCounterDialog(
    BuildContext context,
    CareerProvider game,
    TransferOffer offer,
  ) async {
    final TextEditingController fee = TextEditingController(
      text: offer.offerAmount.toString(),
    );
    final int? amount = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Counter ${offer.toTeamName}'),
        content: TextField(
          controller: fee,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Transfer fee',
            prefixText: '\$',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(int.tryParse(fee.text.trim())),
            child: const Text('Send Counter'),
          ),
        ],
      ),
    );
    fee.dispose();
    if (amount == null || amount <= 0) return;
    final String? error = await game.counterSaleOffer(offer.offerId, amount);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Counter offer sent. Check Inbox.')),
      );
    }
  }

  Future<void> _showContractDialog(
    BuildContext context,
    CareerProvider game,
    TransferOffer offer,
  ) async {
    final TextEditingController salary = TextEditingController(
      text: ((offer.playerSalary * 1.15).round()).toString(),
    );
    final TextEditingController duration = TextEditingController(text: '3');
    final (int salary, int duration)? terms = await showDialog<(int, int)>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Contract: ${offer.playerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Current salary: ${money(offer.playerSalary)}/season'),
            const SizedBox(height: 12),
            TextField(
              controller: salary,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Salary per season',
                prefixText: '\$',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Contract years'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop((
              int.tryParse(salary.text.trim()) ?? 0,
              int.tryParse(duration.text.trim()) ?? 0,
            )),
            child: const Text('Propose Contract'),
          ),
        ],
      ),
    );
    salary.dispose();
    duration.dispose();
    if (terms == null || terms.$1 <= 0 || terms.$2 <= 0) return;
    final String? error = await game.proposeContract(
      offerId: offer.offerId,
      salary: terms.$1,
      durationYears: terms.$2,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Contract proposal sent. Check Inbox.'),
        ),
      );
    }
  }

  void _showAcademyIntakeSheet(BuildContext context, CareerProvider game) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext _, void Function(void Function()) setSheetState) {
            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade700,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Youth Academy Intake',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Review and choose which prospects to sign to your squad.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: FutureBuilder<List<YouthProspect>>(
                      future: game.pendingProspects(),
                      builder:
                          (
                            BuildContext _,
                            AsyncSnapshot<List<YouthProspect>> snap,
                          ) {
                            if (!snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final List<YouthProspect> list = snap.data!;
                            if (list.isEmpty) {
                              return const Center(
                                child: Text(
                                  'All prospects have been reviewed or signed.',
                                  style: TextStyle(color: AppTheme.textDim),
                                ),
                              );
                            }
                            return ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (BuildContext _, int i) {
                                final YouthProspect p = list[i];
                                return Card(
                                  child: ListTile(
                                    onTap: () => showProspectDetail(
                                      context,
                                      name: p.name,
                                      age: p.age,
                                      positionId: p.positionId,
                                      power: p.power,
                                      potential: p.potential,
                                      value: 0,
                                      countryId: p.countryId,
                                      profile: p.profile,
                                      height: p.height,
                                      source: 'Youth Academy',
                                    ),
                                    leading: PositionBadge(
                                      positionId: p.positionId,
                                      profile: p.profile,
                                    ),
                                    title: Text(
                                      '${p.name}  ${p.power}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '17y · POT ${p.potential} · Foot ${p.profile == 'I' ? 'L' : 'R'}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: FilledButton(
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                      ),
                                      onPressed: () async {
                                        final Player? signed = await game
                                            .signYouthProspect(p.prospectId);
                                        if (signed != null && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${signed.name} joined your squad!',
                                              ),
                                            ),
                                          );
                                          setSheetState(() {});
                                        }
                                      },
                                      child: const Text('Sign'),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
