import 'dart:collection';
import 'dart:typed_data';

import 'package:cindel/src/native/wire.dart'
    if (dart.library.js_interop) 'package:cindel/src/web/wire.dart';
import 'package:test/test.dart';

const _browser = bool.fromEnvironment('dart.library.js_interop');

void main() {
  group('Cindel ID codec', () {
    // Scenario: ID batches cross byte, word and integer precision boundaries.
    // Covers:
    // - Byte compatibility with the previous writer and lossless round trips.
    // Expected: Native and Web keep their existing little-endian wire values.
    test('preserves the previous bytes at integer boundaries.', () {
      // Arrange.
      final ids = [0, 1, 255, 65536, 4294967295, 4294967296, 9007199254740991];
      if (!_browser) ids.add(int.parse('9223372036854775807'));
      // Act.
      final payload = encodeIdList(ids);
      // Assert.
      expect(payload, _legacyEncode(ids));
      expect(decodeIdList(payload), ids);
      expect(payload.sublist(0, 4), [ids.length, 0, 0, 0]);
      if (_browser) {
        // Powers of two above the public safe-ID range are exactly representable
        // in JS. Preserve the low-level codec's existing arithmetic as well.
        final large = [
          int.parse('9007199254740992'),
          int.parse('9223372036854775808'),
        ];
        expect(encodeIdList(large), _legacyEncode(large));
      }
    });

    // Scenario: A large batch contains ordered, duplicated and absent IDs.
    // Covers:
    // - One input traversal, exact output capacity and independent output bytes.
    // Expected: No input list copy is requested and the result has no spare capacity.
    test('writes one exact-sized output without copying the input.', () {
      // Arrange.
      final values = List.generate(32768, (i) => i.isEven ? i + 1 : 7);
      final ids = _ObservedIds(values);
      // Act.
      final payload = encodeIdList(ids);
      // Assert.
      expect(ids.reads, values.length);
      expect(payload.length, 4 + values.length * 8);
      expect(payload.buffer.lengthInBytes, payload.length);
      expect(payload, _legacyEncode(values));
      expect(decodeIdList(payload), values);
      values[0] = 99;
      expect(decodeIdList(payload).first, 1);
    });

    // Scenario: Empty batches are encoded repeatedly.
    // Covers:
    // - Count-only payloads and independently mutable output buffers.
    // Expected: Each call returns its own four-byte zero count.
    test('preserves empty batches and output ownership.', () {
      // Arrange / Act.
      final first = encodeIdList([]);
      final second = encodeIdList([]);
      // Assert.
      expect(first, [0, 0, 0, 0]);
      expect(first.buffer.lengthInBytes, 4);
      first[0] = 1;
      expect(second, [0, 0, 0, 0]);
      expect(decodeIdList(second), isEmpty);
    });

    // Scenario: Invalid IDs appear at the start or after valid batch entries.
    // Covers:
    // - Existing range validation, including Web's upper-word overflow.
    // Expected: The new encoder throws the same RangeError details as the writer.
    test('preserves ID range errors.', () {
      // Arrange.
      final cases = <List<int>>[
        [-1],
        [1, 2, -1],
      ];
      if (_browser) cases.add([int.parse('18446744073709551616')]);
      for (final ids in cases) {
        // Act.
        final previous = _rangeError(() => _legacyEncode(ids));
        final current = _rangeError(() => encodeIdList(ids));
        // Assert.
        expect(current.invalidValue, previous.invalidValue);
        expect(current.name, previous.name);
        expect(current.start, previous.start);
        expect(current.end, previous.end);
      }
    });

    // Scenario: A malformed List reports a count outside the u32 wire range.
    // Covers:
    // - Count validation before allocation or access to any element.
    // Expected: Both invalid counts fail with the previous RangeError details.
    test('rejects invalid counts before allocating the payload.', () {
      // Arrange.
      for (final count in [-1, 4294967296]) {
        final ids = _InvalidCountIds(count);
        // Act.
        final previous = _rangeError(() => _legacyEncode(ids));
        final current = _rangeError(() => encodeIdList(ids));
        // Assert.
        expect(current.invalidValue, previous.invalidValue);
        expect(current.name, previous.name);
        expect(current.start, previous.start);
        expect(current.end, previous.end);
      }
    });
  });
}

Uint8List _legacyEncode(List<int> ids) {
  final writer = CindelWireWriter()..writeLength(ids.length);
  for (final id in ids) {
    writer.writeUint64(id);
  }
  return writer.finish();
}

RangeError _rangeError(void Function() action) {
  try {
    action();
  } on RangeError catch (error) {
    return error;
  }
  throw StateError('Expected a RangeError.');
}

final class _ObservedIds extends ListBase<int> {
  _ObservedIds(this.values);
  final List<int> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('fixed input');
  @override
  int operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('fixed input');
  @override
  List<int> toList({bool growable = true}) =>
      throw StateError('Redundant ID copy.');
}

final class _InvalidCountIds extends ListBase<int> {
  _InvalidCountIds(this.count);
  final int count;
  @override
  int get length => count;
  @override
  set length(int value) => throw UnsupportedError('fixed input');
  @override
  int operator [](int index) =>
      throw StateError('Read before count validation.');
  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('fixed input');
}
