import 'dart:async';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backup_contract_fixture.dart';
import 'backup_contract_suite.dart' show BackupBytesConsumer;
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';

void main({bool concurrentHandles = true}) {
  group('SQLite persistent revisions', () {
    Future<CindelDatabase> open([String? path]) async {
      if (path == null) {
        path = await createCloseTestDirectory();
        final directory = path;
        addTearDown(() => deleteCloseTestDirectory(directory));
      }
      final db = await Cindel.open(
        directory: path,
        backend: CindelStorageBackend.sqlite,
        schemas: [backupNodeSchema],
      );
      addTearDown(db.close);
      return db;
    }

    Future<List<CindelChangeSet>> observe(CindelDatabase db) async {
      final events = <CindelChangeSet>[];
      final subscription = db
          .watchCollectionChanges(
            'backup_nodes',
            pollInterval: const Duration(milliseconds: 5),
          )
          .listen(events.add);
      addTearDown(subscription.cancel);
      await _until(() => events.isNotEmpty);
      return events;
    }

    // Scenario: A typed write rolls back with an already initialized watcher.
    // Covers: Real revision polling after rollback, without a later write masking it.
    // Expected: No change event; the next successful commit is still delivered.
    test('rollback does not publish a phantom change.', () async {
      // Arrange.
      final db = await open();
      final nodes = db.typedCollection(backupNodeSchema);
      await nodes.put(BackupNode(1, payload: 'original'));
      final events = await observe(db);
      final initial = events.length;
      final error = StateError('controlled rollback');
      // Act / Assert.
      await expectLater(
        db.writeTxn(() async {
          await nodes.put(BackupNode(2));
          await nodes.all().updateAll({'payload': 'uncommitted'});
          await nodes.delete(1);
          throw error;
        }),
        throwsA(same(error)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events.length, initial);
      expect((await nodes.get(1))!.payload, 'original');
      expect(await nodes.get(2), isNull);
      await nodes.put(BackupNode(2));
      await _until(() => events.length > initial);
      expect(await nodes.all().count(), 2);
    });

    // Scenario: Saving/removing links is rolled back before a poll can observe it.
    // Covers: Relation revisions and deletion cleanup through Worker/Wasm too.
    // Expected: Neither relation changes nor revisions survive rollback.
    test(
      'relation rollback preserves data and the observed revision.',
      () async {
        // Arrange.
        final db = await open();
        final nodes = db.typedCollection(backupNodeSchema);
        await nodes.putAll([BackupNode(1), BackupNode(2)]);
        final events = await observe(db);
        final initial = events.length;
        // Act / Assert.
        await expectLater(
          db.writeTxn(() async {
            await db.saveLinkIds(
              sourceCollection: 'backup_nodes',
              sourceId: 1,
              linkName: 'children',
              targetCollection: 'backup_nodes',
              targetIds: [2],
            );
            await nodes.delete(2);
            throw StateError('rollback relations');
          }),
          throwsStateError,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(events.length, initial);
        expect(await nodes.all().count(), 2);
        await db.saveLinkIds(
          sourceCollection: 'backup_nodes',
          sourceId: 1,
          linkName: 'children',
          targetCollection: 'backup_nodes',
          targetIds: [2],
        );
        await _until(() => events.length > initial);
        final afterSave = events.length;
        await nodes.delete(2);
        await _until(() => events.length > afterSave);
      },
    );

    // Scenario: A late batch row violates a unique index, then a valid write runs.
    // Covers: Failed statements, clean revision retry and no idle phantom events.
    // Expected: The failure leaves both the collection and revision unchanged.
    test('failed batch preserves the revision and permits a retry.', () async {
      // Arrange.
      final db = await open();
      final nodes = db.typedCollection(backupNodeSchema);
      await nodes.put(BackupNode(1));
      final events = await observe(db);
      final initial = events.length;
      // Act / Assert.
      await expectLater(
        nodes.putAll([BackupNode(2), BackupNode(3, code: 1)]),
        throwsA(
          predicate(
            (error) => error.toString().toLowerCase().contains('unique'),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(events.length, initial);
      expect(await nodes.all().count(), 1);
      await nodes.put(BackupNode(2));
      await _until(() => events.length > initial);
    });

    // Scenario: A database is closed and reopened after a batch, then migrated.
    // Covers: Persistent revision metadata through native and real Web reopen.
    // Expected: Later notifications keep increasing instead of restarting at one.
    test(
      'reopen and migration preserve monotonic revision metadata.',
      () async {
        // Arrange.
        var db = await open();
        final path = db.directory;
        final first = await observe(db);
        await db.typedCollection(backupNodeSchema).putAll([
          BackupNode(1),
          BackupNode(2),
        ]);
        await _until(() => first.any((event) => event.revision != null));
        final before = first
            .lastWhere((event) => event.revision != null)
            .revision!;
        await db.setMigrationVersion(1);
        await db.close();
        // Act.
        db = await open(path);
        final reopened = await observe(db);
        await db.typedCollection(backupNodeSchema).put(BackupNode(3));
        await _until(() => reopened.any((event) => event.revision != null));
        final after = reopened
            .lastWhere((event) => event.revision != null)
            .revision!;
        // Assert.
        expect(after, before + 1);
        await db.close();
        db = await Cindel.open(
          directory: path,
          backend: CindelStorageBackend.sqlite,
          schemas: [backupNodeSchema],
          migrationPlan: CindelMigrationPlan(
            targetVersion: 2,
            compactOnSuccess: false,
            steps: [
              CindelMigrationStep(
                fromVersion: 1,
                toVersion: 2,
                openSchemas: [backupNodeSchema],
                targetSchemas: [backupNodeSchema],
                migrate: (context) async {
                  await context.registerTargetSchemas();
                  await context.importObjectStream(
                    backupNodeSchema,
                    context.streamObjects(backupNodeSchema),
                    batchSize: 2,
                  );
                  await context.database
                      .typedCollection(backupNodeSchema)
                      .put(BackupNode(4));
                },
              ),
            ],
          ),
        );
        addTearDown(db.close);
        final migrated = await observe(db);
        await db.typedCollection(backupNodeSchema).put(BackupNode(5));
        await _until(() => migrated.any((event) => event.revision != null));
        expect(
          migrated.lastWhere((event) => event.revision != null).revision,
          greaterThan(after),
        );
        expect(await db.typedCollection(backupNodeSchema).all().count(), 5);
      },
    );

    // Scenario: Restore several batches and then perform a normal typed write.
    // Covers: Published revisions through SQLite native and Web import paths.
    // Expected: The restored revision is persisted and advanced by the next write.
    test('restore publishes a revision before normal writes resume.', () async {
      // Arrange.
      final source = await open();
      await source.typedCollection(backupNodeSchema).putAll([
        BackupNode(1),
        BackupNode(2),
      ]);
      final output = BackupBytesConsumer();
      await CindelBackup.exportDatabase(
        database: source,
        collections: [CindelBackupCollection<BackupNode>(backupNodeSchema)],
        output: output,
        compression: CindelBackupCompression.none,
        batchSize: 1,
      );
      await source.close();
      var target = await open();
      final path = target.directory;
      // Act.
      await CindelBackup.importDatabase(
        database: target,
        collections: [CindelBackupCollection<BackupNode>(backupNodeSchema)],
        input: Stream.value(output.bytes),
        compression: CindelBackupCompression.none,
        batchSize: 1,
      );
      await target.close();
      target = await open(path);
      final events = await observe(target);
      await target.typedCollection(backupNodeSchema).put(BackupNode(3));
      await _until(() => events.any((event) => event.revision != null));
      // Assert.
      expect(events.lastWhere((event) => event.revision != null).revision, 2);
      expect(await target.typedCollection(backupNodeSchema).all().count(), 3);
    });

    if (concurrentHandles) {
      // Scenario: Another connection writes without any watchers of its own.
      // Covers: Typed batch/update/delete polling, external events and reconnects.
      // Expected: The observing handle sees every confirmed operation.
      test(
        'observes writes by another connection with no listeners.',
        () async {
          // Arrange.
          final reader = await open();
          var writer = await open(reader.directory);
          final events = await observe(reader);
          var observed = events.length;
          Future<void> changed(Future<Object?> Function() action) async {
            await action();
            await _until(() => events.length > observed);
            expect(events.last.isExternal, isTrue);
            observed = events.length;
          }

          // Act.
          await changed(
            () => writer.typedCollection(backupNodeSchema).putAll([
              BackupNode(1),
              BackupNode(2),
            ]),
          );
          await writer.close();
          writer = await open(reader.directory);
          await changed(
            () => writer.typedCollection(backupNodeSchema).all().updateAll({
              'payload': 'updated',
            }),
          );
          // Assert.
          expect(
            (await reader.typedCollection(backupNodeSchema).get(1))!.payload,
            'updated',
          );
          await changed(
            () => writer.typedCollection(backupNodeSchema).delete(1),
          );
          await changed(
            () => writer.typedCollection(backupNodeSchema).all().deleteAll(),
          );
          expect(
            await reader.typedCollection(backupNodeSchema).all().count(),
            0,
          );
        },
      );
    }
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Revision event missing.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
