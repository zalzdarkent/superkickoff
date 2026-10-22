/// Training focus groups. Position ids follow the game's database mapping:
/// 1 GK, 2-3 CB, 4 FB, 5 CDM, 6 CAM, 7 CM, 8-9 wingers, 10 ST, 11 CF.
enum TrainingFocus {
  attack(
    label: 'Attack',
    description: 'Forwards and wingers gain power and sharpness.',
    positionIds: <int>[8, 9, 10, 11],
  ),
  midfield(
    label: 'Midfield',
    description: 'Central and wide midfielders work on their overall game.',
    positionIds: <int>[5, 6, 7],
  ),
  defence(
    label: 'Defence',
    description: 'Centre-backs and full-backs improve their defensive power.',
    positionIds: <int>[2, 3, 4],
  ),
  goalkeeper(
    label: 'Goalkeeper',
    description: 'Your keepers work on positioning and reflexes.',
    positionIds: <int>[1],
  ),
  fitness(
    label: 'Fitness',
    description: 'The whole squad recovers and builds match stamina.',
    positionIds: <int>[],
  );

  const TrainingFocus({
    required this.label,
    required this.description,
    required this.positionIds,
  });

  final String label;
  final String description;
  final List<int> positionIds;

  bool get isFitness => this == TrainingFocus.fitness;

  static TrainingFocus fromKey(String? key) {
    for (final TrainingFocus focus in TrainingFocus.values) {
      if (focus.name == key) return focus;
    }
    return TrainingFocus.attack;
  }
}

/// Shared training economy constants.
class TrainingRules {
  TrainingRules._();

  static const int cost = 75000;
  static const int maxPlayers = 3;
  static const int powerGain = 1;
  static const int fitnessGain = 4;
}
