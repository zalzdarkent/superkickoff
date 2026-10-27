import 'package:flutter/material.dart';

import 'dart:math' as math;

import 'package:provider/provider.dart';

import '../../core/country_names.dart';
import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'annual_awards_gala_sheet.dart';
import 'player_detail_sheet.dart';
import 'tactical_analysis_sheet.dart';

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

class _ClubHubSheetState extends State<ClubHubSheet>
    with SingleTickerProviderStateMixin {
  late Future<ClubOverview?> _future;
  late Future<List<ClubTrophy>> _trophies;
  late Future<List<PlayerAward>> _awards;
  late Future<YouthAcademyState> _academy;
  late Future<ClubFacilities> _facilities;
  late Future<List<ClubStaff>> _staff;
  late final TabController _tabController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _future = context.read<CareerProvider>().clubOverview();
    _trophies = context.read<CareerProvider>().clubTrophies();
    _awards = context.read<CareerProvider>().clubAwards();
    _academy = context.read<CareerProvider>().youthAcademyState();
    _facilities = context.read<CareerProvider>().clubFacilities();
    _staff = context.read<CareerProvider>().clubStaff();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = context.read<CareerProvider>().clubOverview();
      _trophies = context.read<CareerProvider>().clubTrophies();
      _awards = context.read<CareerProvider>().clubAwards();
      _academy = context.read<CareerProvider>().youthAcademyState();
      _facilities = context.read<CareerProvider>().clubFacilities();
      _staff = context.read<CareerProvider>().clubStaff();
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
    final String? error = await context
        .read<CareerProvider>()
        .upgradeYouthAcademy();
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

  Future<void> _upgradeTraining() async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? error =
        await context.read<CareerProvider>().upgradeTrainingGround();
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
      const SnackBar(content: Text('Training Ground berhasil ditingkatkan!')),
    );
  }

  Future<void> _upgradeMedical() async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? error =
        await context.read<CareerProvider>().upgradeMedicalCentre();
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
      const SnackBar(content: Text('Medical Centre berhasil ditingkatkan!')),
    );
  }

  Future<void> _fireStaff(String role) async {
    if (_busy) return;
    setState(() => _busy = true);
    await context.read<CareerProvider>().fireStaff(role);
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Staf berhasil diberhentikan.')),
    );
  }

  void _showHireStaffSheet(String role) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final List<ClubStaff> candidates =
            context.read<CareerProvider>().availableStaffCandidates(role: role);
        final String roleTitle = switch (role) {
          'head_physio' => 'Rekrut Fisioterapis Utama',
          'tactical_analyst' => 'Rekrut Lead Analis Taktis',
          'head_scout' => 'Rekrut Kepala Pemandu Bakat',
          _ => 'Rekrut Staf Profesional',
        };

        return FractionallySizedBox(
          heightFactor: 0.75,
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                Text(
                  roleTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pilih profesional terbaik untuk meningkatkan keunggulan performa klub.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
                const Divider(height: 20),
                Expanded(
                  child: ListView.separated(
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext ctx, int index) {
                      final ClubStaff c = candidates[index];
                      final int fee =
                          context.read<CareerProvider>().hiringFeeForStaff(c);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          c.name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: <Widget>[
                                            for (int i = 0; i < 5; i++)
                                              Icon(
                                                i < c.stars
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                size: 13,
                                                color: Colors.amber,
                                              ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Gaji: ${money(c.salary)}/mgg',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.textDim,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () async {
                                      Navigator.of(sheetContext).pop();
                                      final String? error = await context
                                          .read<CareerProvider>()
                                          .hireStaff(c);
                                      if (!mounted) return;
                                      if (error != null) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(error),
                                            backgroundColor: AppTheme.danger,
                                          ),
                                        );
                                      } else {
                                        _reload();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${c.name} berhasil direkrut!',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Text('Rekrut (${money(fee)})'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Keahlian: ${c.specialty}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
                      '${'${countryFlag(club.countryIso2, name: club.countryName, countryId: club.team.countryId)} ${club.countryName}'.trim()} \u00b7 Division ${club.team.division}',
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
        TabBar(
          controller: _tabController,
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
            Tab(text: 'Facilities'),
            Tab(text: 'Academy'),
            Tab(text: 'Honours'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: <Widget>[
              _overviewTab(club),
              _financesTab(club),
              _stadiumTab(club),
              _facilitiesTab(club),
              _academyTab(),
              _honoursTab(),
            ],
          ),
        ),
      ],
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
                  _info(
                    'Country',
                    '${countryFlag(club.countryIso2, name: club.countryName, countryId: club.team.countryId)} ${club.countryName}'.trim(),
                    width,
                  ),
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
                    club.coachCountry.isEmpty
                        ? '\u2014'
                        : '${countryFlag('', name: club.coachCountry)} ${club.coachCountry}'.trim(),
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
                    '${club.stadiumName} · ${_number(club.capacity)} seats',
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

  Widget _facilitiesTab(ClubOverview club) {
    return FutureBuilder<(ClubFacilities, List<ClubStaff>)>(
      future: Future.wait([_facilities, _staff]).then(
        (List<Object> values) =>
            (values[0] as ClubFacilities, values[1] as List<ClubStaff>),
      ),
      builder: (
        BuildContext context,
        AsyncSnapshot<(ClubFacilities, List<ClubStaff>)> snap,
      ) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ClubFacilities fac = snap.data!.$1;
        final List<ClubStaff> staff = snap.data!.$2;

        final ClubStaff? physio = staff.cast<ClubStaff?>().firstWhere(
          (ClubStaff? s) => s?.isPhysio ?? false,
          orElse: () => null,
        );
        final ClubStaff? analyst = staff.cast<ClubStaff?>().firstWhere(
          (ClubStaff? s) => s?.isAnalyst ?? false,
          orElse: () => null,
        );
        final ClubStaff? headScout = staff.cast<ClubStaff?>().firstWhere(
          (ClubStaff? s) => s?.isHeadScout ?? false,
          orElse: () => null,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Training Ground Facility Card
              _facilityCard(
                icon: Icons.fitness_center,
                iconColor: AppTheme.accent,
                title: 'Training Ground',
                subTitle: fac.trainingTitle,
                description: fac.trainingDescription,
                level: fac.trainingLevel,
                maxLevel: 5,
                pills: <String>[
                  'Max ${fac.trainingMaxPlayers} Pemain / sesi',
                  'Kebugaran +${fac.trainingFitnessGain}',
                  'Wonderkid Surge +${(fac.trainingLevel - 1) * 20}%',
                ],
                upgradeCost: fac.isMaxTraining ? null : fac.nextTrainingCost,
                onUpgrade: _upgradeTraining,
              ),
              const SizedBox(height: 16),

              // Medical Centre Facility Card
              _facilityCard(
                icon: Icons.medical_services,
                iconColor: AppTheme.danger,
                title: 'Medical Centre',
                subTitle: fac.medicalTitle,
                description: fac.medicalDescription,
                level: fac.medicalLevel,
                maxLevel: 5,
                pills: <String>[
                  '-${((fac.injuryReductionRate) * 100).round()}% Risiko Cedera',
                  '+${fac.weeklyFitnessBonus} Stamina Mingguan',
                  'Rehabilitasi Kilat',
                ],
                upgradeCost: fac.isMaxMedical ? null : fac.nextMedicalCost,
                onUpgrade: _upgradeMedical,
              ),
              const SizedBox(height: 22),

              // Staff Header
              const Text(
                'Staf Profesional Klub',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Rekrut staf ahli berperingkat bintang untuk memaksimalkan performa, intel strategi, dan kebugaran tim.',
                style: TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
              const SizedBox(height: 12),

              // Physio Card
              _staffRoleCard(
                role: 'head_physio',
                roleTitle: 'Head Physiotherapist',
                roleDesc:
                    'Mengurangi risiko cedera pertandingan dan mempercepat pemulihan stamina pasca-laga.',
                icon: Icons.healing,
                staff: physio,
              ),
              const SizedBox(height: 10),

              // Tactical Analyst Card
              _staffRoleCard(
                role: 'tactical_analyst',
                roleTitle: 'Lead Tactical Analyst',
                roleDesc:
                    'Menyusun dossier analisis taktik lawan, celah formasi, dan kunci pemain berbahaya sebelum matchday.',
                icon: Icons.psychology,
                staff: analyst,
                extraAction: analyst != null
                    ? () => showTacticalAnalysisSheet(context)
                    : null,
                extraActionLabel: 'Lihat Intel Lawan',
              ),
              const SizedBox(height: 10),

              // Head Scout Card
              _staffRoleCard(
                role: 'head_scout',
                roleTitle: 'Head of Global Scouting',
                roleDesc:
                    'Meningkatkan akurasi dan potensi bintang wonderkid yang ditemukan dalam misi scouting global.',
                icon: Icons.travel_explore,
                staff: headScout,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _facilityCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subTitle,
    required String description,
    required int level,
    required int maxLevel,
    required List<String> pills,
    required int? upgradeCost,
    required VoidCallback onUpgrade,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: iconColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Level $level / $maxLevel',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
          ),
          const SizedBox(height: 10),
          // 5-step level bar
          Row(
            children: <Widget>[
              for (int i = 1; i <= maxLevel; i++)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= level ? iconColor : Colors.white12,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pills
                .map(
                  (String p) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: upgradeCost == null
                ? OutlinedButton(
                    onPressed: null,
                    child: const Text('Level Maksimal Terpenuhi'),
                  )
                : FilledButton.icon(
                      icon: _busy
                          ? const ButtonLoadingIndicator()
                          : const Icon(Icons.upgrade, size: 18),
                      label: Text('Tingkatkan Fasilitas (${money(upgradeCost)})'),
                      onPressed: _busy ? null : onUpgrade,
                    ),
          ),
        ],
      ),
    );
  }

  Widget _staffRoleCard({
    required String role,
    required String roleTitle,
    required String roleDesc,
    required IconData icon,
    required ClubStaff? staff,
    VoidCallback? extraAction,
    String? extraActionLabel,
  }) {
    if (staff == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: AppTheme.textDim),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    roleTitle,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    roleDesc,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textDim,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _showHireStaffSheet(role),
              child: const Text('Rekrut'),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      staff.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        for (int i = 0; i < 5; i++)
                          Icon(
                            i < staff.stars ? Icons.star : Icons.star_border,
                            size: 13,
                            color: Colors.amber,
                          ),
                        const SizedBox(width: 6),
                        Text(
                          '$roleTitle · ${money(staff.salary)}/mgg',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textDim,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Keahlian: ${staff.specialty}',
              style: const TextStyle(fontSize: 11, color: AppTheme.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (extraAction != null && extraActionLabel != null) ...<Widget>[
                TextButton.icon(
                  onPressed: extraAction,
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: Text(extraActionLabel),
                ),
                const SizedBox(width: 6),
              ],
              TextButton(
                onPressed: _busy ? null : () => _showHireStaffSheet(role),
                child: const Text('Ganti'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _fireStaff(role),
                icon: _busy
                    ? const ButtonLoadingIndicator()
                    : const Icon(Icons.person_remove_outlined, size: 16),
                label: const Text(
                  'Pecat',
                  style: TextStyle(color: AppTheme.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _academyTab() {
    return FutureBuilder<YouthAcademyState>(
      future: _academy,
      builder: (BuildContext context, AsyncSnapshot<YouthAcademyState> snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
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
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
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
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<YouthProspect>> snap,
                    ) {
                      final List<YouthProspect> pending =
                          snap.data ?? <YouthProspect>[];
                      if (pending.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceCard,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: <Widget>[
                              Icon(
                                Icons.hourglass_empty,
                                size: 16,
                                color: AppTheme.textDim,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'No pending intake prospects. Next batch arrives in ~3 months.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textDim,
                                  ),
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
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.stars,
                              color: AppTheme.accent,
                              size: 20,
                            ),
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
                              onPressed: () =>
                                  _showAcademyProspectsSheet(context),
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
                  onPressed: _busy || academy.isMaxLevel
                      ? null
                      : _upgradeAcademy,
                  icon: _busy
                      ? const ButtonLoadingIndicator()
                      : const Icon(Icons.upgrade),
                  label: Text(
                    academy.isMaxLevel
                        ? 'Academy Maxed'
                        : 'Upgrade to Level ${academy.level + 1} · ${money(academy.upgradeCost)}',
                  ),
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
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                            color: AppTheme.textDim,
                                          ),
                                          tooltip: 'Reject prospect',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () async {
                                            final bool rejected = await game
                                                .rejectYouthProspect(
                                                  p.prospectId,
                                                );
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  rejected
                                                      ? '${p.name} rejected.'
                                                      : 'Prospect is no longer available.',
                                                ),
                                              ),
                                            );
                                            if (rejected) {
                                              setSheetState(() {});
                                              setState(() {});
                                            }
                                          },
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                          ),
                                          onPressed: () async {
                                            final Player? signed = await game
                                                .signYouthProspect(
                                                  p.prospectId,
                                                );
                                            if (signed != null &&
                                                context.mounted) {
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
                                              setState(() {});
                                            }
                                          },
                                          child: const Text('Sign'),
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

  Widget _honoursTab() {
    return FutureBuilder<List<Object>>(
      future: Future.wait<Object>(<Future<Object>>[_trophies, _awards]),
      builder: (BuildContext context, AsyncSnapshot<List<Object>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<ClubTrophy> trophies =
            (snapshot.data?[0] as List<ClubTrophy>?) ?? const <ClubTrophy>[];
        final List<PlayerAward> awards =
            (snapshot.data?[1] as List<PlayerAward>?) ?? const <PlayerAward>[];

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
            // 1. Gala Banner Card
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF2A1F02), Color(0xFF1E1B4B)],
                ),
                border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.workspace_premium,
                    color: Color(0xFFFFD700),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'ANNUAL AWARDS GALA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Color(0xFFFFD700),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Ballon d\'Or, Golden Boot, & XI Terbaik',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      final CareerProvider game = context.read<CareerProvider>();
                      final SeasonGalaSummary gala = await game.seasonGalaAwards(
                        game.season?.seasonId ?? 1,
                      );
                      if (!context.mounted) return;
                      showAnnualAwardsGala(context, gala: gala);
                    },
                    child: const Text(
                      'Buka Gala',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Trophies Cabinet Header
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
                        'TROPHIES WON',
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
            if (trophies.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Text(
                  'Belum ada trofi kejuaraan. Menangkan liga atau turnamen piala untuk mengisi lemari trofi ini.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
              )
            else
              for (final MapEntry<String, List<ClubTrophy>> entry in entries)
                _trophyRow(entry.key, entry.value),

            const SizedBox(height: 16),

            // 3. Individual Awards Cabinet Header
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
                    Icons.military_tech,
                    color: Color(0xFF60A5FA),
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${awards.length}',
                        style: const TextStyle(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF60A5FA),
                        ),
                      ),
                      const Text(
                        'INDIVIDUAL PLAYER AWARDS',
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
            if (awards.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Text(
                  'Belum ada pemain klub yang memenangkan penghargaan individu musim ini.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
              )
            else
              for (final PlayerAward award in awards)
                _awardRow(award),
          ],
        );
      },
    );
  }

  Widget _awardRow(PlayerAward award) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: InkWell(
        onTap: award.playerId > 0
            ? () => showPlayerDetail(context, award.playerId)
            : null,
        child: Row(
          children: <Widget>[
            const Icon(Icons.stars, color: Color(0xFFFFD700), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    award.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFD700),
                    ),
                  ),
                  Text(
                    award.playerName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (award.statSubtitle != null)
                    Text(
                      award.statSubtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textDim,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${award.year}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
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
          FutureBuilder<FinanceSummary>(
            future: context.read<CareerProvider>().financeSummary(),
            builder:
                (BuildContext context, AsyncSnapshot<FinanceSummary> snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _SeasonFinancePanel(finance: snap.data!);
                },
          ),
          const SizedBox(height: 18),
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
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<ClubSponsorship>> snap,
                ) {
                  final List<ClubSponsorship> sponsors =
                      snap.data ?? <ClubSponsorship>[];
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

                  /*
                  Widget _seasonFinance(FinanceSummary finance) {
                    final List<_FinanceSlice> income = <_FinanceSlice>[
                      _FinanceSlice(
                        'Tickets',
                        finance.ticketIncome,
                        const Color(0xff4dd0e1),
                      ),
                      _FinanceSlice(
                        'Sponsors',
                        finance.sponsorIncome,
                        const Color(0xffffca28),
                      ),
                      _FinanceSlice(
                        'Player sales',
                        finance.playerSaleIncome,
                        const Color(0xff81c784),
                      ),
                      _FinanceSlice(
                        'Prizes',
                        finance.prizeIncome,
                        const Color(0xffba68c8),
                      ),
                    ];
                    final List<_FinanceSlice> expenses = <_FinanceSlice>[
                      _FinanceSlice(
                        'Salaries',
                        finance.salaryExpense,
                        const Color(0xffef5350),
                      ),
                      _FinanceSlice(
                        'Player purchases',
                        finance.playerPurchaseExpense,
                        const Color(0xffff8a65),
                      ),
                      _FinanceSlice(
                        'Other',
                        finance.otherExpense,
                        const Color(0xff90a4ae),
                      ),
                    ];
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'CURRENT SEASON',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            color: AppTheme.textDim,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _financeCard(
                                'Income',
                                finance.totalIncome,
                                income,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _financeCard(
                                'Expenses',
                                finance.totalExpense,
                                expenses,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _moneyRow('Season balance', finance.net, signed: true),
                        const SizedBox(height: 8),
                        const Text(
                          'Income and expenses recorded for the active season. Salaries are estimated from the current weekly wage bill and completed weeks.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textDim,
                          ),
                        ),
                      ],
                    );
                  }

                  Widget _financeCard(
                    String title,
                    int total,
                    List<_FinanceSlice> slices,
                  ) {
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: <Widget>[
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 116,
                            child: Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                CustomPaint(
                                  size: const Size.square(104),
                                  painter: _DonutPainter(slices),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      money(total),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      'total',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textDim,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          for (final _FinanceSlice slice in slices)
                            if (slice.amount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: slice.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        slice.label,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                    Text(
                                      money(slice.amount),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    );
                  }

                  */
                  return Column(
                    children: <Widget>[
                      for (final ClubSponsorship s in sponsors)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                switch (s.type) {
                                  1 => Icons.checkroom,
                                  2 => Icons.stadium,
                                  _ => Icons.shield_outlined,
                                },
                                color: AppTheme.accent,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              s.sponsorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${s.typeLabel} · Target: Top ${s.target}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              '+${money(s.weeklyReward)}/w',
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
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
                    'Manajemen Kontrak Sponsor',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tiap musim klub dapat bermitra dengan 3 brand komersial berbeda: Jersey Utama, Stadion, dan Lengan.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: FutureBuilder<List<Object>>(
                      future: Future.wait<Object>(<Future<Object>>[
                        game.activeSponsorships(),
                        game.availableSponsorshipOffers(),
                      ]),
                      builder: (BuildContext _, AsyncSnapshot<List<Object>> snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final List<ClubSponsorship> active =
                            snap.data![0] as List<ClubSponsorship>;
                        final List<ClubSponsorship> offers =
                            snap.data![1] as List<ClubSponsorship>;

                        return ListView(
                          children: <Widget>[
                            if (active.isNotEmpty) ...<Widget>[
                              const Text(
                                'KONTRAK AKTIF SAAT INI',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDim,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final ClubSponsorship s in active)
                                Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: <Widget>[
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accent.withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            switch (s.type) {
                                              1 => Icons.checkroom,
                                              2 => Icons.stadium,
                                              _ => Icons.shield_outlined,
                                            },
                                            color: AppTheme.accent,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                s.sponsorName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${s.typeLabel} · +${money(s.weeklyReward)}/minggu',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textDim,
                                                ),
                                              ),
                                              Text(
                                                'Bonus Target: ${money(s.bonusPrize)} (Top ${s.target})',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final bool? ok = await showDialog<bool>(
                                              context: context,
                                              builder: (BuildContext dCtx) => AlertDialog(
                                                title: const Text('Putus Kontrak Sponsor?'),
                                                content: Text(
                                                  'Apakah Anda yakin ingin memutus kontrak dengan ${s.sponsorName}? Slot ${s.typeLabel} akan kembali kosong untuk tawaran brand baru.',
                                                ),
                                                actions: <Widget>[
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dCtx, false),
                                                    child: const Text('Batal'),
                                                  ),
                                                  FilledButton(
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor: AppTheme.danger,
                                                    ),
                                                    onPressed: () => Navigator.pop(dCtx, true),
                                                    child: const Text('Putus Kontrak'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              await game.terminateSponsorship(s.sponsorshipId);
                                              setSheetState(() {});
                                              setState(() => _reload());
                                            }
                                          },
                                          child: const Text(
                                            'Putus',
                                            style: TextStyle(
                                              color: AppTheme.danger,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                            if (offers.isNotEmpty) ...<Widget>[
                              const Text(
                                'TAWARAN BRAND SPONSOR TERSEDIA',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final ClubSponsorship offer in offers)
                                Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.08),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                switch (offer.type) {
                                                  1 => Icons.checkroom,
                                                  2 => Icons.stadium,
                                                  _ => Icons.shield_outlined,
                                                },
                                                color: AppTheme.accent,
                                                size: 18,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              offer.sponsorName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.surface,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.white12),
                                              ),
                                              child: Text(
                                                offer.typeLabel,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.textDim,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Bonus Tanda Tangan: ${money(offer.baseReward)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          'Pendapatan Mingguan: +${money(offer.weeklyReward)}/minggu',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.accent,
                                          ),
                                        ),
                                        Text(
                                          'Bonus Target: ${money(offer.bonusPrize)} (Finis Top ${offer.target})',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton(
                                            onPressed: () async {
                                              await game.signSponsorship(offer);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Kontrak ${offer.typeLabel} resmi diteken bersama ${offer.sponsorName}! Bonus awal ${money(offer.baseReward)}.',
                                                    ),
                                                  ),
                                                );
                                                setSheetState(() {});
                                                setState(() => _reload());
                                              }
                                            },
                                            child: Text(
                                              'Tandatangani Kontrak (+${money(offer.baseReward)})',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ] else if (active.length >= 3) ...<Widget>[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  children: <Widget>[
                                    Icon(Icons.check_circle, color: AppTheme.accent, size: 24),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Semua 3 slot sponsor (Jersey Utama, Stadion, dan Lengan) telah terisi penuh oleh brand mitra komersial.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
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
                          ? const ButtonLoadingIndicator()
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

class _FinanceSlice {
  const _FinanceSlice(this.label, this.amount, this.color);

  final String label;
  final int amount;
  final Color color;
}

class _SeasonFinancePanel extends StatelessWidget {
  const _SeasonFinancePanel({required this.finance});

  final FinanceSummary finance;

  @override
  Widget build(BuildContext context) {
    final List<_FinanceSlice> income = <_FinanceSlice>[
      _FinanceSlice('Tickets', finance.ticketIncome, const Color(0xff4dd0e1)),
      _FinanceSlice('Sponsors', finance.sponsorIncome, const Color(0xffffca28)),
      _FinanceSlice(
        'Player sales',
        finance.playerSaleIncome,
        const Color(0xff81c784),
      ),
      _FinanceSlice('Prizes', finance.prizeIncome, const Color(0xffba68c8)),
    ];
    final List<_FinanceSlice> expenses = <_FinanceSlice>[
      _FinanceSlice('Salaries', finance.salaryExpense, const Color(0xffef5350)),
      _FinanceSlice(
        'Player purchases',
        finance.playerPurchaseExpense,
        const Color(0xffff8a65),
      ),
      _FinanceSlice('Other', finance.otherExpense, const Color(0xff90a4ae)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'CURRENT SEASON',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1,
            color: AppTheme.textDim,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: _FinanceCard(
                title: 'Income',
                total: finance.totalIncome,
                slices: income,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FinanceCard(
                title: 'Expenses',
                total: finance.totalExpense,
                slices: expenses,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _moneyRowStatic('Season balance', finance.net, signed: true),
        const SizedBox(height: 8),
        const Text(
          'Income and expenses recorded for the active season. Salaries are estimated from the current weekly wage bill and completed weeks.',
          style: TextStyle(fontSize: 11, color: AppTheme.textDim),
        ),
      ],
    );
  }

  static Widget _moneyRowStatic(
    String label,
    int value, {
    bool signed = false,
  }) {
    final Color color = signed
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
            signed
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
}

class _FinanceCard extends StatelessWidget {
  const _FinanceCard({
    required this.title,
    required this.total,
    required this.slices,
  });

  final String title;
  final int total;
  final List<_FinanceSlice> slices;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 116,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CustomPaint(
                  size: const Size.square(104),
                  painter: _DonutPainter(slices),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      money(total),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'total',
                      style: TextStyle(fontSize: 10, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (final _FinanceSlice slice in slices)
            if (slice.amount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: slice.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        slice.label,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    Text(
                      money(slice.amount),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.slices);

  final List<_FinanceSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final double total = slices.fold<double>(
      0,
      (double sum, _FinanceSlice slice) => sum + slice.amount,
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      paint.color = Colors.white12;
      canvas.drawArc(bounds.deflate(10), 0, math.pi * 2, false, paint);
      return;
    }
    double start = -math.pi / 2;
    for (final _FinanceSlice slice in slices) {
      if (slice.amount <= 0) continue;
      paint.color = slice.color;
      final double sweep = math.pi * 2 * slice.amount / total;
      canvas.drawArc(bounds.deflate(10), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) => oldDelegate.slices != slices;
}
