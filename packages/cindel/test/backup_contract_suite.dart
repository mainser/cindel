import 'dart:async';
import 'dart:convert';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'backup_contract_fixture.dart';
import 'backup_typing_suite.dart' as backup_typing;
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'dart_distinct_fixture.dart';
import 'schema_generation_fixture.dart' show Recipient, RecipientMetadata;

void main({bool includeSameDirectoryHandles = true}) {
  backup_typing.main();
  group('Cindel backup atomic contract', () {
    final collections = [CindelBackupCollection(backupNodeSchema)];

    Future<CindelDatabase> open([
      String? directory,
      List<CindelCollectionSchema<dynamic>>? schemas,
    ]) async {
      final path = directory ?? await createCloseTestDirectory();
      if (directory == null) addTearDown(() => deleteCloseTestDirectory(path));
      final db = await openTestDatabase(
        directory: path,
        schemas: schemas ?? [backupNodeSchema],
      );
      addTearDown(db.close);
      return db;
    }

    Future<List<Map<String, dynamic>>> archive({
      int nodes = 3,
      bool withLinks = true,
    }) async {
      final source = await open();
      await source.typedCollection(backupNodeSchema).putAll([
        for (var i = 1; i <= nodes; i++) BackupNode(i, payload: 'n$i'),
      ]);
      await source.setMigrationVersion(7);
      if (withLinks) {
        await source.saveLinkIds(
          sourceCollection: 'backup_nodes',
          sourceId: 1,
          linkName: 'children',
          targetCollection: 'backup_nodes',
          targetIds: [for (var i = 1; i <= nodes; i++) i],
        );
        await source.saveLinkIds(
          sourceCollection: 'backup_nodes',
          sourceId: 2,
          linkName: 'parent',
          targetCollection: 'backup_nodes',
          targetIds: [1],
        );
        await source.saveLinkIds(
          sourceCollection: 'backup_nodes',
          sourceId: 3,
          linkName: 'children',
          targetCollection: 'backup_nodes',
          targetIds: [1],
        );
      }
      final output = BackupBytesConsumer();
      await CindelBackup.exportDatabase(
        database: source,
        collections: collections,
        output: output,
        compression: CindelBackupCompression.none,
        batchSize: 2,
      );
      await source.close();
      return const LineSplitter()
          .convert(utf8.decode(output.bytes))
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList();
    }

    Future<void> restore(
      CindelDatabase db,
      List<Map<String, dynamic>> records, {
      bool legacy = false,
    }) => CindelBackup.importDatabase(
      database: db,
      collections: collections,
      input: _stream(records),
      batchSize: 1,
      compression: CindelBackupCompression.none,
      allowLegacyWithoutLinks: legacy,
    );

    Future<void> unchanged(CindelDatabase db) async {
      expect(await db.documentIdsPage('backup_nodes', limit: 1), isEmpty);
      expect(await db.migrationVersion(), 9);
      expect(
        await db.allocateId('backup_nodes'),
        1,
        reason: 'Failed restore must not advance IDs.',
      );
    }

    // Scenario: A version-two archive contains paged links, cycles, backlinks
    // and allocation metadata.
    // Covers:
    // - Export/import round-trip and reopening the restored graph.
    // Expected: All expected edges load, migration version is seven and the
    // next node ID is 14.
    test(
      'round-trips paged links, cycles, backlinks and metadata, then reopens.',
      () async {
        // Arrange: use the inputs described in this scenario.
        // Act.
        final records = await archive(nodes: 13);
        // Assert.
        expect(records.first['version'], 2);
        expect(records.where((r) => r['type'] == 'link'), hasLength(15));
        var target = await open();
        final directory = target.directory;
        await restore(target, records);
        await target.close();
        target = await open(directory);
        final one = (await target.typedCollection(backupNodeSchema).get(1))!;
        await one.children.load();
        await one.owners.load();
        expect(one.children.map((n) => n.dbId).toList()..sort(), [
          for (var i = 1; i <= 13; i++) i,
        ]);
        expect(one.owners.map((n) => n.dbId).toList()..sort(), [1, 3]);
        final two = (await target.typedCollection(backupNodeSchema).get(2))!;
        await two.parent.load();
        expect(two.parent.value!.dbId, 1);
        expect(await target.migrationVersion(), 7);
        expect(await target.allocateId('backup_nodes'), 14);
      },
    );

    // Scenario: Generated rows contain nested embedded objects, Unicode
    // strings, nulls and empty lists.
    // Covers:
    // - Typed backup serialization and hydration for scalar/list/embedded
    // fields.
    // Expected: Restored rows retain list contents, nested labels and the
    // distinction between empty lists and null fields.
    test(
      'preserves generated embedded objects, nulls and empty/string lists.',
      () async {
        // Arrange.
        final source = await open(null, [DistinctRecordSchema]);
        final row = DistinctRecord()
          ..dbId = 1
          ..name = 'one'
          ..email = 'one@local'
          ..tags = ['a, b', '', 'á🚀']
          ..primaryRecipient = (Recipient()
            ..name = 'nested'
            ..metadata = (RecipientMetadata()..label = 'inner'))
          ..recipients = [Recipient()..name = 'list'];
        await source.distinctRecords.putAll([
          row,
          DistinctRecord()
            ..dbId = 2
            ..name = 'two'
            ..email = 'two@local',
        ]);
        final output = BackupBytesConsumer();
        // Act.
        await CindelBackup.exportDatabase(
          database: source,
          collections: [
            CindelBackupCollection<DistinctRecord>(DistinctRecordSchema),
          ],
          output: output,
          compression: CindelBackupCompression.none,
        );
        await source.close();
        final target = await open(null, [DistinctRecordSchema]);
        await CindelBackup.importDatabase(
          database: target,
          collections: [
            CindelBackupCollection<DistinctRecord>(DistinctRecordSchema),
          ],
          input: Stream.value(output.bytes),
          compression: CindelBackupCompression.none,
        );
        final restored = (await target.distinctRecords.get(1))!;
        // Assert.
        expect(restored.tags, row.tags);
        expect(restored.displayName, isNull);
        expect(restored.primaryRecipient!.metadata!.label, 'inner');
        expect(restored.recipients!.single.name, 'list');
        final empty = (await target.distinctRecords.get(2))!;
        expect(empty.tags, isEmpty);
        expect(empty.recipients, isNull);
      },
    );

    // Scenario: An archive links two collections, then a copy is corrupted
    // with a missing target.
    // Covers:
    // - Atomic cross-collection restore and backlink reconstruction.
    // Expected: The corrupted import leaves both collections empty; the valid
    // archive restores both forward and reverse relationships.
    test(
      'restores cross-collection links atomically with their backlinks.',
      () async {
        // Arrange.
        final schemas = [backupNodeSchema, backupLeafSchema];
        final selection = [
          CindelBackupCollection(backupNodeSchema),
          CindelBackupCollection(backupLeafSchema),
        ];
        final source = await open(null, schemas);
        await source.typedCollection(backupNodeSchema).put(BackupNode(1));
        await source.typedCollection(backupLeafSchema).put(BackupNode(1));
        await source.saveLinkIds(
          sourceCollection: 'backup_leaves',
          sourceId: 1,
          linkName: 'children',
          targetCollection: 'backup_nodes',
          targetIds: [1],
        );
        final output = BackupBytesConsumer();
        // Act.
        await CindelBackup.exportDatabase(
          database: source,
          collections: selection,
          output: output,
          compression: CindelBackupCompression.none,
        );
        await source.close();
        final target = await open(null, schemas);
        final records = const LineSplitter()
            .convert(utf8.decode(output.bytes))
            .map((s) => jsonDecode(s) as Map<String, dynamic>)
            .toList();
        records.firstWhere((r) => r['type'] == 'link')['targetId'] = 404;
        _checksum(records);
        // Assert.
        await expectLater(
          CindelBackup.importDatabase(
            database: target,
            collections: selection,
            input: _stream(records),
            batchSize: 1,
            compression: CindelBackupCompression.none,
          ),
          throwsStateError,
        );
        expect(await target.documentIdsPage('backup_nodes', limit: 1), isEmpty);
        expect(
          await target.documentIdsPage('backup_leaves', limit: 1),
          isEmpty,
        );
        await CindelBackup.importDatabase(
          database: target,
          collections: selection,
          input: Stream.value(output.bytes),
          compression: CindelBackupCompression.none,
        );
        final leaf = (await target.typedCollection(backupLeafSchema).get(1))!;
        await leaf.children.load();
        expect(leaf.children.single.dbId, 1);
        final backlinks = await target.loadBacklinkObjects<BackupNode>(
          ownerCollection: 'backup_nodes',
          ownerId: 1,
          sourceCollection: 'backup_leaves',
          sourceLinkName: 'children',
        );
        expect(backlinks.single.dbId, 1);
      },
    );

    // Scenario: An export selection omits the collection targeted by a
    // forward link.
    // Covers:
    // - Graph-closure validation before archive output starts.
    // Expected: Export fails with StateError and emits no bytes.
    test(
      'rejects omitted forward-link collections before exporting.',
      () async {
        // Arrange.
        final partial = CindelCollectionSchema<BackupNode>(
          name: 'partial_nodes',
          dartName: 'BackupNode',
          idField: 'dbId',
          fields: backupNodeSchema.fields,
          links: backupNodeSchema.links,
          toDocument: backupNodeSchema.toDocument,
          fromDocument: backupNodeSchema.fromDocument,
        );
        final source = await open(null, [backupNodeSchema, partial]);
        final output = BackupBytesConsumer();
        // Act / Assert.
        await expectLater(
          CindelBackup.exportDatabase(
            database: source,
            collections: [CindelBackupCollection(partial)],
            output: output,
            compression: CindelBackupCompression.none,
          ),
          throwsStateError,
        );
        expect(output.bytes, isEmpty);
      },
    );

    // Scenario: An export output callback tries to write through the
    // exporting handle and then fails.
    // Covers:
    // - Read-snapshot write rejection and snapshot release on output errors.
    // Expected: The nested write fails, export propagates failure and a
    // subsequent write succeeds with IDs 1/3 present.
    test(
      'export rejects writes through its own handle and releases its snapshot on output error.',
      () async {
        // Arrange.
        final source = await open();
        await source.typedCollection(backupNodeSchema).put(BackupNode(1));
        final output = BackupBytesConsumer(
          onChunk: (_) async {
            await expectLater(
              source.typedCollection(backupNodeSchema).put(BackupNode(2)),
              throwsA(
                predicate<Object>(
                  (error) => error.toString().contains('read transaction'),
                ),
              ),
            );
            throw StateError('Output failed.');
          },
        );
        // Act / Assert.
        await expectLater(
          CindelBackup.exportDatabase(
            database: source,
            collections: collections,
            output: output,
            compression: CindelBackupCompression.none,
          ),
          throwsStateError,
        );
        await source.typedCollection(backupNodeSchema).put(BackupNode(3));
        expect(await source.documentIdsPage('backup_nodes', limit: 10), [1, 3]);
      },
    );

    for (final corruption in [
      'checksum',
      'truncate',
      'duplicate-footer',
      'after-footer',
      'schema',
      'duplicate-id',
      'unique-index',
      'dangling-link',
      'to-one',
      'duplicate-link',
      'decode',
    ]) {
      // Scenario: Each corruption variant damages archive structure, schema,
      // IDs, uniqueness, links or decoded values.
      // Covers:
      // - Atomic restore rejection and cleanup of staged batches.
      // Expected: Failure leaves documents, relations, counters and metadata
      // unchanged; retrying the valid archive restores IDs 1/2/3.
      test(
        '$corruption leaves documents, relations, IDs and metadata unchanged.',
        () async {
          // Arrange.
          final records = await archive();
          final original = jsonDecode(jsonEncode(records)) as List;
          final docs = records.where((r) => r['type'] == 'doc').toList();
          switch (corruption) {
            case 'checksum':
              records.last['checksum'] = 0;
            case 'truncate':
              records.removeLast();
            case 'duplicate-footer':
              records.add(Map.of(records.last));
            case 'after-footer':
              records.add(Map.of(docs.first));
            case 'schema':
              (records[1]['manifest'] as Map)['id'] = 'wrong';
              _checksum(records);
            case 'duplicate-id':
              docs[1]['id'] = docs[0]['id'];
              docs[1]['document']['dbId'] = docs[0]['id'];
              _checksum(records);
            case 'unique-index':
              docs.last['document']['code'] = 1;
              _checksum(records);
            case 'dangling-link':
              records.firstWhere((r) => r['type'] == 'link')['targetId'] = 999;
              _checksum(records);
            case 'to-one':
              final edge = Map<String, dynamic>.of(
                records.firstWhere((r) => r['name'] == 'parent'),
              )..['targetId'] = 3;
              records.insert(records.length - 1, edge);
              records.last['links']++;
              _checksum(records);
            case 'duplicate-link':
              records.insert(
                records.length - 1,
                Map.of(records.firstWhere((r) => r['type'] == 'link')),
              );
              records.last['links']++;
              _checksum(records);
            case 'decode':
              docs.last['document']['payload'] = 42;
              _checksum(records);
          }
          final target = await open();
          await target.setMigrationVersion(9);
          // Act / Assert.
          await expectLater(restore(target, records), throwsA(anything));
          await unchanged(target);
          // Reuse the same wrappers after failure: no pending objects may leak.
          await restore(target, original.cast<Map<String, dynamic>>());
          expect(await target.documentIdsPage('backup_nodes', limit: 10), [
            1,
            2,
            3,
          ]);
        },
      );
    }

    // Scenario: Input streaming or progress reporting throws after document
    // batches were flushed.
    // Covers:
    // - Restore rollback after asynchronous producer/callback failures.
    // Expected: StateError propagates and the target retains its pre-import
    // state.
    test(
      'stream and progress failures after flushed batches are atomic.',
      () async {
        // Arrange.
        final records = await archive();
        // Act / Assert.
        for (final progressFailure in [false, true]) {
          final target = await open();
          await target.setMigrationVersion(9);
          Stream<List<int>> broken() async* {
            yield* _stream(records.take(4));
            throw StateError('Input failed after the first batches.');
          }

          await expectLater(
            CindelBackup.importDatabase(
              database: target,
              collections: collections,
              input: progressFailure ? _stream(records) : broken(),
              batchSize: 1,
              compression: CindelBackupCompression.none,
              onProgress: progressFailure
                  ? (p) {
                      if (p.documents == 3) {
                        throw StateError('Progress failed.');
                      }
                    }
                  : null,
            ),
            throwsStateError,
          );
          await unchanged(target);
          await target.close();
        }
      },
    );

    // Scenario: A concurrent row appears after archive staging but before
    // publication.
    // Covers:
    // - Final target-emptiness validation without deleting concurrent data.
    // Expected: Restore is rejected and the independently inserted ID 50
    // remains.
    test(
      'rechecks target emptiness when publishing without deleting concurrent data.',
      () async {
        // Arrange.
        final records = await archive();
        final target = await open();
        Stream<List<int>> raced() async* {
          yield* _stream(records.take(records.length - 1));
          await target.typedCollection(backupNodeSchema).put(BackupNode(50));
          yield* _stream([records.last]);
        }

        // Act / Assert.
        await expectLater(
          CindelBackup.importDatabase(
            database: target,
            collections: collections,
            input: raced(),
            batchSize: 1,
            compression: CindelBackupCompression.none,
          ),
          throwsStateError,
        );
        expect(await target.documentIdsPage('backup_nodes', limit: 10), [50]);
      },
    );

    // Scenario: A separate transaction occupies the target when staged data
    // is ready to publish.
    // Covers:
    // - Failed-publication cleanup and reuse of the same target.
    // Expected: Import fails without publishing rows, and a later restore
    // succeeds after the transaction is released.
    test(
      'cleans staging when another transaction prevents publication.',
      () async {
        // Arrange.
        final records = await archive();
        final target = await open();
        final started = Completer<void>();
        final release = Completer<void>();
        Future<void>? transaction;
        Stream<List<int>> busy() async* {
          yield* _stream(records.take(records.length - 1));
          transaction = target.writeTxn(() async {
            started.complete();
            await release.future;
          });
          await started.future;
          yield* _stream([records.last]);
        }

        // Act / Assert.
        try {
          await expectLater(
            CindelBackup.importDatabase(
              database: target,
              collections: collections,
              input: busy(),
              batchSize: 1,
              compression: CindelBackupCompression.none,
            ),
            throwsStateError,
          );
        } finally {
          release.complete();
          await transaction;
        }
        expect(await target.documentIdsPage('backup_nodes', limit: 1), isEmpty);
        await restore(target, records);
      },
    );

    // Scenario: A legacy version-one archive is imported into a linked
    // schema.
    // Covers:
    // - Explicit acknowledgement of missing legacy link data.
    // Expected: Default import rejects the archive; opting in restores its
    // three documents.
    test(
      'legacy archives require explicit acknowledgement for lost links.',
      () async {
        // Arrange.
        final records = await archive(withLinks: false);
        records.first['version'] = 1;
        records[1].remove('manifest');
        records.last.remove('links');
        _checksum(records);
        final target = await open();
        // Act / Assert.
        await expectLater(restore(target, records), throwsStateError);
        await restore(target, records, legacy: true);
        expect(await target.documentIdsPage('backup_nodes', limit: 10), [
          1,
          2,
          3,
        ]);
      },
    );

    // Scenario: A legacy document-only import selects one collection and
    // explicitly accepts missing links.
    // Covers:
    // - Partial legacy selections with omitted forward-link destinations.
    // Expected: Only the selected leaf collection receives IDs 1/2/3; the
    // destination collection stays empty.
    test(
      'legacy document-only selection can omit link destinations explicitly.',
      () async {
        // Arrange.
        final records = await archive(withLinks: false);
        records.first['version'] = 1;
        records[1].remove('manifest');
        records.last.remove('links');
        for (final record in records) {
          if (record['collection'] == 'backup_nodes') {
            record['collection'] = 'backup_leaves';
          }
        }
        _checksum(records);
        final target = await open(null, [backupNodeSchema, backupLeafSchema]);
        // Act.
        await CindelBackup.importDatabase(
          database: target,
          collections: [CindelBackupCollection<BackupNode>(backupLeafSchema)],
          input: _stream(records),
          compression: CindelBackupCompression.none,
          allowLegacyWithoutLinks: true,
        );
        // Assert.
        expect(await target.documentIdsPage('backup_leaves', limit: 10), [
          1,
          2,
          3,
        ]);
        expect(await target.documentIdsPage('backup_nodes', limit: 1), isEmpty);
      },
    );

    // Scenario: An import receives an oversized unfinished record or its
    // database closes during staging.
    // Covers:
    // - Record byte limits, close-time cleanup and retry after reopening.
    // Expected: Both imports fail without publishing rows or metadata
    // changes, and a valid retry succeeds.
    test(
      'bounds incomplete records and removes staging after close.',
      () async {
        // Arrange.
        final target = await open();
        await target.setMigrationVersion(9);
        Stream<List<int>> oversized() async* {
          for (var i = 0; i < 20; i++) {
            yield List.filled(128, 97);
          }
        }

        // Act / Assert.
        await expectLater(
          CindelBackup.importDatabase(
            database: target,
            collections: collections,
            input: oversized(),
            maxRecordBytes: 1024,
            compression: CindelBackupCompression.none,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'record limit',
              contains('1024 bytes'),
            ),
          ),
        );
        await unchanged(target);
        final directory = target.directory;
        final records = await () async {
          await target.close();
          return archive();
        }();
        final reopened = await open(directory);
        Stream<List<int>> closeDuringImport() async* {
          yield* _stream(records.take(4));
          await reopened.close();
          yield* _stream(records.skip(4));
        }

        await expectLater(
          CindelBackup.importDatabase(
            database: reopened,
            collections: collections,
            input: closeDuringImport(),
            batchSize: 1,
            compression: CindelBackupCompression.none,
          ),
          throwsA(anything),
        );
        final again = await open(directory);
        expect(await again.documentIdsPage('backup_nodes', limit: 1), isEmpty);
        await restore(again, records);
      },
    );

    // Scenario: A lazily generated archive contains 1024 documents with 64
    // KiB payloads.
    // Covers:
    // - Streaming input and restore completeness with a large requested batch
    // size.
    // Expected: The report counts 1024 documents and more than 64 MiB; the
    // final payload retains all 65536 characters.
    test(
      'restores a 64 MiB generated stream without accumulating an archive.',
      () async {
        // Arrange.
        final template = await archive(withLinks: false);
        final target = await open();
        const count = 1024;
        Stream<List<int>> large() async* {
          var hash = 0x811c9dc5;
          List<int> line(Map<String, dynamic> record) {
            final bytes = utf8.encode(jsonEncode(record));
            hash = _hash(hash, bytes);
            return [...bytes, 10];
          }

          yield line(template.first);
          yield line(template[1]);
          for (var i = 1; i <= count; i++) {
            yield line({
              'type': 'doc',
              'collection': 'backup_nodes',
              'id': i,
              'document': {'dbId': i, 'code': i, 'payload': 'x' * 65536},
            });
          }
          yield utf8.encode(
            '${jsonEncode({'type': 'footer', 'documents': count, 'links': 0, 'checksum': hash})}\n',
          );
        }

        // Act.
        final report = await CindelBackup.importDatabase(
          database: target,
          collections: collections,
          input: large(),
          batchSize: 100000,
          compression: CindelBackupCompression.none,
        );
        // Assert.
        expect(report.documents, count);
        expect(report.archiveBytes, greaterThan(64 * 1024 * 1024));
        expect(
          (await target.typedCollection(backupNodeSchema).get(count))!
              .payload
              .length,
          65536,
        );
      },
    );

    if (includeSameDirectoryHandles) {
      // Scenario: Another handle changes rows, links and migration metadata
      // during export.
      // Covers:
      // - One consistent export snapshot across all archive sections.
      // Expected: Restoring the archive yields the original document, link to
      // ID 2 and migration version three.
      test(
        'export holds one snapshot across documents, links and metadata.',
        () async {
          // Arrange.
          final source = await open();
          await source.typedCollection(backupNodeSchema).putAll([
            BackupNode(1, payload: 'before'),
            BackupNode(2),
          ]);
          await source.saveLinkIds(
            sourceCollection: 'backup_nodes',
            sourceId: 1,
            linkName: 'children',
            targetCollection: 'backup_nodes',
            targetIds: [2],
          );
          await source.setMigrationVersion(3);
          final writer = await open(source.directory);
          var changed = false;
          final output = BackupBytesConsumer(
            onChunk: (bytes) async {
              if (!changed && utf8.decode(bytes).contains('"type":"doc"')) {
                changed = true;
                await writer
                    .typedCollection(backupNodeSchema)
                    .put(BackupNode(2, payload: 'after'));
                await writer.saveLinkIds(
                  sourceCollection: 'backup_nodes',
                  sourceId: 1,
                  linkName: 'children',
                  targetCollection: 'backup_nodes',
                  targetIds: [],
                );
                await writer.setMigrationVersion(4);
              }
            },
          );
          // Act.
          await CindelBackup.exportDatabase(
            database: source,
            collections: collections,
            output: output,
            batchSize: 1,
            compression: CindelBackupCompression.none,
          );
          await writer.close();
          await source.close();
          final target = await open();
          await CindelBackup.importDatabase(
            database: target,
            collections: collections,
            input: Stream.value(output.bytes),
            compression: CindelBackupCompression.none,
          );
          // Assert.
          expect(
            (await target.typedCollection(backupNodeSchema).get(2))!.payload,
            '',
          );
          final one = (await target.typedCollection(backupNodeSchema).get(1))!;
          await one.children.load();
          expect(one.children.single.dbId, 2);
          expect(await target.migrationVersion(), 3);
        },
      );
    }
  });
}

Stream<List<int>> _stream(Iterable<Map<String, dynamic>> records) async* {
  for (final record in records) {
    yield utf8.encode('${jsonEncode(record)}\n');
  }
}

int _hash(int hash, List<int> bytes) {
  for (final byte in bytes) {
    hash ^= byte;
    hash =
        (hash +
            (hash << 1) +
            (hash << 4) +
            (hash << 7) +
            (hash << 8) +
            (hash << 24)) &
        0xffffffff;
  }
  return hash;
}

void _checksum(List<Map<String, dynamic>> records) {
  var hash = 0x811c9dc5;
  for (final record in records.where((r) => r['type'] != 'footer')) {
    hash = _hash(hash, utf8.encode(jsonEncode(record)));
  }
  records.last['checksum'] = hash;
}

final class BackupBytesConsumer implements StreamConsumer<List<int>> {
  BackupBytesConsumer({this.onChunk});
  final Future<void> Function(List<int>)? onChunk;
  final bytes = <int>[];
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      await onChunk?.call(chunk);
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}
