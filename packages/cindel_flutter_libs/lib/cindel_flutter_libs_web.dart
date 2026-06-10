import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web plugin registration for the Cindel runtime assets package.
///
/// The Cindel public API lives in `package:cindel/cindel.dart`. This plugin
/// exists so Flutter Web includes the packaged Worker, JavaScript glue, and
/// Wasm runtime assets from `cindel_flutter_libs`.
class CindelFlutterLibsWeb {
  /// Registers the Web companion package with Flutter.
  static void registerWith(Registrar registrar) {}
}
