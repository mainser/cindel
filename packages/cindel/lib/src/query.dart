import 'dart:async';
import 'dart:typed_data';

import 'package:cindel_annotations/cindel_annotations.dart';

import 'cindel_error.dart';
import 'database.dart';
import 'native/wire.dart';
import 'schema.dart';
import 'text.dart';

// Public query API and runtime helpers.
//
// This library is split into `part` files so the exported API remains stable
// while contributors can work on filters, native planning, projections, and
// in-memory result helpers independently.
part 'query/filters.dart';
part 'query/query_core.dart';
part 'query/native_filter_encoding.dart';
part 'query/property_queries.dart';
part 'query/result_helpers.dart';
