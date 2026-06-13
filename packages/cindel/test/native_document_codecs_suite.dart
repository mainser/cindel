// ignore_for_file: cast_to_non_type, undefined_class, undefined_function
// ignore_for_file: undefined_identifier, uri_does_not_exist

import 'dart:convert';
import 'dart:ffi';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:cindel/src/native/bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel native document codecs', () {
    // Scenario: The reusable native byte scratch buffer receives values larger
    // than its current capacity.
    // Covers:
    // - `_ReusableNativeBytes.withUtf8String` resize branch.
    // - `_ReusableNativeBytes.withBytes` resize branch.
    // Expected: Callbacks receive the complete encoded bytes after resizing.
    test('resizes reusable native byte buffers for larger writes.', () {
      // Arrange.
      expect(CindelNativeBindings, isNotNull);
      final scratch = _newPrivate('_ReusableNativeBytes', [1]);
      final seen = <List<int>>[];

      try {
        // Act.
        _invokeMethod(scratch, 'withUtf8String', [
          'Ana',
          (Pointer<Uint8> pointer, int length) {
            seen.add(pointer.asTypedList(length).toList());
          },
        ]);
        _invokeMethod(scratch, 'withBytes', [
          [1, 2, 3, 4, 5],
          (Pointer<Uint8> pointer, int length) {
            seen.add(pointer.asTypedList(length).toList());
          },
        ]);
      } finally {
        _invokeMethod(scratch, 'free', const []);
      }

      // Assert.
      expect(seen, [
        utf8.encode('Ana'),
        [1, 2, 3, 4, 5],
      ]);
    });

    // Scenario: Native string-list writers receive non-ASCII list values.
    // Covers:
    // - `_ReusableNativeBytes.withCompactStringList` UTF-8 fallback branch.
    // - `_decodeNativeStringBytes` UTF-8 branch.
    // Expected: The encoded compact list decodes with the same values.
    test('round-trips compact string lists through UTF-8 fallback.', () {
      // Arrange.
      final scratch = _newPrivate('_ReusableNativeBytes', [1]);
      Uint8List? encoded;

      try {
        // Act.
        _invokeMethod(scratch, 'withCompactStringList', [
          ['Ana', 'Ña', ''],
          (Pointer<Uint8> pointer, int length) {
            encoded = Uint8List.fromList(pointer.asTypedList(length));
          },
        ]);
      } finally {
        _invokeMethod(scratch, 'free', const []);
      }

      // Assert.
      expect(_decodeStringList(encoded!), ['Ana', 'Ña', '']);
    });

    // Scenario: Legacy generated JSON string-list payloads include escapes,
    // null values, or invalid element types.
    // Covers:
    // - `_decodeNativeStringList` slow JSON fallback.
    // - JSON null-to-empty-string compatibility.
    // - Non-string JSON element rejection.
    // Expected: Supported legacy values decode, unsupported values return null.
    test('decodes and rejects legacy JSON string-list payloads.', () {
      // Act / Assert.
      expect(_decodeStringList(_bytes('["A\\n",null]')), ['A\n', '']);
      expect(_decodeStringList(_bytes('[1]')), isNull);
    });

    // Scenario: Native returns a versioned offset-table string-list payload.
    // Covers:
    // - `_decodeNativeStringList` versioned native list branch.
    // - `_readU32Le` count decoding.
    // Expected: The versioned payload decodes through the same string-list API.
    test('decodes versioned native offset-table string lists.', () {
      // Arrange.
      final bytes = Uint8List(27);
      _writeU32(bytes, 0, 0xffff_ffff);
      bytes[4] = 1;
      _writeU32(bytes, 5, 2);
      _writeU24(bytes, 9, 15);
      _writeU24(bytes, 12, 21);
      _writeU24(bytes, 15, 3);
      bytes.setAll(18, utf8.encode('Ana'));
      _writeU24(bytes, 21, 3);
      bytes.setAll(24, utf8.encode('Ben'));

      // Act / Assert.
      expect(_decodeStringList(bytes), ['Ana', 'Ben']);
    });

    // Scenario: Native returns malformed compact string-list payloads.
    // Covers:
    // - Truncated versioned offset tables.
    // - U24 value range guard.
    // Expected: Malformed reads return null and oversized U24 writes fail.
    test('rejects malformed native string-list payloads.', () {
      // Arrange.
      final truncatedVersioned = Uint8List(12);
      _writeU32(truncatedVersioned, 0, 0xffff_ffff);
      truncatedVersioned[4] = 1;
      _writeU32(truncatedVersioned, 5, 2);

      // Act / Assert.
      expect(_decodeStringList(truncatedVersioned), isNull);
      expect(
        () => _invokePrivateRaw('_writeU24Le', [Uint8List(3), 0, 0x0100_0000]),
        throwsStateError,
      );
    });
  });
}

List<String>? _decodeStringList(Uint8List bytes) {
  return _invokePrivate<List<String>?>('_decodeNativeStringList', [bytes]);
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

Object _newPrivate(String name, List<Object?> positionalArguments) {
  final classMirror =
      _bindingsLibrary().declarations[_privateSymbol(name)]! as ClassMirror;
  return classMirror
      .newInstance(const Symbol(''), positionalArguments)
      .reflectee;
}

Object? _invokeMethod(
  Object target,
  String name,
  List<Object?> positionalArguments,
) {
  return reflect(
    target,
  ).invoke(_privateSymbol(name), positionalArguments).reflectee;
}

T _invokePrivate<T>(String name, List<Object?> positionalArguments) {
  return _invokePrivateRaw(name, positionalArguments) as T;
}

Object? _invokePrivateRaw(String name, List<Object?> positionalArguments) {
  return _bindingsLibrary()
      .invoke(_privateSymbol(name), positionalArguments)
      .reflectee;
}

LibraryMirror _bindingsLibrary() {
  final library = currentMirrorSystem()
      .libraries[Uri.parse('package:cindel/src/native/bindings.dart')];
  if (library == null) {
    fail('Could not find package:cindel/src/native/bindings.dart.');
  }
  return library;
}

Symbol _privateSymbol(String name) =>
    MirrorSystem.getSymbol(name, _bindingsLibrary());

void _writeU24(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
}

void _writeU32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
  bytes[offset + 3] = (value >> 24) & 0xff;
}
