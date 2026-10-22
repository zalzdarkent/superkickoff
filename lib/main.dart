import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/career_provider.dart';
import 'ui/screens/start_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider<CareerProvider>(
      create: (_) => CareerProvider()..init(),
      child: const SuperkickoffApp(),
    ),
  );
}

class SuperkickoffApp extends StatelessWidget {
  const SuperkickoffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Superkickoff',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const _BootGate(),
    );
  }
}

/// Waits for the provider bootstrap, then opens either the career hub or the
/// start screen.
class _BootGate extends StatelessWidget {
  const _BootGate();

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    if (!game.initialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 16),
              Text('Loading database...'),
            ],
          ),
        ),
      );
    }
    // A saved career always goes through Continue / New Career first.
    return const StartScreen();
  }
}
