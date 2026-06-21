import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';
import 'schema_generation_fixture.dart';

void main() {
  group('Cindel backup', () {
    // Scenario: tooling exports a full typed database and restores it into an
    // empty database using the backend under test.
    // Covers:
    // - `documentIdsPage` export paging instead of full id-list reads.
    // - Gzip JSONL archive generation and import.
    // - Restore without requiring another backend to be enabled in this test
    //   runner.
    // - Migration version and checksum round-trip.
    // Expected: restored typed collections contain the same data and metadata.
    test('exports and imports a compressed typed archive.', () async {
      final sourceBackend = testStorageBackend;
      final targetBackend = sourceBackend;
      final sourceDir = await Directory.systemTemp.createTemp(
        'cindel_backup_source_${sourceBackend.name}_',
      );
      final targetDir = await Directory.systemTemp.createTemp(
        'cindel_backup_target_${targetBackend.name}_',
      );
      addTearDown(() async {
        if (await sourceDir.exists()) {
          await sourceDir.delete(recursive: true);
        }
        if (await targetDir.exists()) {
          await targetDir.delete(recursive: true);
        }
      });

      final schemas = <CindelCollectionSchema<dynamic>>[
        UserSchema,
        AccountSchema,
        ApiProductSchema,
      ];
      final collections = [
        CindelBackupCollection<User>(UserSchema),
        CindelBackupCollection<Account>(AccountSchema),
        CindelBackupCollection<ApiProduct>(ApiProductSchema),
      ];
      var source = await openTestDatabase(
        directory: sourceDir.path,
        schemas: schemas,
        backend: sourceBackend,
      );
      addTearDown(source.close);
      await source.setMigrationVersion(7);
      await _seed(source);

      final archive = _BytesConsumer();
      final exportProgress = <CindelBackupProgress>[];
      final exported = await CindelBackup.exportDatabase(
        database: source,
        collections: collections,
        output: archive,
        batchSize: 37,
        onProgress: exportProgress.add,
      );
      await source.close();

      final restored = await openTestDatabase(
        directory: targetDir.path,
        schemas: schemas,
        backend: targetBackend,
      );
      addTearDown(restored.close);
      final importProgress = <CindelBackupProgress>[];
      final imported = await CindelBackup.importDatabase(
        database: restored,
        collections: [
          CindelBackupCollection<User>(UserSchema),
          CindelBackupCollection<Account>(AccountSchema),
          CindelBackupCollection<ApiProduct>(ApiProductSchema),
        ],
        input: Stream.value(archive.bytes),
        batchSize: 3,
        onProgress: importProgress.add,
      );

      expect(exported.documents, 15);
      expect(imported.documents, exported.documents);
      expect(imported.checksum, exported.checksum);
      expect(exported.compression, CindelBackupCompression.gzip);
      expect(exported.archiveBytes, lessThan(exported.uncompressedBytes));
      expect(exportProgress.map((event) => event.phase).toSet(), {
        CindelBackupPhase.export,
      });
      expect(exportProgress.last.collection, ApiProductSchema.name);
      expect(exportProgress.last.documents, 15);
      expect(importProgress.map((event) => event.phase).toSet(), {
        CindelBackupPhase.import,
      });
      expect(importProgress.last.collection, ApiProductSchema.name);
      expect(importProgress.last.documents, 15);
      expect(await restored.migrationVersion(), 7);
      await _expectRestored(restored);
    });

    // Scenario: Backup callers pass invalid public options before any archive
    // stream is consumed.
    // Covers:
    // - Export `batchSize` validation.
    // - Import `batchSize` validation.
    // - Duplicate collection registration validation.
    // Expected: Invalid options fail with `ArgumentError` before storage or
    // stream work starts.
    test('rejects invalid backup options.', () async {
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final collections = [CindelBackupCollection<User>(UserSchema)];

      await expectLater(
        CindelBackup.exportDatabase(
          database: database,
          collections: collections,
          output: _BytesConsumer(),
          batchSize: 0,
        ),
        throwsArgumentError,
      );
      await expectLater(
        CindelBackup.importDatabase(
          database: database,
          collections: collections,
          input: const Stream<List<int>>.empty(),
          batchSize: 0,
        ),
        throwsArgumentError,
      );
      await expectLater(
        CindelBackup.exportDatabase(
          database: database,
          collections: [
            CindelBackupCollection<User>(UserSchema),
            CindelBackupCollection<User>(UserSchema),
          ],
          output: _BytesConsumer(),
        ),
        throwsArgumentError,
      );
    });

    // Scenario: Restore receives malformed JSONL records or archive metadata
    // that does not match the decoded payload.
    // Covers:
    // - Missing, duplicate, and unsupported header records.
    // - Unknown or duplicate schema records.
    // - Unknown document collections and record types.
    // - Footer document-count and checksum validation.
    // Expected: Bad archives fail with `StateError` instead of partially
    // restoring unchecked data.
    test('rejects malformed and inconsistent archives.', () async {
      final database = await openTestDatabaseInMemory(schemas: [UserSchema]);
      addTearDown(database.close);
      final collections = [CindelBackupCollection<User>(UserSchema)];

      Future<void> expectRejected(Stream<List<int>> input) {
        return expectLater(
          CindelBackup.importDatabase(
            database: database,
            collections: collections,
            input: input,
            compression: CindelBackupCompression.none,
          ),
          throwsStateError,
        );
      }

      await expectRejected(const Stream<List<int>>.empty());
      await expectRejected(_rawJsonl(['[]']));
      await expectRejected(_recordsJsonl([_header(format: 'wrong')]));
      await expectRejected(_recordsJsonl([_header(), _header()]));
      await expectRejected(
        _recordsJsonl([
          _header(),
          {'type': 'schema', 'collection': 'Ghost'},
        ]),
      );
      await expectRejected(_recordsJsonl([_header(), _schema(), _schema()]));
      await expectRejected(
        _recordsJsonl([
          _header(),
          {
            'type': 'doc',
            'collection': 'Ghost',
            'document': <String, Object?>{},
          },
        ]),
      );
      await expectRejected(
        _recordsJsonl([
          _header(),
          {'type': 'unknown'},
        ]),
      );
      await expectRejected(_archiveJsonl([_header()], documents: 0));
      await expectRejected(_archiveJsonl([_header(), _schema()], documents: 1));
      await expectRejected(
        _archiveJsonl([_header(), _schema()], documents: 0, checksum: -1),
      );
    });

    // Scenario: Restore is requested for a collection that already contains
    // local data.
    // Covers:
    // - Empty-target preflight before reading the archive stream.
    // Expected: Restore fails with `StateError` before existing data can be
    // overwritten or merged.
    test('rejects restore into non-empty target.', () async {
      final directory = await Directory.systemTemp.createTemp(
        'cindel_backup_non_empty_${testStorageBackend.name}_',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final database = await openTestDatabase(
        directory: directory.path,
        schemas: [UserSchema],
      );
      addTearDown(database.close);
      await database.users.put(_user(1));

      await expectLater(
        CindelBackup.importDatabase(
          database: database,
          collections: [CindelBackupCollection<User>(UserSchema)],
          input: const Stream<Uint8List>.empty(),
        ),
        throwsStateError,
      );
    });
  });
}

Future<void> _seed(CindelDatabase db) async {
  await db.users.putAll([
    for (var index = 0; index < 10; index += 1) _user(index),
  ]);
  await db.accounts.putAll([
    for (var index = 0; index < 3; index += 1)
      Account()
        ..username = 'account_$index'
        ..displayLabel = 'Account $index',
  ]);
  await db.apiProducts.putAll([
    for (var index = 0; index < 2; index += 1)
      ApiProduct()
        ..id = 'sku-$index'
        ..name = 'Product $index',
  ]);
}

Future<void> _expectRestored(CindelDatabase db) async {
  final users = await db.users.getAll([1, 10]);
  expect(users[0]?.email, 'user0@example.com');
  expect(users[1]?.email, 'user9@example.com');
  expect(users[1]?.createdAt.microsecondsSinceEpoch, 9);

  final accounts = await db.accounts.getAll([1, 3]);
  expect(accounts[0]?.username, 'account_0');
  expect(accounts[1]?.displayLabel, 'Account 2');

  final products = await db.apiProducts.getAll([1, 2]);
  expect(products[0]?.id, 'sku-0');
  expect(products[1]?.name, 'Product 1');
}

User _user(int index) {
  return User()
    ..name = 'User $index'
    ..email = 'user$index@example.com'
    ..username = 'user_$index'
    ..displayName = 'User $index'
    ..active = index.isEven
    ..tags = ['backup', 'group_${index % 3}']
    ..scores = [index, index + 1]
    ..createdAt = DateTime.fromMicrosecondsSinceEpoch(index, isUtc: true);
}

final class _BytesConsumer implements StreamConsumer<List<int>> {
  final _builder = BytesBuilder(copy: false);

  Uint8List get bytes => _builder.takeBytes();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _builder.add(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

Map<String, Object?> _header({String format = 'cindel.backup.jsonl'}) {
  return {
    'type': 'header',
    'format': format,
    'version': 1,
    'migrationVersion': null,
  };
}

Map<String, Object?> _schema() {
  return {'type': 'schema', 'collection': UserSchema.name, 'schemaVersion': 1};
}

Stream<Uint8List> _recordsJsonl(List<Map<String, Object?>> records) {
  return Stream.value(_jsonlBytes(records));
}

Stream<Uint8List> _archiveJsonl(
  List<Map<String, Object?>> records, {
  required int documents,
  int? checksum,
}) {
  final footer = {
    'type': 'footer',
    'documents': documents,
    'checksum': checksum ?? _recordsChecksum(records),
  };
  return Stream.value(_jsonlBytes([...records, footer]));
}

Stream<Uint8List> _rawJsonl(List<String> lines) {
  return Stream.value(Uint8List.fromList(utf8.encode('${lines.join('\n')}\n')));
}

Uint8List _jsonlBytes(List<Map<String, Object?>> records) {
  return Uint8List.fromList(
    utf8.encode('${records.map(jsonEncode).join('\n')}\n'),
  );
}

int _recordsChecksum(List<Map<String, Object?>> records) {
  var hash = 0x811c9dc5;
  for (final record in records) {
    hash = _fnv1aFrom(hash, utf8.encode(jsonEncode(record)));
  }
  return hash;
}

int _fnv1aFrom(int seed, List<int> bytes) {
  var hash = seed;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
