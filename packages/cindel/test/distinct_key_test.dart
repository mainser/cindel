import 'package:cindel/src/query/distinct_key.dart';
import 'package:test/test.dart';

void main() {
  String key(Object? value) => cindelDistinctKey({'value': value}, ['value']);

  test('distinct keys preserve nested scalar types and container kinds', () {
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
    expect(values.map(key).toSet(), hasLength(values.length));
  });

  test('distinct keys compare objects by fields, not map insertion order', () {
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
