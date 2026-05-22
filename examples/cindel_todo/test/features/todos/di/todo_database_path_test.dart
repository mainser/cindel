import 'dart:io';

import 'package:cindel_todo/features/todos/di/todos_di.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cindelTodoDatabaseDirectory', () {
    // Scenario: The Windows support directory already includes the Cindel app
    // namespace.
    // Covers:
    // - [cindelTodoDatabaseDirectory] appending only the example database name.
    // - Regression protection for duplicated `cindel_todo/cindel_todo` paths.
    // Expected: The final path ends in one `cindel_todo` segment.
    test('appends the example database folder once', () {
      // Arrange.
      final supportDirectory = Directory(
        '${Platform.pathSeparator}users${Platform.pathSeparator}appdata'
        '${Platform.pathSeparator}Cindel',
      );

      // Act.
      final databaseDirectory = cindelTodoDatabaseDirectory(supportDirectory);

      // Assert.
      expect(
        databaseDirectory.path,
        '${supportDirectory.path}${Platform.pathSeparator}cindel_todo',
      );
      expect(databaseDirectory.path.endsWith('cindel_todo'), isTrue);
      expect(
        databaseDirectory.path.endsWith(
          'cindel_todo${Platform.pathSeparator}cindel_todo',
        ),
        isFalse,
      );
    });
  });
}
