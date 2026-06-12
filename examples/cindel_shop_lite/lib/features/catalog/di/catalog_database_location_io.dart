import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Builds the stable application-support path for the Shop Lite database.
Future<String> cindelShopLiteDatabaseDirectory() async {
  final supportDirectory = await _applicationSupportDirectory();
  return '${supportDirectory.path}${Platform.pathSeparator}cindel_shop_lite';
}

Future<Directory> _applicationSupportDirectory() async {
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
