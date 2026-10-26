import '../data/models/models.dart';

/// The ordered stages of the break between two seasons. The manager must work
/// through them one by one; a stage only opens once the previous one is done.
enum OffseasonStep {
  summary('Season review', 'How the season ended'),
  contracts('Contracts & retirements', 'Renew expiring deals, say goodbye'),
  development('Player development', 'Who grew, who faded'),
  transfers('Transfer window', 'Buy and sell before the deadline'),
  preseason('Pre-season camp', 'Prepare the squad for the new campaign'),
  board('Board & objectives', 'Agree the target for next season'),
  newSeason('New season', 'Kick-off');

  const OffseasonStep(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// Persisted progress of the off-season (single row, survives save/load).
class OffseasonState {
  const OffseasonState({
    required this.seasonId,
    required this.step,
    required this.report,
    required this.windowWeeks,
    this.camp,
    this.ambition,
  });

  final int seasonId;
  final int step;
  final String report;
  final int windowWeeks;
  final String? camp;
  final String? ambition;

  OffseasonStep get current => OffseasonStep.values[step];

  List<String> get reportLines =>
      report.isEmpty ? <String>[] : report.split('\n');

  factory OffseasonState.fromMap(Map<String, Object?> m) => OffseasonState(
    seasonId: m['season_id'] as int,
    step: (m['step'] as int?) ?? 0,
    report: (m['report'] as String?) ?? '',
    windowWeeks: (m['window_weeks'] as int?) ?? 0,
    camp: m['camp'] as String?,
    ambition: m['ambition'] as String?,
  );
}

/// A user player whose contract runs out this summer.
class ExpiringContract {
  const ExpiringContract({
    required this.player,
    required this.endDate,
    required this.newSalary,
    required this.signingBonus,
  });

  final Player player;
  final String endDate;
  final int newSalary;
  final int signingBonus;
}

/// Pre-season camp choices. Costs are negative income for [tour].
enum PreseasonCamp {
  rest('Rest & recover', 'Free. The squad returns fully fit.', 0),
  training(
    'Intensive training camp',
    'Costs \$400K. Squad fully fit and up to three young players gain +1 power.',
    400000,
  ),
  tour(
    'Commercial tour',
    'Earns \$750K from friendlies abroad, but the squad is only 85% fit.',
    -750000,
  );

  const PreseasonCamp(this.label, this.description, this.cost);

  final String label;
  final String description;
  final int cost;

  static PreseasonCamp? fromKey(String? key) {
    for (final PreseasonCamp c in PreseasonCamp.values) {
      if (c.name == key) return c;
    }
    return null;
  }
}

/// How demanding the board's target for next season is.
enum BoardAmbition {
  safe('Safe', 'A comfortable target.', 3, 0.03),
  balanced(
    'Realistic',
    'Finish where the squad strength says we should.',
    0,
    0.07,
  ),
  ambitious('Ambitious', 'Punch above our weight.', -3, 0.15);

  const BoardAmbition(this.label, this.description, this.rankOffset, this.rate);

  final String label;
  final String description;

  /// Added to the club's expected rank (negative = a better finish).
  final int rankOffset;

  /// Share of the club budget paid as bonus when the target is met.
  final double rate;

  static BoardAmbition? fromKey(String? key) {
    for (final BoardAmbition a in BoardAmbition.values) {
      if (a.name == key) return a;
    }
    return null;
  }
}

/// A concrete objective offer shown on the board stage.
class BoardOption {
  const BoardOption({
    required this.ambition,
    required this.targetRank,
    required this.bonus,
  });

  final BoardAmbition ambition;
  final int targetRank;
  final int bonus;

  /// Paid up front as extra transfer budget.
  int get advance => bonus ~/ 2;
}
