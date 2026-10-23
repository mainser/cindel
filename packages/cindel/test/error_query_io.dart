import 'dart:typed_data';
import 'package:cindel/cindel.dart';

Future<List<int>> failingQuery(CindelDatabase db) => db.queryNativePlanIds(
  'backup_nodes',
  CindelNativeQueryPlan(
    source: const CindelNativeAllQuerySource(),
    filter: Uint8List.fromList([255]),
  ),
);
