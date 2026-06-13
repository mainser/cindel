import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel errors', () {
    // Scenario: Cindel reports runtime failures with stable error types.
    // Covers:
    // - Every concrete [CindelError] constructor.
    // - Stable [CindelError.name] values.
    // - [CindelError.toString] formatting.
    // Expected: Errors remain StateError-compatible and expose concise names.
    test('formats all concrete runtime errors.', () {
      // Arrange.
      final errors = <CindelError>[
        CindelOpenError(backend: 'mdbx'),
        CindelDatabaseClosedError(),
        CindelTransactionError('Nested transactions are not supported.'),
        CindelSchemaError('Missing schema.'),
        CindelQueryError('Invalid query.'),
        CindelUniqueIndexError('email'),
        CindelNativeError('Native payload was invalid.'),
      ];

      // Act.
      final names = [for (final error in errors) error.name];
      final messages = [for (final error in errors) error.message];
      final formatted = [for (final error in errors) error.toString()];

      // Assert.
      expect(errors, everyElement(isA<StateError>()));
      expect(names, [
        'CindelOpenError',
        'CindelDatabaseClosedError',
        'CindelTransactionError',
        'CindelSchemaError',
        'CindelQueryError',
        'CindelUniqueIndexError',
        'CindelNativeError',
      ]);
      expect(messages, [
        'Failed to open Cindel native engine with backend `mdbx`.',
        'CindelDatabase is closed.',
        'Nested transactions are not supported.',
        'Missing schema.',
        'Invalid query.',
        'Unique index `email` already contains this value.',
        'Native payload was invalid.',
      ]);
      expect(formatted, [
        'CindelOpenError: Failed to open Cindel native engine with backend '
            '`mdbx`.',
        'CindelDatabaseClosedError: CindelDatabase is closed.',
        'CindelTransactionError: Nested transactions are not supported.',
        'CindelSchemaError: Missing schema.',
        'CindelQueryError: Invalid query.',
        'CindelUniqueIndexError: Unique index `email` already contains this '
            'value.',
        'CindelNativeError: Native payload was invalid.',
      ]);
    });
  });
}
