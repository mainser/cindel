import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:isar/isar.dart' as isar;

import 'backend_get_compare.dart' as backend;

void main(List<String> args) async {
  final config = _Config.fromArgs(args);
  await _runOnce(config, 0);

  final rows = <_OpenRow>[];
  for (var repeat = 1; repeat <= config.repeats; repeat += 1) {
    rows.addAll(await _runOnce(config, repeat));
  }

  stdout.writeln('profile,repeat,open_ms,size_bytes,path');
  for (final row in rows) {
    stdout.writeln(
      [
        row.profile,
        row.repeat,
        _ms(row.open),
        row.sizeBytes,
        _csvCell(row.path),
      ].join(','),
    );
  }
}

Future<List<_OpenRow>> _runOnce(_Config config, int repeat) async {
  final rows = <_OpenRow>[];
  rows.add(
    await _runCindel(repeat, schemas: const [], profile: 'cindel-empty'),
  );
  rows.add(
    await _runCindel(
      repeat,
      schemas: [backend.CindelGetBenchSchema],
      profile: 'cindel-schema',
    ),
  );
  rows.add(await _runIsar(repeat));
  return rows;
}

Future<_OpenRow> _runCindel(
  int repeat, {
  required Iterable<CindelCollectionSchema<dynamic>> schemas,
  required String profile,
}) async {
  final temp = await Directory.systemTemp.createTemp('${profile}_');
  CindelDatabase? db;
  try {
    final watch = Stopwatch()..start();
    db = await Cindel.open(
      directory: temp.path,
      backend: CindelStorageBackend.mdbx,
      schemas: schemas,
    );
    watch.stop();

    return _OpenRow(
      profile: profile,
      repeat: repeat,
      open: watch.elapsed,
      sizeBytes: _directorySizeBytes(temp),
      path: temp.path,
    );
  } finally {
    await db?.close();
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

Future<_OpenRow> _runIsar(int repeat) async {
  final temp = await Directory.systemTemp.createTemp('isar-schema_');
  isar.Isar? db;
  try {
    final watch = Stopwatch()..start();
    db = isar.Isar.open(
      schemas: [backend.IsarGetBenchSchema],
      directory: temp.path,
      engine: isar.IsarEngine.isar,
      maxSizeMiB: 1024,
    );
    watch.stop();

    return _OpenRow(
      profile: 'isar-schema',
      repeat: repeat,
      open: watch.elapsed,
      sizeBytes: _directorySizeBytes(temp),
      path: temp.path,
    );
  } finally {
    db?.close(deleteFromDisk: true);
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

final class _Config {
  const _Config({required this.repeats});

  final int repeats;

  factory _Config.fromArgs(List<String> args) {
    var repeats = 25;
    for (var i = 0; i < args.length; i += 1) {
      switch (args[i]) {
        case '--repeats':
          repeats = int.parse(args[++i]);
        case '--help':
        case '-h':
          stdout.writeln('Usage: dart run bin/open_compare.dart --repeats N');
          exit(0);
        default:
          throw ArgumentError('unknown argument `${args[i]}`');
      }
    }
    return _Config(repeats: repeats);
  }
}

final class _OpenRow {
  const _OpenRow({
    required this.profile,
    required this.repeat,
    required this.open,
    required this.sizeBytes,
    required this.path,
  });

  final String profile;
  final int repeat;
  final Duration open;
  final int sizeBytes;
  final String path;
}

String _ms(Duration duration) =>
    (duration.inMicroseconds / Duration.microsecondsPerMillisecond)
        .toStringAsFixed(3);

String _csvCell(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

int _directorySizeBytes(Directory directory) {
  var size = 0;
  if (!directory.existsSync()) {
    return size;
  }
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File) {
      size += entity.lengthSync();
    }
  }
  return size;
}
