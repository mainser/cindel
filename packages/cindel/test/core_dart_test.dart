import 'binary_document_suite.dart' as binary_document;
import 'generic_document_suite.dart' as generic_document;
import 'native_asset_functions_suite.dart' as native_asset_functions;
import 'schema_helpers_suite.dart' as schema_helpers;
import 'text_suite.dart' as text;
import 'wire_codec_suite.dart' as wire_codec;

void main() {
  binary_document.main();
  generic_document.main();
  native_asset_functions.main();
  schema_helpers.main();
  text.main();
  wire_codec.main();
}
