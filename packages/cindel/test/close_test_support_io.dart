import 'dart:io';

/// Uses the same public string directory contract as the browser fixture.
Future<String> createCloseTestDirectory() async =>
    (await Directory.systemTemp.createTemp('cindel_close_')).path;

/// Database teardown is registered after this cleanup and therefore runs first.
Future<void> deleteCloseTestDirectory(String directory) =>
    Directory(directory).delete(recursive: true);
