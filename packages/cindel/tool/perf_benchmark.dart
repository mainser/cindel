import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cindel/cindel.dart';

const _defaultDocuments = 1000;
const _defaultQueryRepeats = 100;

Future<void> main(List<String> args) async {
  final config = BenchmarkConfig.parse(args);
  final reports = <BenchmarkReport>[];

  for (final backend in config.backends) {
    reports.add(await runBackendBenchmark(config, backend));
  }

  final run = BenchmarkRun(
    generatedAtUnixMs: DateTime.now().millisecondsSinceEpoch,
    config: config,
    reports: reports,
  );
  final output = const JsonEncoder.withIndent('  ').convert(run.toJson());
  final outputPath = config.outputPath;
  if (outputPath == null) {
    stdout.writeln(output);
  } else {
    File(outputPath).writeAsStringSync('$output\n');
  }
}

Future<BenchmarkReport> runBackendBenchmark(
  BenchmarkConfig config,
  CindelStorageBackend backend,
) async {
  final documents = List<CindelDocument>.generate(
    config.documents,
    benchmarkDocument,
    growable: false,
  );

  final measurements = <Measurement>[];
  final encodedDocuments = <Uint8List>[];
  measurements.add(
    await measureLoop('dart_document_encode', documents.length, (index) {
      encodedDocuments.add(
        Uint8List.fromList(utf8.encode(jsonEncode(documents[index]))),
      );
    }),
  );
  measurements.add(
    await measureLoop('dart_document_decode', encodedDocuments.length, (index) {
      final decoded = jsonDecode(utf8.decode(encodedDocuments[index]));
      if (decoded is! Map) {
        throw StateError('Decoded benchmark document was not a map.');
      }
    }),
  );

  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'cindel_dart_perf_${backend.name}_',
  );
  CindelDatabase? database;

  try {
    measurements.add(
      await measureOnce('open_register_schemas', () async {
        database = await Cindel.open(
          directory: temporaryDirectory.path,
          backend: backend,
          schemas: [benchmarkSchema, binaryBenchmarkSchema],
        );
      }),
    );
    final db = database!;
    final typedUsers = db.typedCollection(binaryBenchmarkSchema);
    final allIds = List.generate(documents.length, (i) => i);

    measurements.add(
      await measureLoop('put', documents.length, (index) {
        return db.put('users', index, documents[index]);
      }),
    );

    measurements.add(
      await measureLoop('get', documents.length, (index) async {
        final document = await db.get('users', index);
        if (document == null) {
          throw StateError('Missing benchmark document $index.');
        }
      }),
    );

    final readTxnGetCount = documents.length < config.queryRepeats
        ? documents.length
        : config.queryRepeats;
    final readTxnIds = List.generate(readTxnGetCount, (index) => index);
    measurements.add(
      await measureOnce('get_loop_outside_read_txn', () async {
        for (final id in readTxnIds) {
          final document = await db.get('users', id);
          if (document == null) {
            throw StateError('Missing benchmark document $id.');
          }
        }
      }, items: readTxnGetCount),
    );

    measurements.add(
      await measureOnce('get_loop_inside_read_txn', () async {
        await db.readTxn(() async {
          for (final id in readTxnIds) {
            final document = await db.get('users', id);
            if (document == null) {
              throw StateError('Missing benchmark document $id.');
            }
          }
        });
      }, items: readTxnGetCount),
    );

    measurements.add(
      await measureOnce('get_all', () async {
        final result = await db.getAll('users', allIds);
        if (result.length != documents.length ||
            result.any((value) => value == null)) {
          throw StateError('getAll returned missing benchmark documents.');
        }
      }, items: documents.length),
    );

    measurements.add(
      await measureOnce('typed_put_all_binary', () {
        return typedUsers.putAll(documents);
      }, items: documents.length),
    );

    measurements.add(
      await measureLoop('typed_get', documents.length, (index) async {
        final document = await typedUsers.get(index);
        if (document == null) {
          throw StateError('Missing typed benchmark document $index.');
        }
      }),
    );

    measurements.add(
      await measureOnce('typed_get_all', () async {
        final result = await typedUsers.getAll(allIds);
        if (result.length != documents.length ||
            result.any((value) => value == null)) {
          throw StateError(
            'typed getAll returned missing benchmark documents.',
          );
        }
      }, items: documents.length),
    );

    if (backend == CindelStorageBackend.mdbx) {
      measurements.add(
        await measureLoop('get_binary_document', documents.length, (
          index,
        ) async {
          final bytes = await db.getBinaryDocument('binary_users', index);
          if (bytes == null || bytes.isEmpty) {
            throw StateError('Missing binary benchmark document $index.');
          }
        }),
      );

      measurements.add(
        await measureOnce('get_all_binary_documents', () async {
          final result = await db.getAllBinaryDocuments('binary_users', allIds);
          if (result.length != documents.length ||
              result.any((value) => value == null || value.isEmpty)) {
            throw StateError(
              'getAllBinaryDocuments returned missing benchmark documents.',
            );
          }
        }, items: documents.length),
      );
    }

    late List<CindelDocument> cachedDocuments;
    measurements.add(
      await measureOnce('query_all', () async {
        cachedDocuments = await db.queryAll('users');
        if (cachedDocuments.length != documents.length) {
          throw StateError(
            'queryAll returned ${cachedDocuments.length} documents.',
          );
        }
      }, items: documents.length),
    );

    measurements.add(
      await measureLoop('query_equal', config.queryRepeats, (repeat) async {
        final id = repeat % documents.length;
        final result = await db.queryEqual(
          'users',
          'email',
          'user-$id@example.com',
        );
        if (result.length != 1 || result.single['id'] != id) {
          throw StateError('Unexpected queryEqual result for $id.');
        }
      }),
    );

    final rangeUpper = documents.length < 100 ? documents.length - 1 : 99;
    measurements.add(
      await measureLoop('query_range', config.queryRepeats, (_) async {
        final result = await db.queryRange(
          'users',
          'score',
          lower: 0,
          upper: rangeUpper,
        );
        if (result.isEmpty) {
          throw StateError('queryRange returned no documents.');
        }
      }),
    );

    measurements.add(
      await measureLoop('dart_filter_cached', config.queryRepeats, (_) {
        final result = cachedDocuments
            .where((document) => (document['score']! as int) < 100)
            .toList(growable: false);
        if (result.isEmpty) {
          throw StateError('Cached filter returned no documents.');
        }
      }),
    );

    measurements.add(
      await measureLoop('dart_sort_cached', config.queryRepeats, (_) {
        final result = List<CindelDocument>.of(cachedDocuments)
          ..sort((left, right) {
            final scoreCompare = (left['score']! as int).compareTo(
              right['score']! as int,
            );
            if (scoreCompare != 0) {
              return scoreCompare;
            }
            return (left['id']! as int).compareTo(right['id']! as int);
          });
        if (result.length != cachedDocuments.length) {
          throw StateError('Cached sort lost documents.');
        }
      }),
    );

    measurements.add(
      await measureLoop('dart_distinct_cached', config.queryRepeats, (_) {
        final seenScores = <int>{};
        final result = <CindelDocument>[];
        for (final document in cachedDocuments) {
          if (seenScores.add(document['score']! as int)) {
            result.add(document);
          }
        }
        if (result.isEmpty) {
          throw StateError('Cached distinct returned no documents.');
        }
      }),
    );

    measurements.add(
      await measureLoop('dart_projection_cached', config.queryRepeats, (_) {
        final result = cachedDocuments
            .map((document) => document['email']! as String)
            .toList(growable: false);
        if (result.length != cachedDocuments.length) {
          throw StateError('Cached projection lost values.');
        }
      }),
    );

    measurements.add(
      await measureLoop('dart_window_cached', config.queryRepeats, (_) {
        final start = cachedDocuments.length > 10 ? 10 : 0;
        final end = (start + 50).clamp(0, cachedDocuments.length);
        final result = cachedDocuments.sublist(start, end);
        if (cachedDocuments.isNotEmpty && result.isEmpty) {
          throw StateError('Cached window returned no values.');
        }
      }),
    );

    final batchStartId = documents.length;
    final batchDocuments = <int, CindelDocument>{
      for (var offset = 0; offset < documents.length; offset++)
        batchStartId + offset: benchmarkDocument(batchStartId + offset),
    };
    measurements.add(
      await measureOnce('put_all', () {
        return db.putAll('users', batchDocuments);
      }, items: batchDocuments.length),
    );

    measurements.add(
      await measureOnce('delete_all', () {
        return db.deleteAll('users', batchDocuments.keys);
      }, items: batchDocuments.length),
    );

    final databaseSizeBytes = directorySizeBytes(temporaryDirectory);
    return BenchmarkReport(
      backend: backend.name,
      databaseSizeBytes: databaseSizeBytes,
      measurements: measurements,
    );
  } finally {
    await database?.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  }
}

CindelDocument benchmarkDocument(int id) {
  return {
    'id': id,
    'name': 'User $id',
    'email': 'user-$id@example.com',
    'score': id % 1000,
    'active': id.isEven,
  };
}

final benchmarkSchema = CindelCollectionSchema<CindelDocument>(
  name: 'users',
  dartName: 'BenchmarkUser',
  idField: 'id',
  fields: const [
    CindelFieldSchema(
      name: 'id',
      dartType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'name',
      dartType: 'String',
      isId: false,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'email',
      dartType: 'String',
      isId: false,
      isIndexed: true,
    ),
    CindelFieldSchema(
      name: 'score',
      dartType: 'int',
      isId: false,
      isIndexed: true,
    ),
    CindelFieldSchema(
      name: 'active',
      dartType: 'bool',
      isId: false,
      isIndexed: false,
    ),
  ],
  toDocument: (object) => Map<String, Object?>.of(object),
  fromDocument: (document) => Map<String, Object?>.of(document),
);

final binaryBenchmarkSchema = CindelCollectionSchema<CindelDocument>(
  name: 'binary_users',
  dartName: 'BinaryBenchmarkUser',
  idField: 'id',
  fields: benchmarkSchema.fields,
  toDocument: (object) => Map<String, Object?>.of(object),
  fromDocument: (document) => Map<String, Object?>.of(document),
  toBinaryDocument: (object) => cindelEncodeSchemaBinaryDocument(
    [object['name'], object['email'], object['score'], object['active']],
    const [
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.boolValue,
    ],
  ),
  fromBinaryDocument: (bytes) {
    final fields = cindelDecodeSchemaBinaryDocument(bytes, const [
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.stringValue,
      CindelBinaryFieldType.intValue,
      CindelBinaryFieldType.boolValue,
    ]);
    return {
      'name': fields[0],
      'email': fields[1],
      'score': fields[2],
      'active': fields[3],
    };
  },
  setId: (object, id) {
    object['id'] = id;
  },
);

Future<Measurement> measureOnce(
  String operation,
  FutureOr<void> Function() action, {
  int items = 1,
}) async {
  final stopwatch = Stopwatch()..start();
  await action();
  stopwatch.stop();
  return Measurement(
    operation: operation,
    items: items,
    totalMicroseconds: stopwatch.elapsedMicroseconds,
    samplesMicroseconds: [stopwatch.elapsedMicroseconds],
  );
}

Future<Measurement> measureLoop(
  String operation,
  int items,
  FutureOr<void> Function(int index) action,
) async {
  final samples = <int>[];
  final totalStopwatch = Stopwatch()..start();
  for (var index = 0; index < items; index++) {
    final sampleStopwatch = Stopwatch()..start();
    await action(index);
    sampleStopwatch.stop();
    samples.add(sampleStopwatch.elapsedMicroseconds);
  }
  totalStopwatch.stop();
  return Measurement(
    operation: operation,
    items: items,
    totalMicroseconds: totalStopwatch.elapsedMicroseconds,
    samplesMicroseconds: samples,
  );
}

int directorySizeBytes(Directory directory) {
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

final class BenchmarkRun {
  const BenchmarkRun({
    required this.generatedAtUnixMs,
    required this.config,
    required this.reports,
  });

  final int generatedAtUnixMs;
  final BenchmarkConfig config;
  final List<BenchmarkReport> reports;

  Map<String, Object?> toJson() {
    return {
      'generated_at_unix_ms': generatedAtUnixMs,
      'config': config.toJson(),
      'reports': [for (final report in reports) report.toJson()],
    };
  }
}

final class BenchmarkReport {
  const BenchmarkReport({
    required this.backend,
    required this.databaseSizeBytes,
    required this.measurements,
  });

  final String backend;
  final int databaseSizeBytes;
  final List<Measurement> measurements;

  Map<String, Object?> toJson() {
    return {
      'backend': backend,
      'database_size_bytes': databaseSizeBytes,
      'measurements': [
        for (final measurement in measurements) measurement.toJson(),
      ],
    };
  }
}

final class Measurement {
  const Measurement({
    required this.operation,
    required this.items,
    required this.totalMicroseconds,
    required this.samplesMicroseconds,
  });

  final String operation;
  final int items;
  final int totalMicroseconds;
  final List<int> samplesMicroseconds;

  double get totalMs => totalMicroseconds / 1000;

  double get opsPerSecond {
    if (totalMicroseconds == 0) {
      return double.infinity;
    }
    return items / (totalMicroseconds / Duration.microsecondsPerSecond);
  }

  Map<String, Object?> toJson() {
    return {
      'operation': operation,
      'items': items,
      'total_ms': totalMs,
      'ops_per_second': opsPerSecond,
      'p50_us': percentile(0.50),
      'p95_us': percentile(0.95),
    };
  }

  double? percentile(double value) {
    if (samplesMicroseconds.isEmpty) {
      return null;
    }
    final sorted = List<int>.of(samplesMicroseconds)..sort();
    final index = ((sorted.length - 1) * value).round();
    return sorted[index].toDouble();
  }
}

final class BenchmarkConfig {
  const BenchmarkConfig({
    required this.backendSelection,
    required this.documents,
    required this.queryRepeats,
    required this.outputPath,
  });

  final BackendSelection backendSelection;
  final int documents;
  final int queryRepeats;
  final String? outputPath;

  List<CindelStorageBackend> get backends {
    return switch (backendSelection) {
      BackendSelection.sqlite => const [CindelStorageBackend.sqlite],
      BackendSelection.mdbx => const [CindelStorageBackend.mdbx],
      BackendSelection.all => const [
        CindelStorageBackend.sqlite,
        CindelStorageBackend.mdbx,
      ],
    };
  }

  Map<String, Object?> toJson() {
    return {
      'backend': backendSelection.name,
      'documents': documents,
      'query_repeats': queryRepeats,
    };
  }

  static BenchmarkConfig parse(List<String> args) {
    var backend = BackendSelection.mdbx;
    var documents = _defaultDocuments;
    var queryRepeats = _defaultQueryRepeats;
    String? outputPath;
    String? pendingFlag;

    for (final arg in args) {
      final flag = pendingFlag;
      if (flag != null) {
        pendingFlag = null;
        switch (flag) {
          case '--backend':
            backend = BackendSelection.parse(arg);
          case '--documents':
            documents = parsePositiveInt(flag, arg);
          case '--query-repeats':
            queryRepeats = parsePositiveInt(flag, arg);
          case '--output':
            outputPath = arg;
          default:
            throw StateError('Unexpected benchmark flag `$flag`.');
        }
        continue;
      }

      switch (arg) {
        case '--backend':
        case '--documents':
        case '--query-repeats':
        case '--output':
          pendingFlag = arg;
        case '--help':
        case '-h':
          printHelp();
          exit(0);
        default:
          printHelp();
          throw ArgumentError('Unknown argument `$arg`.');
      }
    }

    if (pendingFlag != null) {
      throw ArgumentError('Missing value for `$pendingFlag`.');
    }

    return BenchmarkConfig(
      backendSelection: backend,
      documents: documents,
      queryRepeats: queryRepeats,
      outputPath: outputPath,
    );
  }
}

enum BackendSelection {
  sqlite,
  mdbx,
  all;

  static BackendSelection parse(String value) {
    return switch (value) {
      'sqlite' => BackendSelection.sqlite,
      'mdbx' => BackendSelection.mdbx,
      'all' => BackendSelection.all,
      _ => throw ArgumentError(
        '`--backend` must be one of `sqlite`, `mdbx`, or `all`; got `$value`.',
      ),
    };
  }
}

int parsePositiveInt(String flag, String value) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('`$flag` must be a positive integer.');
  }
  return parsed;
}

void printHelp() {
  stdout.writeln(
    'Usage: dart run tool/perf_benchmark.dart '
    '[--backend sqlite|mdbx|all] '
    '[--documents N] '
    '[--query-repeats N] '
    '[--output PATH]',
  );
}
