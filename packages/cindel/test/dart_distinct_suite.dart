import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart' show Recipient, RecipientMetadata;
import 'dart_distinct_fixture.dart';

void main() {
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
      test('preserves field boundaries with ${separator.codeUnits}.', () async {
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

        await _expectResults(query().distinctByFields(['name', 'email']), [
          3,
          2,
        ]);
      });
    }

    test('preserves list element boundaries and order.', () async {
      await database.distinctRecords.putAll([
        _user(1)..tags = ['a, b'],
        _user(2)..tags = ['a', 'b'],
        _user(3)..tags = ['a, b'],
        _user(4)..tags = ['b', 'a'],
      ]);

      await _expectResults(query().distinctByTags(), [4, 3, 2]);
    });

    test('preserves nested object boundaries inside lists.', () async {
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

      await _expectResults(query().distinctByRecipients(), [3, 2]);
    });

    test('distinguishes null from its string representation.', () async {
      await database.distinctRecords.putAll([
        _user(1)..displayName = null,
        _user(2)..displayName = 'null',
        _user(3)..displayName = null,
      ]);

      await _expectResults(query().distinctByDisplayName(), [3, 2]);
    });

    test(
      'distinguishes empty lists from lists containing an empty string.',
      () async {
        await database.distinctRecords.putAll([
          _user(1)..tags = [],
          _user(2)..tags = [''],
          _user(3)..tags = [],
        ]);

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
