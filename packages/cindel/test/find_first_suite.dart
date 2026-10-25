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

    // Scenario: A reusable object query has an offset and a limit larger than
    // one.
    // Covers:
    // - findFirst limiting native hydration without mutating the query.
    // Expected: Only ID 3 is decoded initially; findAll still returns IDs 3
    // through 6.
    test('decodes one native object and leaves the query reusable.', () async {
      // Arrange.
      final query = products.all().sortBy('dbId').offset(2).limit(4);
      // Act / Assert.
      expect((await query.findFirst())?.dbId, 3);
      expect(decodedObjects, 1);
      expect((await query.findAll()).map((item) => item.dbId), [3, 4, 5, 6]);
    });

    // Scenario: A projected property uses a decoder with an invocation
    // counter.
    // Covers:
    // - Single-value projection limiting and preservation of the decoder.
    // Expected: findFirst decodes B exactly once and findAll still decodes
    // every projected name.
    test('decodes one projected value and preserves its decoder.', () async {
      // Arrange.
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
      // Act / Assert.
      expect(await projection.findFirst(), 'decoded:B');
      expect(decodedValues, 1);
      expect(await projection.findAll(), names.map((name) => 'decoded:$name'));
    });

    // Scenario: A multi-field projection starts after the first stored
    // object.
    // Covers:
    // - findFirst object hydration for multiple projected fields.
    // Expected: The result is ID 2/name A with one decoded object; the full
    // projection still has seven rows.
    test('hydrates one object for a multi-field projection.', () async {
      // Arrange.
      final projection = products.all().sortBy('dbId').offset(1).properties([
        'dbId',
        'name',
      ]);
      // Act / Assert.
      expect(await projection.findFirst(), {'dbId': 2, 'name': 'A'});
      expect(decodedObjects, 1);
      expect((await projection.findAll()).length, 7);
    });

    // Scenario: The first projected ID value is null and later values are
    // non-null.
    // Covers:
    // - Null first-value preservation and decoder call count.
    // Expected: findFirst returns null without skipping ahead and invokes the
    // decoder once.
    test('does not skip a null first projected value.', () async {
      // Arrange.
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
      // Act / Assert.
      expect(await projection.findFirst(), isNull);
      expect(decodedValues, 1);
    });

    // Scenario: Queries have zero limits, exhausted offsets, no matches or an
    // empty collection.
    // Covers:
    // - Empty findFirst behavior for objects, single properties and multiple
    // properties.
    // Expected: Every shape returns null and empty selections decode no
    // objects.
    test(
      'preserves empty results, zero limits and offsets for every shape.',
      () async {
        // Arrange: use the inputs described in this scenario.
        // Act / Assert.
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

    // Scenario: A filtered query sorts names, removes duplicates and then
    // applies a window.
    // Covers:
    // - Selection order shared by object and property findFirst.
    // Expected: The first selected name is C and the reusable full window
    // contains C, D and E.
    test(
      'applies filtering, sorting and distinct before the first-result window.',
      () async {
        // Arrange.
        final query = products
            .all()
            .whereMatches(CindelFilter.field('dbId').greaterThan(2))
            .sortBy('name')
            .distinctByFields(['name'])
            .offset(1)
            .limit(3);
        // Act / Assert.
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

    // Scenario: A predicate evaluated in Dart is combined with an ordered
    // window.
    // Covers:
    // - Post-filter pagination and all findFirst projection shapes.
    // Expected: The first result is ID 5/name D, the full window is 5/6/7 and
    // limit zero returns null.
    test('keeps the window after filters evaluated in Dart.', () async {
      // Arrange.
      final query = products
          .all()
          .whereMatches(const _AfterThirdId())
          .sortBy('dbId')
          .offset(1)
          .limit(3);
      // Act / Assert.
      expect((await query.findFirst())?.dbId, 5);
      expect(await query.property<String>('name').findFirst(), 'D');
      expect(await query.properties(['dbId']).findFirst(), {'dbId': 5});
      expect((await query.findAll()).map((item) => item.dbId), [5, 6, 7]);
      expect(await query.limit(0).findFirst(), isNull);
    });

    // Scenario: findFirst runs inside active read and write transactions.
    // Covers:
    // - Transaction-aware first object and property reads after a pending
    // deletion.
    // Expected: Every tested projection sees ID 2/name A in the appropriate
    // transaction snapshot.
    test('respects active read and write transactions.', () async {
      // Arrange.
      Future<void> checkFirst() async {
        final query = products.all().sortBy('dbId').offset(1);
        expect((await query.findFirst())?.dbId, 2);
        expect(await query.property<String>('name').findFirst(), 'A');
        expect(await query.properties(['dbId']).findFirst(), {'dbId': 2});
      }

      // Act.
      await database.readTxn(checkFirst);
      // Assert.
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
