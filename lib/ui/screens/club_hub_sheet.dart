import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opens the club hub: overview, finances and stadium in three tabs.
Future<void> showClubHub(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) =>
        const FractionallySizedBox(heightFactor: 0.9, child: ClubHubSheet()),
  );
}

class ClubHubSheet extends StatefulWidget {
  const ClubHubSheet({super.key});

  @override
  State<ClubHubSheet> createState() => _ClubHubSheetState();
}

class _ClubHubSheetState extends State<ClubHubSheet> {
  late Future<ClubOverview?> _future;
  late Future<List<ClubTrophy>> _trophies;
  late Future<YouthAcademyState> _academy;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().clubOverview();
    _trophies = context.read<CareerProvider>().clubTrophies();
    _academy = context.read<CareerProvider>().youthAcademyState();
  }

  void _reload() {
    setState(() {
      _future = context.read<CareerProvider>().clubOverview();
      _trophies = context.read<CareerProvider>().clubTrophies();
      _academy = context.read<CareerProvider>().youthAcademyState();
    });
  }

  Future<void> _expand() async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? error = await context.read<CareerProvider>().expandStadium();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.danger),
      );
      return;
    }
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stadium expanded successfully.')),
    );
  }

  Future<void> _upgradeAcademy() async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? error = await context.read<CareerProvider>().upgradeYouthAcademy();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.danger),
      );
      return;
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: FutureBuilder<ClubOverview?>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<ClubOverview?> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final ClubOverview? club = snap.data;
          if (club == null) {
            return const Center(child: Text('Club not found.'));
          }
          return _content(club);
        },
      ),
    );
  }

  Widget _content(ClubOverview club) {
    return DefaultTabController(
      length: 5,
      child: Column(
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
                CrestAvatar(team: club.team, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        club.team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${club.countryName} \u00b7 Division ${club.team.division}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: <Widget>[
                    Text(
                      '${club.team.power}',
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accent,
                      ),
                    ),
                    const Text(
                      'POWER',
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
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textDim,
            indicatorColor: AppTheme.accent,
            dividerColor: Colors.white10,
            tabs: <Widget>[
              Tab(text: 'Overview'),
              Tab(text: 'Finances'),
              Tab(text: 'Stadium'),
              Tab(text: 'Academy'),
              Tab(text: 'Honours'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _overviewTab(club),
                _financesTab(club),
                _stadiumTab(club),
                _academyTab(),
                _honoursTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewTab(ClubOverview club) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double width = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _info('Country', club.countryName, width),
                  _info('Founded', '${club.team.foundedYear}', width),
                  _info('Division', '${club.team.division}', width),
                  _info('Stadium', club.stadiumName, width),
                  _info('City', club.stadiumCity, width),
                  _info('Capacity', _number(club.capacity), width),
                  _info('Coach', club.coachName, width),
                  _info(
                    'Coach age',
                    club.coachAge <= 0 ? '\u2014' : '${club.coachAge}',
                    width,
                  ),
                  _info(
                    'Coach country',
                    club.coachCountry.isEmpty ? '\u2014' : club.coachCountry,
                    width,
                  ),
                  _info('Coach points', '${club.coachPoints}', width),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.stadium, color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${club.stadiumName} \u00b7 ${_number(club.capacity)} seats',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _academyTab() {
    return FutureBuilder<YouthAcademyState>(
      future: _academy,
      builder: (BuildContext context, AsyncSnapshot<YouthAcademyState> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final YouthAcademyState academy = snap.data!;
        final int minOverall = 42 + academy.level * 2;
        final int maxOverall = minOverall + 3;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.school, size: 38, color: AppTheme.accent),
              const SizedBox(height: 12),
              Text(
                'Youth Academy · Level ${academy.level}/10',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '5–9 prospects scouted every 3 in-game months. You choose who joins the squad.',
                style: TextStyle(fontSize: 12, color: AppTheme.textDim),
              ),
              const SizedBox(height: 16),
              Text(
                'Expected prospect OVR: $minOverall–$maxOverall',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Higher academy levels yield higher overall and potential.',
                style: TextStyle(fontSize: 12, color: AppTheme.textDim),
              ),
              const SizedBox(height: 20),
              FutureBuilder<List<YouthProspect>>(
                future: context.read<CareerProvider>().pendingProspects(),
                builder: (BuildContext context, AsyncSnapshot<List<YouthProspect>> snap) {
                  final List<YouthProspect> pending = snap.data ?? <YouthProspect>[];
                  if (pending.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.hourglass_empty, size: 16, color: AppTheme.textDim),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No pending intake prospects. Next batch arrives in ~3 months.',
                              style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.stars, color: AppTheme.accent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${pending.length} prospects awaiting review!',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _showAcademyProspectsSheet(context),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Review'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || academy.isMaxLevel ? null : _upgradeAcademy,
                  icon: const Icon(Icons.upgrade),
                  label: Text(academy.isMaxLevel
                      ? 'Academy Maxed'
                      : 'Upgrade to Level ${academy.level + 1} · ${money(academy.upgradeCost)}'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAcademyProspectsSheet(BuildContext context) {
    final CareerProvider game = context.read<CareerProvider>();
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
                    'Youth Academy Prospects',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Promote the prospects you want into your squad.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: FutureBuilder<List<YouthProspect>>(
                      future: game.pendingProspects(),
                      builder: (BuildContext _, AsyncSnapshot<List<YouthProspect>> snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final List<YouthProspect> list = snap.data!;
                        if (list.isEmpty) {
                          return const Center(
                            child: Text(
                              'All prospects have been signed or reviewed.',
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
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                  onPressed: () async {
                                    final Player? signed =
                                        await game.signYouthProspect(p.prospectId);
                                    if (signed != null && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${signed.name} joined your squad!'),
                                        ),
                                      );
                                      setSheetState(() {});
                                      setState(() {});
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

  Widget _honoursTab() {
    return FutureBuilder<List<ClubTrophy>>(
      future: _trophies,
      builder:
          (BuildContext context, AsyncSnapshot<List<ClubTrophy>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<ClubTrophy> trophies =
                snapshot.data ?? const <ClubTrophy>[];
            if (trophies.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No trophies yet. Win a league, domestic cup or '
                    'continental competition to fill this cabinet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textDim),
                  ),
                ),
              );
            }
            final Map<String, List<ClubTrophy>> grouped =
                <String, List<ClubTrophy>>{};
            for (final ClubTrophy trophy in trophies) {
              grouped
                  .putIfAbsent(trophy.tournamentName, () => <ClubTrophy>[])
                  .add(trophy);
            }
            final List<MapEntry<String, List<ClubTrophy>>> entries =
                grouped.entries.toList()..sort(
                  (
                    MapEntry<String, List<ClubTrophy>> a,
                    MapEntry<String, List<ClubTrophy>> b,
                  ) => b.value.length.compareTo(a.value.length),
                );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                      const Icon(
                        Icons.emoji_events,
                        color: AppTheme.warn,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${trophies.length}',
                            style: const TextStyle(
                              fontSize: 26,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.warn,
                            ),
                          ),
                          const Text(
                            'TROPHIES',
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
                const SizedBox(height: 10),
                for (final MapEntry<String, List<ClubTrophy>> entry in entries)
                  _trophyRow(entry.key, entry.value),
              ],
            );
          },
    );
  }

  Widget _trophyRow(String name, List<ClubTrophy> won) {
    final List<int> years = won.map((ClubTrophy t) => t.year).toSet().toList()
      ..sort((int a, int b) => b.compareTo(a));
    final IconData icon = won.first.isInternational
        ? Icons.public
        : won.first.isLeague
        ? Icons.emoji_events
        : Icons.military_tech;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppTheme.warn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  years.join(', '),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          Text(
            'x${won.length}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financesTab(ClubOverview club) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'AVAILABLE BUDGET',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: AppTheme.textDim,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(club.team.budget),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _moneyRow('Squad value', club.squadValue),
          _moneyRow('Wage bill', club.wageBill),
          _moneyRow('Transfer spend', club.transferSpend),
          _moneyRow('Transfer income', club.transferIncome),
          _moneyRow('Net transfers', club.netTransfers, signed: true),
          const Divider(height: 24),
          _moneyRow(
            'Contracts expiring (12m)',
            club.expiringContracts,
            isCount: true,
            warnWhenPositive: true,
          ),
          const SizedBox(height: 12),
          const Text(
            'Wage bill is the combined salary of every player in the squad. '
            'Transfer totals include all seasons.',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
          const Divider(height: 28),
          Row(
            children: <Widget>[
              const Text(
                'Sponsorship Deals',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showSponsorDealsSheet(context),
                icon: const Icon(Icons.handshake_outlined, size: 16),
                label: const Text('Manage Deals'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<ClubSponsorship>>(
            future: context.read<CareerProvider>().activeSponsorships(),
            builder: (BuildContext context, AsyncSnapshot<List<ClubSponsorship>> snap) {
              final List<ClubSponsorship> sponsors = snap.data ?? <ClubSponsorship>[];
              if (sponsors.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'No active sponsors. Tap "Manage Deals" to sign corporate sponsors for extra revenue!',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (final ClubSponsorship s in sponsors)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.verified, color: AppTheme.accent, size: 20),
                        title: Text(s.sponsorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('${s.typeLabel} · Target: Top ${s.target}', style: const TextStyle(fontSize: 11)),
                        trailing: Text(
                          '+${money(s.weeklyReward)}/w',
                          style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showSponsorDealsSheet(BuildContext context) {
    final CareerProvider game = context.read<CareerProvider>();
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
              padding: const EdgeInsets.all(16),
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
                    'Available Sponsorship Offers',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sign sponsor contracts to earn immediate signing bonuses, weekly income, and target incentives.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: FutureBuilder<List<ClubSponsorship>>(
                      future: game.availableSponsorshipOffers(),
                      builder: (BuildContext _, AsyncSnapshot<List<ClubSponsorship>> snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final List<ClubSponsorship> offers = snap.data!;
                        if (offers.isEmpty) {
                          return const Center(
                            child: Text(
                              'All sponsorship slots are currently filled for this season!',
                              style: TextStyle(color: AppTheme.textDim),
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: offers.length,
                          itemBuilder: (BuildContext _, int i) {
                            final ClubSponsorship offer = offers[i];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        const Icon(Icons.business, color: AppTheme.accent),
                                        const SizedBox(width: 8),
                                        Text(
                                          offer.sponsorName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const Spacer(),
                                        Text(
                                          offer.typeLabel,
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Upfront signing bonus: ${money(offer.baseReward)}', style: const TextStyle(fontSize: 12)),
                                    Text('Weekly reward: +${money(offer.weeklyReward)}/week', style: const TextStyle(fontSize: 12, color: AppTheme.accent)),
                                    Text('Target bonus: ${money(offer.bonusPrize)} (Top ${offer.target} finish)', style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: () async {
                                          await game.signSponsorship(offer);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Signed deal with ${offer.sponsorName}! Received ${money(offer.baseReward)} upfront.')),
                                            );
                                            setSheetState(() {});
                                            setState(() => _reload());
                                          }
                                        },
                                        child: Text('Sign Deal (+${money(offer.baseReward)})'),
                                      ),
                                    ),
                                  ],
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

  Widget _stadiumTab(ClubOverview club) {
    final bool atMax = club.atMaxCapacity;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _number(club.capacity),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Current capacity',
                      style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _number(
                      club.maxGeneral +
                          club.maxStand +
                          club.maxTerrace +
                          club.maxBoxes,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDim,
                    ),
                  ),
                  const Text(
                    'Maximum',
                    style: TextStyle(fontSize: 10, color: AppTheme.textDim),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value:
                  (club.maxGeneral +
                          club.maxStand +
                          club.maxTerrace +
                          club.maxBoxes) <=
                      0
                  ? 0
                  : club.capacity /
                        (club.maxGeneral +
                            club.maxStand +
                            club.maxTerrace +
                            club.maxBoxes),
              minHeight: 8,
              backgroundColor: Colors.grey.shade800,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 18),
          _tier('General', club.general, club.maxGeneral),
          _tier('Stand', club.stand, club.maxStand),
          _tier('Terrace', club.terrace, club.maxTerrace),
          _tier('Boxes', club.boxes, club.maxBoxes),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  atMax ? 'Stadium fully expanded' : 'Next expansion',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  atMax
                      ? 'Every stand is already at its maximum capacity.'
                      : '+${_number(club.upgradeSeats)} seats for '
                            '${money(club.expansionCost)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Budget ${money(club.team.budget)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: atMax || _busy ? null : _expand,
                      icon: _busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_home_work, size: 17),
                      label: Text(atMax ? 'Maxed out' : 'Expand 10%'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tier(String label, int current, int max) {
    final double progress = max <= 0 ? 0 : (current / max).clamp(0, 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade800,
                color: progress >= 1 ? AppTheme.warn : AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(
              '${_number(current)} / ${_number(max)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(
    String label,
    int value, {
    bool signed = false,
    bool isCount = false,
    bool warnWhenPositive = false,
  }) {
    final Color color = isCount && value > 0 && warnWhenPositive
        ? AppTheme.warn
        : signed
        ? (value >= 0 ? AppTheme.accent : AppTheme.danger)
        : Colors.white;
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
            isCount
                ? '$value'
                : signed
                ? '${value >= 0 ? '+' : '-'}${money(value.abs())}'
                : money(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
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

  static String _number(int value) {
    final String digits = value.abs().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return value < 0 ? '-$out' : out.toString();
  }
}
