import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db/schema.dart' as t;
import '../../data/models/models.dart';
import '../../game/international_tournament_service.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import 'player_detail_sheet.dart';

/// Screen displaying international windows, tournament standings, results,
/// national team squads, and user club player duty tracking.
class InternationalTab extends StatefulWidget {
  const InternationalTab({super.key});

  @override
  State<InternationalTab> createState() => _InternationalTabState();
}

class _InternationalTabState extends State<InternationalTab> {
  int _subTabIndex = 0;

  // Selected tournament for standings/fixtures
  int _selectedTournamentId = t.tournamentWorldCup;

  // Selected country for squad viewer
  int _selectedCountryId = 0;
  List<Country> _allCountries = <Country>[];
  bool _loadingCountries = false;

  String _countryName(int id) {
    for (final Country c in _allCountries) {
      if (c.countryId == id) return c.name;
    }
    return 'Tim #$id';
  }

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    setState(() => _loadingCountries = true);
    final CareerProvider game = context.read<CareerProvider>();
    final List<Country> countries = await game.nationalTeams.getNationalTeams();
    if (!mounted) return;
    setState(() {
      _allCountries = countries;
      if (countries.isNotEmpty) {
        // Pick user's country or the first one
        final int userCountryId = game.userTeam?.countryId ?? 0;
        final bool hasUserCountry = countries.any((Country c) => c.countryId == userCountryId);
        _selectedCountryId = hasUserCountry ? userCountryId : countries.first.countryId;
      }
      _loadingCountries = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();

    return Column(
      children: <Widget>[
        // Sub-navigation bar
        Container(
          color: AppTheme.surfaceCard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              _subTabChip(0, 'Jadwal & Tugas', Icons.event_available_outlined),
              const SizedBox(width: 8),
              _subTabChip(1, 'Turnamen', Icons.emoji_events_outlined),
              const SizedBox(width: 8),
              _subTabChip(2, 'Skuad Timnas', Icons.groups_outlined),
            ],
          ),
        ),
        Expanded(
          child: _buildSubTabContent(game),
        ),
      ],
    );
  }

  Widget _subTabChip(int index, String label, IconData icon) {
    final bool active = _subTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _subTabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.accent : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 14,
              color: active ? Colors.black : AppTheme.textDim,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? Colors.black : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabContent(CareerProvider game) {
    switch (_subTabIndex) {
      case 0:
        return _buildWindowsAndDutyTab(game);
      case 1:
        return _buildTournamentsTab(game);
      case 2:
        return _buildSquadViewerTab(game);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Sub-tab 0: Windows & Duty
  // ---------------------------------------------------------------------------
  Widget _buildWindowsAndDutyTab(CareerProvider game) {
    final List<InternationalDuty> dutyList = game.userClubPlayersOnDuty;
    final List<InternationalWindow> windows = game.internationalWindows;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Duty Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: dutyList.isNotEmpty
                  ? const Color(0xFF1E88E5).withValues(alpha: 0.5)
                  : Colors.white10,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.public, color: Color(0xFF1E88E5), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Pemain Klub yang Bertugas Timnas',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: dutyList.isNotEmpty
                          ? const Color(0xFF1E88E5).withValues(alpha: 0.2)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${dutyList.length} Pemain',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: dutyList.isNotEmpty
                            ? const Color(0xFF64B5F6)
                            : AppTheme.textDim,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (dutyList.isEmpty)
                const Text(
                  'Saat ini tidak ada pemain klub Anda yang sedang bertugas di tim nasional.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                )
              else
                ...dutyList.map((InternationalDuty duty) => _dutyPlayerTile(duty)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Windows Section
        const Text(
          'Jendela Pertandingan Internasional (FIFA)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 10),
        if (windows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Belum ada jendela internasional untuk musim ini.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          )
        else
          ...windows.map((InternationalWindow win) => _windowCard(win)),
      ],
    );
  }

  Widget _dutyPlayerTile(InternationalDuty duty) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.person, size: 16, color: Color(0xFF64B5F6)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  duty.playerName.isEmpty
                      ? 'Pemain #${duty.playerId}'
                      : '${duty.playerName} (${duty.positionAbbr})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${duty.countryName.isEmpty ? 'Negara #${duty.countryId}' : duty.countryName} · Pelepasan: ${duty.releaseStartDate} s/d ${duty.returnDate}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
              ),
            ),
            child: const Text(
              'TIMNAS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64B5F6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _windowCard(InternationalWindow win) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  win.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (win.isMandatoryRelease)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text(
                    'WAJIB LEPAS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(Icons.date_range, size: 13, color: AppTheme.textDim),
              const SizedBox(width: 4),
              Text(
                'Laga: ${win.startDate} s/d ${win.endDate}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              const Icon(Icons.flight_takeoff, size: 13, color: AppTheme.textDim),
              const SizedBox(width: 4),
              Text(
                'Pelepasan: ${win.releaseStartDate} | Kembali: ${win.returnDate}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-tab 1: Tournaments & Standings
  // ---------------------------------------------------------------------------
  static const List<Map<String, dynamic>> _tournaments = <Map<String, dynamic>>[
    <String, dynamic>{'id': t.tournamentWorldCup, 'name': 'FIFA World Cup', 'badge': '48 Tim (12 Grup)'},
    <String, dynamic>{'id': t.tournamentEuro, 'name': 'UEFA EURO', 'badge': '24 Tim (6 Grup)'},
    <String, dynamic>{'id': t.tournamentAsianCup, 'name': 'AFC Asian Cup', 'badge': '24 Tim (6 Grup)'},
    <String, dynamic>{'id': t.tournamentNationsLeague, 'name': 'UEFA Nations League', 'badge': 'Divisi & Promosi'},
    <String, dynamic>{'id': t.tournamentAseanChampionship, 'name': 'ASEAN Championship', 'badge': '10 Tim (2 Grup)'},
    <String, dynamic>{'id': t.tournamentFifaAseanCup, 'name': 'FIFA ASEAN Cup', 'badge': '14 Tim (2 Grup)'},
    <String, dynamic>{'id': t.tournamentFriendlies, 'name': 'Laga Uji Coba Internasional', 'badge': 'Persahabatan FIFA'},
  ];

  Widget _buildTournamentsTab(CareerProvider game) {
    return Column(
      children: <Widget>[
        // Competition selection horizontal chips
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: _tournaments.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> item = _tournaments[index];
              final int id = item['id'] as int;
              final bool selected = id == _selectedTournamentId;
              return ChoiceChip(
                label: Text(item['name'] as String),
                selected: selected,
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surfaceCard,
                side: BorderSide(
                  color: selected ? AppTheme.accent : Colors.white10,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _selectedTournamentId = id);
                },
              );
            },
          ),
        ),

        // Standings & Matches
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              // Tournament info banner
              _tournamentInfoBanner(_selectedTournamentId),
              const SizedBox(height: 16),

              // Standings
              _standingsSection(game, _selectedTournamentId),
              const SizedBox(height: 20),

              // Matches
              _matchesSection(game, _selectedTournamentId),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tournamentInfoBanner(int tournamentId) {
    final Map<String, dynamic> item = _tournaments.firstWhere(
      (Map<String, dynamic> m) => m['id'] == tournamentId,
      orElse: () => _tournaments.first,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.emoji_events, size: 28, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item['name'] as String,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Format: ${item['badge']}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _standingsSection(CareerProvider game, int tournamentId) {
    if (tournamentId == t.tournamentFriendlies) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<InternationalStanding>>(
      future: game.getInternationalStandings(tournamentId),
      builder: (BuildContext context, AsyncSnapshot<List<InternationalStanding>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final List<InternationalStanding> list = snap.data ?? <InternationalStanding>[];
        if (list.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Belum ada klasemen yang terbentuk untuk kompetisi ini.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          );
        }

        // Group standings by group_id
        final Map<int, List<InternationalStanding>> byGroup = <int, List<InternationalStanding>>{};
        for (final InternationalStanding s in list) {
          final int gid = s.groupId ?? 1;
          byGroup.putIfAbsent(gid, () => <InternationalStanding>[]).add(s);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Klasemen Grup',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            ...byGroup.entries.map((MapEntry<int, List<InternationalStanding>> entry) {
              final String groupLetter = String.fromCharCode(65 + (entry.key - 1));
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Grup $groupLetter',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _tableHeader(),
                    const Divider(color: Colors.white12, height: 12),
                    ...entry.value.asMap().entries.map(
                      (MapEntry<int, InternationalStanding> e) =>
                          _tableRow(e.key + 1, e.value),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _tableHeader() {
    return const Row(
      children: <Widget>[
        SizedBox(width: 20, child: Text('#', style: TextStyle(fontSize: 10, color: AppTheme.textDim))),
        Expanded(child: Text('Tim', style: TextStyle(fontSize: 10, color: AppTheme.textDim))),
        SizedBox(width: 24, child: Text('M', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppTheme.textDim))),
        SizedBox(width: 24, child: Text('W', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppTheme.textDim))),
        SizedBox(width: 24, child: Text('D', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppTheme.textDim))),
        SizedBox(width: 24, child: Text('L', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppTheme.textDim))),
        SizedBox(width: 30, child: Text('GD', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppTheme.textDim))),
        SizedBox(width: 28, child: Text('P', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accent))),
      ],
    );
  }

  Widget _tableRow(int rank, InternationalStanding s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 11,
                fontWeight: rank <= 2 ? FontWeight.bold : FontWeight.normal,
                color: rank <= 2 ? AppTheme.accent : Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: Text(
              s.countryName.isNotEmpty ? s.countryName : _countryName(s.countryId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
          SizedBox(width: 24, child: Text('${s.played}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70))),
          SizedBox(width: 24, child: Text('${s.won}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70))),
          SizedBox(width: 24, child: Text('${s.drawn}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70))),
          SizedBox(width: 24, child: Text('${s.lost}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70))),
          SizedBox(width: 30, child: Text('${s.goalDifference > 0 ? '+' : ''}${s.goalDifference}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70))),
          SizedBox(width: 28, child: Text('${s.points}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accent))),
        ],
      ),
    );
  }

  Widget _matchesSection(CareerProvider game, int tournamentId) {
    return FutureBuilder<List<CountryMatch>>(
      future: game.getInternationalTournamentMatches(tournamentId),
      builder: (BuildContext context, AsyncSnapshot<List<CountryMatch>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final List<CountryMatch> matches = snap.data ?? <CountryMatch>[];
        if (matches.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Jadwal & Hasil Pertandingan',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            ...matches.map((CountryMatch m) => _matchRow(m)),
          ],
        );
      },
    );
  }

  Widget _matchRow(CountryMatch m) {
    final bool finished = m.status == t.matchFinished;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 70,
            child: Text(
              m.date ?? '-',
              style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
            ),
          ),
          Expanded(
            child: Text(
              _countryName(m.homeCountryId),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: finished ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              finished ? '${m.homeGoals ?? 0} - ${m.awayGoals ?? 0}' : 'vs',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: finished ? AppTheme.accent : AppTheme.textDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              _countryName(m.awayCountryId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-tab 2: National Team Squads
  // ---------------------------------------------------------------------------
  Widget _buildSquadViewerTab(CareerProvider game) {
    if (_loadingCountries) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        // Country Selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppTheme.surfaceCard,
          child: Row(
            children: <Widget>[
              const Icon(Icons.flag_outlined, size: 18, color: AppTheme.accent),
              const SizedBox(width: 8),
              const Text(
                'Pilih Timnas:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedCountryId != 0 ? _selectedCountryId : null,
                    isExpanded: true,
                    dropdownColor: AppTheme.surfaceCard,
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.accent),
                    items: _allCountries.map((Country c) {
                      return DropdownMenuItem<int>(
                        value: c.countryId,
                        child: Text(
                          c.name,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (int? id) {
                      if (id != null) setState(() => _selectedCountryId = id);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Squad list
        Expanded(
          child: _selectedCountryId == 0
              ? const Center(child: Text('Pilih negara'))
              : FutureBuilder<List<PlayerNationalStats>>(
                  future: game.getCountrySquad(_selectedCountryId),
                  builder: (BuildContext context, AsyncSnapshot<List<PlayerNationalStats>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<PlayerNationalStats> squad = snap.data ?? <PlayerNationalStats>[];
                    if (squad.isEmpty) {
                      return const Center(
                        child: Text(
                          'Skuad belum diumumkan untuk tim nasional ini.',
                          style: TextStyle(color: AppTheme.textDim),
                        ),
                      );
                    }

                    // Group squad by position
                    final List<PlayerNationalStats> gks = squad.where((PlayerNationalStats p) => p.positionId == t.posGoalkeeper).toList();
                    final List<PlayerNationalStats> defs = squad.where((PlayerNationalStats p) => p.positionId == t.posDefender).toList();
                    final List<PlayerNationalStats> mids = squad.where((PlayerNationalStats p) => p.positionId == t.posMidfielder).toList();
                    final List<PlayerNationalStats> atts = squad.where((PlayerNationalStats p) => p.positionId == t.posAttacker).toList();

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        _squadSectionHeader('Kiper (GK)', gks.length),
                        ...gks.map((PlayerNationalStats p) => _squadPlayerTile(context, p)),
                        const SizedBox(height: 12),

                        _squadSectionHeader('Bek (DEF)', defs.length),
                        ...defs.map((PlayerNationalStats p) => _squadPlayerTile(context, p)),
                        const SizedBox(height: 12),

                        _squadSectionHeader('Gelandang (MID)', mids.length),
                        ...mids.map((PlayerNationalStats p) => _squadPlayerTile(context, p)),
                        const SizedBox(height: 12),

                        _squadSectionHeader('Penyerang (ATT)', atts.length),
                        ...atts.map((PlayerNationalStats p) => _squadPlayerTile(context, p)),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _squadSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }

  Widget _squadPlayerTile(BuildContext context, PlayerNationalStats p) {
    return InkWell(
      onTap: () => showPlayerDetail(context, p.playerId),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '${p.shirtNumber ?? '-'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
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
                          p.playerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (p.isCaptain) ...<Widget>[
                        const SizedBox(width: 4),
                        const Icon(Icons.star, size: 13, color: Colors.amber),
                      ],
                    ],
                  ),
                  Text(
                    (p.clubName != null && p.clubName!.isNotEmpty)
                        ? p.clubName!
                        : (p.clubId > 0 ? 'Klub #${p.clubId}' : 'Free Agent'),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${p.caps} Caps · ${p.goals} Gol',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  'OVR ${p.power}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
