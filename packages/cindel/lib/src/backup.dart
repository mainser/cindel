import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'native/wire.dart' if (dart.library.js_interop) 'web/wire.dart';

import 'backup_compression_stub.dart'
    if (dart.library.io) 'backup_compression_io.dart'
    as platform;
import 'database.dart' if (dart.library.js_interop) 'web/database.dart';
import 'schema.dart';
import 'binary_document.dart'
    if (dart.library.js_interop) 'web/binary_document.dart';
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
  CindelBackupCollection(this.schema)
    : _typed = schema.withType<_TypedBackupCollection<dynamic>>(
        <S>(schema) => _TypedBackupCollection<S>(schema),
      );

  /// Generated collection schema.
  final CindelCollectionSchema<T> schema;

  // The public wrapper may infer dynamic from the backup's heterogeneous list.
  // Dispatch through the schema itself so all model callbacks keep its real T.
  final _TypedBackupCollection<dynamic> _typed;

  String get _name => schema.name;
  Map<String, Object?> get _manifest => _typed._manifest;

  Stream<_BackupDocumentRecord> _exportPage(
    CindelDatabase database,
    List<int> ids,
  ) => _typed._exportPage(database, ids);

  Future<void> _stage(
    CindelDatabase database,
    List<_BackupDocumentRecord> records,
  ) => _typed._stage(database, records);
}

final class _TypedBackupCollection<T> {
  _TypedBackupCollection(this.schema);

  final CindelCollectionSchema<T> schema;

  String get _name => schema.name;

  Stream<_BackupDocumentRecord> _exportPage(
    CindelDatabase database,
    List<int> ids,
  ) async* {
    // Keep one hydrated document at a time even when an ID page is very large.
    final collection = database.typedCollection(schema);
    for (final id in ids) {
      final object = await collection.get(id);
      if (object == null)
        throw StateError('Document disappeared from the backup snapshot.');
      yield _BackupDocumentRecord(
        id: id,
        document: {...schema.toDocument(object), schema.idField: id},
      );
    }
  }

  Future<void> _stage(
    CindelDatabase database,
    List<_BackupDocumentRecord> records,
  ) async {
    final objects = <T>[];
    for (final record in records) {
      final object = schema.fromDocument(record.document);
      schema.setId?.call(object, record.id);
      if (schema.getId?.call(object) != record.id) {
        throw StateError('Backup document ID does not match `${schema.name}`.');
      }
      objects.add(object);
    }
    final native = database.backend == CindelStorageBackend.sqlite;
    final Uint8List payload;
    if (native) {
      final write = schema.writeNativeDocument;
      if (write == null)
        throw StateError('Backup requires generated native serializers.');
      final fields = schema.fields.where((f) => !f.isId).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      payload = encodeNativeDocumentWriteBatch([
        for (var i = 0; i < objects.length; i++)
          WireNativeDocumentWrite(
            id: records[i].id,
            values: () {
              final writer = _BackupValueWriter(fields.length);
              write(writer, objects[i]);
              return [
                for (var f = 0; f < fields.length; f++)
                  _nativeValue(writer.values[f], fields[f].binaryType!),
              ];
            }(),
          ),
      ]);
    } else {
      final encode = schema.toBinaryDocument;
      if (encode == null)
        throw StateError('Backup requires generated binary serializers.');
      payload = encodeDocumentWriteBatch([
        for (var i = 0; i < objects.length; i++)
          WireDocumentWrite(id: records[i].id, bytes: encode(objects[i])),
      ]);
    }
    await _command(database, {
      'op': 'documents',
      'collection': _name,
      'native': native ? 1 : 0,
    }, payload);
  }

  Map<String, Object?> get _manifest {
    final fields = [...schema.fields]..sort((a, b) => a.name.compareTo(b.name));
    final links = [...schema.links]..sort((a, b) => a.name.compareTo(b.name));
    final indexes = [...schema.compositeIndexes]
      ..sort((a, b) => a.name.compareTo(b.name));
    return {
      'id': schema.idField,
      'fields': [
        for (final f in fields)
          [
            f.name,
            f.dartType,
            f.binaryType,
            f.isId,
            f.isIndexed,
            f.isIndexUnique,
            f.isIndexReplace,
            f.indexCaseSensitive,
            f.indexType.name,
          ],
      ],
      'indexes': [
        for (final i in indexes)
          [i.name, i.fields, i.isUnique, i.isReplace, i.caseSensitive],
      ],
      'links': [
        for (final l in links)
          [l.name, l.targetCollection, l.isToMany, l.isBacklink, l.backlinkTo],
      ],
    };
  }
}

/// Full-database typed backup helpers.
abstract final class CindelBackup {
  /// Exports [collections] from [database] into [output] in one read snapshot.
  ///
  /// Include the targets of all forward links. [maxRecordBytes] bounds one
  /// JSONL record; increase it on both export and import for larger documents.
  static Future<CindelBackupReport> exportDatabase({
    required CindelDatabase database,
    required Iterable<CindelBackupCollection<dynamic>> collections,
    required StreamConsumer<List<int>> output,
    int batchSize = 1000,
    int maxRecordBytes = 16 * 1024 * 1024,
    CindelBackupCompression? compression,
    CindelBackupProgressCallback? onProgress,
  }) async {
    _checkBatchSize(batchSize);
    if (maxRecordBytes <= 0)
      throw ArgumentError.value(
        maxRecordBytes,
        'maxRecordBytes',
        'Must be positive.',
      );
    final collectionList = _collectionList(collections);
    _checkLinkClosure(collectionList);
    final selectedCompression =
        compression ?? platform.defaultCindelBackupCompression;
    var checksum = const _BackupChecksum();
    var documents = 0;
    var links = 0;
    var uncompressedBytes = 0;
    var archiveBytes = 0;

    String record(Map<String, Object?> json, {bool checksummed = true}) {
      final line = jsonEncode(json);
      final bytes = utf8.encode(line);
      if (bytes.length > maxRecordBytes)
        throw StateError('Backup record exceeds $maxRecordBytes bytes.');
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
          'version': 2,
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
            'manifest': collection._manifest,
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
          final records = collection._exportPage(database, ids);
          await for (final document in records) {
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

      // Persisted forward edges are enough to reconstruct backlinks, including cycles.
      for (final collection in collectionList) {
        final forward = collection.schema.links.where((l) => !l.isBacklink);
        if (forward.isEmpty) continue;
        int? afterId;
        while (true) {
          final ids = await database.documentIdsPage(
            collection._name,
            afterId: afterId,
            limit: batchSize,
          );
          if (ids.isEmpty) break;
          for (final id in ids) {
            for (final link in forward) {
              int? afterTarget;
              while (true) {
                final targets = decodeIdList(
                  await _command(database, {
                    'op': 'links',
                    'collection': collection._name,
                    'id': id,
                    'name': link.name,
                    'target': link.targetCollection,
                    'after': afterTarget,
                    'limit': batchSize,
                  }),
                );
                if (targets.isEmpty) break;
                for (final target in targets) {
                  links++;
                  yield _lineBytes(
                    record({
                      'type': 'link',
                      'collection': collection._name,
                      'id': id,
                      'name': link.name,
                      'target': link.targetCollection,
                      'targetId': target,
                    }),
                  );
                }
                afterTarget = targets.last;
              }
            }
          }
          afterId = ids.last;
        }
      }

      yield _lineBytes(
        record({
          'type': 'footer',
          'documents': documents,
          'links': links,
          'checksum': checksum.value,
        }, checksummed: false),
      );
    }

    await database.readTxn(() async {
      await platform
          .encodeBackupBytes(source(), selectedCompression)
          .map((chunk) {
            archiveBytes += chunk.length;
            return chunk;
          })
          .pipe(output);
    });

    return CindelBackupReport(
      documents: documents,
      uncompressedBytes: uncompressedBytes,
      archiveBytes: archiveBytes,
      checksum: checksum.value,
      compression: selectedCompression,
    );
  }

  /// Restores an archive atomically into empty selected collections.
  ///
  /// Input is staged on disk (OPFS on Web); the destination is changed only after
  /// validation. Temporary storage is removed on completion, failure, or close.
  /// Legacy v1 archives contain no links. Restoring them with linked schemas
  /// requires explicit [allowLegacyWithoutLinks] acknowledgement.
  static Future<CindelBackupReport> importDatabase({
    required CindelDatabase database,
    required Iterable<CindelBackupCollection<dynamic>> collections,
    required Stream<List<int>> input,
    int batchSize = 1000,
    int maxRecordBytes = 16 * 1024 * 1024,
    CindelBackupCompression? compression,
    CindelBackupProgressCallback? onProgress,
    bool allowLegacyWithoutLinks = false,
  }) async {
    _checkBatchSize(batchSize);
    if (maxRecordBytes <= 0)
      throw ArgumentError.value(
        maxRecordBytes,
        'maxRecordBytes',
        'Must be positive.',
      );
    final collectionList = _collectionList(collections);
    final byName = {for (final c in collectionList) c._name: c};
    final selectedCompression =
        compression ?? platform.defaultCindelBackupCompression;
    var checksum = const _BackupChecksum();
    var documents = 0;
    var links = 0;
    var uncompressedBytes = 0;
    var archiveBytes = 0;
    int? version;
    var migrationVersion = 0;
    var footer = false;
    var dataStarted = false;
    var linksStarted = false;
    final seenSchemas = <String>{};
    final pending = <_BackupDocumentRecord>[];
    final pendingLinks = <List<Object>>[];
    var pendingLinkBytes = 0;
    String? pendingCollection;
    var pendingBytes = 0;
    Future<void> flush() async {
      if (pending.isEmpty) return;
      await byName[pendingCollection]!._stage(database, pending);
      pending.clear();
      pendingBytes = 0;
    }

    Future<void> flushLinks() async {
      if (pendingLinks.isEmpty) return;
      await _command(database, {'op': 'edges', 'rows': pendingLinks});
      pendingLinks.clear();
      pendingLinkBytes = 0;
    }

    final random = Random.secure();
    final token = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _command(database, {
      'op': 'begin',
      'token': token,
      'collections': byName.keys.toList(),
    });
    var committed = false;
    try {
      final source = platform.decodeBackupBytes(
        input.map((chunk) {
          archiveBytes += chunk.length;
          return chunk;
        }),
        selectedCompression,
      );
      await for (final line in _backupLines(source, maxRecordBytes)) {
        if (line.isEmpty) continue;
        if (footer) throw StateError('Backup has records after its footer.');
        final json = _decodeRecord(line);
        final type = json['type'];
        final bytes = utf8.encode(line);
        uncompressedBytes += bytes.length + 1;
        if (type != 'footer') checksum = checksum.add(bytes);
        if (version == null && type != 'header')
          throw StateError('Backup header must be first.');
        switch (type) {
          case 'header':
            if (version != null)
              throw StateError('Backup contains duplicate header records.');
            if (json['format'] != 'cindel.backup.jsonl' ||
                (json['version'] != 1 && json['version'] != 2)) {
              throw StateError('Unsupported Cindel backup archive.');
            }
            version = json['version'] as int;
            if (version == 2) _checkLinkClosure(collectionList);
            migrationVersion = _nonNegativeInt(json['migrationVersion'] ?? 0);
            if (version == 1 &&
                !allowLegacyWithoutLinks &&
                collectionList.any((c) => c.schema.links.isNotEmpty)) {
              throw StateError(
                'Legacy backups have no relationships. Set allowLegacyWithoutLinks explicitly to restore documents only.',
              );
            }
          case 'schema':
            final name = json['collection'] as String;
            final collection = byName[name];
            if (collection == null)
              throw StateError('Backup contains unknown collection `$name`.');
            if (dataStarted || !seenSchemas.add(name))
              throw StateError('Duplicate or misplaced backup schema `$name`.');
            if (version == 2 &&
                jsonEncode(_canonical(json['manifest'])) !=
                    jsonEncode(_canonical(collection._manifest))) {
              throw StateError('Incompatible backup schema `$name`.');
            }
            if (version == 1 &&
                json['schemaVersion'] != await database.schemaVersion(name)) {
              throw StateError('Incompatible legacy schema version `$name`.');
            }
          case 'doc':
            dataStarted = true;
            if (linksStarted || seenSchemas.length != byName.length)
              throw StateError('Misplaced backup document.');
            final name = json['collection'] as String;
            if (!byName.containsKey(name))
              throw StateError('Backup contains unknown collection `$name`.');
            final id = _nonNegativeInt(json['id']);
            final document = Map<String, Object?>.from(json['document'] as Map);
            if (document[byName[name]!.schema.idField] != id)
              throw StateError('Backup document ID mismatch.');
            if (pendingCollection != name ||
                pendingBytes + bytes.length > _backupBatchBytes)
              await flush();
            pendingCollection = name;
            pending.add(_BackupDocumentRecord(id: id, document: document));
            pendingBytes += bytes.length;
            documents++;
            onProgress?.call(
              CindelBackupProgress(
                phase: CindelBackupPhase.import,
                collection: name,
                documents: documents,
              ),
            );
            if (pending.length >= batchSize ||
                pendingBytes >= _backupBatchBytes)
              await flush();
          case 'link':
            dataStarted = true;
            linksStarted = true;
            if (version != 2 || seenSchemas.length != byName.length)
              throw StateError('Misplaced backup link.');
            await flush();
            final name = json['collection'] as String;
            final candidates = byName[name]?.schema.links.where(
              (l) =>
                  !l.isBacklink &&
                  l.name == json['name'] &&
                  l.targetCollection == json['target'],
            );
            if (candidates == null || candidates.length != 1)
              throw StateError('Unknown backup relationship.');
            final link = candidates.single;
            if (pendingLinkBytes + bytes.length > _backupBatchBytes)
              await flushLinks();
            pendingLinks.add([
              name,
              _nonNegativeInt(json['id']),
              link.name,
              link.targetCollection,
              _nonNegativeInt(json['targetId']),
              link.isToMany ? 1 : 0,
            ]);
            pendingLinkBytes += bytes.length;
            if (pendingLinks.length >= batchSize ||
                pendingLinkBytes >= _backupBatchBytes)
              await flushLinks();
            links++;
          case 'footer':
            if (seenSchemas.length != byName.length)
              throw StateError(
                'Backup schema list does not match restore schemas.',
              );
            if (json['documents'] != documents ||
                (version == 2 && json['links'] != links))
              throw StateError('Backup record count mismatch.');
            if (json['checksum'] != checksum.value)
              throw StateError('Backup checksum mismatch.');
            footer = true;
          default:
            throw StateError('Unknown backup record type `$type`.');
        }
      }
      if (!footer) throw StateError('Backup footer is missing.');
      await flush();
      await flushLinks();
      await _command(database, {'op': 'commit', 'version': migrationVersion});
      committed = true;
    } finally {
      pending.clear();
      pendingLinks.clear();
      if (!committed) {
        try {
          await _command(database, {'op': 'abort'});
        } catch (_) {
          /* Closed handles own cleanup. */
        }
      }
    }
    await database.backupRestored(byName.keys);
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
  if (batchSize <= 0 || batchSize > 100000) {
    throw ArgumentError.value(
      batchSize,
      'batchSize',
      'Must be between 1 and 100000.',
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
      hash =
          (hash +
              (hash << 1) +
              (hash << 4) +
              (hash << 7) +
              (hash << 8) +
              (hash << 24)) &
          0xffffffff;
    }
    return _BackupChecksum(hash);
  }
}

// A batch is bounded by both record count and encoded size. One unusually large
// record may exceed the batch budget, up to the explicit archive record limit.
const _backupBatchBytes = 1024 * 1024;

int _nonNegativeInt(Object? value) {
  if (value is! int || value < 0) throw StateError('Invalid backup integer.');
  return value;
}

void _checkLinkClosure(List<CindelBackupCollection<dynamic>> collections) {
  final names = collections.map((c) => c._name).toSet();
  for (final collection in collections) {
    for (final link in collection.schema.links.where((l) => !l.isBacklink)) {
      if (!names.contains(link.targetCollection)) {
        throw StateError(
          'Backup must include link target `${link.targetCollection}` for `${collection._name}.${link.name}`.',
        );
      }
    }
  }
}

Future<Uint8List> _command(
  CindelDatabase database,
  Map<String, Object?> args, [
  Uint8List? payload,
]) async {
  WireValue value(Object? v) => switch (v) {
    null => const WireValue.nullValue(),
    int v => WireValue.int(v),
    String v => WireValue.string(v),
    List v => WireValue.list(v.map(value).toList()),
    _ => throw StateError('Invalid backup command argument.'),
  };
  final header = encodeFieldUpdates({
    for (final e in args.entries) e.key: value(e.value),
  });
  final bytes = Uint8List(4 + header.length + (payload?.length ?? 0));
  ByteData.sublistView(bytes).setUint32(0, header.length, Endian.little);
  bytes.setRange(4, 4 + header.length, header);
  if (payload != null) bytes.setRange(4 + header.length, bytes.length, payload);
  final response = await database.backupCommand(bytes);
  if (response.isEmpty || response[0] != 0)
    throw StateError(
      response.isEmpty
          ? 'Empty backup response.'
          : utf8.decode(response.sublist(1)),
    );
  return Uint8List.sublistView(response, 1);
}

Stream<String> _backupLines(
  Stream<List<int>> input,
  int maxRecordBytes,
) async* {
  final pending = BytesBuilder(copy: false);
  await for (final chunk in input) {
    var start = 0;
    for (var i = 0; i <= chunk.length; i++) {
      if (i < chunk.length && chunk[i] != 10) continue;
      if (pending.length + i - start > maxRecordBytes)
        throw StateError('Backup record exceeds $maxRecordBytes bytes.');
      if (i > start) pending.add(chunk.sublist(start, i));
      if (i < chunk.length) yield utf8.decode(pending.takeBytes());
      start = i + 1;
    }
  }
  if (pending.isNotEmpty) yield utf8.decode(pending.takeBytes());
}

WireNativeDocumentValue _nativeValue(Object? value, String type) {
  if (value == null) return const WireNativeDocumentNull();
  return switch (type) {
    'bool' => WireNativeDocumentBool(value as bool),
    'int' => WireNativeDocumentInt(value as int),
    'double' => WireNativeDocumentDouble(value as double),
    'string' => WireNativeDocumentBytes(
      Uint8List.fromList(utf8.encode(value as String)),
    ),
    'list' => WireNativeDocumentBytes(
      cindelEncodeBinaryList(value as List<Object?>),
    ),
    'object' => WireNativeDocumentBytes(
      cindelEncodeBinaryObject(value as Map<String, Object?>),
    ),
    _ => throw StateError('Unsupported backup field type `$type`.'),
  };
}

// Uses the generated native serializer, including nested lists and objects.
// It is local to a bounded backup batch and does not alter normal write paths.
final class _BackupValueWriter implements CindelNativeDocumentWriter {
  _BackupValueWriter(int length) : values = List<Object?>.filled(length, null);
  final List<Object?> values;
  @override
  void writeNull(int index) => values[index] = null;
  @override
  void writeBool(int index, bool value) => values[index] = value;
  @override
  void writeInt(int index, int value) => values[index] = value;
  @override
  void writeDouble(int index, double value) => values[index] = value;
  @override
  void writeString(int index, String value) => values[index] = value;
  @override
  void writeObject(int index, Map<String, Object?> value) =>
      values[index] = value;
  @override
  void writeObjectList(int index, List<Map<String, Object?>?> value) =>
      values[index] = value;
  @override
  CindelNativeDocumentWriter beginList(int index, int length) {
    final child = _BackupValueWriter(length);
    values[index] = child.values;
    return child;
  }

  @override
  void endList(CindelNativeDocumentWriter child) {}
}

Object? _canonical(Object? value) {
  if (value is List) return value.map(_canonical).toList();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  return value;
}
