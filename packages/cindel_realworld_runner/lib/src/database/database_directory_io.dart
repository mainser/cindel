import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> cindelRealworldDatabaseDirectory() async {
  final support = await _supportDirectory();
  final runId = DateTime.now().microsecondsSinceEpoch;
  return '${support.path}${Platform.pathSeparator}'
      'cindel_realworld_runner_$runId';
}

Future<Directory> _supportDirectory() async {
  if (!Platform.isWindows) {
    return getApplicationSupportDirectory();
  }

  final appDataPath =
      Platform.environment['APPDATA'] ?? Platform.environment['LOCALAPPDATA'];
  if (appDataPath == null || appDataPath.trim().isEmpty) {
    throw StateError('Windows application data directory is unavailable.');
  }
  return Directory('$appDataPath${Platform.pathSeparator}Cindel');
}
