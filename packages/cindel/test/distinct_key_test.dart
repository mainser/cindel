import 'package:cindel/src/query/distinct_key.dart';
import 'package:test/test.dart';

void main() {
  String key(Object? value) => cindelDistinctKey({'value': value}, ['value']);

  // Scenario: Scalar values and nested containers have similar textual
  // representations.
  // Covers:
  // - Scalar type tags, nulls and list/map container boundaries.
  // Expected: Every listed value produces a different distinct key.
  test('distinct keys preserve nested scalar types and container kinds', () {
    // Arrange.
    final values = <Object?>[
      null,
      'null',
      true,
      'true',
      1,
      '1',
      1.5,
      '1.5',
      '',
      [],
      {},
      [''],
      [null],
      ['null'],
      [1],
      ['1'],
      [
        [1],
      ],
      [
        ['1'],
      ],
      {'a': 1},
      {'a': '1'},
    ];
    // Act / Assert.
    expect(values.map(key).toSet(), hasLength(values.length));
  });

  // Scenario: Equivalent objects use different map insertion orders and list
  // implementations.
  // Covers:
  // - Canonical object field order and structural list equality.
  // Expected: Equivalent containers share keys, but punctuation in different
  // field/value boundaries does not collide.
  test('distinct keys compare objects by fields, not map insertion order', () {
    // Arrange: use the inputs described in this scenario.
    // Act / Assert.
    expect(
      key({
        'a': [1, 'x'],
        'b': {'c': null, 'd': true},
      }),
      key({
        'b': {'d': true, 'c': null},
        'a': [1, 'x'],
      }),
    );
    expect(key(<String>['a']), key(List<Object?>.unmodifiable(['a'])));
    expect(key({'a: b': 'c'}), isNot(key({'a': 'b: c'})));
  });
}
