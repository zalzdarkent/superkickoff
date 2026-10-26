import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/player_valuation_service.dart';

void main() {
  test('overall increase raises market value meaningfully', () {
    final int value = SquadRepository.valueAfterOverallChange(
      currentValue: 24000000,
      previousPower: 81,
      newPower: 82,
      age: 24,
    );

    // +1 overall on an 81-rated 24-year-old moving from 24M towards target ~28.5M:
    expect(value, greaterThan(24000000));
    expect(value, lessThanOrEqualTo(28500000));
  });

  test('younger players achieve higher valuation target than older players', () {
    const PlayerValuationService service = PlayerValuationService();
    int targetFor(int age) => service.calculateTargetMarketValue(
      power: 82,
      potential: 88,
      age: age,
      positionId: 7,
    );

    expect(targetFor(21), greaterThan(targetFor(26)));
    expect(targetFor(26), greaterThan(targetFor(33)));
  });

  test('value never drops when overall does not change', () {
    expect(
      SquadRepository.valueAfterOverallChange(
        currentValue: 25000000,
        previousPower: 81,
        newPower: 81,
        age: 25,
      ),
      25000000,
    );
  });
}
