import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main({bool includeSameDirectoryHandles = true}) {
  group('Cindel SQLite projected values', () {
    late String directory;
    late CindelDatabase database;

    setUp(() async {
      directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      database = await _open(directory);
      addTearDown(() => database.close());
      await database.apiProducts.putAll([
        for (var id = 1; id <= 8; id++)
          ApiProduct()
            ..dbId = id
            ..id = id % 3 == 0 ? null : (id.isEven ? 'a' : 'b')
            ..name = 'Árbol ${id % 3}',
      ]);
    });

    test('projects and aggregates filtered and indexed windows.', () async {
      for (final source in [
        database.apiProducts.all(),
        database.apiProducts.all().filter().dbIdGreaterThan(3),
        database.apiProducts.where().idEqualTo('a'),
        database.apiProducts.where().idBetween('a', 'b'),
        database.apiProducts
            .where()
            .idBetween('a', 'b')
            .filter()
            .dbIdGreaterThan(3),
      ]) {
        final ordered = source.sortByNameDesc().thenByDbId();
        for (final query in [ordered, ordered.offset(1).limit(3)]) {
          final objects = await query.findAll();
          final ids = objects.map((object) => object.dbId).toList();
          final values = objects.map((object) => object.id).toList();
          final nonNull = values.nonNulls.toList()..sort();
          final sortedIds = ids.toList()..sort();
          expect(await query.dbIdProperty().findAll(), ids);
          expect(await query.idProperty().findAll(), values);
          expect(
            await query.nameProperty().findAll(),
            objects.map((object) => object.name),
          );
          expect(await query.idProperty().count(), nonNull.length);
          expect(await query.idProperty().min(), nonNull.firstOrNull);
          expect(await query.idProperty().max(), nonNull.lastOrNull);
          expect(await query.dbIdProperty().count(), ids.length);
          expect(await query.dbIdProperty().min(), sortedIds.firstOrNull);
          expect(await query.dbIdProperty().max(), sortedIds.lastOrNull);
          final sum = ids.fold<int>(0, (sum, id) => sum + id);
          expect(await query.dbIdProperty().sum(), ids.isEmpty ? null : sum);
          expect(
            await query.dbIdProperty().average(),
            ids.isEmpty ? null : sum / ids.length,
          );
        }
      }
    });

    test('streams floating aggregates in the selected row order.', () async {
      final samples = database.typedCollection(_sampleSchema);
      await samples.putAll([
        _AggregateSample(1, 1e16),
        _AggregateSample(2, 1),
        _AggregateSample(3, -1e16),
        _AggregateSample(4, 1),
        _AggregateSample(5, null),
      ]);
      final ascending = samples.all().sortBy('id');
      final descending = samples.all().sortBy(
        'id',
        order: CindelSortOrder.descending,
      );
      // These sums differ because floating-point addition depends on row order.
      expect(await ascending.property<double?>('value').sum(), 1.0);
      expect(await descending.property<double?>('value').sum(), 0.0);
      expect(await ascending.property<double?>('value').average(), 0.25);
      expect(await descending.property<double?>('value').average(), 0.0);
      for (final query in [
        ascending.offset(1).limit(2),
        descending.offset(2).limit(2),
      ]) {
        final property = query.property<double?>('value');
        final values = (await property.findAll()).nonNulls.toList();
        final sum = values.fold<double>(0, (sum, value) => sum + value);
        expect(await property.sum(), sum);
        expect(await property.average(), sum / values.length);
      }
    });

    test(
      'streams large nullable numeric aggregates and empty windows.',
      () async {
        final samples = database.typedCollection(_sampleSchema);
        await samples.putAll([
          for (var id = 1; id <= 2048; id++)
            _AggregateSample(id, id % 3 == 0 ? null : id / 4 - 256),
        ]);
        await database.readTxn(() async {
          final all = samples.all().sortBy('id');
          for (final query in [
            all,
            all.offset(100).limit(1200),
            all.limit(0),
            all.offset(2048),
            all.offset(2).limit(1),
          ]) {
            final property = query.property<double?>('value');
            final values = (await property.findAll()).nonNulls.toList();
            final sum = values.fold<double>(0, (sum, value) => sum + value);
            final sorted = values.toList()..sort();
            expect(await property.count(), values.length);
            expect(await property.min(), sorted.firstOrNull);
            expect(await property.max(), sorted.lastOrNull);
            expect(await property.sum(), values.isEmpty ? null : sum);
            expect(
              await property.average(),
              values.isEmpty ? null : sum / values.length,
            );
          }
        });
      },
    );

    test('keeps empty and all-null aggregate behavior.', () async {
      final all = database.apiProducts.all().sortByDbId();
      for (final query in [
        all.limit(0),
        all.offset(99),
        all.filter().dbIdGreaterThan(99),
      ]) {
        expect(await query.dbIdProperty().findAll(), isEmpty);
        expect(await query.dbIdProperty().count(), 0);
        expect(await query.dbIdProperty().min(), isNull);
        expect(await query.dbIdProperty().max(), isNull);
        expect(await query.dbIdProperty().sum(), isNull);
        expect(await query.dbIdProperty().average(), isNull);
      }
      final nulls = all.filter().idEqualTo(null).idProperty();
      expect(await nulls.findAll(), [null, null]);
      expect(await nulls.count(), 0);
      expect(await nulls.min(), isNull);
      expect(await nulls.max(), isNull);
      expect(await nulls.sum(), isNull);
      expect(await nulls.average(), isNull);
    });

    test('preserves distinct representatives and their window.', () async {
      final distinct = database.apiProducts.all().sortByName().distinctByName();
      for (final query in [distinct, distinct.offset(1).limit(1)]) {
        final objects = await query.findAll();
        expect(
          await query.nameProperty().findAll(),
          objects.map((object) => object.name),
        );
        expect(
          await query.dbIdProperty().findAll(),
          objects.map((object) => object.dbId),
        );
        expect(
          await query.dbIdProperty().sum(),
          objects.fold<int>(0, (sum, object) => sum + object.dbId),
        );
      }
    });

    test('reads pending changes and respects rollback and reopen.', () async {
      final ids = database.apiProducts.all().sortByDbId().dbIdProperty();
      await expectLater(
        database.writeTxn<void>(() async {
          await database.apiProducts.delete(1);
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 20
              ..name = 'New',
          );
          await database.apiProducts.put(
            ApiProduct()
              ..dbId = 2
              ..id = 'updated'
              ..name = 'Updated',
          );
          expect(await ids.findAll(), [2, 3, 4, 5, 6, 7, 8, 20]);
          expect(await ids.sum(), 55);
          expect(
            await database.apiProducts
                .all()
                .filter()
                .dbIdEqualTo(2)
                .idProperty()
                .findAll(),
            ['updated'],
          );
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await ids.sum(), 36);
      await database.writeTxn(() => database.apiProducts.delete(1));
      await database.close();
      database = await _open(directory);
      expect(
        await database.apiProducts.all().sortByDbId().dbIdProperty().findAll(),
        [2, 3, 4, 5, 6, 7, 8],
      );
      expect(await database.apiProducts.all().dbIdProperty().sum(), 35);
    });

    if (includeSameDirectoryHandles) {
      test('projects and aggregates from the active read snapshot.', () async {
        final other = await _open(directory);
        addTearDown(other.close);
        final ids = database.apiProducts.all().sortByDbId().dbIdProperty();
        await database.readTxn(() async {
          expect(await ids.sum(), 36);
          await other.writeTxn(() => other.apiProducts.delete(1));
          expect(await ids.findAll(), [1, 2, 3, 4, 5, 6, 7, 8]);
          expect(await ids.sum(), 36);
        });
        expect(await ids.sum(), 35);
      });
    }
  });
}

Future<CindelDatabase> _open(String directory) => openTestDatabase(
  directory: directory,
  schemas: [ApiProductSchema, _sampleSchema],
);

class _AggregateSample {
  _AggregateSample(this.id, this.value);

  int id;
  final double? value;
}

final _sampleSchema = CindelCollectionSchema<_AggregateSample>(
  name: 'aggregateSamples',
  dartName: '_AggregateSample',
  idField: 'id',
  fields: const [
    CindelFieldSchema(
      name: 'id',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'value',
      dartType: 'double?',
      binaryType: 'double',
      isId: false,
      isIndexed: false,
    ),
  ],
  toDocument: (sample) => {'id': sample.id, 'value': sample.value},
  fromDocument: (document) =>
      _AggregateSample(document['id']! as int, document['value'] as double?),
  toBinaryDocument: (sample) => cindelEncodeSchemaBinaryDocument(
    [sample.value],
    [CindelBinaryFieldType.doubleValue],
  ),
  fromBinaryDocument: (bytes) => _AggregateSample(
    0,
    CindelSchemaBinaryDocumentReader(bytes, staticSize: 8).readDouble(0, 0),
  ),
  writeNativeDocument: (writer, sample) {
    final value = sample.value;
    if (value == null) {
      writer.writeNull(0);
    } else {
      writer.writeDouble(0, value);
    }
  },
  readNativeDocument: (reader, index) =>
      _AggregateSample(reader.readId(index), reader.readDouble(index, 0)),
  getId: (sample) => sample.id,
  setId: (sample, id) => sample.id = id,
);
