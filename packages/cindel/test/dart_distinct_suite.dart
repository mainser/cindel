import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart' show Recipient, RecipientMetadata;
import 'dart_distinct_fixture.dart';
import 'distinct_update_suite.dart' as distinct_update;
import 'nested_update_suite.dart' as nested_update;

void main() {
  distinct_update.main();
  nested_update.main();
  group('Cindel Dart distinct', () {
    late CindelDatabase database;

    setUp(() async {
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await openTestDatabase(
        directory: directory,
        schemas: [DistinctRecordSchema],
      );
      addTearDown(database.close);
    });

    // Generated nested filters require Dart evaluation on all three backends.
    // No custom predicate or replacement schema is needed to reach this path.
    CindelQuery<DistinctRecord> query() => database.distinctRecords
        .filter()
        .primaryRecipient(
          (recipient) => recipient.metadata(
            (metadata) => metadata.labelEqualTo('included'),
          ),
        )
        .sortByDbIdDesc();

    for (final separator in ['\u0001String:', '\u0000']) {
      // Scenario: Two field tuples contain separators at different
      // boundaries, with duplicates and an excluded row.
      // Covers:
      // - Collision-free composite distinct keys for each separator variant.
      // Expected: Distinct keeps IDs 3 and 2 as separate tuples in query
      // order.
      test('preserves field boundaries with ${separator.codeUnits}.', () async {
        // Arrange.
        await database.distinctRecords.putAll([
          _user(1)
            ..name = 'a${separator}b'
            ..email = 'c',
          _user(2)
            ..name = 'a'
            ..email = 'b${separator}c',
          _user(3)
            ..name = 'a${separator}b'
            ..email = 'c',
          _user(4, included: false)
            ..name = 'a'
            ..email = 'b${separator}c',
        ]);

        // Act / Assert.
        await _expectResults(query().distinctByFields(['name', 'email']), [
          3,
          2,
        ]);
      });
    }

    // Scenario: String lists differ by element boundaries and ordering.
    // Covers:
    // - Structural list distinct keys rather than joined string
    // representations.
    // Expected: IDs 4, 3 and 2 remain distinct while the identical list is
    // deduplicated.
    test('preserves list element boundaries and order.', () async {
      // Arrange.
      await database.distinctRecords.putAll([
        _user(1)..tags = ['a, b'],
        _user(2)..tags = ['a', 'b'],
        _user(3)..tags = ['a, b'],
        _user(4)..tags = ['b', 'a'],
      ]);

      // Act / Assert.
      await _expectResults(query().distinctByTags(), [4, 3, 2]);
    });

    // Scenario: Lists of embedded recipients contain punctuation that mimics
    // serialized field boundaries.
    // Covers:
    // - Nested object/list key encoding and duplicate representatives.
    // Expected: The distinct query returns IDs 3 and 2 without merging
    // different embedded objects.
    test('preserves nested object boundaries inside lists.', () async {
      // Arrange.
      List<Recipient> recipients(String name, String address) => [
        Recipient()
          ..name = name
          ..address = address
          ..metadata = (RecipientMetadata()..label = 'nested'),
      ];
      await database.distinctRecords.putAll([
        _user(1)..recipients = recipients('a, address: b', 'c'),
        _user(2)..recipients = recipients('a', 'b, address: c'),
        _user(3)..recipients = recipients('a, address: b', 'c'),
      ]);

      // Act / Assert.
      await _expectResults(query().distinctByRecipients(), [3, 2]);
    });

    // Scenario: Nullable names contain null and the literal string null.
    // Covers:
    // - Type-preserving distinct keys for nullable scalar fields.
    // Expected: Null duplicates collapse but the string remains separate,
    // yielding IDs 3 and 2.
    test('distinguishes null from its string representation.', () async {
      // Arrange.
      await database.distinctRecords.putAll([
        _user(1)..displayName = null,
        _user(2)..displayName = 'null',
        _user(3)..displayName = null,
      ]);

      // Act / Assert.
      await _expectResults(query().distinctByDisplayName(), [3, 2]);
    });

    // Scenario: Tags contain either an empty list or a list with one empty
    // string.
    // Covers:
    // - Empty-container versus empty-element distinct encoding.
    // Expected: The two values stay separate and the query returns IDs 3 and
    // 2.
    test(
      'distinguishes empty lists from lists containing an empty string.',
      () async {
        // Arrange.
        await database.distinctRecords.putAll([
          _user(1)..tags = [],
          _user(2)..tags = [''],
          _user(3)..tags = [],
        ]);

        // Act / Assert.
        await _expectResults(query().distinctByTags(), [3, 2]);
      },
    );
  });
}

DistinctRecord _user(int id, {bool included = true}) => DistinctRecord()
  ..dbId = id
  ..name = 'User $id'
  ..email = '$id@example.com'
  ..primaryRecipient = (Recipient()
    ..metadata = (RecipientMetadata()
      ..label = included ? 'included' : 'excluded'));

Future<void> _expectResults(
  CindelQuery<DistinctRecord> query,
  List<int> ids,
) async {
  expect((await query.findAll()).map((user) => user.dbId), ids);
  expect(await query.count(), ids.length);
  expect(await query.dbIdProperty().findAll(), ids);
  expect((await query.findFirst())?.dbId, ids.first);
  final window = query.offset(1).limit(1);
  expect((await window.findAll()).map((user) => user.dbId), [ids[1]]);
  expect(await window.count(), 1);
  expect(await window.dbIdProperty().findFirst(), ids[1]);
  expect(await window.properties(['dbId']).findAll(), [
    {'dbId': ids[1]},
  ]);
  expect(await query.limit(0).findAll(), isEmpty);
  expect(await query.offset(ids.length).findFirst(), isNull);
}
