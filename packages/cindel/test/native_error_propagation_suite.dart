import 'dart:io';
import 'dart:typed_data';

import 'package:cindel/cindel.dart';
import 'package:cindel/src/native/bindings.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'backup_contract_fixture.dart';

void main() {
  group('native error propagation', () {
    test('keeps filesystem open failures and backend identity.', () async {
      final directory = await Directory.systemTemp.createTemp('cindel_error_');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/file');
      await file.writeAsString('not a directory');
      await expectLater(
        openTestDatabase(directory: file.path),
        throwsA(
          isA<CindelOpenError>()
              .having(
                (error) => error.backend,
                'backend',
                testStorageBackend.name,
              )
              .having((error) => error.cause.toString(), 'cause', isNotEmpty),
        ),
      );
      expect(await file.readAsString(), 'not a directory');
    });

    test(
      'does not return partial rows or nullable fields after a reader failure.',
      () async {
        final db = await openTestDatabaseInMemory(schemas: [backupNodeSchema]);
        addTearDown(db.close);
        final other = await openTestDatabaseInMemory(
          schemas: [backupNodeSchema],
        );
        addTearDown(other.close);
        await db.typedCollection(backupNodeSchema).putAll([
          for (var i = 1; i <= 4; i++)
            BackupNode(i, payload: 'invalid list bytes'),
        ]);
        var visited = 0;
        // Deliberately incompatible field layout models a failed native decoder.
        // The first two rows hydrate; the third fails before the list can escape.
        await expectLater(
          db.queryNativePlanObjects<int>(
            'backup_nodes',
            const CindelNativeQueryPlan(source: CindelNativeAllQuerySource()),
            Uint8List.fromList([1, 4]),
            (reader, index) {
              visited++;
              if (visited == 3) reader.readList(index, 1);
              return visited;
            },
          ),
          throwsA(
            isA<CindelError>()
                .having((error) => error.cause, 'cause', isNotNull)
                .having(
                  (error) => error.message.toLowerCase(),
                  'detail',
                  contains('list'),
                ),
          ),
        );
        expect(visited, 3);
        await db.typedCollection(backupNodeSchema).put(BackupNode(5));
        expect(await db.documentIds('backup_nodes'), [1, 2, 3, 4, 5]);
        expect(await other.documentIds('backup_nodes'), isEmpty);
        await expectLater(
          db.getAllNativeBinaryDocuments<int>(
            'backup_nodes',
            [1],
            Uint8List.fromList([1, 4]),
            (reader, index) {
              reader.readList(index, 1);
              return 1;
            },
          ),
          throwsA(isA<CindelError>()),
        );
        expect(await db.typedCollection(backupNodeSchema).get(999), isNull);
      },
    );

    test('keeps operation causes separate and clears successful calls.', () {
      final bindings = CindelNativeBindings();
      final backend = testStorageBackend == CindelStorageBackend.sqlite ? 0 : 1;
      final first = bindings.open(':memory:', backend: backend);
      final second = bindings.open(':memory:', backend: backend);
      addTearDown(() {
        bindings.close(first);
        bindings.close(second);
      });
      expect(
        () => bindings.commitTransaction(first),
        throwsA(
          isA<CindelTransactionError>().having(
            (error) => error.cause.toString(),
            'cause',
            contains('no active transaction'),
          ),
        ),
      );
      bindings.beginWriteTransaction(second);
      bindings.commitTransaction(second);
      expect(
        () => bindings.registerSchemas(first, Uint8List.fromList([255])),
        throwsA(
          isA<CindelSchemaError>().having(
            (error) => error.cause.toString(),
            'cause',
            isNot(contains('no active transaction')),
          ),
        ),
      );
      bindings.beginWriteTransaction(first);
      bindings.rollbackTransaction(first);
    });
  });
}
