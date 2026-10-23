import 'dart:async';
import 'dart:convert';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'backup_contract_fixture.dart';
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';

void main() {
  group('Cindel relation lifecycle', () {
    Future<CindelDatabase> open({
      CindelCollectionSchema<BackupNode>? schema,
      String? path,
    }) async {
      final directory = path ?? await createCloseTestDirectory();
      if (path == null) addTearDown(() => deleteCloseTestDirectory(directory));
      final db = await openTestDatabase(
        directory: directory,
        schemas: [schema ?? backupNodeSchema, backupLeafSchema],
      );
      addTearDown(db.close);
      return db;
    }

    Future<void> seed(
      CindelDatabase db, [
      CindelCollectionSchema<BackupNode>? schema,
    ]) async {
      await db.typedCollection(schema ?? backupNodeSchema).putAll([
        BackupNode(1),
        BackupNode(2),
        BackupNode(3),
      ]);
      await db.typedCollection(backupLeafSchema).put(BackupNode(1));
      await link(db, 'backup_nodes', 1, 'children', [1, 2]);
      await link(db, 'backup_nodes', 2, 'children', [1]);
      await link(db, 'backup_leaves', 1, 'children', [1, 3]);
      await link(db, 'backup_leaves', 1, 'parent', [1]);
    }

    Future<void> assertDeleted(
      CindelDatabase db,
      CindelCollectionSchema<BackupNode> schema,
    ) async {
      await db
          .typedCollection(schema)
          .put(BackupNode(1, payload: 'replacement'));
      final replacement = (await db.typedCollection(schema).get(1))!;
      await replacement.children.load();
      await replacement.owners.load();
      expect(replacement.children, isEmpty);
      expect(replacement.owners, isEmpty);
      final leaf = (await db.typedCollection(backupLeafSchema).get(1))!;
      await leaf.children.load();
      await leaf.parent.load();
      expect(leaf.children.map((n) => n.dbId), [3]);
      expect(leaf.parent.value, isNull);
      expect(
        (await db.cleanupOrphanLinks()).removedLinks,
        0,
        reason:
            'Deletes must remove the stored edges, not just hide missing targets.',
      );
    }

    for (final indexed in [false, true]) {
      for (final operation in ['single', 'batch', 'query']) {
        test(
          '$operation deletion removes incoming/outgoing links with indexed=$indexed and survives reopen.',
          () async {
            final schema = indexed
                ? backupNodeSchema
                : _nodeSchema(indexed: false);
            var db = await open(schema: schema);
            await seed(db, schema);
            final nodes = db.typedCollection(schema);
            switch (operation) {
              case 'single':
                await nodes.delete(1);
              case 'batch':
                await nodes.deleteAll([1, 1, 999]);
              case 'query':
                expect(
                  await nodes.all().sortBy('dbId').limit(1).deleteAll(),
                  1,
                );
            }
            final path = db.directory;
            await db.close();
            db = await open(schema: schema, path: path);
            await assertDeleted(db, schema);
          },
        );
      }
    }

    test(
      'updates preserve links; rollback restores edges; delete/reinsert does not resurrect them.',
      () async {
        final db = await open();
        await seed(db);
        final nodes = db.typedCollection(backupNodeSchema);
        await nodes.put(BackupNode(1, payload: 'updated'));
        var row = (await nodes.get(1))!;
        await row.children.load();
        expect(row.children.map((n) => n.dbId).toSet(), {1, 2});
        await expectLater(
          db.writeTxn(() async {
            await nodes.delete(1);
            await nodes.put(BackupNode(1));
            final leaf = (await db.typedCollection(backupLeafSchema).get(1))!;
            await leaf.parent.load();
            expect(leaf.parent.value, isNull);
            throw StateError('rollback');
          }),
          throwsStateError,
        );
        row = (await nodes.get(1))!;
        await row.children.load();
        expect(row.children.map((n) => n.dbId).toSet(), {1, 2});
        await db.writeTxn(() async {
          await nodes.delete(1);
          await nodes.put(BackupNode(1));
        });
        await assertDeleted(db, backupNodeSchema);
        await db.writeTxn(() async {
          await link(db, 'backup_nodes', 1, 'children', [2]);
          await nodes.delete(1);
          await nodes.put(BackupNode(1));
          await link(db, 'backup_nodes', 1, 'children', [3]);
        });
        row = (await nodes.get(1))!;
        await row.children.load();
        expect(row.children.map((n) => n.dbId), [3]);
      },
    );

    for (final batch in [false, true]) {
      test('unique replacement cleans the evicted ID, batch=$batch.', () async {
        final schema = _nodeSchema(replace: true);
        final db = await open(schema: schema);
        await seed(db, schema);
        final nodes = db.typedCollection(schema);
        final replacement = BackupNode(9, code: 1);
        if (batch) {
          await nodes.putAll([replacement]);
        } else {
          await nodes.put(replacement);
        }
        expect(await nodes.get(1), isNull);
        await nodes.put(BackupNode(1, code: 10));
        final leaf = (await db.typedCollection(backupLeafSchema).get(1))!;
        await leaf.parent.load();
        expect(leaf.parent.value, isNull);
        final report = await db.cleanupOrphanLinks();
        expect(report.removedLinks, 0);
        final row = (await nodes.get(1))!;
        await row.children.load();
        expect(row.children, isEmpty);
      });
    }

    test(
      'only related watchers are notified after commit, never on rollback.',
      () async {
        final db = await open();
        await seed(db);
        final events = <CindelChangeSet>[];
        final subscription = db
            .watchCollectionChanges(
              'backup_leaves',
              fireImmediately: false,
              pollInterval: const Duration(hours: 1),
            )
            .listen(events.add);
        addTearDown(subscription.cancel);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await expectLater(
          db.writeTxn(() async {
            await db.typedCollection(backupNodeSchema).delete(1);
            await Future<void>.delayed(const Duration(milliseconds: 10));
            expect(events, isEmpty);
            throw StateError('rollback');
          }),
          throwsStateError,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events, isEmpty);
        await db.writeTxn(() async {
          await db.typedCollection(backupNodeSchema).delete(1);
          expect(events, isEmpty);
        });
        for (var i = 0; i < 100 && events.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(events, hasLength(1));
        expect(events.single.documentIds, isNull);
        expect(events.single.isExternal, isFalse);
      },
    );

    test(
      'migration reconstruction preserves identities; explicit cleanup removes only orphaned edges.',
      () async {
        final original = await open();
        await seed(original);
        final path = original.directory;
        await original.close();
        final db = await CindelDatabase.openForMigration(
          directory: path,
          schemas: [backupNodeSchema, backupLeafSchema],
          backend: testStorageBackend,
        );
        addTearDown(db.close);
        await db.registerMigratedSchemas([backupNodeSchema, backupLeafSchema]);
        await db.typedCollection(backupNodeSchema).putAll([
          BackupNode(1),
          BackupNode(2),
        ]);
        await db.typedCollection(backupLeafSchema).put(BackupNode(1));
        final row = (await db.typedCollection(backupNodeSchema).get(1))!;
        await row.children.load();
        expect(row.children.map((n) => n.dbId).toSet(), {1, 2});
        await expectLater(
          db.readTxn(() => db.cleanupOrphanLinks()),
          throwsStateError,
        );
        await expectLater(
          db.writeTxn(() => db.cleanupOrphanLinks()),
          throwsStateError,
        );
        final report = await db.cleanupOrphanLinks();
        expect(report.examinedLinks, 6);
        expect(report.removedLinks, 1);
        expect(await db.cleanupOrphanLinks(), (
          examinedLinks: 5,
          removedLinks: 0,
        ));
        await db.typedCollection(backupNodeSchema).put(BackupNode(3));
        final leaf = (await db.typedCollection(backupLeafSchema).get(1))!;
        await leaf.children.load();
        expect(leaf.children.map((n) => n.dbId), [1]);
      },
    );

    test(
      'backup after deletion restores a closed graph without orphaned links.',
      () async {
        final db = await open();
        await seed(db);
        await db.typedCollection(backupNodeSchema).delete(1);
        final sink = _Bytes();
        final selection = [
          CindelBackupCollection<BackupNode>(backupNodeSchema),
          CindelBackupCollection<BackupNode>(backupLeafSchema),
        ];
        await CindelBackup.exportDatabase(
          database: db,
          collections: selection,
          output: sink,
          compression: CindelBackupCompression.none,
        );
        final records = const LineSplitter()
            .convert(utf8.decode(sink.bytes))
            .map((s) => jsonDecode(s) as Map);
        expect(records.where((r) => r['type'] == 'link'), hasLength(1));
        await db.close();
        final target = await open();
        await CindelBackup.importDatabase(
          database: target,
          collections: selection,
          input: Stream.value(sink.bytes),
          compression: CindelBackupCompression.none,
        );
        await assertDeleted(target, backupNodeSchema);
      },
    );

    test(
      'cleanup admitted before close completes without notification work on a closed handle.',
      () async {
        final db = await open();
        final pending = db.cleanupOrphanLinks();
        final closed = db.close();
        expect(await pending, (examinedLinks: 0, removedLinks: 0));
        await closed;
        await expectLater(db.cleanupOrphanLinks(), throwsStateError);
      },
    );

    test(
      'deletes 4096 incident links and retains unrelated relations.',
      () async {
        final db = await open();
        await db.typedCollection(backupNodeSchema).putAll([
          for (var id = 1; id <= 4098; id++) BackupNode(id),
        ]);
        await link(db, 'backup_nodes', 1, 'children', [
          for (var id = 2; id <= 4097; id++) id,
        ]);
        await link(db, 'backup_nodes', 4098, 'children', [4097]);
        await db.typedCollection(backupNodeSchema).delete(1);
        expect(await db.cleanupOrphanLinks(), (
          examinedLinks: 1,
          removedLinks: 0,
        ));
        final row = (await db.typedCollection(backupNodeSchema).get(4097))!;
        await row.owners.load();
        expect(row.owners.single.dbId, 4098);
      },
    );
  });
}

Future<void> link(
  CindelDatabase db,
  String source,
  int id,
  String name,
  List<int> ids,
) => db.saveLinkIds(
  sourceCollection: source,
  sourceId: id,
  linkName: name,
  targetCollection: 'backup_nodes',
  targetIds: ids,
);

CindelCollectionSchema<BackupNode> _nodeSchema({
  bool indexed = true,
  bool replace = false,
}) => CindelCollectionSchema<BackupNode>(
  name: backupNodeSchema.name,
  dartName: 'BackupNode',
  idField: 'dbId',
  fields: [
    for (final f in backupNodeSchema.fields)
      f.name == 'code'
          ? CindelFieldSchema(
              name: 'code',
              dartType: 'int',
              binaryType: 'int',
              isId: false,
              isIndexed: indexed,
              isIndexUnique: indexed,
              isIndexReplace: replace,
            )
          : f,
  ],
  links: backupNodeSchema.links,
  toDocument: backupNodeSchema.toDocument,
  fromDocument: backupNodeSchema.fromDocument,
  toBinaryDocument: backupNodeSchema.toBinaryDocument,
  fromBinaryDocument: backupNodeSchema.fromBinaryDocument,
  writeNativeDocument: backupNodeSchema.writeNativeDocument,
  readNativeDocument: backupNodeSchema.readNativeDocument,
  getId: backupNodeSchema.getId,
  setId: backupNodeSchema.setId,
  bindLinks: backupNodeSchema.bindLinks,
);

final class _Bytes implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}
