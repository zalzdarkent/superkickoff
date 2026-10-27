import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/state/career_provider.dart';

void main() {
  Player player({String? injuryReturnDate}) => Player(
    playerId: 1,
    name: 'Test Player',
    age: 20,
    positionId: 7,
    power: 50,
    potential: 60,
    fitness: 40,
    value: 1000,
    salary: 100,
    countryId: 1,
    squadStatus: 1,
    marketStatus: 1,
    statusId: 1,
    isCaptain: false,
    shirtNumber: 1,
    stars: 2,
    skillA: 50,
    skillB: 50,
    height: 175,
    championships: null,
    injuryReturnDate: injuryReturnDate,
  );

  test('calculates remaining injury days using game dates', () {
    expect(
      player(injuryReturnDate: '2025-08-03').injuryDaysRemaining('2025-08-01'),
      2,
    );
    expect(
      player(injuryReturnDate: '2025-08-02').injuryDaysRemaining('2025-08-01'),
      1,
    );
  });

  test('hides injuries on or after the recovery date', () {
    expect(
      player(injuryReturnDate: '2025-08-02').injuryDaysRemaining('2025-08-02'),
      isNull,
    );
    expect(player().injuryDaysRemaining('2025-08-01'), isNull);
  });

  test('uses the completed matchday date before the next fixture date', () {
    final CareerProvider game = CareerProvider()
      ..nextDate = '2025-08-08'
      ..lastMatchday = <FixtureMatch>[
        FixtureMatch(
          matchId: 1,
          tournamentId: 1,
          round: 1,
          phase: 0,
          status: 2,
          homeTeamId: 1,
          awayTeamId: 2,
          stadiumId: 1,
          date: '2025-08-01',
          homeGoals: 0,
          awayGoals: 0,
          winnerId: null,
        ),
      ];

    expect(game.squadInjuryReferenceDate, '2025-08-01');
    expect(
      player(injuryReturnDate: '2025-08-04')
          .injuryDaysRemaining(game.squadInjuryReferenceDate),
      3,
    );
  });

  test('uses the next fixture date when no matchday has been played', () {
    final CareerProvider game = CareerProvider()..nextDate = '2025-08-08';

    expect(game.squadInjuryReferenceDate, '2025-08-08');
  });

  test('uses the last played date restored from a continued save', () {
    final CareerProvider game = CareerProvider()
      ..nextDate = '2025-08-08'
      ..lastPlayedDate = '2025-08-01';

    expect(game.squadInjuryReferenceDate, '2025-08-01');
  });
}
