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

    test(
      'round-trips paged links, cycles, backlinks and metadata, then reopens.',
      () async {
        final records = await archive(nodes: 13);
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

    test(
      'preserves generated embedded objects, nulls and empty/string lists.',
      () async {
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
        expect(restored.tags, row.tags);
        expect(restored.displayName, isNull);
        expect(restored.primaryRecipient!.metadata!.label, 'inner');
        expect(restored.recipients!.single.name, 'list');
        final empty = (await target.distinctRecords.get(2))!;
        expect(empty.tags, isEmpty);
        expect(empty.recipients, isNull);
      },
    );

    test(
      'restores cross-collection links atomically with their backlinks.',
      () async {
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

    test(
      'rejects omitted forward-link collections before exporting.',
      () async {
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

    test(
      'export rejects writes through its own handle and releases its snapshot on output error.',
      () async {
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
      test(
        '$corruption leaves documents, relations, IDs and metadata unchanged.',
        () async {
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

    test(
      'stream and progress failures after flushed batches are atomic.',
      () async {
        final records = await archive();
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

    test(
      'rechecks target emptiness when publishing without deleting concurrent data.',
      () async {
        final records = await archive();
        final target = await open();
        Stream<List<int>> raced() async* {
          yield* _stream(records.take(records.length - 1));
          await target.typedCollection(backupNodeSchema).put(BackupNode(50));
          yield* _stream([records.last]);
        }

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

    test(
      'cleans staging when another transaction prevents publication.',
      () async {
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

    test(
      'legacy archives require explicit acknowledgement for lost links.',
      () async {
        final records = await archive(withLinks: false);
        records.first['version'] = 1;
        records[1].remove('manifest');
        records.last.remove('links');
        _checksum(records);
        final target = await open();
        await expectLater(restore(target, records), throwsStateError);
        await restore(target, records, legacy: true);
        expect(await target.documentIdsPage('backup_nodes', limit: 10), [
          1,
          2,
          3,
        ]);
      },
    );

    test(
      'legacy document-only selection can omit link destinations explicitly.',
      () async {
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
        await CindelBackup.importDatabase(
          database: target,
          collections: [CindelBackupCollection<BackupNode>(backupLeafSchema)],
          input: _stream(records),
          compression: CindelBackupCompression.none,
          allowLegacyWithoutLinks: true,
        );
        expect(await target.documentIdsPage('backup_leaves', limit: 10), [
          1,
          2,
          3,
        ]);
        expect(await target.documentIdsPage('backup_nodes', limit: 1), isEmpty);
      },
    );

    test(
      'bounds incomplete records and removes staging after close.',
      () async {
        final target = await open();
        await target.setMigrationVersion(9);
        Stream<List<int>> oversized() async* {
          for (var i = 0; i < 20; i++) {
            yield List.filled(128, 97);
          }
        }

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

    test(
      'restores a 64 MiB generated stream without accumulating an archive.',
      () async {
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

        final report = await CindelBackup.importDatabase(
          database: target,
          collections: collections,
          input: large(),
          batchSize: 100000,
          compression: CindelBackupCompression.none,
        );
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
      test(
        'export holds one snapshot across documents, links and metadata.',
        () async {
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
