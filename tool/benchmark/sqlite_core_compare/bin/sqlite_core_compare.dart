import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:isar/isar.dart' as isar;

import 'isar_core_model.dart';

const _collection = 'todos';
const _payload =
    'abcdefghijklmnopqrstuvwabcdefghijklmnopqrstuvwabcdefghijklmnopqrstuvw';

final CindelCoreBenchSchema = CindelCollectionSchema<CindelCoreBench>(
  name: _collection,
  dartName: 'CindelCoreBench',
  idField: 'id',
  fields: const <CindelFieldSchema>[
    CindelFieldSchema(
      name: 'id',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'title',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'titleWords',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'completed',
      dartType: 'bool',
      binaryType: 'bool',
      isId: false,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'createdAtMicros',
      dartType: 'int',
      binaryType: 'int',
      isId: false,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'payload',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
  ],
  toDocument: _cindelCoreBenchToDocument,
  fromDocument: _cindelCoreBenchFromDocument,
  getId: _cindelCoreBenchGetId,
  writeNativeDocument: _cindelCoreBenchWriteNativeDocument,
  readNativeDocument: _cindelCoreBenchReadNativeDocument,
);

extension CindelCoreBenchAccess on CindelDatabase {
  CindelTypedCollection<CindelCoreBench> get coreBenchs =>
      typedCollection(CindelCoreBenchSchema);
}

class CindelCoreBench {
  const CindelCoreBench({
    required this.id,
    required this.title,
    required this.titleWords,
    required this.completed,
    required this.createdAtMicros,
    required this.payload,
  });

  final int id;
  final String title;
  final String titleWords;
  final bool completed;
  final int createdAtMicros;
  final String payload;
}

Future<void> main(List<String> args) async {
  final config = _Config.fromArgs(args);
  if (config.isarLibraryPath != null) {
    await isar.Isar.initialize(config.isarLibraryPath);
  }

  await _runOnce(config, 0);

  final rows = <_BenchRow>[];
  for (var repeat = 1; repeat <= config.repeats; repeat += 1) {
    rows
      ..add(await _runCindelSqlite(config, repeat))
      ..add(await _runIsarSqlite(config, repeat));
  }

  _printSummary(rows);
  final output = config.outputPath;
  if (output != null) {
    final file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_csv(rows, config));
    stdout.writeln('CSV: ${file.path}');
  }
}

Future<void> _runOnce(_Config config, int repeat) async {
  await _runCindelSqlite(config, repeat);
  await _runIsarSqlite(config, repeat);
}

Future<_BenchRow> _runCindelSqlite(_Config config, int repeat) async {
  final temp = await Directory.systemTemp.createTemp('cindel_sqlite_core_');
  CindelDatabase? db;
  try {
    final prepared = _prepareCindelObjects(config.documents);
    final idsToGet = _idsToGet(config);

    final openWatch = Stopwatch()..start();
    db = await Cindel.open(
      directory: temp.path,
      backend: CindelStorageBackend.sqlite,
      schemas: [CindelCoreBenchSchema],
    );
    openWatch.stop();

    final insertWatch = Stopwatch()..start();
    await db.coreBenchs.putAll(prepared.objects);
    insertWatch.stop();
    final sizeAfterInsert = _directorySizeBytes(temp);

    final getWatch = Stopwatch()..start();
    final docs = await db.coreBenchs.getAll(idsToGet);
    getWatch.stop();
    _checkCount('Cindel SQLite getAll', docs, idsToGet.length);

    final deleteWatch = Stopwatch()..start();
    await db.coreBenchs.deleteAll(idsToGet);
    deleteWatch.stop();

    return _BenchRow(
      profile: 'cindel-sqlite-typed',
      repeat: repeat,
      prepare: prepared.prepare,
      open: openWatch.elapsed,
      insert: insertWatch.elapsed,
      get: getWatch.elapsed,
      delete: deleteWatch.elapsed,
      getItems: docs.length,
      deleteItems: idsToGet.length,
      databaseSizeBytes: sizeAfterInsert,
      path: temp.path,
    );
  } finally {
    await db?.close();
    if (!config.keep && temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

Future<_BenchRow> _runIsarSqlite(_Config config, int repeat) async {
  final temp = await Directory.systemTemp.createTemp('isar_sqlite_core_');
  isar.Isar? db;
  try {
    final prepared = _prepareIsarObjects(config.documents);
    final idsToGet = _idsToGet(config);

    final openWatch = Stopwatch()..start();
    db = isar.Isar.open(
      schemas: [IsarCoreBenchSchema],
      directory: temp.path,
      engine: isar.IsarEngine.sqlite,
      maxSizeMiB: 1024,
      inspector: false,
    );
    openWatch.stop();

    final insertWatch = Stopwatch()..start();
    db.write((isar) => isar.isarCoreBenchs.putAll(prepared.objects));
    insertWatch.stop();
    final sizeAfterInsert = _directorySizeBytes(temp);

    final getWatch = Stopwatch()..start();
    final docs = db.read((isar) => isar.isarCoreBenchs.getAll(idsToGet));
    getWatch.stop();
    _checkCount('Isar SQLite getAll', docs, idsToGet.length);

    final deleteWatch = Stopwatch()..start();
    final deleted = db.write((isar) => isar.isarCoreBenchs.deleteAll(idsToGet));
    deleteWatch.stop();

    return _BenchRow(
      profile: 'isar-sqlite-typed',
      repeat: repeat,
      prepare: prepared.prepare,
      open: openWatch.elapsed,
      insert: insertWatch.elapsed,
      get: getWatch.elapsed,
      delete: deleteWatch.elapsed,
      getItems: docs.length,
      deleteItems: deleted,
      databaseSizeBytes: sizeAfterInsert,
      path: temp.path,
    );
  } finally {
    db?.close(deleteFromDisk: !config.keep);
    if (!config.keep && temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

void _checkCount(String operation, List<Object?> values, int expected) {
  if (values.length != expected || values.any((value) => value == null)) {
    throw StateError('$operation returned missing documents.');
  }
}

List<int> _idsToGet(_Config config) {
  return List<int>.generate(config.getCount, (index) => index * 2);
}

_PreparedCindelObjects _prepareCindelObjects(int count) {
  final watch = Stopwatch()..start();
  final objects = List<CindelCoreBench>.generate(
    count,
    (id) => CindelCoreBench(
      id: id,
      title: _titleFor(id),
      titleWords: _titleWordsFor(id),
      completed: _completedFor(id),
      createdAtMicros: _createdAtMicrosFor(id),
      payload: _payload,
    ),
    growable: false,
  );
  watch.stop();
  return _PreparedCindelObjects(objects: objects, prepare: watch.elapsed);
}

_PreparedIsarObjects _prepareIsarObjects(int count) {
  final watch = Stopwatch()..start();
  final objects = List<IsarCoreBench>.generate(
    count,
    (id) => IsarCoreBench(
      id: id,
      title: _titleFor(id),
      titleWords: _titleWordsFor(id),
      completed: _completedFor(id),
      createdAtMicros: _createdAtMicrosFor(id),
      payload: _payload,
    ),
    growable: false,
  );
  watch.stop();
  return _PreparedIsarObjects(objects: objects, prepare: watch.elapsed);
}

Map<String, Object?> _cindelCoreBenchToDocument(CindelCoreBench object) {
  return {
    'id': object.id,
    'title': object.title,
    'titleWords': object.titleWords,
    'completed': object.completed,
    'createdAtMicros': object.createdAtMicros,
    'payload': object.payload,
  };
}

CindelCoreBench _cindelCoreBenchFromDocument(Map<String, Object?> document) {
  return CindelCoreBench(
    id: document['id']! as int,
    title: document['title']! as String,
    titleWords: document['titleWords']! as String,
    completed: document['completed']! as bool,
    createdAtMicros: document['createdAtMicros']! as int,
    payload: document['payload']! as String,
  );
}

int _cindelCoreBenchGetId(CindelCoreBench object) => object.id;

void _cindelCoreBenchWriteNativeDocument(
  CindelNativeDocumentWriter writer,
  CindelCoreBench object,
) {
  writer
    ..writeBool(0, object.completed)
    ..writeInt(1, object.createdAtMicros)
    ..writeString(2, object.payload)
    ..writeString(3, object.title)
    ..writeString(4, object.titleWords);
}

CindelCoreBench _cindelCoreBenchReadNativeDocument(
  CindelNativeDocumentReader reader,
  int documentIndex,
) {
  return CindelCoreBench(
    id: reader.readId(documentIndex),
    completed: reader.readBool(documentIndex, 0) ?? false,
    createdAtMicros: reader.readInt(documentIndex, 1) ?? 0,
    payload: reader.readString(documentIndex, 2) ?? '',
    title: reader.readString(documentIndex, 3) ?? '',
    titleWords: reader.readString(documentIndex, 4) ?? '',
  );
}

String _titleFor(int id) => 'title-${id % 10000}';

String _titleWordsFor(int id) => 'title ${id % 10000} group ${id % 37}';

bool _completedFor(int id) => id.isEven;

int _createdAtMicrosFor(int id) => 1773779200000000 + id;

void _printSummary(List<_BenchRow> rows) {
  stdout.writeln('');
  stdout.writeln('Metric              Unit  Cindel SQLite  Isar SQLite');
  stdout.writeln('-----------------------------------------------------');

  String cell(String profile, Duration Function(_BenchRow row) value) {
    final profileRows = rows.where((row) => row.profile == profile).toList();
    return _medianDuration(profileRows.map(value)).padLeft(13);
  }

  void row(String metric, String unit, Duration Function(_BenchRow row) value) {
    stdout.writeln(
      '${metric.padRight(20)}'
      '${unit.padRight(6)}'
      '${cell('cindel-sqlite-typed', value)}  '
      '${cell('isar-sqlite-typed', value)}',
    );
  }

  row('Prepare', 'ms', (row) => row.prepare);
  row('Open', 'ms', (row) => row.open);
  row('Insert', 'ms', (row) => row.insert);
  row('Get', 'ms', (row) => row.get);
  row('Delete', 'ms', (row) => row.delete);

  String sizeCell(String profile) {
    final values =
        rows
            .where((row) => row.profile == profile)
            .map((row) => row.databaseSizeBytes)
            .toList()
          ..sort();
    final middle = values.length ~/ 2;
    return values[middle].toString().padLeft(13);
  }

  stdout.writeln(
    '${'Database Size'.padRight(20)}'
    '${'bytes'.padRight(6)}'
    '${sizeCell('cindel-sqlite-typed')}  '
    '${sizeCell('isar-sqlite-typed')}',
  );
  stdout.writeln('');
}

String _medianDuration(Iterable<Duration> durations) {
  final values = durations.map((duration) => duration.inMicroseconds).toList()
    ..sort();
  final middle = values.length ~/ 2;
  return (values[middle] / 1000.0).toStringAsFixed(3);
}

String _csv(List<_BenchRow> rows, _Config config) {
  final generatedAt = DateTime.now().toIso8601String();
  final buffer = StringBuffer()
    ..writeln(
      [
        'generated_at',
        'profile',
        'repeat',
        'documents',
        'get_count',
        'prepare_ms',
        'open_ms',
        'insert_ms',
        'get_ms',
        'delete_ms',
        'get_items',
        'delete_items',
        'database_size_bytes',
        'path',
      ].join(','),
    );
  for (final row in rows) {
    buffer.writeln(
      [
        generatedAt,
        row.profile,
        row.repeat,
        config.documents,
        config.getCount,
        _ms(row.prepare),
        _ms(row.open),
        _ms(row.insert),
        _ms(row.get),
        _ms(row.delete),
        row.getItems,
        row.deleteItems,
        row.databaseSizeBytes,
        _csvCell(row.path),
      ].join(','),
    );
  }
  return buffer.toString();
}

final class _PreparedCindelObjects {
  const _PreparedCindelObjects({required this.objects, required this.prepare});

  final List<CindelCoreBench> objects;
  final Duration prepare;
}

final class _PreparedIsarObjects {
  const _PreparedIsarObjects({required this.objects, required this.prepare});

  final List<IsarCoreBench> objects;
  final Duration prepare;
}

final class _BenchRow {
  const _BenchRow({
    required this.profile,
    required this.repeat,
    required this.prepare,
    required this.open,
    required this.insert,
    required this.get,
    required this.delete,
    required this.getItems,
    required this.deleteItems,
    required this.databaseSizeBytes,
    required this.path,
  });

  final String profile;
  final int repeat;
  final Duration prepare;
  final Duration open;
  final Duration insert;
  final Duration get;
  final Duration delete;
  final int getItems;
  final int deleteItems;
  final int databaseSizeBytes;
  final String path;
}

final class _Config {
  const _Config({
    required this.documents,
    required this.getCount,
    required this.repeats,
    required this.keep,
    required this.isarLibraryPath,
    required this.outputPath,
  });

  final int documents;
  final int getCount;
  final int repeats;
  final bool keep;
  final String? isarLibraryPath;
  final String? outputPath;

  factory _Config.fromArgs(List<String> args) {
    var documents = 50000;
    var getCount = 25000;
    var repeats = 3;
    var keep = false;
    String? isarLibraryPath;
    String? outputPath;
    for (var i = 0; i < args.length; i += 1) {
      switch (args[i]) {
        case '--documents':
          documents = int.parse(args[++i]);
        case '--get-count':
          getCount = int.parse(args[++i]);
        case '--repeats':
          repeats = int.parse(args[++i]);
        case '--keep':
          keep = true;
        case '--isar-library':
          isarLibraryPath = args[++i];
        case '--output':
          outputPath = args[++i];
        case '--help':
        case '-h':
          stdout.writeln(
            'Usage: dart run bin/sqlite_core_compare.dart '
            '[--documents N] [--get-count N] [--repeats N] '
            '[--isar-library PATH] [--output PATH] [--keep]',
          );
          exit(0);
        default:
          throw ArgumentError('unknown argument `${args[i]}`');
      }
    }
    if (getCount > documents) {
      throw ArgumentError.value(getCount, 'get-count', 'Must be <= documents.');
    }
    return _Config(
      documents: documents,
      getCount: getCount,
      repeats: repeats,
      keep: keep,
      isarLibraryPath: isarLibraryPath,
      outputPath: outputPath,
    );
  }
}

int _directorySizeBytes(Directory directory) {
  if (!directory.existsSync()) {
    return 0;
  }
  var total = 0;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      total += entity.lengthSync();
    }
  }
  return total;
}

String _ms(Duration duration) =>
    (duration.inMicroseconds / 1000.0).toStringAsFixed(3);

String _csvCell(String value) {
  if (value.contains(',') || value.contains('"')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
