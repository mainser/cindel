import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:cindel/src/native/bindings.dart';

// This fixture exercises the same typed serialization hooks as generated code,
// without bringing the generator or its dev dependencies into a consumer app.
final class AppleRow {
  AppleRow(this.id, this.value);
  int id;
  String value;
}

final schema = CindelCollectionSchema<AppleRow>(
  name: 'apple_rows',
  dartName: 'AppleRow',
  idField: 'id',
  fields: const [
    CindelFieldSchema(
      name: 'id',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'value',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
  ],
  toDocument: (row) => {'id': row.id, 'value': row.value},
  fromDocument: (doc) => AppleRow(doc['id']! as int, doc['value']! as String),
  getId: (row) => row.id,
  setId: (row, id) => row.id = id,
  toBinaryDocument: (row) => cindelEncodeSchemaBinaryDocument(
    [row.value],
    [CindelBinaryFieldType.stringValue],
  ),
  fromBinaryDocument: (bytes) => AppleRow(
    0,
    CindelSchemaBinaryDocumentReader(bytes, staticSize: 3).readString(0, 0)!,
  ),
  writeNativeDocument: (writer, row) => writer.writeString(0, row.value),
  readNativeDocument: (reader, index) =>
      AppleRow(reader.readId(index), reader.readString(index, 0)!),
);

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  try {
    check(
      !Platform.environment.containsKey('CINDEL_NATIVE_LIBRARY'),
      'FFI override is forbidden',
    );
    // Construction resolves every binding eagerly, not just the ABI symbol.
    check(CindelNativeBindings().abiVersion == 39, 'Expected ABI 39');
    for (final backend in [
      CindelStorageBackend.mdbx,
      CindelStorageBackend.sqlite,
    ]) {
      final directory = await Directory.systemTemp.createTemp('cindel-apple-');
      final timer = Stopwatch()..start();
      var db = await Cindel.open(
        directory: directory.path,
        schemas: [schema],
        backend: backend,
      );
      try {
        final rows = db.typedCollection(schema);
        await db.writeTxn(
          () => rows.putAll([AppleRow(1, 'first'), AppleRow(2, 'second')]),
        );
        check((await rows.get(1))?.value == 'first', '$backend read');
        check(await rows.all().count() == 2, '$backend count');
        try {
          await db.writeTxn<void>(() async {
            await rows.put(AppleRow(3, 'rollback'));
            throw StateError('intentional rollback');
          });
        } on StateError catch (error) {
          if (error.message != 'intentional rollback') rethrow;
        }
        check(await rows.get(3) == null, '$backend rollback');
        await rows.put(AppleRow(1, 'updated'));
        await rows.delete(2);
        await db.close();
        db = await Cindel.open(
          directory: directory.path,
          schemas: [schema],
          backend: backend,
        );
        check(
          (await db.typedCollection(schema).get(1))?.value == 'updated',
          '$backend reopen',
        );
        check(
          await db.typedCollection(schema).get(2) == null,
          '$backend delete',
        );
        print(
          'CINDEL_APPLE_METRIC $backend ${timer.elapsedMicroseconds}us RSS=${ProcessInfo.currentRss}',
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    }
    print('CINDEL_APPLE_PASS ABI=39 MDBX SQLite CRUD rollback reopen all-FFI');
    exit(0);
  } catch (error, stack) {
    print('CINDEL_APPLE_FAIL $error\n$stack');
    exit(1);
  }
}
