import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// Runs the core suites against CINDEL_NATIVE_LIBRARY, including @Native calls.
/// Additional arguments are forwarded to package:test, including coverage flags.
Future<void> main(List<String> arguments) async {
  final libraryPath = Platform.environment['CINDEL_NATIVE_LIBRARY'];
  if (libraryPath == null || !File(libraryPath).existsSync()) {
    throw StateError(
      'Set CINDEL_NATIVE_LIBRARY to the compiled Cindel library.',
    );
  }
  final library = File(libraryPath).absolute.path;
  final workspace = File.fromUri(Platform.script).parent.parent.parent.parent;
  final configFile = File('${workspace.path}/.dart_tool/package_config.json');
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final testPackage = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((entry) => entry['name'] == 'test');
  final testExecutable = File.fromUri(
    Directory.fromUri(
      configFile.uri.resolve(testPackage['rootUri'] as String),
    ).uri.resolve('bin/test.dart'),
  );
  final mapping = File('${workspace.path}/.dart_tool/native_assets.yaml');
  final previousMapping = await mapping.exists()
      ? await mapping.readAsBytes()
      : null;
  try {
    await mapping.writeAsString(
      jsonEncode({
        'format-version': [1, 0, 0],
        'native-assets': {
          Abi.current().toString(): {
            'package:cindel/src/native/bindings.dart': ['absolute', library],
          },
        },
      }),
    );
    // Invoke package:test directly: `dart test` would run the workspace's
    // disabled build hook again and replace the mapping before compilation.
    final process = await Process.start(
      'dart',
      [
        '--packages=${configFile.path}',
        testExecutable.path,
        'packages/cindel/test/core_dart_test.dart',
        'packages/cindel/test/distinct_key_test.dart',
        '--reporter',
        'expanded',
        ...arguments,
      ],
      workingDirectory: workspace.path,
      runInShell: Platform.isWindows,
    );
    await Future.wait([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    exitCode = await process.exitCode;
  } finally {
    if (previousMapping == null) {
      if (await mapping.exists()) await mapping.delete();
    } else {
      await mapping.writeAsBytes(previousMapping);
    }
  }
}
