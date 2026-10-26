import 'dart:convert';
import 'dart:typed_data';
import 'package:cindel/src/web/native_document_reader.dart';
import 'package:test/test.dart';

void main() {
  // Scenario: A wide reader visits multiple rows and then a corrupt row.
  // Covers:
  // - Cached static size and offsets with empty schemas and mixed widths.
  // - Independent validation of headers, static sections and dynamic offsets.
  // Expected: Valid rows retain every field; corruption is never hidden by reuse.
  test('reuses schema offsets without skipping row validation.', () {
    // Arrange.
    final good = _wideDocument();
    final nulls = _wideDocument(nulls: true);
    final badHeader = Uint8List.fromList(good)..[0] ^= 1;
    final truncated = Uint8List.fromList(good.sublist(0, 5));
    final badOffset = Uint8List.fromList(good);
    // First string follows bool + int + double in the static section.
    badOffset.setRange(20, 23, [1, 0, 0]);
    final badPayload = Uint8List.fromList(good.sublist(0, good.length - 1));
    final reader = CindelWebNativeDocumentReader(
      ids: [1, 2, 3, 4, 5, 6, 7, 1],
      documents: [
        good,
        nulls,
        badHeader,
        truncated,
        badOffset,
        badPayload,
        null,
        good,
      ],
      fieldTypes: Uint8List.fromList([
        for (var i = 0; i < 16; i++) ...[0, 1, 2, 3],
      ]),
    );

    // Act / Assert: schema reuse never skips checks for the next document.
    for (final row in [0, 7]) {
      for (var i = 0; i < 16; i++) {
        expect(reader.readBool(row, i * 4), isTrue);
        expect(reader.readInt(row, i * 4 + 1), -42);
        expect(reader.readDouble(row, i * 4 + 2), 2.5);
        expect(reader.readString(row, i * 4 + 3), 'é漢$i');
      }
    }
    for (var i = 0; i < 16; i++) {
      expect(reader.readBool(1, i * 4), isNull);
      expect(reader.readInt(1, i * 4 + 1), isNull);
      expect(reader.readDouble(1, i * 4 + 2), isNull);
      expect(reader.readString(1, i * 4 + 3), isNull);
    }
    expect(() => reader.readBool(2, 0), throwsFormatException);
    expect(() => reader.readBool(3, 0), throwsFormatException);
    expect(() => reader.readString(4, 3), throwsFormatException);
    expect(() => reader.readString(5, 63), throwsFormatException);
    expect(reader.isPresent(6), isFalse);
    expect(() => reader.readBool(6, 0), throwsStateError);
    expect(() => reader.readInt(0, 0), throwsStateError);
    expect(() => reader.readInt(0, 64), throwsRangeError);
    expect(reader.readString(7, 63), 'é漢15');
    final empty = CindelWebNativeDocumentReader(
      ids: [8],
      documents: [
        Uint8List.fromList([0, 0, 0]),
      ],
      fieldTypes: Uint8List(0),
    );
    expect(empty.readId(0), 8);
    expect(() => empty.readBool(0, 0), throwsRangeError);
  });
}

// Encode an independent wire fixture, including each dynamic field's own offset.
Uint8List _wideDocument({bool nulls = false}) {
  const staticSize = 16 * (1 + 8 + 8 + 3);
  final fixed = Uint8List(3 + staticSize);
  final data = ByteData.sublistView(fixed);
  final dynamic = BytesBuilder();
  void u24(int at, int value) {
    fixed[at] = value & 255;
    fixed[at + 1] = (value >> 8) & 255;
    fixed[at + 2] = (value >> 16) & 255;
  }

  u24(0, staticSize);
  for (var i = 0; i < 16; i++) {
    final offset = 3 + 20 * i;
    fixed[offset] = nulls ? 255 : 1;
    if (nulls) {
      fixed[offset + 8] = 128;
    } else {
      // Signed -42 in little-endian form, without VM-only Int64 accessors.
      fixed.setRange(offset + 1, offset + 9, [
        214,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
      ]);
    }
    data.setFloat64(offset + 9, nulls ? double.nan : 2.5, Endian.little);
    if (!nulls) {
      final text = utf8.encode('é漢$i');
      u24(offset + 17, staticSize + dynamic.length);
      dynamic.add([text.length, 0, 0]);
      dynamic.add(text);
    }
  }
  return Uint8List.fromList([...fixed, ...dynamic.takeBytes()]);
}
