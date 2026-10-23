import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/db/schema.dart' as t;
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opens the compact player profile (tabs instead of a long page).
Future<void> showPlayerDetail(BuildContext context, int playerId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: PlayerDetailSheet(playerId: playerId),
    ),
  );
}

Future<void> showProspectDetail(
  BuildContext context, {
  required String name,
  required int age,
  required int positionId,
  required int power,
  required int potential,
  required int value,
  required int countryId,
  required String profile,
  int? height,
  String? source,
  int? signingFee,
}) {
  final CareerProvider game = context.read<CareerProvider>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.68,
      child: _ProspectDetailSheet(
        countryName: game.countryName(countryId),
        name: name,
        age: age,
        positionId: positionId,
        power: power,
        potential: potential,
        value: value,
        countryId: countryId,
        profile: profile,
        height: height,
        source: source,
        signingFee: signingFee,
      ),
    ),
  );
}

class PlayerDetailSheet extends StatefulWidget {
  const PlayerDetailSheet({super.key, required this.playerId});

  final int playerId;

  @override
  State<PlayerDetailSheet> createState() => _PlayerDetailSheetState();
}

class _ProspectDetailSheet extends StatelessWidget {
  const _ProspectDetailSheet({
    required this.name,
    required this.age,
    required this.positionId,
    required this.power,
    required this.potential,
    required this.value,
    required this.countryId,
    required this.countryName,
    required this.profile,
    this.height,
    this.source,
    this.signingFee,
  });

  final String name;
  final int age;
  final int positionId;
  final int power;
  final int potential;
  final int value;
  final int countryId;
  final Future<String> countryName;
  final String profile;
  final int? height;
  final String? source;
  final int? signingFee;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.accentDim,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: PositionBadge(positionId: positionId, profile: profile),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<String>(
                      future: countryName,
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<String> snapshot,
                          ) {
                            final String label = snapshot.data ?? 'Loading...';
                            return Text(
                              'Age $age · $label',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textDim,
                              ),
                            );
                          },
                    ),
                  ],
                ),
              ),
              Column(
                children: <Widget>[
                  Text(
                    '$power',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.accent,
                    ),
                  ),
                  const Text(
                    'OVR',
                    style: TextStyle(fontSize: 9, color: AppTheme.textDim),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (source != null) _detailRow('Source', source!),
          _detailRow(
            'Position',
            PositionBadge.labelFor(positionId, profile: profile),
          ),
          _detailRow('Potential', '$potential+'),
          _detailRow('Preferred foot', profile == 'I' ? 'Left' : 'Right'),
          if (height != null) _detailRow('Height', '$height cm'),
          if (value > 0) _detailRow('Market value', money(value)),
          if (signingFee != null) _detailRow('Signing fee', money(signingFee!)),
          const Spacer(),
          const Text(
            'This is a scouting profile. Full contract and match statistics become available after the player joins the squad.',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _PlayerDetailSheetState extends State<PlayerDetailSheet>
    with SingleTickerProviderStateMixin {
  late Future<PlayerDetail?> _future;
  late final TabController _tabs;
  bool _renewing = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().playerDetail(widget.playerId);
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = context.read<CareerProvider>().playerDetail(widget.playerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: FutureBuilder<PlayerDetail?>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<PlayerDetail?> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final PlayerDetail? detail = snap.data;
          if (detail == null) {
            return const Center(child: Text('Player not found.'));
          }
          return _content(context, detail);
        },
      ),
    );
  }

  Widget _content(BuildContext context, PlayerDetail detail) {
    final Player p = detail.player;
    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade700,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.accentDim,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.45),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  PositionBadge.labelFor(p.positionId, profile: p.profile),
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (p.isCaptain) ...<Widget>[
                          const SizedBox(width: 6),
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${detail.clubName.isEmpty ? 'Free agent' : detail.clubName}'
                      '${detail.countryName.isEmpty ? '' : ' \u00b7 ${detail.countryName}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Stars(value: p.stars, size: 12),
                    if (detail.suspensionMatches > 0) ...<Widget>[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: AppTheme.danger.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          'SUSPENDED \u00b7 ${detail.suspensionMatches} '
                          'match${detail.suspensionMatches == 1 ? '' : 'es'}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.danger,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: <Widget>[
                  Text(
                    '${p.power}',
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.accent,
                    ),
                  ),
                  const Text(
                    'OVR',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      color: AppTheme.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textDim,
          indicatorColor: AppTheme.accent,
          dividerColor: Colors.white10,
          tabs: <Widget>[
            Tab(text: 'Profile'),
            Tab(text: 'Contract'),
            Tab(text: 'Stats'),
            Tab(text: 'History'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: <Widget>[
              _profileTab(detail),
              _contractTab(detail),
              _statsTab(detail.stats),
              _historyTab(detail),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileTab(PlayerDetail detail) {
    final Player p = detail.player;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _meter('Power', p.power, AppTheme.accent)),
              const SizedBox(width: 12),
              Expanded(child: _meter('Potential', p.potential, AppTheme.warn)),
              const SizedBox(width: 12),
              Expanded(
                child: _meter(
                  'Fitness',
                  p.fitness,
                  p.fitness > 70 ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double width = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _info('Age', '${p.age}', width),
                  _info('Height', '${p.height} cm', width),
                  _info(
                    'Preferred foot',
                    p.profile.toUpperCase() == 'I' ? 'Left' : 'Right',
                    width,
                  ),
                  _info(
                    'Position',
                    PositionBadge.labelFor(p.positionId, profile: p.profile),
                    width,
                  ),
                  _info('Value', money(p.value), width),
                  _info('Salary', money(p.salary), width),
                  _info(
                    'Squad role',
                    p.squadStatus == t.squadFirstTeam
                        ? 'Pemain Inti (First team)'
                        : p.squadStatus == t.squadLoanListed
                        ? 'Daftar Pinjaman (Loan listed)'
                        : 'Cadangan (Reserve)',
                    width,
                  ),
                  _info(
                    'Market',
                    p.marketStatus == t.marketForSale
                        ? 'For sale'
                        : p.marketStatus == t.marketOnLoan
                        ? 'On loan'
                        : 'Not listed',
                    width,
                  ),
                  if (detail.suspensionMatches > 0)
                    _info(
                      'Suspension',
                      '${detail.suspensionMatches} matches',
                      width,
                    ),
                ],
              );
            },
          ),
          if ((p.championships ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            const Text(
              'Honours',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              p.championships!,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contractTab(PlayerDetail detail) {
    final ContractInfo? c = detail.contract;
    final CareerProvider game = context.read<CareerProvider>();
    final bool isMine =
        detail.clubId != null && detail.clubId == game.userTeamId;
    if (c == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No active contract. This player is a free agent.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textDim),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'CONTRACT UNTIL',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppTheme.textDim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shortDate(c.endDate),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    const Text(
                      'SALARY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: AppTheme.textDim,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      money(c.salary),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Bonuses',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          _bonus('Goal bonus', c.goalBonus),
          _bonus('Assist bonus', c.assistBonus),
          _bonus('MVP bonus', c.mvpBonus),
          _bonus('Title bonus', c.titleBonus),
          _bonus('Appearance bonus', c.appearanceBonus),
          const SizedBox(height: 14),
          Text(
            'Started ${shortDate(c.startDate)}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
          if (isMine) ...<Widget>[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _renewing ? null : () => _renew(detail),
                icon: _renewing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.description_outlined, size: 18),
                label: const Text('Renew contract'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Adds two seasons with a 15% raise. The signing bonus is '
              'two salaries and is paid from your club budget.',
              style: TextStyle(fontSize: 10, color: AppTheme.textDim),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _renew(PlayerDetail detail) async {
    final ContractInfo? c = detail.contract;
    if (c == null || _renewing) return;
    final int newSalary = (c.salary * 1.15).round();
    final int signingBonus = newSalary * 2;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Renew ${detail.player.name}?'),
        content: Text(
          'Contract extension: 2 seasons\n\n'
          'Salary: ${money(c.salary)} \u2192 ${money(newSalary)}\n'
          'Signing bonus: ${money(signingBonus)}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Renew'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _renewing = true);
    final String? error = await context.read<CareerProvider>().renewContract(
      detail.player.playerId,
    );
    if (!mounted) return;
    setState(() => _renewing = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.danger),
      );
      return;
    }
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${detail.player.name} signed a new contract.')),
    );
  }

  Widget _statsTab(PlayerSeasonSummary s) {
    if (s.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No match statistics yet this season.',
            style: TextStyle(color: AppTheme.textDim),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Current season \u00b7 all competitions',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double width = (c.maxWidth - 20) / 3;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _stat('Apps', '${s.matches}', width),
                  _stat('Minutes', '${s.minutes}', width),
                  _stat(
                    'Rating',
                    s.rating <= 0 ? '-' : s.rating.toStringAsFixed(2),
                    width,
                  ),
                  _stat('Goals', '${s.goals}', width),
                  _stat('Assists', '${s.assists}', width),
                  _stat('MVP', '${s.mvps}', width),
                  _stat('Yellow', '${s.yellowCards}', width),
                  _stat('Red', '${s.redCards}', width),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _historyTab(PlayerDetail detail) {
    final List<TransferRecord> transfers = detail.transfers;
    if (transfers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No transfer records for this player.',
            style: TextStyle(color: AppTheme.textDim),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: transfers.length,
      separatorBuilder: (_, _) => const Divider(height: 14),
      itemBuilder: (BuildContext context, int i) {
        final TransferRecord r = transfers[i];
        return Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.swap_horiz, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${r.fromTeamName} \u2192 ${r.toTeamName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shortDate(r.date),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              r.value <= 0 ? 'Free' : money(r.value),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _meter(String label, int value, Color color) {
    final int clamped = value.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
            ),
            Text(
              '$value',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 6,
            backgroundColor: Colors.grey.shade800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _info(String label, String value, double width) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 0.6,
                color: AppTheme.textDim,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, double width) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bonus(String label, int? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ),
          Text(
            value == null || value <= 0 ? '\u2014' : money(value),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
