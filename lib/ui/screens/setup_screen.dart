import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import 'home_screen.dart';

/// Career setup wizard: country -> league -> club -> generate season.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int step = 0;
  Map<String, Object?>? selectedCountry;
  Map<String, Object?>? selectedLeague;
  Map<String, Object?>? selectedTeam;
  List<Map<String, Object?>> countryOptions = <Map<String, Object?>>[];
  List<Map<String, Object?>> leagueOptions = <Map<String, Object?>>[];
  List<Map<String, Object?>> teamOptions = <Map<String, Object?>>[];
  bool loadingOptions = false;
  bool generating = false;
  double generationProgress = 0;
  String generationStatus = '';
  String? error;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  CareerProvider get game => context.read<CareerProvider>();

  Future<void> _loadCountries() async {
    setState(() => loadingOptions = true);
    final List<Map<String, Object?>> countries = await game.playableCountries();
    if (!mounted) return;
    setState(() {
      countryOptions = countries;
      loadingOptions = false;
    });
  }

  Future<void> _selectCountry(Map<String, Object?> country) async {
    setState(() {
      selectedCountry = country;
      loadingOptions = true;
    });
    final List<Map<String, Object?>> leagues =
        await game.leaguesForCountry(country['country_id'] as int);
    if (!mounted) return;
    setState(() {
      leagueOptions = leagues;
      step = 1;
      loadingOptions = false;
    });
  }

  Future<void> _selectLeague(Map<String, Object?> league) async {
    setState(() {
      selectedLeague = league;
      loadingOptions = true;
    });
    final List<Map<String, Object?>> teams = await game.teamsForLeague(
      selectedCountry!['country_id'] as int,
      league['division_id'] as int,
    );
    if (!mounted) return;
    setState(() {
      teamOptions = teams;
      step = 2;
      loadingOptions = false;
    });
  }

  Future<void> _startCareer() async {
    setState(() {
      generating = true;
      generationProgress = 0;
    });
    final Tournament leagueTournament = await _tournamentById(
        selectedLeague!['tournament_id'] as int);
    try {
      await game.startCareer(
        countryId: selectedCountry!['country_id'] as int,
        leagueTournament: leagueTournament,
        teamId: selectedTeam!['team_id'] as int,
        onProgress: (String s) => setState(() {
          generationStatus = s;
          generationProgress = (generationProgress + 0.2).clamp(0.0, 1.0);
        }),
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

  Future<Tournament> _tournamentById(int id) async {
    final CareerProvider provider = context.read<CareerProvider>();
    // Reference repo access through a tiny public helper.
    final Tournament? t = await provider.tournamentById(id);
    if (t == null) throw StateError('Tournament $id missing');
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Career'),
        backgroundColor: AppTheme.surface,
      ),
      body: generating ? _generatingBody() : _stepsBody(),
    );
  }

  Widget _generatingBody() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(value: generationProgress > 0.05 ? generationProgress : null),
            const SizedBox(height: 18),
            Text(generationStatus.isEmpty
                ? 'Preparing world...'
                : generationStatus),
            const SizedBox(height: 8),
            const Text(
              'This bundles fixtures for every club in the season.',
              style: TextStyle(fontSize: 11, color: AppTheme.textDim),
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 18),
              Text(error!, style: const TextStyle(color: AppTheme.danger)),
            ],
          ],
        ),
      );

  Widget _stepsBody() {
    switch (step) {
      case 0:
        return _countryStep();
      case 1:
        return _leagueStep();
      default:
        return _teamStep();
    }
  }

  // ---------------------------------------------------------------- steps

  Widget _countryStep() => _optionList(
        title: 'Choose a country',
        subtitle: 'Sorted alphabetically by country',
        options: countryOptions,
        headline: (Map<String, Object?> o) => o['name'].toString(),
        subline: (Map<String, Object?> o) =>
            '${o['team_count']} clubs • ${o['league_count']} leagues • power ${(o['power'] as int?) ?? 0}',
        trailing: (Map<String, Object?> o) =>
            Text((o['iso2'] ?? '') as String, style: const TextStyle(color: AppTheme.textDim)),
        onPick: _selectCountry,
        emptyHint: 'No countries loaded',
      );

  Widget _leagueStep() => _optionList(
        title: 'Choose a league',
        subtitle: 'Only free leagues can be selected (see PRD quotas)',
        options: leagueOptions,
        headline: (Map<String, Object?> o) => o['name'].toString(),
        subline: (Map<String, Object?> o) => '${o['team_count']} clubs',
        onPick: _selectLeague,
        emptyHint: 'No leagues for this country',
      );

  Widget _teamStep() {
    return Column(
      children: <Widget>[
        Expanded(
          child: _optionList(
            title: 'Choose your club',
            subtitle: 'Higher power means stronger squad and budget',
            options: teamOptions,
            headline: (Map<String, Object?> o) => o['name'].toString(),
            subline: (Map<String, Object?> o) =>
                'power ${(o['power'] as int?) ?? 0} • value ${money((o['value'] as int?) ?? 0)} '
                '• budget ${money((o['budget'] as int?) ?? 0)}',
            onPick: (Map<String, Object?> o) => setState(() {
              selectedTeam = o;
              step = 3;
            }),
            emptyHint: 'No clubs found',
          ),
        ),
        if (selectedTeam != null)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.flag, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${selectedCountry!['name']} • '
                        '${selectedLeague!['name']}'
                        ' • ${selectedTeam!['name']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _startCareer,
                    child: const Text('Start Career — Generate Season'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _optionList({
    required String title,
    required String subtitle,
    required List<Map<String, Object?>> options,
    required String Function(Map<String, Object?>) headline,
    required String Function(Map<String, Object?>) subline,
    Widget Function(Map<String, Object?>)? trailing,
    required ValueChanged<Map<String, Object?>> onPick,
    required String emptyHint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textDim)),
        ),
        if (loadingOptions)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (options.isEmpty)
          Expanded(child: Center(child: Text(emptyHint)))
        else
          Expanded(
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (BuildContext context, int index) {
                final Map<String, Object?> option = options[index];
                return Card(
                  child: ListTile(
                    title: Text(
                      headline(option),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(subline(option)),
                    trailing: trailing?.call(option),
                    onTap: () => onPick(option),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
