import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

typedef _Row = Map<String, Object?>;

/// Career setup wizard: profile -> league country -> division -> club.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const List<String> _stepTitles = <String>[
    'Profile',
    'League',
    'Division',
    'Club',
  ];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  int step = 0;
  _Row? nationality;
  _Row? selectedCountry;
  _Row? selectedLeague;
  _Row? selectedTeam;
  List<_Row> allCountries = <_Row>[];
  List<_Row> leagueCountries = <_Row>[];
  List<_Row> leagueOptions = <_Row>[];
  List<_Row> teamOptions = <_Row>[];
  bool loadingOptions = false;
  bool generating = false;
  String generationStatus = '';
  String? error;

  CareerProvider get game => context.read<CareerProvider>();

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    setState(() => loadingOptions = true);
    final List<_Row> all = await game.allCountries();
    final List<_Row> playable = await game.playableCountries();
    if (!mounted) return;
    setState(() {
      allCountries = all;
      leagueCountries = playable;
      loadingOptions = false;
    });
  }

  void _goTo(int next) => setState(() {
    step = next;
    error = null;
    _searchController.clear();
  });

  Future<void> _toLeagueStep() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => error = 'Enter your manager name first.');
      return;
    }
    if (nationality == null) {
      setState(() => error = 'Pick your nationality.');
      return;
    }
    // Put the manager's own country first: the most likely league to manage.
    final int home = nationality!['country_id'] as int;
    leagueCountries = List<_Row>.of(leagueCountries)..sort((_Row a, _Row b) {
      final int ra = a['country_id'] == home ? 0 : 1;
      final int rb = b['country_id'] == home ? 0 : 1;
      return ra != rb
          ? ra - rb
          : a['name'].toString().compareTo(b['name'].toString());
    });
    _goTo(1);
  }

  Future<void> _selectCountry(_Row country) async {
    setState(() {
      selectedCountry = country;
      loadingOptions = true;
    });
    final List<_Row> leagues = await game.leaguesForCountry(
      country['country_id'] as int,
    );
    if (!mounted) return;
    setState(() => loadingOptions = false);
    _goTo(2);
    setState(() => leagueOptions = leagues);
  }

  Future<void> _selectLeague(_Row league) async {
    setState(() {
      selectedLeague = league;
      selectedTeam = null;
      loadingOptions = true;
    });
    final List<_Row> teams = await game.teamsForLeague(
      selectedCountry!['country_id'] as int,
      league['division_id'] as int,
    );
    teams.sort(
      (_Row a, _Row b) =>
          ((b['power'] as int?) ?? 0).compareTo((a['power'] as int?) ?? 0),
    );
    if (!mounted) return;
    setState(() => loadingOptions = false);
    _goTo(3);
    setState(() => teamOptions = teams);
  }

  Future<void> _startCareer() async {
    setState(() {
      generating = true;
      error = null;
    });
    try {
      final Tournament? league = await game.tournamentById(
        selectedLeague!['tournament_id'] as int,
      );
      if (league == null) throw StateError('League missing');
      await game.startCareer(
        managerName: _nameController.text.trim(),
        nationalityId: nationality!['country_id'] as int,
        countryId: selectedCountry!['country_id'] as int,
        leagueTournament: league,
        teamId: selectedTeam!['team_id'] as int,
        onProgress: (String s) => setState(() => generationStatus = s),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (Route<dynamic> route) => false,
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        error = '$err';
        generating = false;
      });
    }
  }

  /// ISO-3166 alpha-2 -> flag emoji.
  String _flag(Object? iso2) {
    final String code = '${iso2 ?? ''}'.toUpperCase();
    if (code.length != 2) return '🏳️';
    return String.fromCharCodes(
      code.codeUnits.map((int c) => 0x1F1E6 + c - 0x41),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == 0 || generating,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _goTo(step - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Career'),
          leading: BackButton(
            onPressed: () =>
                step == 0 || generating ? Navigator.pop(context) : _goTo(step - 1),
          ),
        ),
        body: SafeArea(
          child: generating
              ? _generatingBody()
              : Column(
                  children: <Widget>[
                    _stepper(),
                    Expanded(child: _stepBody()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _stepper() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: <Widget>[
        for (int i = 0; i < _stepTitles.length; i++) ...<Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? AppTheme.accent : AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _stepTitles[i],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: i == step ? FontWeight.bold : FontWeight.w400,
                    color: i == step ? Colors.white : AppTheme.textDim,
                  ),
                ),
              ],
            ),
          ),
          if (i < _stepTitles.length - 1) const SizedBox(width: 6),
        ],
      ],
    ),
  );

  Widget _generatingBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            generationStatus.isEmpty ? 'Preparing world...' : generationStatus,
          ),
          const SizedBox(height: 8),
          const Text(
            'Building fixtures for every club in the season.',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
        ],
      ),
    ),
  );

  Widget _stepBody() {
    switch (step) {
      case 0:
        return _profileStep();
      case 1:
        return _leagueCountryStep();
      case 2:
        return _divisionStep();
      default:
        return _clubStep();
    }
  }

  Widget _header(String title, String subtitle) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
        ),
      ],
    ),
  );

  Widget _bottomBar({required String label, VoidCallback? onPressed, Widget? summary}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AppTheme.surfaceCard,
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                ),
              ),
            ?summary,
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onPressed, child: Text(label)),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------- steps

  Widget _profileStep() => Column(
    children: <Widget>[
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: <Widget>[
            _header('Who are you?', 'Create your manager profile.'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
                decoration: const InputDecoration(
                  labelText: 'Manager name',
                  hintText: 'e.g. Budi Santoso',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: _pickNationality,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Nationality',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  child: nationality == null
                      ? const Text(
                          'Select country',
                          style: TextStyle(fontSize: 16, color: AppTheme.textDim),
                        )
                      : Row(
                          children: <Widget>[
                            CountryFlagAvatar(
                              iso2: nationality!['iso2'],
                              countryId: nationality!['country_id'] as int?,
                              name: nationality!['name']?.toString(),
                              width: 28,
                              height: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                nationality!['name'].toString(),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      _bottomBar(label: 'Continue', onPressed: _toLeagueStep),
    ],
  );

  Future<void> _pickNationality() async {
    final _Row? picked = await showModalBottomSheet<_Row>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (BuildContext ctx) => _CountrySheet(
        countries: allCountries,
        flag: _flag,
      ),
    );
    if (picked != null) setState(() => nationality = picked);
  }

  Widget _searchBox(String hint) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
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
  );

  Widget _leagueCountryStep() {
    final String q = _searchController.text.trim().toLowerCase();
    final List<_Row> shown = leagueCountries
        .where((_Row c) => c['name'].toString().toLowerCase().contains(q))
        .toList();
    final int? home = nationality?['country_id'] as int?;
    return Column(
      children: <Widget>[
        _header(
          'Where do you want to manage?',
          'Pick the country whose league you will play in.',
        ),
        _searchBox('Search country'),
        Expanded(
          child: loadingOptions
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int i) {
                    final _Row c = shown[i];
                    return _tile(
                      leadingWidget: CountryFlagAvatar(
                        iso2: c['iso2'],
                        countryId: c['country_id'] as int?,
                        name: c['name']?.toString(),
                        width: 34,
                        height: 24,
                      ),
                      title: c['name'].toString(),
                      subtitle:
                          '${c['team_count']} clubs • ${c['league_count']} divisions',
                      badge: c['country_id'] == home ? 'Your country' : null,
                      onTap: () => _selectCountry(c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _divisionStep() => Column(
    children: <Widget>[
      _header(
        '${selectedCountry!['name']}',
        'Choose a division.',
      ),
      Expanded(
        child: loadingOptions
            ? const Center(child: CircularProgressIndicator())
            : leagueOptions.isEmpty
            ? const Center(child: Text('No leagues for this country'))
            : ListView.builder(
                itemCount: leagueOptions.length,
                itemBuilder: (BuildContext context, int i) {
                  final _Row l = leagueOptions[i];
                  return _tile(
                    leadingWidget: TournamentAvatar(
                      name: l['name'].toString(),
                      logoBase64: l['logo_base64'] as String?,
                      radius: 20,
                    ),
                    title: l['name'].toString(),
                    subtitle: '${l['team_count']} clubs',
                    onTap: () => _selectLeague(l),
                  );
                },
              ),
      ),
    ],
  );

  Widget _clubStep() {
    final String q = _searchController.text.trim().toLowerCase();
    final List<_Row> shown = teamOptions
        .where((_Row t) => t['name'].toString().toLowerCase().contains(q))
        .toList();
    final String leagueName = selectedLeague!['name'].toString();
    final String? leagueLogo = selectedLeague!['logo_base64'] as String?;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: <Widget>[
              if (leagueLogo != null && leagueLogo.isNotEmpty) ...<Widget>[
                TournamentAvatar(
                  name: leagueName,
                  logoBase64: leagueLogo,
                  radius: 20,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      leagueName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Choose your club.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _searchBox('Search club'),
        Expanded(
          child: loadingOptions
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int i) {
                    final _Row t = shown[i];
                    final bool picked =
                        selectedTeam?['team_id'] == t['team_id'];
                    return _tile(
                      leadingWidget: CrestAvatar.raw(
                        teamId: (t['team_id'] as int?) ?? 0,
                        name: t['name'].toString(),
                        abbreviation: (t['abbreviation'] as String?) ?? '',
                        logoBase64: t['logo_base64'] as String?,
                        radius: 20,
                      ),
                      title: t['name'].toString(),
                      subtitle:
                          'Value ${money((t['value'] as int?) ?? 0)} • Budget ${money((t['budget'] as int?) ?? 0)}',
                      ratingBadge: '${(t['power'] as int?) ?? 0}',
                      selected: picked,
                      onTap: () => setState(() => selectedTeam = t),
                    );
                  },
                ),
        ),
        if (selectedTeam != null)
          _bottomBar(
            label: 'Start Career',
            onPressed: _startCareer,
            summary: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  CrestAvatar.raw(
                    teamId: (selectedTeam!['team_id'] as int?) ?? 0,
                    name: selectedTeam!['name'].toString(),
                    abbreviation: (selectedTeam!['abbreviation'] as String?) ?? '',
                    logoBase64: selectedTeam!['logo_base64'] as String?,
                    radius: 12,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_nameController.text.trim()} • ${selectedTeam!['name']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Shared list row: [leading] is an emoji flag or a short number badge,
  /// or [leadingWidget] for custom badges/crests.
  Widget _tile({
    String? leading,
    Widget? leadingWidget,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    String? ratingBadge,
    bool selected = false,
  }) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? AppTheme.accent : Colors.transparent,
        width: 1.5,
      ),
    ),
    child: ListTile(
      onTap: onTap,
      leading: leadingWidget ??
          CircleAvatar(
            backgroundColor: AppTheme.surface,
            child: Text(leading ?? '', style: const TextStyle(fontSize: 18)),
          ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (ratingBadge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                ratingBadge,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.accent,
                ),
              ),
            ),
          if (badge != null)
            Chip(
              label: Text(badge),
              backgroundColor: AppTheme.accentDim,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            )
          else
            Icon(
              selected ? Icons.check_circle : Icons.chevron_right,
              color: selected ? AppTheme.accent : AppTheme.textDim,
            ),
        ],
      ),
    ),
  );
}

/// Searchable country list shown as a bottom sheet.
class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.countries, required this.flag});

  final List<_Row> countries;
  final String Function(Object?) flag;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final List<_Row> shown = widget.countries
        .where((_Row c) => c['name'].toString().toLowerCase().contains(q))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (String v) => setState(() => q = v.toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search nationality',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (BuildContext context, int i) => ListTile(
                  leading: CountryFlagAvatar(
                    iso2: shown[i]['iso2'],
                    countryId: shown[i]['country_id'] as int?,
                    name: shown[i]['name']?.toString(),
                    width: 32,
                    height: 22,
                  ),
                  title: Text(shown[i]['name'].toString()),
                  onTap: () => Navigator.pop(context, shown[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
