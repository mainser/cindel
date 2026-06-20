import 'dart:async';
import 'dart:convert';

import 'backup_compression_stub.dart'
    if (dart.library.io) 'backup_compression_io.dart'
    as platform;
import 'database.dart' if (dart.library.js_interop) 'web/database.dart';
import 'schema.dart';
import 'typed_collection.dart'
    if (dart.library.js_interop) 'web/typed_collection.dart';

/// Backup archive compression.
enum CindelBackupCompression {
  /// Plain UTF-8 JSONL.
  none,

  /// Gzip-compressed UTF-8 JSONL.
  gzip,
}

/// Backup import/export phase reported through [CindelBackupProgressCallback].
enum CindelBackupPhase { export, import }

/// Callback used by Cindel backup import/export.
typedef CindelBackupProgressCallback =
    void Function(CindelBackupProgress progress);

/// Progress snapshot for backup import/export.
final class CindelBackupProgress {
  const CindelBackupProgress({
    required this.phase,
    required this.collection,
    required this.documents,
  });

  /// Current backup phase.
  final CindelBackupPhase phase;

  /// Collection currently being processed, or `null` for archive metadata.
  final String? collection;

  /// Number of documents processed so far.
  final int documents;
}

/// Summary returned after backup import/export completes.
final class CindelBackupReport {
  const CindelBackupReport({
    required this.documents,
    required this.uncompressedBytes,
    required this.archiveBytes,
    required this.checksum,
    required this.compression,
  });

  /// Number of document records in the archive.
  final int documents;

  /// Size of the JSONL archive before compression.
  final int uncompressedBytes;

  /// Size read from or written to the caller-provided archive stream.
  final int archiveBytes;

  /// FNV-1a checksum of non-footer JSONL records.
  final int checksum;

  /// Compression used for this archive stream.
  final CindelBackupCompression compression;
}

/// Typed collection included in a Cindel backup archive.
final class CindelBackupCollection<T> {
  /// Creates backup access for a generated [schema].
  CindelBackupCollection(this.schema);

  /// Generated collection schema.
  final CindelCollectionSchema<T> schema;

  final List<T> _pendingImport = [];

  String get _name => schema.name;

  Future<List<_BackupDocumentRecord>> _exportPage(
    CindelDatabase database,
    List<int> ids,
  ) async {
    final objects = await database.typedCollection(schema).getAll(ids);
    final records = <_BackupDocumentRecord>[];
    for (var index = 0; index < objects.length; index += 1) {
      final object = objects[index];
      if (object == null) {
        continue;
      }
      final id = ids[index];
      records.add(
        _BackupDocumentRecord(
          id: id,
          document: {...schema.toDocument(object), schema.idField: id},
        ),
      );
    }
    return records;
  }

  void _addImport(Map<String, Object?> document, int? id) {
    final object = schema.fromDocument(document);
    if (id != null && schema.setId != null) {
      schema.setId!(object, id);
    }
    _pendingImport.add(object);
  }

  Future<void> _flushImport(CindelDatabase database) async {
    if (_pendingImport.isEmpty) {
      return;
    }
    final batch = List<T>.of(_pendingImport);
    _pendingImport.clear();
    await database.typedCollection(schema).putAll(batch);
  }
}

/// Full-database typed backup helpers.
abstract final class CindelBackup {
  /// Exports [collections] from [database] into [output].
  static Future<CindelBackupReport> exportDatabase({
    required CindelDatabase database,
    required Iterable<CindelBackupCollection<dynamic>> collections,
    required StreamConsumer<List<int>> output,
    int batchSize = 1000,
    CindelBackupCompression? compression,
    CindelBackupProgressCallback? onProgress,
  }) async {
    _checkBatchSize(batchSize);
    final collectionList = _collectionList(collections);
    final selectedCompression =
        compression ?? platform.defaultCindelBackupCompression;
    var checksum = const _BackupChecksum();
    var documents = 0;
    var uncompressedBytes = 0;
    var archiveBytes = 0;

    String record(Map<String, Object?> json, {bool checksummed = true}) {
      final line = jsonEncode(json);
      final bytes = utf8.encode(line);
      if (checksummed) {
        checksum = checksum.add(bytes);
      }
      uncompressedBytes += bytes.length + 1;
      return line;
    }

    Stream<List<int>> source() async* {
      yield _lineBytes(
        record({
          'type': 'header',
          'format': 'cindel.backup.jsonl',
          'version': 1,
          'backend': database.backend.name,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'migrationVersion': await database.migrationVersion(),
        }),
      );

      for (final collection in collectionList) {
        yield _lineBytes(
          record({
            'type': 'schema',
            'collection': collection._name,
            'schemaVersion': await database.schemaVersion(collection._name),
          }),
        );
      }

      for (final collection in collectionList) {
        int? afterId;
        while (true) {
          final ids = await database.documentIdsPage(
            collection._name,
            afterId: afterId,
            limit: batchSize,
          );
          if (ids.isEmpty) {
            break;
          }
          final records = await collection._exportPage(database, ids);
          for (final document in records) {
            documents += 1;
            onProgress?.call(
              CindelBackupProgress(
                phase: CindelBackupPhase.export,
                collection: collection._name,
                documents: documents,
              ),
            );
            yield _lineBytes(
              record({
                'type': 'doc',
                'collection': collection._name,
                'id': document.id,
                'document': document.document,
              }),
            );
          }
          afterId = ids.last;
        }
      }

      yield _lineBytes(
        record({
          'type': 'footer',
          'documents': documents,
          'checksum': checksum.value,
        }, checksummed: false),
      );
    }

    await platform
        .encodeBackupBytes(source(), selectedCompression)
        .map((chunk) {
          archiveBytes += chunk.length;
          return chunk;
        })
        .pipe(output);

    return CindelBackupReport(
      documents: documents,
      uncompressedBytes: uncompressedBytes,
      archiveBytes: archiveBytes,
      checksum: checksum.value,
      compression: selectedCompression,
    );
  }

  /// Imports a backup archive into an empty [database].
  static Future<CindelBackupReport> importDatabase({
    required CindelDatabase database,
    required Iterable<CindelBackupCollection<dynamic>> collections,
    required Stream<List<int>> input,
    int batchSize = 1000,
    CindelBackupCompression? compression,
    CindelBackupProgressCallback? onProgress,
  }) async {
    _checkBatchSize(batchSize);
    final collectionList = _collectionList(collections);
    final collectionsByName = {
      for (final collection in collectionList) collection._name: collection,
    };
    final selectedCompression =
        compression ?? platform.defaultCindelBackupCompression;

    for (final collection in collectionList) {
      final ids = await database.documentIdsPage(collection._name, limit: 1);
      if (ids.isNotEmpty) {
        throw StateError('Restore target `${collection._name}` must be empty.');
      }
    }

    var checksum = const _BackupChecksum();
    var documents = 0;
    var uncompressedBytes = 0;
    var archiveBytes = 0;
    int? expectedChecksum;
    int? expectedDocuments;
    int? migrationVersion;
    var sawHeader = false;
    final seenSchemas = <String>{};

    Future<void> flush(String collection) async {
      await collectionsByName[collection]!._flushImport(database);
    }

    final countedInput = input.map((chunk) {
      archiveBytes += chunk.length;
      return chunk;
    });

    await for (final line
        in platform
            .decodeBackupBytes(countedInput, selectedCompression)
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) {
        continue;
      }
      final json = _decodeRecord(line);
      final type = json['type'];
      if (type != 'footer') {
        final bytes = utf8.encode(line);
        checksum = checksum.add(bytes);
        uncompressedBytes += bytes.length + 1;
      }

      switch (type) {
        case 'header':
          if (sawHeader) {
            throw StateError('Backup contains duplicate header records.');
          }
          sawHeader = true;
          if (json['format'] != 'cindel.backup.jsonl' || json['version'] != 1) {
            throw StateError('Unsupported Cindel backup archive.');
          }
          migrationVersion = json['migrationVersion'] as int?;
        case 'schema':
          final collection = json['collection'] as String;
          if (!collectionsByName.containsKey(collection)) {
            throw StateError(
              'Backup contains unknown collection `$collection`.',
            );
          }
          if (!seenSchemas.add(collection)) {
            throw StateError('Backup contains duplicate schema `$collection`.');
          }
        case 'doc':
          final collection = json['collection'] as String;
          final target = collectionsByName[collection];
          if (target == null) {
            throw StateError(
              'Backup contains unknown collection `$collection`.',
            );
          }
          final document = Map<String, Object?>.from(json['document'] as Map);
          final id = json['id'] as int?;
          target._addImport(document, id);
          documents += 1;
          onProgress?.call(
            CindelBackupProgress(
              phase: CindelBackupPhase.import,
              collection: collection,
              documents: documents,
            ),
          );
          if (target._pendingImport.length >= batchSize) {
            await flush(collection);
          }
        case 'footer':
          expectedDocuments = json['documents'] as int;
          expectedChecksum = json['checksum'] as int;
          uncompressedBytes += utf8.encode(line).length + 1;
        default:
          throw StateError('Unknown backup record type `$type`.');
      }
    }

    for (final collection in collectionList) {
      await flush(collection._name);
    }
    if (!sawHeader) {
      throw StateError('Backup header is missing.');
    }
    if (seenSchemas.length != collectionList.length) {
      throw StateError('Backup schema list does not match restore schemas.');
    }
    if (expectedDocuments != documents) {
      throw StateError('Backup document count mismatch.');
    }
    if (expectedChecksum != checksum.value) {
      throw StateError('Backup checksum mismatch.');
    }
    if (migrationVersion != null) {
      await database.setMigrationVersion(migrationVersion);
    }

    return CindelBackupReport(
      documents: documents,
      uncompressedBytes: uncompressedBytes,
      archiveBytes: archiveBytes,
      checksum: checksum.value,
      compression: selectedCompression,
    );
  }
}

final class _BackupDocumentRecord {
  const _BackupDocumentRecord({required this.id, required this.document});

  final int id;
  final Map<String, Object?> document;
}

Map<String, Object?> _decodeRecord(String line) {
  final value = jsonDecode(line);
  if (value is! Map) {
    throw StateError('Backup record must be a JSON object.');
  }
  return Map<String, Object?>.from(value);
}

List<CindelBackupCollection<dynamic>> _collectionList(
  Iterable<CindelBackupCollection<dynamic>> collections,
) {
  final list = List<CindelBackupCollection<dynamic>>.unmodifiable(collections);
  final names = <String>{};
  for (final collection in list) {
    if (!names.add(collection._name)) {
      throw ArgumentError.value(
        collection._name,
        'collections',
        'Duplicate collection.',
      );
    }
  }
  return list;
}

List<int> _lineBytes(String line) {
  return utf8.encode('$line\n');
}

void _checkBatchSize(int batchSize) {
  if (batchSize <= 0) {
    throw ArgumentError.value(
      batchSize,
      'batchSize',
      'Must be greater than zero.',
    );
  }
}

final class _BackupChecksum {
  const _BackupChecksum([this.value = 0x811c9dc5]);

  final int value;

  _BackupChecksum add(List<int> bytes) {
    var hash = value;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return _BackupChecksum(hash);
  }
}
