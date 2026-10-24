@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:cindel/cindel.dart';
import 'close_test_support_io.dart';
import 'type_compatibility_fixture.dart';
import 'type_compatibility_suite.dart';

void main() {
  for (final backend in CindelStorageBackend.values) {
    group(backend.name, () => runTypeCompatibility(backend));
  }
  _directSqliteProjections();
}

void _directSqliteProjections() {
  // Scenario: Public native projections hydrate objects, while Web delegates to SQL.
  // Covers: The underlying SQL projection independently of that Dart routing choice.
  // Expected: Lists and objects have the same values through the direct native plan.
  test('direct SQLite projection of a string list', () async {
    await _checkProjection(
      Modelc20Schema,
      Modelc20()
        ..dbId = 1
        ..value = ['a'],
      [
        ['a'],
      ],
    );
  });
  test('direct SQLite projection of an embedded object', () async {
    await _checkProjection(
      Envelopec00Schema,
      Envelopec00()
        ..dbId = 1
        ..value = (Payloadc00()..value = true),
      [
        {'value': true},
      ],
    );
  });
}

Future<void> _checkProjection<T>(
  CindelCollectionSchema<T> schema,
  T object,
  Object expected,
) async {
  final directory = await createCloseTestDirectory();
  addTearDown(() => deleteCloseTestDirectory(directory));
  final db = await Cindel.open(
    directory: directory,
    backend: CindelStorageBackend.sqlite,
    schemas: [schema],
  );
  addTearDown(db.close);
  await db.typedCollection(schema).put(object);
  expect(
    await db.queryNativePlanProjection(
      schema.name,
      const CindelNativeQueryPlan(source: CindelNativeAllQuerySource()),
      'value',
    ),
    expected,
  );
}
