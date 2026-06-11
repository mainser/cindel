import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

Future<File> _packageFile(String packageUri) async {
  final uri = await Isolate.resolvePackageUri(Uri.parse(packageUri));
  if (uri == null) {
    throw StateError('Could not resolve $packageUri');
  }
  return File.fromUri(uri);
}

Future<String> _readPackageFile(String packageUri) async {
  return (await _packageFile(packageUri)).readAsString();
}

void main() {
  // Scenario: A Flutter Web app imports only the normal Cindel public library.
  // Covers:
  // - Conditional exports for the Web `Cindel.open(...)` facade.
  // - Conditional exports for the Web database and typed collection surfaces.
  // - Preventing a future split back into a separate app-facing Web library.
  // Expected: `package:cindel/cindel.dart` owns the Web application entrypoint.
  test(
    'package:cindel/cindel.dart owns the Web application entrypoint',
    () async {
      final source = await _readPackageFile('package:cindel/cindel.dart');

      expect(
        source,
        contains(
          "export 'src/cindel.dart' if (dart.library.js_interop) "
          "'src/web/cindel.dart';",
        ),
      );
      expect(
        source,
        contains(
          "export 'src/database.dart' if (dart.library.js_interop) "
          "'src/web/database.dart';",
        ),
      );
      expect(
        source,
        contains(
          "export 'src/typed_collection.dart'\n"
          "    if (dart.library.js_interop) 'src/web/typed_collection.dart';",
        ),
      );
    },
  );

  // Scenario: The old bridge-only Web library name is accidentally restored.
  // Covers:
  // - Public package surface cleanup after Web moved behind `Cindel.open(...)`.
  // - Keeping direct Worker access out of the application API.
  // Expected: No `cindel_web.dart` public entrypoint is present beside
  // `cindel.dart`.
  test('package:cindel/cindel_web.dart is not a public entrypoint', () async {
    final publicEntrypoint = await _packageFile('package:cindel/cindel.dart');
    final removedEntrypoint = File.fromUri(
      publicEntrypoint.uri.resolve('cindel_web.dart'),
    );

    expect(removedEntrypoint.existsSync(), isFalse);
  });
}
