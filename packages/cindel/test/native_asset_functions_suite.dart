// ignore_for_file: cast_to_non_type, undefined_class, undefined_function
// ignore_for_file: undefined_identifier, uri_does_not_exist

import 'dart:ffi';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'dart:mirrors';

import 'package:cindel/src/native/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel native asset functions', () {
    // Scenario: The executable is inside a macOS app bundle whose path
    // contains spaces.
    // Covers:
    // - Framework and dylib lookup relative to the executable.
    // Expected: Both candidates point into Contents/Frameworks and contain no
    // URL-encoded spaces.
    test(
      'resolves macOS frameworks from the executable, including spaces.',
      () {
        // Arrange.
        final executable = File(
          '${Directory.systemTemp.path}/Cindel App.app/Contents/MacOS/Runner',
        );
        // Act.
        final candidates = _invokePrivate<List<String>>(
          '_macOSFrameworkCandidates',
          [executable.path],
        );
        final frameworks = executable.parent.parent.uri.resolve('Frameworks/');
        // Assert.
        expect(candidates, [
          frameworks
              .resolve('CindelNative.framework/CindelNative')
              .toFilePath(),
          frameworks.resolve('libcindel_native.dylib').toFilePath(),
        ]);
        expect(candidates.any((path) => path.contains('%20')), isFalse);
      },
    );

    // Scenario: Native-asset functions are invoked directly with an
    // unsupported backend.
    // Covers:
    // - ABI 39 and native error buffer ownership through take/free calls.
    // Expected: The ABI matches, opening returns no handle, error bytes can
    // be consumed/freed and a second take is empty.
    test('executes ABI 39 error ownership through native assets.', () {
      // Arrange.
      final functions = reflect(_nativeAssetFunctions());
      // Act.
      final abi =
          functions.getField(const Symbol('abiVersion')).reflectee
              as int Function();
      // Assert.
      expect(abi(), 39);
      final directory = ':memory:'.toNativeUtf8();
      final status = calloc<Int32>();
      final length = calloc<Size>();
      try {
        final handle =
            functions.invoke(const Symbol('openWithBackend'), [
                  directory.cast<Uint8>(),
                  8,
                  999,
                  status,
                ]).reflectee
                as Pointer<Void>;
        expect(handle, nullptr);
        expect(status.value, lessThan(0));
        final take =
            functions.getField(const Symbol('takeError')).reflectee
                as Pointer<Uint8> Function(int, Pointer<Size>);
        final free =
            functions.getField(const Symbol('freeBuffer')).reflectee
                as void Function(Pointer<Uint8>, int);
        final bytes = take(status.value, length);
        try {
          expect(
            utf8.decode(bytes.asTypedList(length.value)),
            contains('backend'),
          );
        } finally {
          free(bytes, length.value);
        }
        expect(take(status.value, length), nullptr);
      } finally {
        calloc.free(directory);
        calloc.free(status);
        calloc.free(length);
      }
    });

    // Scenario: The native-assets implementation exposes every native symbol
    // through the same function contract used by the dynamic-library adapter.
    // Covers:
    // - Native asset getter tear-offs for engine, batch writer, document
    //   reader, query, transaction, and buffer-freeing functions.
    // - Wrapper method tear-offs for backend-aware open calls.
    // Expected: Every adapter member can be resolved without invoking native
    //   code or requiring a bundled DLL override.
    test('exposes native asset function members as callable tear-offs.', () {
      // Arrange.
      expect(CindelNativeBindings, isNotNull);
      final nativeAssets = _nativeAssetFunctions();
      final mirror = reflect(nativeAssets);

      // Act / Assert.
      for (final name in _nativeAssetFunctionMembers) {
        expect(
          mirror.getField(Symbol(name)).reflectee,
          isA<Function>(),
          reason: name,
        );
      }
    });

    // Scenario: The dynamic-library fallback searches for platform-specific
    // prebuilt binaries before falling back to native-assets symbols.
    // Covers:
    // - Platform-specific candidate filename selection.
    // - Workspace-relative cindel_flutter_libs candidate paths.
    // - Path separator normalization.
    // Expected: Supported platforms return candidates for the current ABI and
    //   helper path joins use the host separator.
    test('builds bundled library candidates for the current platform.', () {
      // Arrange.
      final expectedName = _expectedLibraryName();

      // Act.
      final candidates = _invokePrivate<List<String>>(
        '_candidateLibraryNames',
        const [],
      );
      final joined = _invokePrivate<String>('_joinPath', const [
        'base',
        'native/path',
      ]);

      // Assert.
      if (expectedName == null) {
        expect(candidates, isEmpty);
      } else {
        expect(candidates, isNotEmpty);
        expect(candidates.last, expectedName);
        expect(
          candidates.any((candidate) => candidate.endsWith(expectedName)),
          isTrue,
        );
      }
      expect(
        joined,
        'base${Platform.pathSeparator}native${Platform.pathSeparator}path',
      );
    });
  });
}

Object _nativeAssetFunctions() {
  final library = _bindingsLibrary();
  final classMirror =
      library.declarations[_privateSymbol('_NativeAssetCindelNativeFunctions')]
          as ClassMirror;
  return classMirror.newInstance(const Symbol(''), const []).reflectee;
}

T _invokePrivate<T>(String name, List<Object?> positionalArguments) {
  return _bindingsLibrary()
          .invoke(_privateSymbol(name), positionalArguments)
          .reflectee
      as T;
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

String? _expectedLibraryName() {
  return switch (Abi.current()) {
    Abi.androidArm ||
    Abi.androidArm64 ||
    Abi.androidIA32 ||
    Abi.androidX64 => 'libcindel_native.so',
    Abi.linuxX64 || Abi.linuxArm64 => 'libcindel_native.so',
    Abi.macosX64 || Abi.macosArm64 => 'libcindel_native.dylib',
    Abi.windowsX64 || Abi.windowsArm64 => 'cindel_native.dll',
    _ => null,
  };
}

const _nativeAssetFunctionMembers = [
  'abiVersion',
  'takeError',
  'nativeBatchWriterError',
  'nativeDocumentReaderError',
  'backupCommand',
  'cleanupOrphanLinks',
  'open',
  'openWithBackend',
  'openWithBackendAndSchemas',
  'close',
  'beginReadTransaction',
  'beginWriteTransaction',
  'commitTransaction',
  'rollbackTransaction',
  'put',
  'allocateId',
  'reserveIds',
  'registerSchemas',
  'registerMigratedSchemas',
  'putIndexed',
  'putManyIndexed',
  'putManyStored',
  'nativeBatchWriterNew',
  'nativeBatchWriterBeginDocument',
  'nativeBatchWriterWriteNull',
  'nativeBatchWriterWriteBool',
  'nativeBatchWriterWriteInt',
  'nativeBatchWriterWriteDouble',
  'nativeBatchWriterWriteBytes',
  'nativeBatchWriterWriteListBytes',
  'nativeBatchWriterWriteObjectBytes',
  'nativeBatchWriterBeginList',
  'nativeBatchWriterEndList',
  'nativeBatchWriterBeginObject',
  'nativeBatchWriterEndObject',
  'nativeBatchWriterSaveDocument',
  'nativeBatchWriterEndDocument',
  'nativeBatchWriterFinish',
  'nativeBatchWriterFinishWithOptions',
  'nativeBatchWriterAbort',
  'nativeDocumentReaderNew',
  'nativeDocumentReaderNewFromQueryPlan',
  'nativeDocumentReaderLen',
  'nativeDocumentReaderIsStreaming',
  'nativeDocumentReaderNext',
  'nativeDocumentReaderIsPresent',
  'nativeDocumentReaderReadId',
  'nativeDocumentReaderReadIdValue',
  'nativeDocumentReaderReadCurrentIdValue',
  'nativeDocumentReaderReadBool',
  'nativeDocumentReaderReadBoolValue',
  'nativeDocumentReaderReadCurrentBoolValue',
  'nativeDocumentReaderReadInt',
  'nativeDocumentReaderReadIntValue',
  'nativeDocumentReaderReadCurrentIntValue',
  'nativeDocumentReaderReadDouble',
  'nativeDocumentReaderReadDoubleValue',
  'nativeDocumentReaderReadCurrentDoubleValue',
  'nativeDocumentReaderReadBytes',
  'nativeDocumentReaderReadCurrentBytes',
  'nativeDocumentReaderReadString',
  'nativeDocumentReaderReadStringValue',
  'nativeDocumentReaderReadCurrentStringValue',
  'nativeDocumentReaderReadListBytes',
  'nativeDocumentReaderReadCurrentListBytes',
  'nativeDocumentReaderReadList',
  'nativeDocumentReaderReadCurrentList',
  'nativeDocumentReaderReadObject',
  'nativeDocumentReaderReadCurrentObject',
  'nativeDocumentReaderFree',
  'get',
  'getStored',
  'getMany',
  'getManyStored',
  'documentIds',
  'documentIdsPage',
  'delete',
  'deleteMany',
  'deleteManyNativeDocuments',
  'collectionRevision',
  'takeChanges',
  'discardChanges',
  'schemaVersion',
  'migrationVersion',
  'setMigrationVersion',
  'compact',
  'queryIndexEqual',
  'queryIndexRange',
  'queryFilter',
  'queryProject',
  'queryAggregate',
  'queryPlanIds',
  'queryPlanDocuments',
  'queryPlanCount',
  'queryPlanProject',
  'queryPlanAggregate',
  'queryPlanDelete',
  'queryPlanUpdate',
  'freeBuffer',
];
