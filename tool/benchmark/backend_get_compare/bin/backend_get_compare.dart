import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:isar/isar.dart' as isar;

part 'backend_get_compare.g.dart';

@Collection(name: 'todos')
class CindelGetBench {
  const CindelGetBench({
    required this.id,
    required this.title,
    required this.titleWords,
    required this.completed,
    required this.createdAtMicros,
    required this.payload,
  });

  final Id id;

  final String title;

  final String titleWords;

  @Index()
  final bool completed;

  final int createdAtMicros;

  final String payload;

  CindelGetBench copyWith({bool? completed}) {
    return CindelGetBench(
      id: id,
      title: title,
      titleWords: titleWords,
      completed: completed ?? this.completed,
      createdAtMicros: createdAtMicros,
      payload: payload,
    );
  }
}

@isar.Collection()
class IsarGetBench {
  const IsarGetBench({
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
  @isar.Index()
  final bool completed;
  final int createdAtMicros;
  final String payload;
}

void main(List<String> args) async {
  final config = _Config.fromArgs(args);
  await _runOnce(config, 0);

  final rows = <_BenchRow>[];
  for (var repeat = 1; repeat <= config.repeats; repeat += 1) {
    rows.addAll(await _runOnce(config, repeat));
  }

  stdout.writeln(
    'profile,repeat,documents,payload_bytes,get_count,prepare_ms,open_ms,insert_ms,get_ms,update_ms,delete_ms,filter_query_ms,filter_sort_query_ms,get_items,update_items,delete_items,filter_items,filter_sort_items,database_size_bytes,path',
  );
  for (final row in rows) {
    stdout.writeln(
      [
        row.profile,
        row.repeat,
        config.documents,
        config.payloadBytes,
        config.getCount,
        _ms(row.prepare),
        _ms(row.open),
        _ms(row.insert),
        _ms(row.get),
        _ms(row.update),
        _ms(row.delete),
        _ms(row.filterQuery),
        _ms(row.filterSortQuery),
        row.getItems,
        row.updateItems,
        row.deleteItems,
        row.filterItems,
        row.filterSortItems,
        row.databaseSizeBytes,
        _csvCell(row.path),
      ].join(','),
    );
  }
}

Future<List<_BenchRow>> _runOnce(_Config config, int repeat) async {
  final payload = _stablePayload(config.payloadBytes);
  final idsToGet = List<int>.generate(config.getCount, (index) => index * 2);
  final rows = <_BenchRow>[];
  _warmPrepareModels(payload);

  if (config.includeRaw) {
    rows.add(await _runCindelRawBytes(config, repeat, payload, idsToGet));
  }
  rows.add(await _runCindelTyped(config, repeat, payload, idsToGet));
  rows.add(await _runIsar(config, repeat, payload, idsToGet));

  return rows;
}

void _warmPrepareModels(String payload) {
  const warmCount = 1024;
  _consumeObjects(_cindelObjects(warmCount, payload));
  _consumeObjects(_isarObjects(warmCount, payload));
}

void _consumeObjects(List<Object> objects) {
  if (objects.length == -1) {
    throw StateError('unreachable');
  }
}

Future<_BenchRow> _runCindelRawBytes(
  _Config config,
  int repeat,
  String payload,
  List<int> idsToGet,
) async {
  final temp = await Directory.systemTemp.createTemp('cindel_backend_get_raw_');
  CindelDatabase? db;
  try {
    final prepareWatch = Stopwatch()..start();
    final objects = _cindelObjects(config.documents, payload);
    prepareWatch.stop();

    final openWatch = Stopwatch()..start();
    db = await Cindel.open(
      directory: temp.path,
      backend: CindelStorageBackend.mdbx,
      schemas: [CindelGetBenchSchema],
    );
    openWatch.stop();

    final putWatch = Stopwatch()..start();
    await db.todos.putAll(objects);
    putWatch.stop();
    final sizeAfterInsert = _directorySizeBytes(temp);

    final getWatch = Stopwatch()..start();
    final bytes = await db.getAllBinaryDocuments('todos', idsToGet);
    getWatch.stop();
    if (bytes.length != idsToGet.length || bytes.any((item) => item == null)) {
      throw StateError('cindel raw byte getAll returned missing documents');
    }

    return _BenchRow(
      profile: 'cindel-raw-bytes',
      repeat: repeat,
      prepare: prepareWatch.elapsed,
      open: openWatch.elapsed,
      insert: putWatch.elapsed,
      get: getWatch.elapsed,
      update: Duration.zero,
      delete: Duration.zero,
      filterQuery: Duration.zero,
      filterSortQuery: Duration.zero,
      getItems: bytes.length,
      updateItems: 0,
      deleteItems: 0,
      filterItems: 0,
      filterSortItems: 0,
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

Future<_BenchRow> _runCindelTyped(
  _Config config,
  int repeat,
  String payload,
  List<int> idsToGet,
) async {
  final temp = await Directory.systemTemp.createTemp(
    'cindel_backend_get_typed_',
  );
  CindelDatabase? db;
  try {
    final prepareWatch = Stopwatch()..start();
    final objects = _cindelObjects(config.documents, payload);
    prepareWatch.stop();

    final openWatch = Stopwatch()..start();
    db = await Cindel.open(
      directory: temp.path,
      backend: CindelStorageBackend.mdbx,
      schemas: [CindelGetBenchSchema],
    );
    openWatch.stop();

    final putWatch = Stopwatch()..start();
    await db.todos.putAll(objects);
    putWatch.stop();
    final sizeAfterInsert = _directorySizeBytes(temp);

    final getWatch = Stopwatch()..start();
    final docs = await db.todos.getAll(idsToGet);
    getWatch.stop();
    if (docs.length != idsToGet.length || docs.any((item) => item == null)) {
      throw StateError('cindel typed getAll returned missing documents');
    }

    final filterWatch = Stopwatch()..start();
    final filterDocs = await db.todos.filter().completedEqualTo(true).findAll();
    filterWatch.stop();

    final filterSortWatch = Stopwatch()..start();
    final filterSortDocs = await db.todos
        .filter()
        .completedEqualTo(true)
        .sortBy('title')
        .findAll();
    filterSortWatch.stop();

    final updateWatch = Stopwatch()..start();
    final updated = await db.todos.filter().completedEqualTo(true).updateAll({
      'completed': false,
    });
    updateWatch.stop();

    final deleteWatch = Stopwatch()..start();
    await db.todos.deleteAll(idsToGet);
    deleteWatch.stop();

    return _BenchRow(
      profile: 'cindel-typed',
      repeat: repeat,
      prepare: prepareWatch.elapsed,
      open: openWatch.elapsed,
      insert: putWatch.elapsed,
      get: getWatch.elapsed,
      update: updateWatch.elapsed,
      delete: deleteWatch.elapsed,
      filterQuery: filterWatch.elapsed,
      filterSortQuery: filterSortWatch.elapsed,
      getItems: docs.length,
      updateItems: updated,
      deleteItems: idsToGet.length,
      filterItems: filterDocs.length,
      filterSortItems: filterSortDocs.length,
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

Future<_BenchRow> _runIsar(
  _Config config,
  int repeat,
  String payload,
  List<int> idsToGet,
) async {
  final temp = await Directory.systemTemp.createTemp('isar_backend_get_');
  isar.Isar? isarDb;
  try {
    final prepareWatch = Stopwatch()..start();
    final objects = _isarObjects(config.documents, payload);
    prepareWatch.stop();

    final openWatch = Stopwatch()..start();
    isarDb = isar.Isar.open(
      schemas: [IsarGetBenchSchema],
      directory: temp.path,
      engine: isar.IsarEngine.isar,
      maxSizeMiB: 1024,
    );
    openWatch.stop();

    final putWatch = Stopwatch()..start();
    isarDb.write((isar) => isar.isarGetBenchs.putAll(objects));
    putWatch.stop();
    final sizeAfterInsert = _directorySizeBytes(temp);

    final getWatch = Stopwatch()..start();
    final docs = isarDb.read((isar) => isar.isarGetBenchs.getAll(idsToGet));
    getWatch.stop();
    if (docs.length != idsToGet.length || docs.any((item) => item == null)) {
      throw StateError('isar getAll returned missing documents');
    }

    final filterWatch = Stopwatch()..start();
    final filterDocs = isarDb.isarGetBenchs
        .where()
        .completedEqualTo(true)
        .findAll();
    filterWatch.stop();

    final filterSortWatch = Stopwatch()..start();
    final filterSortDocs = isarDb.isarGetBenchs
        .where()
        .completedEqualTo(true)
        .sortByTitle()
        .findAll();
    filterSortWatch.stop();

    final updateWatch = Stopwatch()..start();
    final updated = isarDb.write(
      (isar) => isar.isarGetBenchs
          .where()
          .completedEqualTo(true)
          .updateAll(completed: false),
    );
    updateWatch.stop();

    final deleteWatch = Stopwatch()..start();
    final deleted = isarDb.write(
      (isar) => isar.isarGetBenchs.deleteAll(idsToGet),
    );
    deleteWatch.stop();

    return _BenchRow(
      profile: 'isar-typed',
      repeat: repeat,
      prepare: prepareWatch.elapsed,
      open: openWatch.elapsed,
      insert: putWatch.elapsed,
      get: getWatch.elapsed,
      update: updateWatch.elapsed,
      delete: deleteWatch.elapsed,
      filterQuery: filterWatch.elapsed,
      filterSortQuery: filterSortWatch.elapsed,
      getItems: docs.length,
      updateItems: updated,
      deleteItems: deleted,
      filterItems: filterDocs.length,
      filterSortItems: filterSortDocs.length,
      databaseSizeBytes: sizeAfterInsert,
      path: temp.path,
    );
  } finally {
    isarDb?.close(deleteFromDisk: !config.keep);
    if (!config.keep && temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

List<CindelGetBench> _cindelObjects(int count, String payload) {
  return List<CindelGetBench>.generate(
    count,
    (id) => CindelGetBench(
      id: id,
      title: 'title-${id % 10000}',
      titleWords: 'title ${id % 10000} group ${id % 37}',
      completed: id.isEven,
      createdAtMicros: 1773779200000000 + id,
      payload: payload,
    ),
    growable: false,
  );
}

List<IsarGetBench> _isarObjects(int count, String payload) {
  return List<IsarGetBench>.generate(
    count,
    (id) => IsarGetBench(
      id: id,
      title: 'title-${id % 10000}',
      titleWords: 'title ${id % 10000} group ${id % 37}',
      completed: id.isEven,
      createdAtMicros: 1773779200000000 + id,
      payload: payload,
    ),
    growable: false,
  );
}

final class _Config {
  const _Config({
    required this.documents,
    required this.payloadBytes,
    required this.getCount,
    required this.repeats,
    required this.includeRaw,
    required this.keep,
  });

  final int documents;
  final int payloadBytes;
  final int getCount;
  final int repeats;
  final bool includeRaw;
  final bool keep;

  factory _Config.fromArgs(List<String> args) {
    var documents = 50000;
    var payloadBytes = 1024;
    var getCount = 25000;
    var repeats = 3;
    var includeRaw = false;
    var keep = false;
    for (var i = 0; i < args.length; i += 1) {
      switch (args[i]) {
        case '--documents':
          documents = int.parse(args[++i]);
        case '--payload-bytes':
          payloadBytes = int.parse(args[++i]);
        case '--get-count':
          getCount = int.parse(args[++i]);
        case '--repeats':
          repeats = int.parse(args[++i]);
        case '--include-raw':
          includeRaw = true;
        case '--keep':
          keep = true;
        case '--help':
        case '-h':
          stdout.writeln(
            'Usage: dart run bin/backend_get_compare.dart --documents N --payload-bytes N --get-count N --repeats N [--keep]',
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
      payloadBytes: payloadBytes,
      getCount: getCount,
      repeats: repeats,
      includeRaw: includeRaw,
      keep: keep,
    );
  }
}

final class _BenchRow {
  const _BenchRow({
    required this.profile,
    required this.repeat,
    required this.prepare,
    required this.open,
    required this.insert,
    required this.get,
    required this.update,
    required this.delete,
    required this.filterQuery,
    required this.filterSortQuery,
    required this.getItems,
    required this.updateItems,
    required this.deleteItems,
    required this.filterItems,
    required this.filterSortItems,
    required this.databaseSizeBytes,
    required this.path,
  });

  final String profile;
  final int repeat;
  final Duration prepare;
  final Duration open;
  final Duration insert;
  final Duration get;
  final Duration update;
  final Duration delete;
  final Duration filterQuery;
  final Duration filterSortQuery;
  final int getItems;
  final int updateItems;
  final int deleteItems;
  final int filterItems;
  final int filterSortItems;
  final int databaseSizeBytes;
  final String path;
}

String _stablePayload(int bytes) {
  final codes = List<int>.filled(bytes.clamp(1, 1 << 30), 0);
  for (var i = 0; i < codes.length; i += 1) {
    codes[i] = 97 + (i % 23);
  }
  return String.fromCharCodes(codes);
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
