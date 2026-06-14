// Exposes the Web worker bridge on Dart Web and a throwing stub elsewhere.
export 'worker_bridge_stub.dart'
    if (dart.library.js_interop) 'worker_bridge_web.dart';
