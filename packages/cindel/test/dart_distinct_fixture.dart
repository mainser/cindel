import 'package:cindel/cindel.dart';

import 'schema_generation_fixture.dart' show Recipient, RecipientMetadata;

part 'dart_distinct_fixture.g.dart';

// Keep this fixture limited to the fields used by the distinct regressions.
// User also contains numeric lists, whose Web reader is not supported yet.
@Collection(name: 'distinctRecords')
class DistinctRecord {
  Id dbId = autoIncrement;
  late String name;
  late String email;
  String? displayName;
  List<String> tags = const [];
  Recipient? primaryRecipient;
  List<Recipient>? recipients;
}
