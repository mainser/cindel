import 'dart:convert';
import 'dart:io';

/// Runs the browser close contracts against the current package sources and
/// the same Worker/Wasm assets bundled for Flutter applications.
///
/// Run from the workspace after resolving its dependencies. Chrome must be
/// installed; CHROME_EXECUTABLE may select its executable. Additional arguments
/// are forwarded to package:test (for example --plain-name to select a case).
Future<void> main(List<String> arguments) async {
  final package = File.fromUri(Platform.script).parent.parent;
  final configFile = await _findPackageConfig(package);
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = (config['packages'] as List).cast<Map<String, dynamic>>();
  for (final entry in packages) {
    // The staging directory has a different depth. Keep all imports pointing
    // at the currently resolved sources and versions rather than copies.
    entry['rootUri'] = Directory.fromUri(
      configFile.uri.resolve(entry['rootUri'] as String),
    ).uri.toString();
  }
  final testPackage = packages.singleWhere((entry) => entry['name'] == 'test');
  final testExecutable = File.fromUri(
    Uri.parse(testPackage['rootUri'] as String).resolve('bin/test.dart'),
  );
  final runtime = Directory.fromUri(
    package.uri.resolve('../cindel_flutter_libs/web/'),
  );
  if (!await runtime.exists()) {
    throw StateError('The packaged Cindel Web runtime assets are missing.');
  }
  final temporaryRoot = Directory.systemTemp.absolute;
  final stage = await temporaryRoot.createTemp('cindel_web_tests_');
  try {
    final stagedConfig = File('${stage.path}/.dart_tool/package_config.json');
    await stagedConfig.parent.create(recursive: true);
    await stagedConfig.writeAsString(jsonEncode(config));
    await File('${stage.path}/pubspec.yaml').writeAsString(
      'name: cindel_browser_test_runner\n'
      'publish_to: none\n'
      'environment:\n'
      '  sdk: ^3.11.0\n',
    );
    final suite = File('${package.path}/test/web_browser_backend_test.dart');
    // A test at the server root resolves Cindel's normal relative assets URL.
    // Only this bootstrap is staged; the shared suite uses the real sources.
    await File('${stage.path}/web_close_test.dart').writeAsString(
      "@TestOn('browser')\n"
      'library;\n'
      "import 'package:test/test.dart';\n"
      "import '${suite.uri}' as suite;\n"
      'void main() => suite.main();\n',
    );
    await _copyDirectory(
      runtime,
      Directory('${stage.path}/assets/packages/cindel_flutter_libs/web'),
    );
    await _copyDirectory(
      Directory('${package.path}/test/fixtures/web_close'),
      Directory('${stage.path}/fixtures'),
    );

    // Execute the resolved package:test entrypoint without another pub get or
    // dependency graph. Dart itself is selected from the active shell PATH.
    final process = await Process.start(
      'dart',
      [
        '--packages=${stagedConfig.path}',
        testExecutable.path,
        'web_close_test.dart',
        '--platform',
        'chrome',
        '--reporter',
        'expanded',
        ...arguments,
      ],
      workingDirectory: stage.path,
      runInShell: Platform.isWindows,
    );
    await Future.wait([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    exitCode = await process.exitCode;
  } finally {
    // This directory contains only this invocation's generated test bootstrap
    // and copied assets; package sources and browser data are outside it.
    if (stage.absolute.parent.path != temporaryRoot.path) {
      throw StateError(
        'Refusing to remove a test directory outside its temporary root.',
      );
    }
    await stage.delete(recursive: true);
  }
}

Future<File> _findPackageConfig(Directory start) async {
  var directory = start;
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (await config.exists()) return config;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Resolve workspace dependencies before running browser tests.',
      );
    }
    directory = parent;
  }
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  if (!await source.exists()) return;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      // Directory.fromUri can retain a trailing separator in path. Its URI
      // always ends in '/', so this does not drop a filename's first character.
      final relative = entity.uri.path.substring(source.uri.path.length);
      final destination = File('${target.path}/$relative');
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }
}
