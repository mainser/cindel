import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart';

void main() {
  group('Cindel MDBX ordered integer index', () {
    late String directory;
    late CindelDatabase database;
    late CindelTypedCollection<_IndexRow> rows;

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await _open(directory);
      addTearDown(database.close);
      rows = database.typedCollection(_schema);
      await rows.putAll([
        for (var id = 96; id >= 1; id--) _IndexRow(id, (id * 37) % 11 - 5),
      ]);
    });

    CindelQuery<_IndexRow> range({int? lower, int? upper}) =>
        CindelQuery<_IndexRow>.range(
          database: database,
          schema: _schema,
          field: 'score',
          lower: lower,
          upper: upper,
        ).sortBy('score').thenBy('dbId');

    // Scenario: Indexed ranges include bounded, open-ended, equal and empty
    // bounds with optional filters.
    // Covers:
    // - Ordered index reads, tied keys and pagination across result shapes.
    // Expected: Returned rows match the fully ordered reference for every
    // tested window.
    test('preserves bounds, ties, filters and all result shapes.', () async {
      // Arrange: use the inputs described in this scenario.
      // Act / Assert.
      for (final (lower, upper) in [
        (-3, 3),
        (null, 0),
        (0, null),
        (0, 0),
        (20, 30),
      ]) {
        for (final filtered in [false, true]) {
          final source = filtered
              ? range(
                  lower: lower,
                  upper: upper,
                ).whereMatches(CindelFilter.field('dbId').greaterThan(20))
              : range(lower: lower, upper: upper);
          // An unlimited plan retains the full-sort path.
          final expected = await source.findAll();
          for (final (offset, limit) in [
            (0, 1),
            (3, 7),
            (0, 0),
            (95, 8),
            (200, 1),
          ]) {
            await _expectRows(
              source.offset(offset).limit(limit),
              expected.skip(offset).take(limit).toList(),
            );
          }
        }
      }
    });

    // Scenario: An indexed window is queried while rows change in a write or
    // an external handle.
    // Covers:
    // - Pending index changes, rollback and read snapshot stability.
    // Expected: Rollback restores the original window, snapshots retain it
    // and later reads reflect committed deletion.
    test('keeps pending writes, rollback and the read snapshot.', () async {
      // Arrange.
      final query = range(lower: -5, upper: 5).limit(4);
      final before = await query.findAll();
      // Act / Assert.
      await expectLater(
        database.writeTxn<void>(() async {
          await rows.put(_IndexRow(1, -5));
          await rows.delete(before.first.dbId);
          final expected = await range(lower: -5, upper: 5).findAll();
          await _expectRows(query, expected.take(4).toList());
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      await _expectRows(query, before);

      final other = await _open(directory);
      addTearDown(other.close);
      await database.readTxn(() async {
        await _expectRows(query, before);
        await other.typedCollection(_schema).delete(before.first.dbId);
        await _expectRows(query, before);
      });
      expect((await query.findFirst())?.dbId, isNot(before.first.dbId));
    });

    // Scenario: Adjacent signed 64-bit index values and sparse IDs are
    // inserted in reverse order.
    // Covers:
    // - Exact index-key ordering and ID tie breaking beyond double precision.
    // Expected: Score and ID projections retain the expected order and
    // endpoint extrema stay exact.
    test('keeps adjacent 64-bit values and sparse ID ties exact.', () async {
      // Arrange.
      await rows.all().deleteAll();
      final expected = [
        _IndexRow(7, -9007199254740993),
        _IndexRow(8, -9007199254740992),
        _IndexRow(255, 0),
        _IndexRow(256, 0),
        _IndexRow(9007199254740993, 0),
        _IndexRow(9, 9007199254740992),
        _IndexRow(10, 9007199254740993),
      ];
      await rows.putAll(expected.reversed);
      final query = range(lower: -9007199254740993, upper: 9007199254740993);
      // Act / Assert.
      expect(
        await query.limit(10).property<int>('score').findAll(),
        expected.map((row) => row.score),
      );
      expect(
        await query.limit(10).property<int>('dbId').findAll(),
        expected.map((row) => row.dbId),
      );
      expect(
        await query.limit(1).property<int>('score').min(),
        expected.first.score,
      );
      expect(
        await query.offset(6).limit(1).property<int>('score').max(),
        expected.last.score,
      );
    });
  });
}

Future<void> _expectRows(
  CindelQuery<_IndexRow> query,
  List<_IndexRow> expected,
) async {
  expect(
    (await query.findAll()).map((row) => (row.dbId, row.score)),
    expected.map((row) => (row.dbId, row.score)),
  );
  expect(
    await query.property<int>('dbId').findAll(),
    expected.map((row) => row.dbId),
  );
  expect(await query.properties(['dbId', 'score']).findAll(), [
    for (final row in expected) {'dbId': row.dbId, 'score': row.score},
  ]);
  expect((await query.findFirst())?.dbId, expected.firstOrNull?.dbId);
  expect(
    await query.property<int>('score').findFirst(),
    expected.firstOrNull?.score,
  );
  expect(await query.count(), expected.length);
  expect(await query.property<int>('score').count(), expected.length);
  final sum = expected.fold<int>(0, (sum, row) => sum + row.score);
  expect(
    await query.property<int>('score').sum(),
    expected.isEmpty ? null : sum,
  );
  expect(
    await query.property<int>('score').average(),
    expected.isEmpty ? null : sum / expected.length,
  );
  expect(await query.property<int>('score').min(), expected.firstOrNull?.score);
  expect(await query.property<int>('score').max(), expected.lastOrNull?.score);
}

final class _IndexRow {
  _IndexRow(this.dbId, this.score);
  int dbId;
  final int score;
}

final _schema = CindelCollectionSchema<_IndexRow>(
  name: 'indexRows',
  dartName: 'IndexRow',
  idField: 'dbId',
  fields: const [
    CindelFieldSchema(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'score',
      dartType: 'int',
      binaryType: 'int',
      isId: false,
      isIndexed: true,
    ),
  ],
  getId: (row) => row.dbId,
  setId: (row, id) => row.dbId = id,
  toDocument: (row) => {'dbId': row.dbId, 'score': row.score},
  toBinaryDocument: (row) => cindelEncodeSchemaBinaryDocument(
    [row.score],
    const [CindelBinaryFieldType.intValue],
  ),
  fromBinaryDocument: (bytes) => _IndexRow(
    autoIncrement,
    CindelSchemaBinaryDocumentReader(bytes, staticSize: 8).readInt(0, 0)!,
  ),
  fromDocument: (document) =>
      _IndexRow(document['dbId']! as int, document['score']! as int),
  writeNativeDocument: (writer, row) => writer.writeInt(0, row.score),
  readNativeDocument: (reader, index) =>
      _IndexRow(reader.readId(index), reader.readInt(index, 0)!),
);

Future<CindelDatabase> _open(String directory) =>
    openTestDatabase(directory: directory, schemas: [_schema]);
