import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'error_query_io.dart'
    if (dart.library.js_interop) 'error_query_web.dart';
import 'backup_contract_fixture.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';

void main() {
  group('error propagation', () {
    Future<({CindelDatabase db, String path})> open() async {
      final path = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(path));
      final db = await openTestDatabase(
        directory: path,
        schemas: [backupNodeSchema],
      );
      addTearDown(db.close);
      return (db: db, path: path);
    }

    // Scenario: A transaction inserts a valid row before violating a unique
    // code index.
    // Covers:
    // - Error cause/context preservation, rollback and subsequent write
    // recovery.
    // Expected: The error identifies uniqueness and the code field, both
    // transaction rows are absent and a later valid insert succeeds.
    test(
      'keeps unique constraint cause through rollback and recovers.',
      () async {
        // Arrange.
        final fixture = await open();
        final db = fixture.db;
        final nodes = db.typedCollection(backupNodeSchema);
        await nodes.put(BackupNode(1, code: 10));
        Object? caught;
        // Act.
        try {
          await db.writeTxn(() async {
            await nodes.put(BackupNode(2, code: 20));
            await nodes.put(BackupNode(3, code: 10));
          });
        } catch (error) {
          caught = error;
        }
        // Assert.
        expect(caught, isA<CindelError>());
        final error = caught! as CindelError;
        expect(error.operation, isNotEmpty);
        expect(error.cause, isNotNull);
        expect(error.message.toLowerCase(), contains('unique'));
        expect(error.message, contains('code'));
        expect(await nodes.get(2), isNull);
        expect(await nodes.get(3), isNull);
        await nodes.put(BackupNode(2, code: 20));
        expect((await nodes.get(2))!.code, 20);
      },
    );

    // Scenario: A persisted collection is reopened with an incompatible field
    // definition.
    // Covers:
    // - Schema-open diagnostics and recovery using the original schema.
    // Expected: Opening fails with a cause naming payload; the original
    // schema reopens at version one.
    test(
      'keeps incompatible schema cause on open and allows reopening.',
      () async {
        // Arrange.
        final path = await createCloseTestDirectory();
        addTearDown(() => deleteCloseTestDirectory(path));
        final original = CindelCollectionSchema<BackupNode>(
          name: backupNodeSchema.name,
          dartName: backupNodeSchema.dartName,
          idField: backupNodeSchema.idField,
          fields: backupNodeSchema.fields,
          toDocument: backupNodeSchema.toDocument,
          fromDocument: backupNodeSchema.fromDocument,
        );
        final source = await openTestDatabase(
          directory: path,
          schemas: [original],
        );
        await source.close();
        final incompatible = CindelCollectionSchema<BackupNode>(
          name: backupNodeSchema.name,
          dartName: backupNodeSchema.dartName,
          idField: backupNodeSchema.idField,
          fields: [
            ...backupNodeSchema.fields.where(
              (field) => field.name != 'payload',
            ),
            const CindelFieldSchema(
              name: 'payload',
              dartType: 'int',
              binaryType: 'int',
              isId: false,
              isIndexed: false,
            ),
          ],
          toDocument: backupNodeSchema.toDocument,
          fromDocument: backupNodeSchema.fromDocument,
        );
        // Act / Assert.
        await expectLater(
          openTestDatabase(directory: path, schemas: [incompatible]),
          throwsA(
            isA<CindelError>()
                .having((error) => error.cause, 'cause', isNotNull)
                .having((error) => error.message, 'field', contains('payload')),
          ),
        );
        final reopened = await openTestDatabase(
          directory: path,
          schemas: [original],
        );
        addTearDown(reopened.close);
        expect(await reopened.schemaVersion(backupNodeSchema.name), 1);
      },
    );

    // Scenario: the engine rejects a malformed filter payload.
    // Expected: failure is distinguishable from an empty successful query.
    // Scenario: A seeded collection receives a deliberately invalid query.
    // Covers:
    // - Query error diagnostics without converting failure to an empty
    // result.
    // Expected: The error retains its cause and filter detail, and the stored
    // ID remains readable.
    test('returns query diagnostics instead of empty results.', () async {
      // Arrange.
      final fixture = await open();
      final db = fixture.db;
      await db.typedCollection(backupNodeSchema).put(BackupNode(1));
      // Act / Assert.
      await expectLater(
        failingQuery(db),
        throwsA(
          isA<CindelError>()
              .having((error) => error.cause, 'cause', isNotNull)
              .having(
                (error) => error.message.toLowerCase(),
                'detail',
                contains('filter'),
              ),
        ),
      );
      expect(await db.documentIds('backup_nodes'), [1]);
    });

    // Scenario: A transaction callback closes its database and then throws a
    // known error instance.
    // Covers:
    // - Original callback error preservation after close-triggered rollback.
    // Expected: The caller receives that exact error instance.
    test(
      'preserves the original callback error after close rolls back.',
      () async {
        // Arrange.
        final fixture = await open();
        final original = StateError('controlled callback failure');
        // Act / Assert.
        await expectLater(
          fixture.db.writeTxn(() async {
            await fixture.db.close();
            throw original;
          }),
          throwsA(same(original)),
        );
      },
    );
  });
}
