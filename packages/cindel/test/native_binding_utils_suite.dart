// ignore_for_file: cast_to_non_type, undefined_class, undefined_function
// ignore_for_file: undefined_identifier, uri_does_not_exist

import 'dart:ffi';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:cindel/src/native/bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel native binding utils', () {
    // Scenario: Optional native byte arguments pass a real null pointer when
    // the Dart value is absent.
    // Covers:
    // - `_withNullableNativeBytes` null branch.
    // Expected: The native callback receives nullptr and length zero.
    test('passes nullptr for absent optional byte buffers.', () {
      // Arrange.
      expect(CindelNativeBindings, isNotNull);

      // Act.
      final result = _invokePrivate<int>('_withNullableNativeBytes', [
        null,
        (Pointer<Uint8> pointer, int length) {
          expect(pointer.address, 0);
          expect(length, 0);
          return 42;
        },
      ]);

      // Assert.
      expect(result, 42);
    });

    // Scenario: Native id-list calls return malformed wire bytes.
    // Covers:
    // - `_queryIds` invalid binary payload handling.
    // - Native result buffer freeing before decode errors are reported.
    // Expected: Invalid native id-list payloads fail as StateError.
    test('rejects malformed native id lists.', () {
      // Arrange.
      var freed = false;

      int action(Pointer<Pointer<Uint8>> outPointer, Pointer<Size> outLength) {
        final pointer = calloc<Uint8>(3);
        pointer.asTypedList(3).setAll(0, const [1, 2, 3]);
        outPointer.value = pointer;
        outLength.value = 3;
        return 0;
      }

      void freeBuffer(Pointer<Uint8> pointer, int length) {
        expect(length, 3);
        freed = true;
        calloc.free(pointer);
      }

      // Act / Assert.
      expect(
        () => _invokePrivate<List<int>>('_queryIds', [
          action,
          freeBuffer,
          'query ids',
        ]),
        throwsStateError,
      );
      expect(freed, isTrue);
    });

    // Scenario: Binding guard helpers reject invalid native-boundary values.
    // Covers:
    // - `_checkId` negative id branch.
    // - `_checkStatus` non-zero status branch.
    // Expected: Invalid ids and failing status codes are surfaced immediately.
    test('rejects invalid ids and failing native statuses.', () {
      // Act / Assert.
      expect(() => _invokePrivateRaw('_checkId', [-1]), throwsArgumentError);
      expect(
        () => _invokePrivateRaw('_checkStatus', [1, 'test operation']),
        throwsStateError,
      );
    });
  });
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
