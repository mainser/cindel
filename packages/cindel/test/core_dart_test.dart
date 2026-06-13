import 'binary_document_suite.dart' as binary_document;
import 'cindel_error_suite.dart' as cindel_error;
import 'database_change_set_suite.dart' as database_change_set;
import 'database_document_codecs_suite.dart' as database_document_codecs;
import 'native_asset_functions_suite.dart' as native_asset_functions;
import 'native_binding_utils_suite.dart' as native_binding_utils;
import 'native_document_codecs_suite.dart' as native_document_codecs;
import 'query_filter_predicate_suite.dart' as query_filter_predicate;
import 'schema_helpers_suite.dart' as schema_helpers;
import 'text_suite.dart' as text;
import 'wire_codec_suite.dart' as wire_codec;

void main() {
  binary_document.main();
  cindel_error.main();
  database_change_set.main();
  database_document_codecs.main();
  native_asset_functions.main();
  native_binding_utils.main();
  native_document_codecs.main();
  query_filter_predicate.main();
  schema_helpers.main();
  text.main();
  wire_codec.main();
}
