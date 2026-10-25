import 'dart:convert';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'backup_contract_fixture.dart';
import 'backup_contract_suite.dart' show BackupBytesConsumer;
import 'dart_distinct_fixture.dart';
import 'schema_generation_fixture.dart' show Recipient, RecipientMetadata;
import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';

void main() {
  group('Backup schema typing', () {
    Future<CindelDatabase> open([
      List<CindelCollectionSchema<dynamic>>? schemas,
    ]) async {
      final path = await createCloseTestDirectory();
      addTearDown(() => deleteCloseTestDirectory(path));
      final db = await openTestDatabase(
        directory: path,
        schemas: schemas ?? [backupNodeSchema, DistinctRecordSchema],
      );
      addTearDown(db.close);
      return db;
    }

    Future<CindelDatabase> source() async {
      final db = await open();
      await db.typedCollection(backupNodeSchema).putAll([
        BackupNode(1, payload: 'parent'),
        BackupNode(2, payload: 'child'),
      ]);
      await db.saveLinkIds(
        sourceCollection: 'backup_nodes',
        sourceId: 1,
        linkName: 'children',
        targetCollection: 'backup_nodes',
        targetIds: [2],
      );
      await db.distinctRecords.putAll([
        DistinctRecord()
          ..dbId = 1
          ..name = 'one'
          ..email = 'one@local'
          ..tags = ['', 'á🚀']
          ..primaryRecipient = (Recipient()
            ..name = 'nested'
            ..metadata = (RecipientMetadata()..label = 'inner'))
          ..recipients = [Recipient()..name = 'list'],
        DistinctRecord()
          ..dbId = 2
          ..name = 'two'
          ..email = 'two@local',
      ]);
      return db;
    }

    Future<void> verify(CindelDatabase db) async {
      final parent = (await db.typedCollection(backupNodeSchema).get(1))!;
      expect(parent.payload, 'parent');
      await parent.children.load();
      expect(parent.children.single.dbId, 2);
      final child = parent.children.single;
      expect(child.payload, 'child');
      await child.owners.load();
      expect(child.owners.single.dbId, 1);
      final record = (await db.distinctRecords.get(1))!;
      expect(record.tags, ['', 'á🚀']);
      expect(record.displayName, isNull);
      expect(record.primaryRecipient!.metadata!.label, 'inner');
      expect(record.recipients!.single.name, 'list');
      final empty = (await db.distinctRecords.get(2))!;
      expect(empty.tags, isEmpty);
      expect(empty.primaryRecipient, isNull);
      expect(empty.recipients, isNull);
    }

    // Scenario: The documented inline call infers its type from the API argument.
    // Covers: Export with heterogeneous schemas, links and embedded values.
    // Expected: Generated callbacks retain their model types on every backend.
    test('exports inline heterogeneous collections.', () async {
      // Arrange.
      final db = await source();
      final output = BackupBytesConsumer();
      // Act.
      final report = await CindelBackup.exportDatabase(
        database: db,
        collections: [
          CindelBackupCollection(backupNodeSchema),
          CindelBackupCollection(DistinctRecordSchema),
        ],
        output: output,
        batchSize: 1,
        compression: CindelBackupCompression.none,
      );
      // Assert.
      expect(report.documents, 4);
      await db.close();
      final target = await open();
      await CindelBackup.importDatabase(
        database: target,
        collections: [
          CindelBackupCollection<BackupNode>(backupNodeSchema),
          CindelBackupCollection<DistinctRecord>(DistinctRecordSchema),
        ],
        input: Stream.value(output.bytes),
        batchSize: 1,
        compression: CindelBackupCompression.none,
      );
      await verify(target);
    });

    // Scenario: An explicitly typed export is restored through the inline API.
    // Covers: Import independently of inline export, including ID setters.
    // Expected: Native/binary writers accept their concrete models without casts.
    test('imports inline heterogeneous collections.', () async {
      // Arrange.
      final db = await source();
      final output = BackupBytesConsumer();
      await CindelBackup.exportDatabase(
        database: db,
        collections: [
          CindelBackupCollection<BackupNode>(backupNodeSchema),
          CindelBackupCollection<DistinctRecord>(DistinctRecordSchema),
        ],
        output: output,
        compression: CindelBackupCompression.none,
      );
      await db.close();
      final target = await open();
      // Act.
      final report = await CindelBackup.importDatabase(
        database: target,
        collections: [
          CindelBackupCollection(backupNodeSchema),
          CindelBackupCollection(DistinctRecordSchema),
        ],
        input: Stream.value(output.bytes),
        batchSize: 1,
        compression: CindelBackupCompression.none,
      );
      // Assert.
      expect(report.documents, 4);
      await verify(target);
    });

    // Scenario: Inferred wrappers and explicitly widened schemas share a list.
    // Covers: Existing local-list usage and widening before wrapper construction.
    // Expected: Both forms preserve the schema's runtime model type.
    test('round-trips inferred lists and widened schemas.', () async {
      // Arrange.
      final db = await source();
      final selection = [
        CindelBackupCollection(backupNodeSchema),
        CindelBackupCollection(DistinctRecordSchema),
      ];
      final output = BackupBytesConsumer();
      // Act / Assert.
      await CindelBackup.exportDatabase(
        database: db,
        collections: selection,
        output: output,
        compression: CindelBackupCompression.none,
      );
      final List<CindelCollectionSchema<dynamic>> schemas = [
        backupNodeSchema,
        DistinctRecordSchema,
      ];
      await db.close();
      final target = await open();
      await CindelBackup.importDatabase(
        database: target,
        collections: [
          for (final schema in schemas) CindelBackupCollection(schema),
        ],
        input: Stream.value(output.bytes),
        compression: CindelBackupCompression.none,
      );
      await verify(target);
    });

    for (final batchSize in [1, 7, 10000]) {
      // Scenario: Inline adapters process more than one row/byte-limited batch.
      // Covers: Serializer call counts, incremental export and import batch peaks.
      // Expected: Each row is converted once; import never hydrates the archive.
      test('preserves bounded batches with batchSize $batchSize.', () async {
        // Arrange.
        const count = 35;
        const payloadSize = 65536;
        var exported = 0;
        var decoded = 0;
        var encoded = 0;
        var awaitingEncoding = 0;
        var batchRemaining = 0;
        var peak = 0;
        final batches = <int>[];
        void encode() {
          if (awaitingEncoding == 0) return; // Initial source population.
          if (batchRemaining == 0) {
            batchRemaining = awaitingEncoding;
            batches.add(batchRemaining);
          }
          batchRemaining--;
          encoded++;
          awaitingEncoding--;
        }

        final base = backupNodeSchema;
        final schema = CindelCollectionSchema<BackupNode>(
          name: base.name,
          dartName: base.dartName,
          idField: base.idField,
          fields: base.fields,
          links: base.links,
          toDocument: (node) {
            exported++;
            return base.toDocument(node);
          },
          fromDocument: (document) {
            decoded++;
            awaitingEncoding++;
            if (awaitingEncoding > peak) peak = awaitingEncoding;
            return base.fromDocument(document);
          },
          toBinaryDocument: (node) {
            encode();
            return base.toBinaryDocument!(node);
          },
          fromBinaryDocument: base.fromBinaryDocument,
          writeNativeDocument: (writer, node) {
            encode();
            base.writeNativeDocument!(writer, node);
          },
          readNativeDocument: base.readNativeDocument,
          getId: base.getId,
          setId: base.setId,
          bindLinks: base.bindLinks,
        );
        final db = await open([schema]);
        await db.typedCollection(schema).putAll([
          for (var i = 1; i <= count; i++)
            BackupNode(i, payload: 'x' * payloadSize),
        ]);
        exported = 0;
        var consumed = 0;
        final output = BackupBytesConsumer(
          onChunk: (bytes) async {
            final record =
                jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
            if (record['type'] == 'doc') {
              consumed++;
              expect(
                exported,
                consumed,
                reason: 'Export must not serialize ahead.',
              );
            }
          },
        );
        // Act.
        await CindelBackup.exportDatabase(
          database: db,
          collections: [CindelBackupCollection(schema)],
          output: output,
          batchSize: batchSize,
          compression: CindelBackupCompression.none,
        );
        // Assert.
        expect(exported, count);
        expect(consumed, count);
        await db.close();
        final target = await open([schema]);
        await CindelBackup.importDatabase(
          database: target,
          collections: [CindelBackupCollection(schema)],
          input: Stream.value(output.bytes),
          batchSize: batchSize,
          compression: CindelBackupCompression.none,
        );
        // Each JSON record exceeds 64 KiB; the existing 1 MiB limit fits 15.
        final bound = batchSize < 15 ? batchSize : 15;
        expect(peak, bound);
        expect(batches, [
          for (var left = count; left > 0; left -= bound)
            left < bound ? left : bound,
        ]);
        expect(decoded, count);
        expect(encoded, count);
        expect(awaitingEncoding, 0);
        expect(
          (await target.typedCollection(schema).get(count))!.payload.length,
          payloadSize,
        );
      });
    }
  });
}
