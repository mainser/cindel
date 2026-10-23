import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel findFirst', () {
    late CindelDatabase database;
    late CindelTypedCollection<ApiProduct> products;
    late int decodedObjects;
    const names = ['B', 'A', 'B', 'C', 'D', 'C', 'E', 'F'];

    setUp(() async {
      final directory = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(directory));
      decodedObjects = 0;
      final base = ApiProductSchema;
      final schema = CindelCollectionSchema<ApiProduct>(
        name: base.name,
        dartName: base.dartName,
        idField: base.idField,
        fields: base.fields,
        links: base.links,
        compositeIndexes: base.compositeIndexes,
        toDocument: base.toDocument,
        fromDocument: base.fromDocument,
        toBinaryDocument: base.toBinaryDocument,
        fromBinaryDocument: base.fromBinaryDocument,
        getId: base.getId,
        setId: base.setId,
        bindLinks: base.bindLinks,
        writeNativeDocument: base.writeNativeDocument,
        readNativeDocument: (reader, index) {
          decodedObjects++;
          return base.readNativeDocument!(reader, index);
        },
      );
      database = await openTestDatabase(
        directory: directory,
        schemas: [schema],
      );
      addTearDown(database.close);
      products = database.typedCollection(schema);
      await products.putAll([
        for (var i = 0; i < names.length; i++)
          ApiProduct()
            ..dbId = i + 1
            ..id = i == 0 ? null : 'group'
            ..name = names[i],
      ]);
      decodedObjects = 0;
    });

    test('decodes one native object and leaves the query reusable.', () async {
      final query = products.all().sortBy('dbId').offset(2).limit(4);
      expect((await query.findFirst())?.dbId, 3);
      expect(decodedObjects, 1);
      expect((await query.findAll()).map((item) => item.dbId), [3, 4, 5, 6]);
    });

    test('decodes one projected value and preserves its decoder.', () async {
      var decodedValues = 0;
      final projection = products
          .all()
          .sortBy('dbId')
          .property<String>(
            'name',
            decode: (value) {
              decodedValues++;
              return 'decoded:$value';
            },
          );
      expect(await projection.findFirst(), 'decoded:B');
      expect(decodedValues, 1);
      expect(await projection.findAll(), names.map((name) => 'decoded:$name'));
    });

    test('hydrates one object for a multi-field projection.', () async {
      final projection = products.all().sortBy('dbId').offset(1).properties([
        'dbId',
        'name',
      ]);
      expect(await projection.findFirst(), {'dbId': 2, 'name': 'A'});
      expect(decodedObjects, 1);
      expect((await projection.findAll()).length, 7);
    });

    test('does not skip a null first projected value.', () async {
      var decodedValues = 0;
      final projection = products
          .all()
          .sortBy('dbId')
          .property<String?>(
            'id',
            decode: (value) {
              decodedValues++;
              return value as String?;
            },
          );
      expect(await projection.findFirst(), isNull);
      expect(decodedValues, 1);
    });

    test(
      'preserves empty results, zero limits and offsets for every shape.',
      () async {
        for (final query in [
          products.all().limit(0),
          products.all().offset(2).limit(0),
          products.all().offset(100),
          products.all().whereMatches(
            CindelFilter.field('name').equalTo('missing'),
          ),
        ]) {
          expect(await query.findFirst(), isNull);
          expect(await query.property<String>('name').findFirst(), isNull);
          expect(await query.properties(['dbId', 'name']).findFirst(), isNull);
        }
        expect(decodedObjects, 0);
        await products.deleteAll(List.generate(names.length, (i) => i + 1));
        expect(await products.all().findFirst(), isNull);
        expect(
          await products.all().property<String>('name').findFirst(),
          isNull,
        );
        expect(await products.all().properties(['name']).findFirst(), isNull);
      },
    );

    test(
      'applies filtering, sorting and distinct before the first-result window.',
      () async {
        final query = products
            .all()
            .whereMatches(CindelFilter.field('dbId').greaterThan(2))
            .sortBy('name')
            .distinctByFields(['name'])
            .offset(1)
            .limit(3);
        expect((await query.findFirst())?.name, 'C');
        expect(await query.property<String>('name').findFirst(), 'C');
        expect(await query.properties(['name']).findFirst(), {'name': 'C'});
        expect((await query.findAll()).map((item) => item.name), [
          'C',
          'D',
          'E',
        ]);
      },
    );

    test('keeps the window after filters evaluated in Dart.', () async {
      final query = products
          .all()
          .whereMatches(const _AfterThirdId())
          .sortBy('dbId')
          .offset(1)
          .limit(3);
      expect((await query.findFirst())?.dbId, 5);
      expect(await query.property<String>('name').findFirst(), 'D');
      expect(await query.properties(['dbId']).findFirst(), {'dbId': 5});
      expect((await query.findAll()).map((item) => item.dbId), [5, 6, 7]);
      expect(await query.limit(0).findFirst(), isNull);
    });

    test('respects active read and write transactions.', () async {
      Future<void> checkFirst() async {
        final query = products.all().sortBy('dbId').offset(1);
        expect((await query.findFirst())?.dbId, 2);
        expect(await query.property<String>('name').findFirst(), 'A');
        expect(await query.properties(['dbId']).findFirst(), {'dbId': 2});
      }

      await database.readTxn(checkFirst);
      await database.writeTxn(() async {
        await products.delete(1);
        final query = products.all().sortBy('dbId');
        expect((await query.findFirst())?.dbId, 2);
        expect(await query.property<String>('name').findFirst(), 'A');
        expect(await query.properties(['dbId']).findFirst(), {'dbId': 2});
      });
    });
  });
}

final class _AfterThirdId implements CindelFilterPredicate {
  const _AfterThirdId();

  @override
  bool matches(CindelDocument document) => (document['dbId'] as int) > 3;
}
