import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'schema_generation_fixture.dart';

void main({bool includeSameDirectoryHandles = true}) {
  group('SQLite typed IDs', () {
    if (includeSameDirectoryHandles) {
      test('preserves rows written through already-open handles.', () async {
        final directory = await createCloseTestDirectory();
        addTearDown(() => deleteCloseTestDirectory(directory));
        final first = await _open(directory);
        addTearDown(first.close);
        final second = await _open(directory);
        addTearDown(second.close);

        final ana = ApiProduct()..name = 'Ana';
        final ben = ApiProduct()..name = 'Ben';
        await first.writeTxn(() => first.apiProducts.put(ana));
        await second.writeTxn(() => second.apiProducts.put(ben));
        expect([ana.dbId, ben.dbId], [1, 2]);
        expect((await second.apiProducts.get(1))?.name, 'Ana');
        expect((await first.apiProducts.get(2))?.name, 'Ben');

        await first.apiProducts.put(
          ApiProduct()
            ..dbId = 40
            ..name = 'Manual',
        );
        final batch = [
          ApiProduct()..name = 'Batch A',
          ApiProduct()..name = 'Batch B',
        ];
        await second.apiProducts.putAll(batch);
        expect(batch.map((item) => item.dbId), [41, 42]);
        expect((await first.apiProducts.get(41))?.name, 'Batch A');
        expect((await first.apiProducts.get(42))?.name, 'Batch B');
      });
    }

    test(
      'persists reservations and rolls back typed counters on reopen.',
      () async {
        final directory = await createCloseTestDirectory();
        addTearDown(() => deleteCloseTestDirectory(directory));
        var database = await _open(directory);
        addTearDown(() => database.close());

        expect(await database.allocateId('apiProducts'), 1);
        await database.close();
        database = await _open(directory);
        final product = ApiProduct()..name = 'Committed';
        await database.writeTxn(() => database.apiProducts.put(product));
        expect(product.dbId, 2);

        await expectLater(
          database.writeTxn<void>(() async {
            await database.apiProducts.put(
              ApiProduct()
                ..dbId = 40
                ..name = 'Rollback',
            );
            expect(await database.allocateId('apiProducts'), 41);
            throw StateError('rollback');
          }),
          throwsA(isA<StateError>()),
        );
        expect(await database.apiProducts.get(40), isNull);
        expect(await database.allocateId('apiProducts'), 3);

        await database.apiProducts.putAll([
          ApiProduct()
            ..dbId = 40
            ..name = 'Manual',
        ]);
        await database.apiProducts.delete(40);
        await database.close();
        database = await _open(directory);
        final next = ApiProduct()..name = 'After reopen';
        await database.apiProducts.put(next);
        expect(next.dbId, 41);
        expect((await database.apiProducts.get(2))?.name, 'Committed');
        expect((await database.apiProducts.get(41))?.name, 'After reopen');
      },
    );
  });
}

Future<CindelDatabase> _open(String directory) => Cindel.open(
  directory: directory,
  backend: CindelStorageBackend.sqlite,
  schemas: [ApiProductSchema],
);
