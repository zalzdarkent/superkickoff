import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/country_names.dart';
import '../../data/db/schema.dart' as t;
import '../../data/models/models.dart';
import '../../game/international_tournament_service.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';

/// Screen displaying international windows, tournament standings, results,
/// national team squads, and user club player duty tracking.
class InternationalTab extends StatefulWidget {
  const InternationalTab({super.key});

  @override
  State<InternationalTab> createState() => _InternationalTabState();
}

class _InternationalTabState extends State<InternationalTab> {
  static const List<(int, String)> _confederations = <(int, String)>[
    (5, 'AFC (Asia)'),
    (3, 'UEFA (Eropa)'),
    (2, 'CONMEBOL'),
    (4, 'CAF (Afrika)'),
    (1, 'CONCACAF'),
    (6, 'OFC'),
  ];

  int _subTabIndex = 0;

  // Selected tournament for standings/fixtures
  int _selectedTournamentId = t.tournamentWorldCup;

  // Selected confederation for FIFA Ranking tab (null = All)
  int? _rankingConfederation;
  String _rankingSearch = '';

  // Selected country for squad viewer
  int _selectedCountryId = 0;
  // 0: Skuad Terpilih (23 pemain), 1: Semua Pemain (Eligible Pool), 2: Statistik Timnas
  int _squadViewMode = 0;
  // Metric for national team statistics: 'goals', 'assists', 'caps', 'rating'
  String _statsMetric = 'goals';
  List<Country> _allCountries = <Country>[];
  bool _loadingCountries = false;

  Country? _countryById(int id) {
    for (final Country c in _allCountries) {
      if (c.countryId == id) return c;
    }
    return null;
  }

  String _countryName(int id) {
    final Country? c = _countryById(id);
    return c != null ? c.name : 'Tim #$id';
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _subTabChip(0, 'Jadwal & Tugas', Icons.event_available_outlined),
                const SizedBox(width: 8),
                _subTabChip(1, 'Turnamen', Icons.emoji_events_outlined),
                const SizedBox(width: 8),
                _subTabChip(2, 'Ranking FIFA', Icons.format_list_numbered),
                const SizedBox(width: 8),
                _subTabChip(3, 'Skuad Timnas', Icons.groups_outlined),
              ],
            ),
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
        return _buildFifaRankingTab(game);
      case 3:
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
    <String, dynamic>{'id': t.tournamentWorldCupQualifiers, 'name': 'Kualifikasi World Cup', 'badge': 'Kualifikasi Benua'},
    <String, dynamic>{'id': t.tournamentEuro, 'name': 'UEFA EURO', 'badge': '24 Tim (6 Grup)'},
    <String, dynamic>{'id': t.tournamentEuroQualifiers, 'name': 'Kualifikasi EURO', 'badge': 'Kualifikasi Eropa'},
    <String, dynamic>{'id': t.tournamentAsianCup, 'name': 'AFC Asian Cup', 'badge': '24 Tim (6 Grup)'},
    <String, dynamic>{'id': t.tournamentAsianCupQualifiers, 'name': 'Kualifikasi Asian Cup', 'badge': 'Kualifikasi Asia'},
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

        // Group standings by group_id in ascending order
        final SplayTreeMap<int, List<InternationalStanding>> byGroup =
            SplayTreeMap<int, List<InternationalStanding>>();
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
              final int gIndex = entry.key - 1;
              final String groupLabel = gIndex >= 0 && gIndex < 26
                  ? 'Grup ${String.fromCharCode(65 + gIndex)}'
                  : 'Grup ${entry.key}';
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
                      groupLabel,
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
    final Country? c = _countryById(s.countryId);
    final String name = s.countryName.isNotEmpty ? s.countryName : _countryName(s.countryId);
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
          CountryFlagAvatar(
            iso2: c?.iso2,
            countryId: s.countryId,
            name: name,
            width: 20,
            height: 14,
            borderRadius: 3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
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
    final Country? homeC = _countryById(m.homeCountryId);
    final Country? awayC = _countryById(m.awayCountryId);
    final String homeName = _countryName(m.homeCountryId);
    final String awayName = _countryName(m.awayCountryId);
    return InkWell(
      onTap: () => _openCountryMatchDetail(m),
      borderRadius: BorderRadius.circular(10),
      child: Container(
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      homeName,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CountryFlagAvatar(
                    iso2: homeC?.iso2,
                    countryId: m.homeCountryId,
                    name: homeName,
                    width: 20,
                    height: 14,
                    borderRadius: 3,
                  ),
                ],
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
              child: Row(
                children: <Widget>[
                  CountryFlagAvatar(
                    iso2: awayC?.iso2,
                    countryId: m.awayCountryId,
                    name: awayName,
                    width: 20,
                    height: 14,
                    borderRadius: 3,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      awayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCountryMatchDetail(CountryMatch match) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => _CountryMatchDetailSheet(
        match: match,
        homeCountry: _countryById(match.homeCountryId),
        awayCountry: _countryById(match.awayCountryId),
      ),
    );
  }

  Future<void> _openCountryPickerSheet() async {
    final Country? picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) => _NationalTeamPickerSheet(
        countries: _allCountries,
        selectedCountryId: _selectedCountryId,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedCountryId = picked.countryId);
    }
  }

  // ---------------------------------------------------------------------------
  // Sub-tab 2: FIFA World Rankings
  // ---------------------------------------------------------------------------
  Widget _buildFifaRankingTab(CareerProvider game) {
    if (_loadingCountries) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter by confederation and search query
    List<Country> list = List<Country>.of(_allCountries);
    if (_rankingConfederation != null) {
      list = list.where((Country c) => c.confederation == _rankingConfederation).toList();
    }
    if (_rankingSearch.trim().isNotEmpty) {
      final String q = _rankingSearch.toLowerCase().trim();
      list = list.where((Country c) {
        return c.name.toLowerCase().contains(q) ||
            c.iso2.toLowerCase().contains(q) ||
            confederationLabel(c.confederation).toLowerCase().contains(q);
      }).toList();
    }

    final int userCountryId = game.userTeam?.countryId ?? 0;

    return Column(
      children: <Widget>[
        // Filter bar: Confederation chips
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              ChoiceChip(
                label: const Text('Semua'),
                selected: _rankingConfederation == null,
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _rankingConfederation == null ? FontWeight.bold : FontWeight.normal,
                  color: _rankingConfederation == null ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surfaceCard,
                side: BorderSide(
                  color: _rankingConfederation == null ? AppTheme.accent : Colors.white10,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _rankingConfederation = null);
                },
              ),
              const SizedBox(width: 8),
              ..._confederations.map(((int, String) item) {
                final int confId = item.$1;
                final String label = item.$2;
                final bool selected = _rankingConfederation == confId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
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
                      if (val) setState(() => _rankingConfederation = confId);
                    },
                  ),
                );
              }),
            ],
          ),
        ),

        // Search text box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            onChanged: (String val) => setState(() => _rankingSearch = val),
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Cari negara...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textDim),
              prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textDim),
              isDense: true,
              filled: true,
              fillColor: AppTheme.surfaceCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppTheme.surfaceCard,
          child: const Row(
            children: <Widget>[
              SizedBox(width: 44, child: Text('#', style: TextStyle(fontSize: 11, color: AppTheme.textDim, fontWeight: FontWeight.bold))),
              Expanded(child: Text('Negara', style: TextStyle(fontSize: 11, color: AppTheme.textDim, fontWeight: FontWeight.bold))),
              SizedBox(width: 70, child: Text('Konfederasi', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppTheme.textDim, fontWeight: FontWeight.bold))),
              SizedBox(width: 50, child: Text('Power', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),

        // List of ranked countries
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text(
                    'Tidak ada negara yang cocok.',
                    style: TextStyle(color: AppTheme.textDim, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (BuildContext context, int index) {
                    final Country c = list[index];
                    final int rank = index + 1;
                    final int? movement = c.rankMovement(rank);
                    final bool isUserCountry = c.countryId == userCountryId;

                    return Container(
                      color: isUserCountry ? AppTheme.accent.withValues(alpha: 0.1) : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: <Widget>[
                          // Rank & Movement
                          SizedBox(
                            width: 44,
                            child: Row(
                              children: <Widget>[
                                Text(
                                  '$rank',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: rank <= 10 || isUserCountry ? FontWeight.bold : FontWeight.normal,
                                    color: isUserCountry ? AppTheme.accent : Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                _movementIndicator(movement),
                              ],
                            ),
                          ),
                          // Flag & Name
                          CountryFlagAvatar(
                            iso2: c.iso2,
                            countryId: c.countryId,
                            name: c.name,
                            width: 22,
                            height: 15,
                            borderRadius: 3,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isUserCountry ? FontWeight.bold : FontWeight.w500,
                                color: isUserCountry ? AppTheme.accent : Colors.white,
                              ),
                            ),
                          ),
                          // Confederation
                          SizedBox(
                            width: 70,
                            child: Text(
                              confederationLabel(c.confederation),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                            ),
                          ),
                          // Power Rating
                          SizedBox(
                            width: 50,
                            child: Text(
                              '${c.power}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: rank <= 5 ? AppTheme.accent : Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _movementIndicator(int? delta) {
    if (delta == null || delta == 0) {
      return const Text(
        '-',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppTheme.textDim,
        ),
      );
    }
    final bool isUp = delta > 0;
    final Color color = isUp ? AppTheme.accent : AppTheme.danger;
    final int change = delta.abs();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(
          isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 13,
          color: color,
        ),
        Text(
          '$change',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-tab 3: National Team Squads
  // ---------------------------------------------------------------------------
  Widget _buildSquadViewerTab(CareerProvider game) {
    if (_loadingCountries) {
      return const Center(child: CircularProgressIndicator());
    }

    final Country? selectedCountry = _countryById(_selectedCountryId);

    return Column(
      children: <Widget>[
        // Searchable Country Selector Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppTheme.surfaceCard,
          child: InkWell(
            onTap: _openCountryPickerSheet,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: <Widget>[
                  CountryFlagAvatar(
                    iso2: selectedCountry?.iso2,
                    countryId: selectedCountry?.countryId,
                    name: selectedCountry?.name,
                    width: 36,
                    height: 25,
                    borderRadius: 4,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          selectedCountry?.name ?? 'Pilih Negara',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (selectedCountry != null)
                          Text(
                            '${confederationLabel(selectedCountry.confederation)} • Power ${selectedCountry.power}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textDim,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.search, size: 15, color: AppTheme.accent),
                        SizedBox(width: 4),
                        Text(
                          'Pilih Timnas',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // View Mode Selector: Skuad Terpilih vs Semua Pemain vs Statistik Timnas
        Container(
          height: 48,
          color: AppTheme.surfaceCard,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              ChoiceChip(
                label: const Text('Skuad Terpilih (23)'),
                selected: _squadViewMode == 0,
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _squadViewMode == 0 ? FontWeight.bold : FontWeight.normal,
                  color: _squadViewMode == 0 ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: _squadViewMode == 0 ? AppTheme.accent : Colors.white12,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _squadViewMode = 0);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Semua Pemain Negara'),
                selected: _squadViewMode == 1,
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _squadViewMode == 1 ? FontWeight.bold : FontWeight.normal,
                  color: _squadViewMode == 1 ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: _squadViewMode == 1 ? AppTheme.accent : Colors.white12,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _squadViewMode = 1);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Statistik & Rekor Timnas'),
                selected: _squadViewMode == 2,
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _squadViewMode == 2 ? FontWeight.bold : FontWeight.normal,
                  color: _squadViewMode == 2 ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: _squadViewMode == 2 ? AppTheme.accent : Colors.white12,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _squadViewMode = 2);
                },
              ),
            ],
          ),
        ),

        // Squad list or Stats Leaderboard
        Expanded(
          child: _selectedCountryId == 0
              ? const Center(child: Text('Pilih negara'))
              : _squadViewMode == 2
                  ? _buildCountryStatsView(game)
                  : FutureBuilder<List<PlayerNationalStats>>(
                  future: _squadViewMode == 0
                      ? game.getCountrySquad(_selectedCountryId)
                      : game.getEligiblePlayersPool(_selectedCountryId),
                  builder: (BuildContext context, AsyncSnapshot<List<PlayerNationalStats>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<PlayerNationalStats> squad = snap.data ?? <PlayerNationalStats>[];
                    if (squad.isEmpty) {
                      return Center(
                        child: Text(
                          _squadViewMode == 0
                              ? 'Skuad belum diumumkan untuk tim nasional ini.'
                              : 'Tidak ada pemain terdaftar untuk negara ini.',
                          style: const TextStyle(color: AppTheme.textDim),
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

  // ---------------------------------------------------------------------------
  // Sub-view: National Team Statistics & Records
  // ---------------------------------------------------------------------------
  Widget _buildCountryStatsView(CareerProvider game) {
    return Column(
      children: <Widget>[
        // Metric selection chips
        Container(
          height: 44,
          color: AppTheme.surfaceCard.withValues(alpha: 0.5),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              ChoiceChip(
                label: const Text('Top Skor (Gol)'),
                selected: _statsMetric == 'goals',
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _statsMetric == 'goals' ? FontWeight.bold : FontWeight.normal,
                  color: _statsMetric == 'goals' ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: _statsMetric == 'goals' ? AppTheme.accent : Colors.white12,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _statsMetric = 'goals');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Top Assist'),
                selected: _statsMetric == 'assists',
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _statsMetric == 'assists' ? FontWeight.bold : FontWeight.normal,
                  color: _statsMetric == 'assists' ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: _statsMetric == 'assists' ? AppTheme.accent : Colors.white12,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _statsMetric = 'assists');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Caps (Penampilan)'),
                selected: _statsMetric == 'caps',
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _statsMetric == 'caps' ? FontWeight.bold : FontWeight.normal,
                  color: _statsMetric == 'caps' ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: _statsMetric == 'caps' ? AppTheme.accent : Colors.white12,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _statsMetric = 'caps');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Rating Tertinggi'),
                selected: _statsMetric == 'rating',
                selectedColor: AppTheme.accent,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: _statsMetric == 'rating' ? FontWeight.bold : FontWeight.normal,
                  color: _statsMetric == 'rating' ? Colors.black : Colors.white70,
                ),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: _statsMetric == 'rating' ? AppTheme.accent : Colors.white12,
                ),
                onSelected: (bool val) {
                  if (val) setState(() => _statsMetric = 'rating');
                },
              ),
            ],
          ),
        ),

        // Leaderboard List
        Expanded(
          child: FutureBuilder<List<LeaderRow>>(
            future: game.getCountryLeaders(
              _selectedCountryId,
              metric: _statsMetric,
              limit: 50,
            ),
            builder: (BuildContext context, AsyncSnapshot<List<LeaderRow>> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<LeaderRow> rows = snap.data ?? <LeaderRow>[];
              if (rows.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Belum ada data statistik untuk ${_countryName(_selectedCountryId)}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                    ),
                  ),
                );
              }

              final String headerLabel = switch (_statsMetric) {
                'goals' => 'GOL',
                'assists' => 'ASSIST',
                'caps' => 'CAPS',
                'rating' => 'RTG',
                _ => 'TOTAL',
              };

              return Column(
                children: <Widget>[
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppTheme.surfaceCard,
                    child: Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 30,
                          child: Text(
                            '#',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textDim,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 38,
                          child: Text(
                            'POS',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textDim,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Pemain',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textDim,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            headerLabel,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textDim,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // List of Leaders
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        color: Colors.white10,
                      ),
                      itemBuilder: (BuildContext context, int index) {
                        final LeaderRow row = rows[index];
                        final bool isTop3 = index < 3;

                        return InkWell(
                          onTap: () => showPlayerDetail(context, row.playerId),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isTop3 ? FontWeight.bold : FontWeight.normal,
                                      color: isTop3 ? AppTheme.accent : AppTheme.textDim,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 38,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: PositionBadge(
                                      positionId: row.positionId,
                                      profile: row.profile,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        row.playerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        row.clubName.isNotEmpty ? row.clubName : 'Free Agent',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textDim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    _statsMetric == 'rating'
                                        ? row.value.toStringAsFixed(1)
                                        : '${row.value.toInt()}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isTop3 ? AppTheme.accent : Colors.white,
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
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NationalTeamPickerSheet extends StatefulWidget {
  const _NationalTeamPickerSheet({
    required this.countries,
    required this.selectedCountryId,
  });

  final List<Country> countries;
  final int selectedCountryId;

  @override
  State<_NationalTeamPickerSheet> createState() =>
      _NationalTeamPickerSheetState();
}

class _NationalTeamPickerSheetState extends State<_NationalTeamPickerSheet> {
  String _searchQuery = '';
  int _selectedConfederation = 0; // 0 = Semua
  bool _sortByAlphabet = true;

  static const List<(int, String)> _confederations = <(int, String)>[
    (0, 'Semua'),
    (5, 'AFC (Asia)'),
    (3, 'UEFA (Eropa)'),
    (2, 'CONMEBOL'),
    (4, 'CAF (Afrika)'),
    (1, 'CONCACAF'),
    (6, 'OFC'),
  ];

  @override
  Widget build(BuildContext context) {
    final String q = _searchQuery.trim().toLowerCase();
    final List<Country> filtered = widget.countries.where((Country c) {
      if (_selectedConfederation != 0 &&
          c.confederation != _selectedConfederation) {
        return false;
      }
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.iso2.toLowerCase().contains(q) ||
          confederationLabel(c.confederation).toLowerCase().contains(q);
    }).toList();

    filtered.sort((Country a, Country b) {
      if (_sortByAlphabet) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      final int cmp = b.power.compareTo(a.power);
      return cmp != 0
          ? cmp
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: <Widget>[
            // Handle & Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.public, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pilih Tim Nasional (${filtered.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        setState(() => _sortByAlphabet = !_sortByAlphabet),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _sortByAlphabet
                                ? Icons.sort_by_alpha
                                : Icons.trending_up,
                            size: 14,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _sortByAlphabet ? 'Urut: A-Z' : 'Urut: Power',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                autofocus: true,
                onChanged: (String v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Cari negara (mis. Indonesia, Jerman, Jepang)...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surfaceCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Confederation Filter Chips
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: _confederations.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (BuildContext context, int i) {
                  final (int confId, String label) = _confederations[i];
                  final bool active = _selectedConfederation == confId;
                  return ChoiceChip(
                    label: Text(label),
                    selected: active,
                    selectedColor: AppTheme.accent,
                    backgroundColor: AppTheme.surfaceCard,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active ? Colors.black : Colors.white70,
                    ),
                    side: BorderSide(
                      color: active ? AppTheme.accent : Colors.white10,
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedConfederation = confId),
                  );
                },
              ),
            ),

            const Divider(color: Colors.white10, height: 8),

            // Country List
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Negara tidak ditemukan.',
                        style: TextStyle(color: AppTheme.textDim),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Country c = filtered[i];
                        final bool selected =
                            c.countryId == widget.selectedCountryId;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          color: selected
                              ? AppTheme.accent.withValues(alpha: 0.12)
                              : AppTheme.surfaceCard,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selected
                                  ? AppTheme.accent
                                  : Colors.white10,
                              width: selected ? 1.4 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () => Navigator.pop(context, c),
                            leading: CountryFlagAvatar(
                              iso2: c.iso2,
                              countryId: c.countryId,
                              name: c.name,
                              width: 36,
                              height: 25,
                              borderRadius: 4,
                            ),
                            title: Text(
                              c.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              '${confederationLabel(c.confederation)} • ${c.iso2.toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textDim,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
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
                                    'OVR ${c.power}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  selected
                                      ? Icons.check_circle
                                      : Icons.chevron_right,
                                  size: 18,
                                  color: selected
                                      ? AppTheme.accent
                                      : AppTheme.textDim,
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
  }
}

/// Bottom sheet displaying the full details, scores, and lineup ratings
/// for a country match.
class _CountryMatchDetailSheet extends StatelessWidget {
  const _CountryMatchDetailSheet({
    required this.match,
    required this.homeCountry,
    required this.awayCountry,
  });

  final CountryMatch match;
  final Country? homeCountry;
  final Country? awayCountry;

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final bool isFinished = match.status == t.matchFinished;
    final String homeName = homeCountry?.name ?? 'Negara #${match.homeCountryId}';
    final String awayName = awayCountry?.name ?? 'Negara #${match.awayCountryId}';

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Grabber handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header: Tournament / Date / Status
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    match.date ?? 'Jadwal Pertandingan',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isFinished
                        ? AppTheme.accent.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isFinished ? AppTheme.accent.withValues(alpha: 0.3) : Colors.white10,
                    ),
                  ),
                  child: Text(
                    isFinished ? 'SELESAI' : 'TERJADWAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isFinished ? AppTheme.accent : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Scoreboard Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: <Widget>[
                  // Home Team
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        CountryFlagAvatar(
                          iso2: homeCountry?.iso2,
                          countryId: match.homeCountryId,
                          name: homeName,
                          width: 44,
                          height: 30,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          homeName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (homeCountry != null)
                          Text(
                            'OVR ${homeCountry!.power}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                          ),
                      ],
                    ),
                  ),

                  // Score Center
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: <Widget>[
                        Text(
                          isFinished ? '${match.homeGoals ?? 0} - ${match.awayGoals ?? 0}' : 'VS',
                          style: TextStyle(
                            fontSize: isFinished ? 28 : 20,
                            fontWeight: FontWeight.w900,
                            color: isFinished ? AppTheme.accent : AppTheme.textDim,
                          ),
                        ),
                        if (isFinished &&
                            match.penaltyHomeGoals != null &&
                            match.penaltyAwayGoals != null)
                          Text(
                            'Pen: ${match.penaltyHomeGoals} - ${match.penaltyAwayGoals}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                          ),
                      ],
                    ),
                  ),

                  // Away Team
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        CountryFlagAvatar(
                          iso2: awayCountry?.iso2,
                          countryId: match.awayCountryId,
                          name: awayName,
                          width: 44,
                          height: 30,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          awayName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (awayCountry != null)
                          Text(
                            'OVR ${awayCountry!.power}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Player Ratings and Stats Section
            Expanded(
              child: isFinished
                  ? FutureBuilder<List<Map<String, Object?>>>(
                      future: game.getCountryMatchPlayers(match.matchId),
                      builder: (BuildContext context, AsyncSnapshot<List<Map<String, Object?>>> snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final List<Map<String, Object?>> players = snap.data ?? <Map<String, Object?>>[];
                        if (players.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Statistik susunan pemain tidak tercatat untuk laga ini.',
                                style: TextStyle(color: AppTheme.textDim, fontSize: 12),
                              ),
                            ),
                          );
                        }

                        final List<Map<String, Object?>> homePlayers = players
                            .where((r) => (r['country_id'] as int?) == match.homeCountryId)
                            .toList();
                        final List<Map<String, Object?>> awayPlayers = players
                            .where((r) => (r['country_id'] as int?) == match.awayCountryId)
                            .toList();

                        return DefaultTabController(
                          length: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TabBar(
                                indicatorColor: AppTheme.accent,
                                labelColor: AppTheme.accent,
                                unselectedLabelColor: AppTheme.textDim,
                                tabs: <Widget>[
                                  Tab(text: homeName),
                                  Tab(text: awayName),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: <Widget>[
                                    _playerListView(context, homePlayers),
                                    _playerListView(context, awayPlayers),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(Icons.timer_outlined, size: 40, color: AppTheme.textDim),
                            const SizedBox(height: 10),
                            const Text(
                              'Pertandingan Belum Dimainkan',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Laga dijadwalkan pada tanggal ${match.date ?? '-'}. Skor dan susunan pemain akan tampil setelah tanggal tersebut lewat.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerListView(BuildContext context, List<Map<String, Object?>> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada data pemain.',
          style: TextStyle(color: AppTheme.textDim, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (BuildContext ctx, int i) {
        final Map<String, Object?> p = list[i];
        final int playerId = (p['player_id'] as int?) ?? 0;
        final String name = (p['player_name'] as String?) ?? 'Player #$playerId';
        final String pos = (p['position_abbr'] as String?) ?? '-';
        final int mins = (p['minutes'] as int?) ?? 0;
        final int goals = (p['goals'] as int?) ?? 0;
        final int assists = (p['assists'] as int?) ?? 0;
        final int yellows = (p['yellow_cards'] as int?) ?? 0;
        final int reds = (p['red_cards'] as int?) ?? 0;
        final double rating = (p['rating'] as num?)?.toDouble() ?? 6.0;
        final bool mvp = ((p['mvp'] as int?) ?? 0) == 1;
        final bool starter = ((p['starter'] as int?) ?? 0) == 1;

        return InkWell(
          onTap: () => showPlayerDetail(context, playerId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                // Position badge
                Container(
                  width: 32,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: starter
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    pos,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: starter ? Colors.white : AppTheme.textDim,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Name & stats badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: starter ? FontWeight.w600 : FontWeight.normal,
                                color: starter ? Colors.white : Colors.white70,
                              ),
                            ),
                          ),
                          if (mvp) ...<Widget>[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amber, width: 0.6),
                              ),
                              child: const Text(
                                'MVP',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Text(
                            '$mins\'',
                            style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                          ),
                          if (goals > 0) ...<Widget>[
                            const SizedBox(width: 6),
                            const Icon(Icons.sports_soccer, size: 10, color: AppTheme.accent),
                            const SizedBox(width: 2),
                            Text(
                              goals > 1 ? '$goals' : '',
                              style: const TextStyle(fontSize: 10, color: AppTheme.accent),
                            ),
                          ],
                          if (assists > 0) ...<Widget>[
                            const SizedBox(width: 6),
                            Text(
                              'A: $assists',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF64B5F6)),
                            ),
                          ],
                          if (yellows > 0) ...<Widget>[
                            const SizedBox(width: 6),
                            Container(
                              width: 7,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ],
                          if (reds > 0) ...<Widget>[
                            const SizedBox(width: 4),
                            Container(
                              width: 7,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Rating Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: rating >= 7.5
                        ? AppTheme.accent.withValues(alpha: 0.2)
                        : (rating >= 6.0 ? Colors.white10 : Colors.red.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: rating >= 7.5
                          ? AppTheme.accent
                          : (rating >= 6.0 ? Colors.white12 : Colors.redAccent),
                      width: 0.6,
                    ),
                  ),
                  child: Text(
                    rating.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: rating >= 7.5
                          ? AppTheme.accent
                          : (rating >= 6.0 ? Colors.white : Colors.redAccent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
