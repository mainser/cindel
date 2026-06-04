import 'dart:typed_data';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('binary documents', () {
    // Scenario: Generated serializers encode a full schema-backed compact
    // document and generated hydrators read fields directly by static offset.
    // Covers:
    // - Compact bool, int, double, string, list, and object field encoding.
    // - [cindelDecodeSchemaBinaryDocument] full-document decoding.
    // - [CindelSchemaBinaryDocumentReader] direct field reads.
    // Expected: Every supported compact field type round-trips with the same
    //   value through both decoding APIs.
    test(
      'round-trips schema-backed compact fields and direct reader access.',
      () {
        final fieldTypes = [
          CindelBinaryFieldType.boolValue,
          CindelBinaryFieldType.intValue,
          CindelBinaryFieldType.doubleValue,
          CindelBinaryFieldType.stringValue,
          CindelBinaryFieldType.listValue,
          CindelBinaryFieldType.objectValue,
        ];
        final bytes = cindelEncodeSchemaBinaryDocument([
          true,
          42,
          1.25,
          'Ana',
          [1, 'two', null],
          {'active': false},
        ], fieldTypes);

        expect(cindelDecodeSchemaBinaryDocument(bytes, fieldTypes), [
          true,
          42,
          1.25,
          'Ana',
          [1, 'two', null],
          {'active': false},
        ]);

        final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 26);
        expect(reader.readBool(0, 0), isTrue);
        expect(reader.readInt(0, 1), 42);
        expect(reader.readDouble(0, 9), 1.25);
        expect(reader.readString(0, 17), 'Ana');
        expect(reader.readList(0, 20), [1, 'two', null]);
        expect(reader.readObject(0, 23), {'active': false});
      },
    );

    // Scenario: Generated serializers encode a compact document whose fields
    // are all null.
    // Covers:
    // - Compact null sentinels for bool, int, and double fields.
    // - Null dynamic offsets for string, list, and object fields.
    // - Direct reader null handling.
    // Expected: Full-document and direct-reader APIs return null for every
    //   compact field type.
    test('round-trips null schema-backed compact fields.', () {
      final fieldTypes = [
        CindelBinaryFieldType.boolValue,
        CindelBinaryFieldType.intValue,
        CindelBinaryFieldType.doubleValue,
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.listValue,
        CindelBinaryFieldType.objectValue,
      ];
      final bytes = cindelEncodeSchemaBinaryDocument(
        List<Object?>.filled(fieldTypes.length, null),
        fieldTypes,
      );
      final reader = CindelSchemaBinaryDocumentReader(bytes, staticSize: 26);

      expect(cindelDecodeSchemaBinaryDocument(bytes, fieldTypes), [
        null,
        null,
        null,
        null,
        null,
        null,
      ]);
      expect(reader.readBool(0, 0), isNull);
      expect(reader.readInt(0, 1), isNull);
      expect(reader.readDouble(0, 9), isNull);
      expect(reader.readString(0, 17), isNull);
      expect(reader.readList(0, 20), isNull);
      expect(reader.readObject(0, 23), isNull);
    });

    // Scenario: Callers pass invalid schema-backed compact document inputs or
    // receive compact bytes that do not match the expected schema.
    // Covers:
    // - Field/type count validation.
    // - Compact int null sentinel and non-finite double rejection.
    // - Short headers, mismatched static sizes, truncated static sections, and
    //   invalid bool bytes.
    // - [CindelSchemaBinaryDocumentReader] constructor validation.
    // Expected: Invalid compact payloads fail before returning partial values.
    test('rejects invalid schema-backed compact documents.', () {
      expect(
        () => cindelEncodeSchemaBinaryDocument([1], const []),
        throwsArgumentError,
      );
      expect(
        () => cindelEncodeSchemaBinaryDocument(
          [-9223372036854775808],
          [CindelBinaryFieldType.intValue],
        ),
        throwsArgumentError,
      );
      expect(
        () => cindelEncodeSchemaBinaryDocument(
          [double.nan],
          [CindelBinaryFieldType.doubleValue],
        ),
        throwsArgumentError,
      );
      expect(
        () => cindelDecodeSchemaBinaryDocument(bytes([1, 0]), [
          CindelBinaryFieldType.boolValue,
        ]),
        throwsStateError,
      );
      expect(
        () => cindelDecodeSchemaBinaryDocument(bytes([1, 0, 0, 0]), [
          CindelBinaryFieldType.intValue,
        ]),
        throwsStateError,
      );
      expect(
        () => cindelDecodeSchemaBinaryDocument(bytes([8, 0, 0, 0]), [
          CindelBinaryFieldType.intValue,
        ]),
        throwsStateError,
      );
      expect(
        () => cindelDecodeSchemaBinaryDocument(bytes([1, 0, 0, 2]), [
          CindelBinaryFieldType.boolValue,
        ]),
        throwsStateError,
      );
      expect(
        () => CindelSchemaBinaryDocumentReader(bytes([1, 0]), staticSize: 1),
        throwsStateError,
      );
      expect(
        () => CindelSchemaBinaryDocumentReader(
          bytes([1, 0, 0, 0]),
          staticSize: 8,
        ),
        throwsStateError,
      );
      expect(
        () => CindelSchemaBinaryDocumentReader(
          bytes([8, 0, 0, 0]),
          staticSize: 8,
        ),
        throwsStateError,
      );

      final invalidBoolReader = CindelSchemaBinaryDocumentReader(
        bytes([1, 0, 0, 2]),
        staticSize: 1,
      );
      expect(() => invalidBoolReader.readBool(0, 0), throwsStateError);
    });

    // Scenario: Native or persisted bytes reference malformed compact dynamic
    // field payloads.
    // Covers:
    // - Dynamic offsets pointing into the static section.
    // - Truncated dynamic length headers.
    // - Truncated dynamic payload bytes.
    // Expected: Malformed dynamic fields throw StateError during decode.
    test('rejects malformed compact dynamic fields.', () {
      expect(
        () => cindelDecodeSchemaBinaryDocument(bytes([3, 0, 0, 1, 0, 0]), [
          CindelBinaryFieldType.stringValue,
        ]),
        throwsStateError,
      );
      expect(
        () => cindelDecodeSchemaBinaryDocument(bytes([3, 0, 0, 3, 0, 0]), [
          CindelBinaryFieldType.stringValue,
        ]),
        throwsStateError,
      );
      expect(
        () => cindelDecodeSchemaBinaryDocument(
          bytes([3, 0, 0, 3, 0, 0, 2, 0, 0, 65]),
          [CindelBinaryFieldType.stringValue],
        ),
        throwsStateError,
      );
    });

    // Scenario: Manual binary object/list payload APIs encode supported Dart
    // values used by generic embedded documents.
    // Covers:
    // - Null, bool, int, double, string, list, and object value records.
    // - DateTime and Duration microsecond payload encoding.
    // - Stable object decoding after key sorting.
    // Expected: Public binary object/list helpers round-trip supported values
    //   using the generic binary payload format.
    test('round-trips binary object and list values.', () {
      final object = {
        'bool': true,
        'date': DateTime.fromMicrosecondsSinceEpoch(7, isUtc: true),
        'double': 1.5,
        'duration': const Duration(microseconds: 8),
        'int': 9,
        'list': [null, 'nested'],
        'nested': {'ok': false},
        'null': null,
        'string': 'value',
      };

      expect(cindelDecodeBinaryObject(cindelEncodeBinaryObject(object)), {
        'bool': true,
        'date': 7,
        'double': 1.5,
        'duration': 8,
        'int': 9,
        'list': [null, 'nested'],
        'nested': {'ok': false},
        'null': null,
        'string': 'value',
      });
      expect(
        cindelDecodeBinaryList(
          cindelEncodeBinaryList([false, 3, 2.5, 'x', null]),
        ),
        [false, 3, 2.5, 'x', null],
      );
    });

    // Scenario: A caller tries to encode unsupported values or decode a value
    // record with an unknown binary kind.
    // Covers:
    // - [_BinaryValue.from] unsupported value rejection through public helpers.
    // - Unknown value-record tag decoding.
    // Expected: Unsupported write values throw ArgumentError and unknown tags
    //   throw StateError.
    test('rejects unsupported and unknown binary value records.', () {
      expect(() => cindelEncodeBinaryList([Object()]), throwsArgumentError);
      expect(
        () => cindelDecodeBinaryList(
          bytes([1, 0, 0, 0, 99, 0, 0, 0, 0, 0, 0, 0]),
        ),
        throwsStateError,
      );
    });

    // Scenario: The decoder receives compact string-list payloads produced by
    // optimized native/generated paths.
    // Covers:
    // - Compact string-list marker decoding.
    // - Nested compact string-list decoding.
    // - Truncated offsets, offset payloads, truncated payloads, and trailing
    //   bytes.
    // Expected: Valid compact string lists decode to nullable string lists and
    //   malformed payloads throw StateError.
    test('decodes and validates compact string list payloads.', () {
      expect(
        cindelDecodeBinaryList(
          bytes([
            0xff, 0xff, 0xff, 0xff, 1, 2, 0, 0, 0,
            0, 0, 0, // null offset
            15, 0, 0, // "hi" payload offset
            2, 0, 0, 104, 105,
          ]),
        ),
        [null, 'hi'],
      );
      expect(
        cindelDecodeBinaryList(
          bytes([
            6, 0, 0,
            6, 0, 0, // "A" payload offset
            0, 0, 0, // null offset
            1, 0, 0, 65,
          ]),
        ),
        ['A', null],
      );
      expect(
        () => cindelDecodeBinaryList(
          bytes([0xff, 0xff, 0xff, 0xff, 1, 1, 0, 0, 0]),
        ),
        throwsStateError,
      );
      expect(
        () => cindelDecodeBinaryList(
          bytes([0xff, 0xff, 0xff, 0xff, 1, 1, 0, 0, 0, 9, 0, 0]),
        ),
        throwsStateError,
      );
      expect(
        () => cindelDecodeBinaryList(
          bytes([0xff, 0xff, 0xff, 0xff, 1, 1, 0, 0, 0, 12, 0, 0, 2, 0, 0, 65]),
        ),
        throwsStateError,
      );
      expect(
        () => cindelDecodeBinaryList(
          bytes([0xff, 0xff, 0xff, 0xff, 1, 1, 0, 0, 0, 12, 0, 0, 0, 0, 0, 65]),
        ),
        throwsStateError,
      );
    });
  });
}

Uint8List bytes(Iterable<int> values) => Uint8List.fromList(values.toList());
