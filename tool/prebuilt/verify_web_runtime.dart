import 'dart:convert';
import 'dart:io';

/// Checks only the supplied release runtime; does not build or run the CI suite.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: verify_web_runtime.dart <runtime-directory>');
  }
  final runtime = Directory(arguments.single).absolute;
  for (final path in [
    'cindel_worker.js',
    'pkg/cindel_native.js',
    'pkg/cindel_native_bg.wasm',
  ]) {
    if (!File('${runtime.path}/$path').existsSync()) {
      throw StateError('Missing release runtime file: ${runtime.path}/$path');
    }
  }
  final tools = File.fromUri(Platform.script).parent;
  final workspace = tools.parent.parent;
  final configFile = File('${workspace.path}/.dart_tool/package_config.json');
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = (config['packages'] as List).cast<Map<String, dynamic>>();
  for (final entry in packages) {
    entry['rootUri'] = Directory.fromUri(
      configFile.uri.resolve(entry['rootUri'] as String),
    ).uri.toString();
  }
  final testPackage = packages.singleWhere((entry) => entry['name'] == 'test');
  final testExecutable = File.fromUri(
    Uri.parse(testPackage['rootUri'] as String).resolve('bin/test.dart'),
  );
  final temporaryRoot = Directory.systemTemp.absolute;
  final stage = await temporaryRoot.createTemp('cindel_release_web_');
  try {
    final stagedConfig = File('${stage.path}/.dart_tool/package_config.json');
    await stagedConfig.parent.create(recursive: true);
    await stagedConfig.writeAsString(jsonEncode(config));
    await File('${stage.path}/pubspec.yaml').writeAsString(
      'name: cindel_release_smoke\npublish_to: none\n'
      'environment:\n  sdk: ^3.11.0\n',
    );
    await File(
      '${tools.path}/web_runtime_smoke_test.dart',
    ).copy('${stage.path}/web_runtime_smoke_test.dart');
    final stagedRuntime = Directory(
      '${stage.path}/assets/packages/cindel_flutter_libs/web',
    );
    await for (final file in runtime.list(
      recursive: true,
      followLinks: false,
    )) {
      if (file is! File) continue;
      final relative = file.uri.path.substring(runtime.uri.path.length);
      final destination = File('${stagedRuntime.path}/$relative');
      await destination.parent.create(recursive: true);
      await file.copy(destination.path);
    }
    // Probe the Wasm export through its generated bindings in an actual Worker.
    // The subsequent database open uses the original packaged Worker unchanged.
    await File('${stage.path}/abi_probe.js').writeAsString('''
import init from './assets/packages/cindel_flutter_libs/web/pkg/cindel_native.js';
const wasm = await init({
  module_or_path: new URL(
    './assets/packages/cindel_flutter_libs/web/pkg/cindel_native_bg.wasm',
    import.meta.url,
  ),
});
self.postMessage(wasm.cindel_abi_version());
''');
    final process = await Process.start(
      'dart',
      [
        '--packages=${stagedConfig.path}',
        testExecutable.path,
        'web_runtime_smoke_test.dart',
        '--platform',
        'chrome',
        '--reporter',
        'expanded',
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
    if (stage.absolute.parent.path != temporaryRoot.path) {
      throw StateError('Refusing to remove a directory outside the temp root.');
    }
    await stage.delete(recursive: true);
  }
}
