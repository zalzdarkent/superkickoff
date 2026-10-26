import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/country_names.dart';
import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../game/formation.dart';
import '../../game/match_engine.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';

/// Opens the comprehensive team details sheet:
/// Formation, starting XI on the tactical pitch, bench, squad list,
/// strength ratings (ATT, MID, DEF, GK, OVR), and club overview.
/// Tapping any player opens their detailed profile.
Future<void> showTeamDetail(
  BuildContext context,
  int teamId, {
  int initialTabIndex = 0,
}) {
  if (teamId <= 0) return Future<void>.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: TeamDetailSheet(
        teamId: teamId,
        initialTabIndex: initialTabIndex,
      ),
    ),
  );
}

class TeamDetailSheet extends StatefulWidget {
  const TeamDetailSheet({
    super.key,
    required this.teamId,
    this.initialTabIndex = 0,
  });

  final int teamId;
  final int initialTabIndex;

  @override
  State<TeamDetailSheet> createState() => _TeamDetailSheetState();
}

class _TeamDetailSheetState extends State<TeamDetailSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _error;

  Team? _team;
  List<Player> _squad = <Player>[];
  Formation _formation = Formation.f442;
  ClubOverview? _overview;
  List<ClubTrophy> _trophies = <ClubTrophy>[];
  Lineup? _lineup;
  List<FixtureMatch> _fixtures = <FixtureMatch>[];
  Map<int, Team> _fixturesTeams = <int, Team>{};
  Map<int, String> _tournamentNames = <int, String>{};

  int _posFilter = 0; // 0: All, 1: GK, 2: DEF, 3: MID, 4: ATT

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final CareerProvider game = context.read<CareerProvider>();
      final Team? team = await game.teamById(widget.teamId);
      if (team == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Tim tidak ditemukan.';
          });
        }
        return;
      }

      final List<Player> squad = await game.squadForTeam(widget.teamId);
      final Formation formation = await game.formationForTeam(widget.teamId);
      final Map<int, int> saved = await game.lineupForTeam(widget.teamId);
      final ClubOverview? overview =
          await game.clubOverviewForTeam(widget.teamId);
      final List<ClubTrophy> trophies =
          await game.clubTrophiesForTeam(widget.teamId);

      // Load fixtures for this club
      final List<FixtureMatch> fixtures =
          await game.fixturesForTeam(widget.teamId);
      final Map<int, Team> fixturesTeams = <int, Team>{};
      fixturesTeams[team.teamId] = team;
      for (final FixtureMatch m in fixtures) {
        final int otherId =
            m.homeTeamId == widget.teamId ? m.awayTeamId : m.homeTeamId;
        if (!fixturesTeams.containsKey(otherId)) {
          final Team? other = await game.teamById(otherId);
          if (other != null) fixturesTeams[otherId] = other;
        }
      }
      final Map<int, String> tourNames = <int, String>{
        if (game.league != null) game.league!.tournamentId: game.league!.name,
        for (final Tournament tour in game.cups) tour.tournamentId: tour.name,
      };

      // Compute starting XI
      final Lineup lineup = Lineup.best(
        squad,
        formation: formation,
        preferredIds: saved.values.toList(),
      );

      if (!mounted) return;
      setState(() {
        _team = team;
        _squad = squad;
        _formation = formation;
        _overview = overview;
        _trophies = trophies;
        _lineup = lineup;
        _fixtures = fixtures;
        _fixturesTeams = fixturesTeams;
        _tournamentNames = tourNames;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Gagal memuat detail tim: $e';
        });
      }
    }
  }

  int _groupOf(Player p) {
    if (p.positionId == 1) return 1;
    if (p.positionId <= 4) return 2;
    if (p.positionId <= 8) return 3;
    return 4;
  }

  Color _groupColor(int group) => switch (group) {
        1 => const Color(0xFFF59E0B),
        2 => const Color(0xFF3B82F6),
        3 => AppTheme.accent,
        _ => AppTheme.danger,
      };

  Color _powerColor(int power) {
    if (power >= 85) return const Color(0xFFF59E0B);
    if (power >= 78) return AppTheme.accent;
    if (power >= 70) return const Color(0xFF3B82F6);
    if (power >= 60) return Colors.white70;
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.error_outline,
                              size: 40, color: AppTheme.danger),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadData,
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final Team team = _team!;
    final Lineup lineup = _lineup!;
    final List<Player> starters = lineup.starters;

    // Calculate ratings
    final int att = (Lineup.attackOn(starters) / 9.4).round().clamp(30, 99);
    final int mid = (Lineup.midfieldOn(starters) / 8.0).round().clamp(30, 99);
    final int def = (Lineup.defenseOn(starters) / 10.4).round().clamp(30, 99);
    final List<Player> gks =
        starters.where((Player p) => p.positionId == 1).toList();
    final int gk = gks.isEmpty
        ? team.power
        : (gks.fold<int>(0, (int s, Player p) => s + p.power) / gks.length)
            .round();
    final int ovr = team.power > 0
        ? team.power
        : (starters.fold<int>(0, (int s, Player p) => s + p.power) /
                (starters.isEmpty ? 1 : starters.length))
            .round();

    final CareerProvider game = context.watch<CareerProvider>();
    final bool isUserTeam = team.teamId == game.userTeamId;

    return Column(
      children: <Widget>[
        // Sheet handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade700,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Team Header Card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: <Widget>[
              CrestAvatar(team: team, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (isUserTeam) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppTheme.accent.withValues(alpha: 0.6),
                              ),
                            ),
                            child: const Text(
                              'TIM ANDA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        if (team.abbreviation.isNotEmpty) ...<Widget>[
                          Text(
                            team.abbreviation.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDim,
                            ),
                          ),
                          const Text(
                            ' · ',
                            style: TextStyle(color: AppTheme.textDim),
                          ),
                        ],
                        Text(
                          'Divisi ${team.division}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textDim,
                          ),
                        ),
                        if (_overview != null &&
                            _overview!.countryName.isNotEmpty) ...<Widget>[
                          const Text(
                            ' · ',
                            style: TextStyle(color: AppTheme.textDim),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (countryFlag(
                                _overview!.countryIso2,
                                name: _overview!.countryName,
                                countryId: team.countryId,
                              ).isNotEmpty) ...<Widget>[
                                Text(
                                  countryFlag(
                                    _overview!.countryIso2,
                                    name: _overview!.countryName,
                                    countryId: team.countryId,
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                const SizedBox(width: 3),
                              ],
                              Text(
                                _overview!.countryName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textDim,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Overall Power pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      _powerColor(ovr).withValues(alpha: 0.25),
                      _powerColor(ovr).withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _powerColor(ovr).withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '$ovr',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _powerColor(ovr),
                        height: 1,
                      ),
                    ),
                    const Text(
                      'OVR',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDim,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // Team Strength Metrics Grid
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _strengthItem('ATT', 'Serangan', att, AppTheme.danger),
              _verticalDivider(),
              _strengthItem('MID', 'Tengah', mid, AppTheme.accent),
              _verticalDivider(),
              _strengthItem('DEF', 'Bertahan', def, const Color(0xFF3B82F6)),
              _verticalDivider(),
              _strengthItem('GK', 'Kiper', gk, const Color(0xFFF59E0B)),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Navigation Tabs
        TabBar(
          controller: _tabController,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textDim,
          indicatorColor: AppTheme.accent,
          indicatorWeight: 2.5,
          dividerColor: Colors.white12,
          tabs: <Widget>[
            Tab(
              icon: const Icon(Icons.dashboard_customize, size: 16),
              text: 'Formasi & XI',
            ),
            Tab(
              icon: const Icon(Icons.groups, size: 16),
              text: 'Skuad (${_squad.length})',
            ),
            Tab(
              icon: const Icon(Icons.calendar_month, size: 16),
              text: 'Jadwal (${_fixtures.length})',
            ),
            Tab(
              icon: const Icon(Icons.shield_outlined, size: 16),
              text: 'Info Klub',
            ),
          ],
        ),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: <Widget>[
              _formationTab(lineup),
              _squadListTab(),
              _fixturesTab(),
              _clubInfoTab(team),
            ],
          ),
        ),
      ],
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white10,
    );
  }

  Widget _strengthItem(String key, String label, int value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              key,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 52,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 3.5,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- Formation & Pitch Tab

  Widget _formationTab(Lineup lineup) {
    final List<Player> starters = lineup.starters;
    final Set<int> starterIds =
        starters.map((Player p) => p.playerId).toSet();
    final List<Player> bench =
        _squad.where((Player p) => !starterIds.contains(p.playerId)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: <Widget>[
        // Formation banner
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.sports_soccer,
                  size: 18,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  'Formasi: ${_formation.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.touch_app,
                          size: 12, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Klik pemain utk detail',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Visual Pitch
        _pitchWidget(starters),

        const SizedBox(height: 14),

        // Bench / Cadangan Section
        _benchSection(bench),
      ],
    );
  }

  Widget _pitchWidget(List<Player> starters) {
    final List<_PitchSlot> slots = _mapStartersToSlots(_formation, starters);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF14532D),
              Color(0xFF166534),
              Color(0xFF14532D),
            ],
          ),
        ),
        child: AspectRatio(
          aspectRatio: 0.76,
          child: Stack(
            children: <Widget>[
              // Grass horizontal stripes
              Column(
                children: <Widget>[
                  for (int i = 0; i < 6; i++)
                    Expanded(
                      child: Container(
                        color: i.isEven
                            ? Colors.black.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.03),
                      ),
                    ),
                ],
              ),

              // Pitch boundary lines
              Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              // Halfway line
              Center(
                child: Container(
                  width: double.infinity,
                  height: 1.5,
                  color: Colors.white24,
                ),
              ),

              // Center circle
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1.5),
                  ),
                ),
              ),

              // Penalty box top
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 140,
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.white24, width: 1.5),
                      right: BorderSide(color: Colors.white24, width: 1.5),
                      bottom: BorderSide(color: Colors.white24, width: 1.5),
                    ),
                  ),
                ),
              ),

              // Penalty box bottom
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  width: 140,
                  height: 52,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.white24, width: 1.5),
                      right: BorderSide(color: Colors.white24, width: 1.5),
                      top: BorderSide(color: Colors.white24, width: 1.5),
                    ),
                  ),
                ),
              ),

              // Pitch Player Slots Layout (ATT on top, MID, DEF, GK at bottom)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
                child: Column(
                  children: <Widget>[
                    for (final int group in <int>[4, 3, 2, 1])
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            for (final _PitchSlot s in slots)
                              if (s.group == group)
                                Flexible(child: _playerPitchNode(s)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_PitchSlot> _mapStartersToSlots(
    Formation f,
    List<Player> starters,
  ) {
    final List<_PitchSlot> slots = <_PitchSlot>[];

    // Partition starters into groups: GK(1), DEF(2), MID(3), ATT(4)
    final List<Player> gks =
        starters.where((Player p) => _groupOf(p) == 1).toList();
    final List<Player> defs =
        starters.where((Player p) => _groupOf(p) == 2).toList();
    final List<Player> mids =
        starters.where((Player p) => _groupOf(p) == 3).toList();
    final List<Player> atts =
        starters.where((Player p) => _groupOf(p) == 4).toList();

    // Map GK
    if (gks.isNotEmpty) {
      slots.add(_PitchSlot(player: gks.first, group: 1, defaultRole: 'GK'));
    }

    // Map DEF
    for (int i = 0; i < defs.length; i++) {
      final Player p = defs[i];
      final String role = PositionBadge.labelFor(p.positionId, profile: p.profile);
      slots.add(_PitchSlot(player: p, group: 2, defaultRole: role));
    }

    // Map MID
    for (int i = 0; i < mids.length; i++) {
      final Player p = mids[i];
      final String role = PositionBadge.labelFor(p.positionId, profile: p.profile);
      slots.add(_PitchSlot(player: p, group: 3, defaultRole: role));
    }

    // Map ATT
    for (int i = 0; i < atts.length; i++) {
      final Player p = atts[i];
      final String role = PositionBadge.labelFor(p.positionId, profile: p.profile);
      slots.add(_PitchSlot(player: p, group: 4, defaultRole: role));
    }

    // Fallback if some group had fewer players (should rarely happen)
    if (slots.length < 11) {
      final Set<int> used =
          slots.map((_PitchSlot s) => s.player.playerId).toSet();
      for (final Player p in starters) {
        if (!used.contains(p.playerId)) {
          slots.add(_PitchSlot(
            player: p,
            group: _groupOf(p),
            defaultRole:
                PositionBadge.labelFor(p.positionId, profile: p.profile),
          ));
        }
      }
    }

    return slots;
  }

  Widget _playerPitchNode(_PitchSlot slot) {
    final Player player = slot.player;
    final Color color = _groupColor(slot.group);
    final String pos =
        PositionBadge.labelFor(player.positionId, profile: player.profile);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        splashColor: AppTheme.accent.withValues(alpha: 0.3),
        onTap: () => showPlayerDetail(context, player.playerId),
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, maxWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Jersey / Position badge with power badge
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        pos,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  // Rating badge pill
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _powerColor(player.power),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      child: Text(
                        '${player.power}',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),

              // Player Name
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benchSection(List<Player> bench) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
              const Icon(Icons.airline_seat_recline_normal,
                  size: 16, color: AppTheme.accent),
              const SizedBox(width: 6),
              const Text(
                'PEMAIN CADANGAN (BENCH)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textDim,
                ),
              ),
              const Spacer(),
              Text(
                '${bench.length} pemain',
                style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (bench.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Tidak ada pemain cadangan yang tersedia.',
                style: TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final Player p in bench)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => showPlayerDetail(context, p.playerId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _groupColor(_groupOf(p))
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            PositionBadge(
                              positionId: p.positionId,
                              profile: p.profile,
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 100),
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: _powerColor(p.power)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${p.power}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: _powerColor(p.power),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Squad List Tab

  Widget _squadListTab() {
    List<Player> display = List<Player>.of(_squad);
    if (_posFilter != 0) {
      display = display.where((Player p) => _groupOf(p) == _posFilter).toList();
    }
    display.sort((Player a, Player b) => b.power.compareTo(a.power));

    final double avgAge = _squad.isEmpty
        ? 0
        : _squad.fold<int>(0, (int s, Player p) => s + p.age) / _squad.length;
    final int totalVal =
        _squad.fold<int>(0, (int s, Player p) => s + p.value);

    return Column(
      children: <Widget>[
        // Quick summary bar
        Container(
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _metaStat('Total Pemain', '${_squad.length}'),
              _verticalDivider(),
              _metaStat('Rata-rata Usia', '${avgAge.toStringAsFixed(1)} thn'),
              _verticalDivider(),
              _metaStat('Total Nilai Skuad', money(totalVal)),
            ],
          ),
        ),

        // Position Filter Chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: <Widget>[
              _filterChip('Semua', 0),
              const SizedBox(width: 6),
              _filterChip('GK', 1),
              const SizedBox(width: 6),
              _filterChip('Bek', 2),
              const SizedBox(width: 6),
              _filterChip('Tengah', 3),
              const SizedBox(width: 6),
              _filterChip('Depan', 4),
            ],
          ),
        ),

        // Players list
        Expanded(
          child: display.isEmpty
              ? const Center(
                  child: Text(
                    'Tidak ada pemain di kategori ini.',
                    style: TextStyle(color: AppTheme.textDim),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                  itemCount: display.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Player p = display[index];
                    return _playerTile(p);
                  },
                ),
        ),
      ],
    );
  }

  Widget _metaStat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: AppTheme.textDim),
        ),
      ],
    );
  }

  Widget _filterChip(String label, int filter) {
    final bool active = _posFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _posFilter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppTheme.accent : AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppTheme.accent : Colors.white12,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: active ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerTile(Player p) {
    final bool isStarter = _lineup?.starters.any((Player s) => s.playerId == p.playerId) ?? false;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showPlayerDetail(context, p.playerId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              PositionBadge(
                positionId: p.positionId,
                profile: p.profile,
              ),
              const SizedBox(width: 10),
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
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isStarter) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'XI',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Text(
                          '${p.age} thn · ${p.profile == 'I' ? 'Kiri' : 'Kanan'} · ',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textDim,
                          ),
                        ),
                        Text(
                          money(p.value),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDim,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Stars(value: p.stars, size: 10),
              const SizedBox(width: 10),
              Container(
                width: 32,
                height: 28,
                decoration: BoxDecoration(
                  color: _powerColor(p.power).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _powerColor(p.power).withValues(alpha: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${p.power}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _powerColor(p.power),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: AppTheme.textDim),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Fixtures / Jadwal Tab

  Widget _fixturesTab() {
    if (_fixtures.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.calendar_today_outlined,
                size: 40, color: AppTheme.textDim),
            SizedBox(height: 12),
            Text(
              'Belum ada jadwal pertandingan musim ini.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
          ],
        ),
      );
    }

    int played = 0;
    int wins = 0;
    int draws = 0;
    int losses = 0;
    int gf = 0;
    int ga = 0;

    for (final FixtureMatch m in _fixtures) {
      if (m.isPlayed) {
        played++;
        final bool isHome = m.homeTeamId == widget.teamId;
        final int teamG = isHome ? (m.homeGoals ?? 0) : (m.awayGoals ?? 0);
        final int oppG = isHome ? (m.awayGoals ?? 0) : (m.homeGoals ?? 0);
        gf += teamG;
        ga += oppG;
        if (teamG > oppG) {
          wins++;
        } else if (teamG < oppG) {
          losses++;
        } else {
          draws++;
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: <Widget>[
        // Season Summary Card
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.query_stats, size: 16, color: AppTheme.accent),
                    SizedBox(width: 8),
                    Text(
                      'Rekor Musim Ini',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    _statBadge('Main', '$played', null),
                    _statBadge('Menang', '$wins', AppTheme.accent),
                    _statBadge('Seri', '$draws', AppTheme.textDim),
                    _statBadge('Kalah', '$losses', AppTheme.danger),
                    _statBadge('Gol', '$gf-$ga', null),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Fixtures list
        for (final FixtureMatch match in _fixtures) ...<Widget>[
          _fixtureCard(match),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _statBadge(String label, String value, Color? color) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
        ),
      ],
    );
  }

  Widget _fixtureCard(FixtureMatch match) {
    final bool isHome = match.homeTeamId == widget.teamId;
    final Team? home = _fixturesTeams[match.homeTeamId];
    final Team? away = _fixturesTeams[match.awayTeamId];
    final String tourName =
        _tournamentNames[match.tournamentId] ?? 'Kompetisi';

    final int teamG = isHome ? (match.homeGoals ?? 0) : (match.awayGoals ?? 0);
    final int oppG = isHome ? (match.awayGoals ?? 0) : (match.homeGoals ?? 0);

    Color resultColor = AppTheme.textDim;
    String resultLetter = 'S';
    if (match.isPlayed) {
      if (teamG > oppG) {
        resultColor = AppTheme.accent;
        resultLetter = 'M';
      } else if (teamG < oppG) {
        resultColor = AppTheme.danger;
        resultLetter = 'K';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header: Competition & date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '${tourName.toUpperCase()} · ${match.phase > 0 ? 'PEKAN ${match.phase}' : 'MATCH'}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppTheme.accent,
                ),
              ),
              if (match.date != null && match.date!.isNotEmpty)
                Text(
                  match.date!,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textDim,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Teams and Score
          Row(
            children: <Widget>[
              // Home Team
              Expanded(
                child: InkWell(
                  onTap: () => showTeamDetail(context, match.homeTeamId),
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          home?.name ?? 'Tim ${match.homeTeamId}',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isHome ? FontWeight.bold : FontWeight.normal,
                            color: isHome ? Colors.white : AppTheme.textDim,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (home != null)
                        CrestAvatar(team: home, radius: 11)
                      else
                        const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.white12,
                          child: Text('?', style: TextStyle(fontSize: 8)),
                        ),
                    ],
                  ),
                ),
              ),

              // Center: Score / Status
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: match.isPlayed
                      ? resultColor.withValues(alpha: 0.15)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: match.isPlayed
                        ? resultColor.withValues(alpha: 0.5)
                        : Colors.white12,
                  ),
                ),
                child: match.isPlayed
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '${match.homeGoals ?? 0} - ${match.awayGoals ?? 0}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: resultColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              resultLetter,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'VS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDim,
                        ),
                      ),
              ),

              // Away Team
              Expanded(
                child: InkWell(
                  onTap: () => showTeamDetail(context, match.awayTeamId),
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: <Widget>[
                      if (away != null)
                        CrestAvatar(team: away, radius: 11)
                      else
                        const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.white12,
                          child: Text('?', style: TextStyle(fontSize: 8)),
                        ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          away?.name ?? 'Tim ${match.awayTeamId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                !isHome ? FontWeight.bold : FontWeight.normal,
                            color: !isHome ? Colors.white : AppTheme.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Club Info Tab

  Widget _clubInfoTab(Team team) {
    final ClubOverview? ov = _overview;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: <Widget>[
        // Stadium Card
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.stadium, size: 16, color: AppTheme.accent),
                    SizedBox(width: 8),
                    Text(
                      'Stadion',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ov?.stadiumName ?? 'Stadion Tim',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (ov != null && ov.stadiumCity.isNotEmpty)
                  Text(
                    ov.stadiumCity,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textDim,
                    ),
                  ),
                const SizedBox(height: 10),
                if (ov != null)
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: <Widget>[
                      _infoPill('Tribun Utama', '${ov.general}'),
                      _infoPill('Tribun Berdiri', '${ov.stand}'),
                      _infoPill('Tribun VIP', '${ov.boxes}'),
                      _infoPill(
                        'Total Kapasitas',
                        '${ov.general + ov.stand + ov.terrace + ov.boxes}',
                        highlight: true,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Manager / Coach Card
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.person_pin, size: 16, color: AppTheme.accent),
                    SizedBox(width: 8),
                    Text(
                      'Manajer / Pelatih',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ov?.coachName.isNotEmpty == true
                      ? ov!.coachName
                      : 'Kepala Pelatih',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (ov != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Usia: ${ov.coachAge} thn · ${'${countryFlag('', name: ov.coachCountry)} ${ov.coachCountry}'.trim()} · ${ov.coachPoints} poin taktik',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Trophies / Prestasi
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.emoji_events, size: 16, color: Color(0xFFF59E0B)),
                    SizedBox(width: 8),
                    Text(
                      'Koleksi Trofi & Gelar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_trophies.isEmpty)
                  const Text(
                    'Belum ada riwayat trofi yang diraih.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                  )
                else
                  for (final ClubTrophy t in _trophies)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.military_tech,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              t.tournamentName,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${t.seasonName} (${t.year})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Financial & Establishment Details
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.history_edu, size: 16, color: AppTheme.accent),
                    SizedBox(width: 8),
                    Text(
                      'Informasi Klub Lainnya',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _rowText('Tahun Berdiri', '${team.foundedYear}'),
                _rowText('Divisi', 'Tingkat ${team.division}'),
                if (team.budget > 0)
                  _rowText('Anggaran Transfer', money(team.budget)),
                if (_overview != null && _overview!.squadValue > 0)
                  _rowText('Estimasi Nilai Klub', money(_overview!.squadValue)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoPill(String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.accent.withValues(alpha: 0.15)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight ? AppTheme.accent : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: highlight ? AppTheme.accent : Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }

  Widget _rowText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PitchSlot {
  const _PitchSlot({
    required this.player,
    required this.group,
    required this.defaultRole,
  });

  final Player player;
  final int group;
  final String defaultRole;
}
