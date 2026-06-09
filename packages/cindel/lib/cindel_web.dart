/// Web entrypoint for Cindel worker transport APIs.
///
/// The main `package:cindel/cindel.dart` entrypoint remains the native FFI API.
/// Import this library from Dart Web code that needs to communicate with the
/// Cindel Web worker runtime.
library cindel_web;

export 'src/web/worker_bridge.dart';
