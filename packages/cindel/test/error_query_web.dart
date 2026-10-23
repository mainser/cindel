import 'dart:typed_data';
import 'package:cindel/src/web/database.dart';
import 'package:cindel/src/web/wire.dart';

Future<List<int>> failingQuery(CindelDatabase db) => db.queryNativePlanIds(
  'backup_nodes',
  WireQueryPlan(
    source: const WireQuerySource.all(),
    filter: Uint8List.fromList([255]),
    sorts: const [],
    distinctFields: const [],
    offset: 0,
    limit: null,
  ),
);
