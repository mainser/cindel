import FlutterMacOS
import CindelNative

public class CindelFlutterLibsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Keep the dynamic framework linked even with dead_strip_dylibs enabled.
    // Dart performs the ABI compatibility check before invoking database APIs.
    _ = cindel_abi_version()
  }
}
