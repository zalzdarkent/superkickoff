/// Tactical shapes available to the manager.
///
/// A formation only controls how many outfield players the engine picks per
/// line (defence / midfield / attack); the keeper is always one.
class Formation {
  const Formation(this.name, this.defenders, this.midfielders, this.forwards);

  final String name;
  final int defenders;
  final int midfielders;
  final int forwards;

  int get outfielders => defenders + midfielders + forwards;

  static const Formation f442 = Formation('4-4-2', 4, 4, 2);
  static const Formation f433 = Formation('4-3-3', 4, 3, 3);
  static const Formation f4231 = Formation('4-2-3-1', 4, 5, 1);
  static const Formation f352 = Formation('3-5-2', 3, 5, 2);
  static const Formation f532 = Formation('5-3-2', 5, 3, 2);
  static const Formation f343 = Formation('3-4-3', 3, 4, 3);

  /// Every choice offered in the squad screen.
  static const List<Formation> all = <Formation>[
    f442,
    f433,
    f4231,
    f352,
    f532,
    f343,
  ];

  /// Parses a stored formation name, falling back to 4-4-2.
  static Formation parse(String? name) {
    for (final Formation f in all) {
      if (f.name == name) return f;
    }
    return f442;
  }

  @override
  String toString() => name;
}
