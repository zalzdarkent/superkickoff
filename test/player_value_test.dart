import 'package:flutter_test/flutter_test.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';

void main() {
  test('overall increase raises market value meaningfully', () {
    final int value = SquadRepository.valueAfterOverallChange(
      currentValue: 60000000,
      previousPower: 81,
      newPower: 82,
      age: 24,
    );

    // +1 overall on an 81-rated 24-year-old: 60M -> ~71.8M
    expect(value, greaterThan(68000000));
    expect(value, lessThan(76000000));
  });

  test('younger players gain more per overall point', () {
    int gainFor(int age) =>
        SquadRepository.valueAfterOverallChange(
          currentValue: 60000000,
          previousPower: 81,
          newPower: 82,
          age: age,
        ) -
        60000000;

    expect(gainFor(21), greaterThan(gainFor(26)));
    expect(gainFor(26), greaterThan(gainFor(32)));
  });

  test('value never drops when overall does not change', () {
    expect(
      SquadRepository.valueAfterOverallChange(
        currentValue: 60000000,
        previousPower: 81,
        newPower: 81,
        age: 25,
      ),
      60000000,
    );
  });
}
