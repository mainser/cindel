import 'dart:typed_data';

import 'package:cindel/src/generic_document.dart';
import 'package:test/test.dart';

void main() {
  group('GenericDocumentV1', () {
    // Scenario: A manual Cindel document uses every supported value family.
    // Covers:
    // - GenericDocumentV1 encode and decode helpers.
    // - Nested object and list values.
    // - Null, bool, int, double, and string scalar values.
    // Expected: The document round-trips without changing public map values.
    test('round-trips nested manual document values.', () {
      // Arrange.
      final document = <String, Object?>{
        'id': 7,
        'name': 'Noel',
        'active': true,
        'score': 9.5,
        'profile': {
          'tags': ['local', null, 3],
          'settings': {'theme': 'dark'},
        },
        'missing': null,
      };

      // Act.
      final bytes = cindelEncodeGenericDocument(document);
      final decoded = cindelDecodeGenericDocument(bytes);

      // Assert.
      expect(cindelIsGenericDocument(bytes), isTrue);
      expect(decoded, document);
    });

    // Scenario: The same logical document is encoded with different map
    // insertion orders.
    // Covers:
    // - Canonical object key ordering by UTF-8 bytes.
    // - Stable document bytes for deterministic manual writes.
    // Expected: Both encodings are byte-identical and decode in canonical
    //   field order.
    test('sorts object keys by UTF-8 bytes.', () {
      // Arrange.
      final first = <String, Object?>{'é': 3, 'aa': 2, 'a': 1};
      final second = <String, Object?>{'a': 1, 'é': 3, 'aa': 2};

      // Act.
      final firstBytes = cindelEncodeGenericDocument(first);
      final secondBytes = cindelEncodeGenericDocument(second);
      final decoded = cindelDecodeGenericDocument(firstBytes);

      // Assert.
      expect(firstBytes, secondBytes);
      expect(decoded.keys.toList(), ['a', 'aa', 'é']);
    });

    // Scenario: Native or storage bytes are corrupt or from another format.
    // Covers:
    // - GenericDocumentV1 magic validation.
    // - Version validation.
    // - Trailing payload rejection.
    // Expected: Invalid document payloads fail closed.
    test('rejects invalid document payloads.', () {
      // Arrange.
      final valid = cindelEncodeGenericDocument({'name': 'Ana'});
      final unsupportedVersion = Uint8List.fromList(valid)..[4] = 2;
      final trailing = Uint8List.fromList([...valid, 0]);

      // Act and assert.
      expect(
        () => cindelDecodeGenericDocument(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => cindelDecodeGenericDocument(unsupportedVersion),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => cindelDecodeGenericDocument(trailing),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
