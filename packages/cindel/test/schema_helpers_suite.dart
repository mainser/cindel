import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

void main() {
  group('native schema helpers', () {
    // Scenario: A generated native serializer writes List<String> values
    // through writers with and without the optional string-list fast path.
    // Covers:
    // - [cindelWriteNativeStringList] fallback beginList/writeString/endList.
    // - [CindelNativeStringListDocumentWriter.writeStringList] fast path.
    // Expected: String lists are written through the fastest available writer
    //   contract without changing the element order.
    test('write string lists through fast and fallback writer paths.', () {
      final fallbackWriter = _RecordingNativeWriter();

      cindelWriteNativeStringList(fallbackWriter, 2, ['a', 'b']);

      final fallbackListWriter = fallbackWriter.listWriters.single;
      expect(fallbackWriter.events, ['beginList:2:2', 'endList']);
      expect(fallbackListWriter.events, ['writeString:0:a', 'writeString:1:b']);

      final fastWriter = _StringListNativeWriter();

      cindelWriteNativeStringList(fastWriter, 3, ['x', 'y']);

      expect(fastWriter.stringLists, {
        3: ['x', 'y'],
      });
      expect(fastWriter.events, ['writeStringList:3']);
    });

    // Scenario: A generated native serializer writes embedded objects through
    // a writer that only supports map-based object APIs.
    // Covers:
    // - [cindelWriteNativeObject] fallback to [writeObject].
    // - [cindelWriteNativeObjectList] fallback to [writeObjectList].
    // - Null embedded list elements in fallback mode.
    // Expected: Objects are converted to maps only when the native object
    //   writer fast path is unavailable.
    test('write embedded objects through fallback writer paths.', () {
      final writer = _RecordingNativeWriter();

      cindelWriteNativeObject<String>(
        writer,
        1,
        ['name'],
        'Ana',
        _writeName,
        _toNameDocument,
      );
      cindelWriteNativeObjectList<String>(
        writer,
        2,
        ['name'],
        ['Ana', null, 'Luis'],
        _writeName,
        _toNameDocument,
      );

      expect(writer.objects[1], {'name': 'Ana'});
      expect(writer.objectLists[2], [
        {'name': 'Ana'},
        null,
        {'name': 'Luis'},
      ]);
    });

    // Scenario: A generated native serializer writes embedded objects through
    // an object-capable parent writer whose list child is map-only.
    // Covers:
    // - [CindelNativeObjectDocumentWriter.beginObject] and [endObject].
    // - Object-list fast path setup through [beginList].
    // - Object-list fallback when the child list writer is not object-capable.
    // Expected: Single embedded objects use the native object fast path, while
    //   list elements fall back to map writes only for the list child.
    test('write embedded objects through native object writer paths.', () {
      final writer = _ObjectNativeWriter(listWriterSupportsObjects: false);

      cindelWriteNativeObject<String>(
        writer,
        4,
        ['name'],
        'Ana',
        _writeName,
        _toNameDocument,
      );
      cindelWriteNativeObjectList<String>(
        writer,
        5,
        ['name'],
        ['Ana', null, 'Luis'],
        _writeName,
        _toNameDocument,
      );

      expect(writer.events, [
        'beginObject:4:name',
        'endObject',
        'beginList:5:3',
        'endList',
      ]);
      expect(writer.objectWriters.single.events, ['writeString:0:Ana']);
      expect(writer.listWriters.single.events, [
        'writeObject:0',
        'writeNull:1',
        'writeObject:2',
      ]);
      expect(writer.listWriters.single.objects[0], {'name': 'Ana'});
      expect(writer.listWriters.single.objects[2], {'name': 'Luis'});
    });

    // Scenario: A generated native serializer writes an embedded object list
    // through an object-capable list writer.
    // Covers:
    // - Object-list child writer detection.
    // - Per-element [beginObject] and [endObject] calls.
    // - Null list elements written with [writeNull].
    // Expected: Non-null elements use native object writers and null elements
    //   stay represented as nulls in the list.
    test('write embedded object lists with object-capable list writers.', () {
      final writer = _ObjectNativeWriter(listWriterSupportsObjects: true);

      cindelWriteNativeObjectList<String>(
        writer,
        6,
        ['name'],
        ['Ana', null, 'Luis'],
        _writeName,
        _toNameDocument,
      );

      final listWriter = writer.listWriters.single as _ObjectNativeWriter;
      expect(writer.events, ['beginList:6:3', 'endList']);
      expect(listWriter.events, [
        'beginObject:0:name',
        'endObject',
        'writeNull:1',
        'beginObject:2:name',
        'endObject',
      ]);
      expect(
        listWriter.objectWriters.map((objectWriter) => objectWriter.events),
        [
          ['writeString:0:Ana'],
          ['writeString:0:Luis'],
        ],
      );
    });

    // Scenario: A generated native deserializer reads embedded objects from a
    // reader that only exposes decoded map/object-list APIs.
    // Covers:
    // - [cindelReadNativeObject] fallback to [readObject].
    // - [cindelReadNativeObjectList] fallback to [readObjectList].
    // - Null embedded objects and null embedded object lists.
    // Expected: Map-based reader results are converted through fromDocument
    //   only when values are present.
    test('read embedded objects through fallback reader paths.', () {
      final reader = _RecordingNativeReader()
        ..objects[_key(0, 1)] = {'name': 'Ana'}
        ..objects[_key(0, 2)] = null
        ..objectLists[_key(0, 3)] = [
          {'name': 'Ana'},
          null,
          {'name': 'Luis'},
        ]
        ..objectLists[_key(0, 4)] = null;

      expect(
        cindelReadNativeObject<String>(
          reader,
          0,
          1,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        'Ana',
      );
      expect(
        cindelReadNativeObject<String>(
          reader,
          0,
          2,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        isNull,
      );
      expect(
        cindelReadNativeObjectList<String>(
          reader,
          0,
          3,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        ['Ana', null, 'Luis'],
      );
      expect(
        cindelReadNativeObjectList<String>(
          reader,
          0,
          4,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        isNull,
      );
    });

    // Scenario: A generated native deserializer reads embedded objects from an
    // object-capable reader and releases child readers after use.
    // Covers:
    // - [CindelNativeObjectDocumentReader.readObjectReader].
    // - Object-list reads with object-capable and map-only child readers.
    // - Null child object readers and null list readers.
    // - Release calls in [finally] blocks.
    // Expected: Present child readers hydrate through readNative and every
    //   acquired child/list reader is released.
    test('read embedded objects through native object reader paths.', () {
      final childReader = _RecordingNativeReader()..strings[_key(0, 0)] = 'Ana';
      final nullObjectReader = _ObjectNativeReader()
        ..objectReaders[_key(0, 1)] = null;
      final objectReader = _ObjectNativeReader()
        ..objectReaders[_key(0, 1)] = childReader;

      expect(
        cindelReadNativeObject<String>(
          objectReader,
          0,
          1,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        'Ana',
      );
      expect(childReader.released, isTrue);
      expect(
        cindelReadNativeObject<String>(
          nullObjectReader,
          0,
          1,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        isNull,
      );

      final fallbackListReader = _RecordingNativeReader(length: 3)
        ..objects[_key(0, 0)] = {'name': 'Ana'}
        ..objects[_key(0, 1)] = null
        ..objects[_key(0, 2)] = {'name': 'Luis'};
      final fallbackListParent = _ObjectNativeReader()
        ..lists[_key(0, 2)] = fallbackListReader
        ..lists[_key(0, 3)] = null;

      expect(
        cindelReadNativeObjectList<String>(
          fallbackListParent,
          0,
          2,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        ['Ana', null, 'Luis'],
      );
      expect(fallbackListReader.released, isTrue);
      expect(
        cindelReadNativeObjectList<String>(
          fallbackListParent,
          0,
          3,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        isNull,
      );

      final firstChild = _RecordingNativeReader()..strings[_key(0, 0)] = 'Ana';
      final secondChild = _RecordingNativeReader()
        ..strings[_key(0, 0)] = 'Luis';
      final nativeListReader = _ObjectNativeReader(length: 3)
        ..objectReaders[_key(0, 0)] = firstChild
        ..objectReaders[_key(0, 1)] = null
        ..objectReaders[_key(0, 2)] = secondChild;
      final nativeListParent = _ObjectNativeReader()
        ..lists[_key(0, 2)] = nativeListReader;

      expect(
        cindelReadNativeObjectList<String>(
          nativeListParent,
          0,
          2,
          ['name'],
          _readName,
          _fromNameDocument,
        ),
        ['Ana', null, 'Luis'],
      );
      expect(firstChild.released, isTrue);
      expect(secondChild.released, isTrue);
      expect(nativeListReader.released, isTrue);
    });
  });
}

void _writeName(CindelNativeDocumentWriter writer, String value) {
  writer.writeString(0, value);
}

String _readName(CindelNativeDocumentReader reader, int documentIndex) {
  return reader.readString(documentIndex, 0)!;
}

Map<String, Object?> _toNameDocument(String value) => {'name': value};

String _fromNameDocument(Map<String, Object?> document) {
  return document['name']! as String;
}

String _key(int documentIndex, int fieldIndex) => '$documentIndex:$fieldIndex';

class _RecordingNativeWriter implements CindelNativeDocumentWriter {
  _RecordingNativeWriter({this.length = 1});

  final int length;
  final events = <String>[];
  final objects = <int, Map<String, Object?>>{};
  final objectLists = <int, List<Map<String, Object?>?>>{};
  final listWriters = <_RecordingNativeWriter>[];

  @override
  CindelNativeDocumentWriter beginList(int fieldIndex, int length) {
    events.add('beginList:$fieldIndex:$length');
    final writer = _RecordingNativeWriter(length: length);
    listWriters.add(writer);
    return writer;
  }

  @override
  void endList(CindelNativeDocumentWriter listWriter) {
    events.add('endList');
  }

  @override
  void writeBool(int fieldIndex, bool value) {
    events.add('writeBool:$fieldIndex:$value');
  }

  @override
  void writeDouble(int fieldIndex, double value) {
    events.add('writeDouble:$fieldIndex:$value');
  }

  @override
  void writeInt(int fieldIndex, int value) {
    events.add('writeInt:$fieldIndex:$value');
  }

  @override
  void writeNull(int fieldIndex) {
    events.add('writeNull:$fieldIndex');
  }

  @override
  void writeObject(int fieldIndex, Map<String, Object?> value) {
    events.add('writeObject:$fieldIndex');
    objects[fieldIndex] = value;
  }

  @override
  void writeObjectList(int fieldIndex, List<Map<String, Object?>?> value) {
    events.add('writeObjectList:$fieldIndex');
    objectLists[fieldIndex] = value;
  }

  @override
  void writeString(int fieldIndex, String value) {
    events.add('writeString:$fieldIndex:$value');
  }
}

class _StringListNativeWriter extends _RecordingNativeWriter
    implements CindelNativeStringListDocumentWriter {
  final stringLists = <int, List<String>>{};

  @override
  void writeStringList(int fieldIndex, List<String> value) {
    events.add('writeStringList:$fieldIndex');
    stringLists[fieldIndex] = value;
  }
}

class _ObjectNativeWriter extends _RecordingNativeWriter
    implements CindelNativeObjectDocumentWriter {
  _ObjectNativeWriter({super.length, required this.listWriterSupportsObjects});

  final bool listWriterSupportsObjects;
  final objectWriters = <_RecordingNativeWriter>[];

  @override
  CindelNativeDocumentWriter beginList(int fieldIndex, int length) {
    events.add('beginList:$fieldIndex:$length');
    final writer = listWriterSupportsObjects
        ? _ObjectNativeWriter(
            length: length,
            listWriterSupportsObjects: listWriterSupportsObjects,
          )
        : _RecordingNativeWriter(length: length);
    listWriters.add(writer);
    return writer;
  }

  @override
  CindelNativeDocumentWriter beginObject(
    int fieldIndex,
    List<String> fieldNames,
  ) {
    events.add('beginObject:$fieldIndex:${fieldNames.join(',')}');
    final writer = _RecordingNativeWriter();
    objectWriters.add(writer);
    return writer;
  }

  @override
  void endObject(CindelNativeDocumentWriter objectWriter) {
    events.add('endObject');
  }
}

class _RecordingNativeReader implements CindelNativeDocumentReader {
  _RecordingNativeReader({this.length = 1});

  @override
  final int length;

  bool released = false;
  final strings = <String, String?>{};
  final objects = <String, Map<String, Object?>?>{};
  final objectLists = <String, List<Map<String, Object?>?>?>{};
  final lists = <String, CindelNativeDocumentReader?>{};

  @override
  bool isPresent(int documentIndex) => true;

  @override
  CindelNativeDocumentReader? readList(int documentIndex, int fieldIndex) {
    return lists[_key(documentIndex, fieldIndex)];
  }

  @override
  Map<String, Object?>? readObject(int documentIndex, int fieldIndex) {
    return objects[_key(documentIndex, fieldIndex)];
  }

  @override
  List<Map<String, Object?>?>? readObjectList(
    int documentIndex,
    int fieldIndex,
  ) {
    return objectLists[_key(documentIndex, fieldIndex)];
  }

  @override
  String? readString(int documentIndex, int fieldIndex) {
    return strings[_key(documentIndex, fieldIndex)];
  }

  @override
  void release() {
    released = true;
  }

  @override
  bool? readBool(int documentIndex, int fieldIndex) => null;

  @override
  double? readDouble(int documentIndex, int fieldIndex) => null;

  @override
  int readId(int documentIndex) => documentIndex;

  @override
  int? readInt(int documentIndex, int fieldIndex) => null;

  @override
  List<String>? readStringList(int documentIndex, int fieldIndex) => null;
}

class _ObjectNativeReader extends _RecordingNativeReader
    implements CindelNativeObjectDocumentReader {
  _ObjectNativeReader({super.length});

  final objectReaders = <String, CindelNativeDocumentReader?>{};

  @override
  CindelNativeDocumentReader? readObjectReader(
    int documentIndex,
    int fieldIndex,
    List<String> fieldNames,
  ) {
    return objectReaders[_key(documentIndex, fieldIndex)];
  }
}
