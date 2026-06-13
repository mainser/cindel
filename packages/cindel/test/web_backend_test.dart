import 'web_public_entrypoint_contract_suite.dart'
    as web_public_entrypoint_contract;
import 'web_schema_manifest_suite.dart' as web_schema_manifest;
import 'web_wire_codec_suite.dart' as web_wire_codec;
import 'web_worker_bridge_stub_suite.dart' as web_worker_bridge_stub;

void main() {
  web_public_entrypoint_contract.main();
  web_schema_manifest.main();
  web_wire_codec.main();
  web_worker_bridge_stub.main();
}
