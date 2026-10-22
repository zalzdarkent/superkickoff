import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/career_provider.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

/// Entry screen with Continue / New Career.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF052E16), AppTheme.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.sports_soccer,
                    size: 56,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'SUPERKICKOFF',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const Text(
                  'Football Career Manager',
                  style: TextStyle(color: AppTheme.textDim),
                ),
                const SizedBox(height: 44),
                if (game.busy)
                  const CircularProgressIndicator()
                else ...<Widget>[
                  if (game.hasCareer)
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Continue Career'),
                      onPressed: () async {
                        await context.read<CareerProvider>().continueCareer();
                        if (!context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HomeScreen(),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('New Career'),
                    onPressed: () async {
                      if (game.hasCareer) {
                        final bool? replace = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: const Text('Start a new career?'),
                            content: const Text(
                              'This permanently replaces the current local save.',
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Replace'),
                              ),
                            ],
                          ),
                        );
                        if (replace != true) return;
                        await game.newCareer();
                      }
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SetupScreen(),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 40),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.star, color: AppTheme.accent, size: 14),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
