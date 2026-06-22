import 'dart:async';
import 'dart:io';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

void main() {
  group('Cindel links and backlinks', () {
    // Scenario: Forward links and backlinks are used through manually wired
    // schemas that mirror generated output.
    // Covers:
    // - To-many and to-one forward link save/load.
    // - Read-only backlink load from the forward relation name.
    // - Relation persistence after reopening a database directory.
    // - Validation for missing link targets and backlink writes.
    // Expected: Relations round-trip through both storage backends and failed
    // saves leave the previously persisted relations intact.
    test('saves, loads, reopens, and validates typed relations.', () async {
      // Arrange.
      final directory = await Directory.systemTemp.createTemp('cindel_links_');
      late CindelDatabase database;
      database = await openTestDatabase(
        directory: directory.path,
        schemas: [ArtistSchema, SongSchema, PlaylistSchema],
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      final artist = Artist()
        ..dbId = 1
        ..name = 'Ana';
      final song = Song()
        ..dbId = 10
        ..title = 'Ship It';
      final playlist = Playlist()
        ..dbId = 20
        ..name = 'Release';

      await database.writeTxn<void>(() async {
        await database.typedCollection(ArtistSchema).put(artist);
        await database.typedCollection(SongSchema).put(song);
        await database.typedCollection(PlaylistSchema).put(playlist);

        song.featuredArtists.add(artist);
        song.primaryArtist.value = artist;
        playlist.songs.add(song);
        await song.featuredArtists.save();
        await song.primaryArtist.save();
        await playlist.songs.save();
      });

      // Act.
      final storedSong = await database.typedCollection(SongSchema).get(10);
      await storedSong!.featuredArtists.load();
      await storedSong.primaryArtist.load();
      expect(storedSong.featuredArtists.single.name, 'Ana');
      expect(storedSong.primaryArtist.value!.name, 'Ana');

      await database.close();
      database = await openTestDatabase(
        directory: directory.path,
        schemas: [ArtistSchema, SongSchema, PlaylistSchema],
      );

      final reopenedSong = await database.typedCollection(SongSchema).get(10);
      await reopenedSong!.featuredArtists.load();
      await reopenedSong.primaryArtist.load();
      expect(reopenedSong.featuredArtists.single.name, 'Ana');
      expect(reopenedSong.primaryArtist.value!.name, 'Ana');
      reopenedSong.primaryArtist.value = null;
      await reopenedSong.primaryArtist.save();
      reopenedSong.primaryArtist.value = artist;
      await reopenedSong.primaryArtist.reset();
      await reopenedSong.primaryArtist.load();
      expect(reopenedSong.primaryArtist.value, isNull);

      final storedArtist = await database.typedCollection(ArtistSchema).get(1);
      await storedArtist!.songs.load();
      expect(storedArtist.songs.single.title, 'Ship It');

      final missingTarget = Song()
        ..dbId = 11
        ..title = 'Broken';
      await database.typedCollection(SongSchema).put(missingTarget);
      missingTarget.featuredArtists.add(
        Artist()
          ..dbId = 404
          ..name = 'Missing',
      );
      await expectLater(missingTarget.featuredArtists.save(), throwsStateError);

      // Assert.
      await reopenedSong.featuredArtists.load();
      expect(reopenedSong.featuredArtists.single.dbId, 1);
      await expectLater(storedArtist.songs.save(), throwsStateError);
    });

    // Scenario: A forward link is saved outside a typed collection put.
    // Covers:
    // - Native source-collection revision bumps from relation saves.
    // - Database-level change-set watcher notifications for link writes.
    // Expected: Watchers see the source object id as changed.
    test('notifies source collection watchers after link saves.', () async {
      // Arrange.
      final database = await openTestDatabaseInMemory(
        schemas: [ArtistSchema, SongSchema],
      );
      addTearDown(database.close);
      final events = <CindelChangeSet>[];
      final subscription = database
          .watchCollectionChanges(
            SongSchema.name,
            pollInterval: const Duration(milliseconds: 5),
            fireImmediately: false,
          )
          .listen(events.add);
      addTearDown(subscription.cancel);

      final artist = Artist()
        ..dbId = 1
        ..name = 'Ana';
      final song = Song()
        ..dbId = 10
        ..title = 'Ship It';
      await database.writeTxn<void>(() async {
        await database.typedCollection(ArtistSchema).put(artist);
        await database.typedCollection(SongSchema).put(song);
      });

      // Act.
      await Future<void>.delayed(Duration.zero);
      song.featuredArtists.add(artist);
      await song.featuredArtists.save();
      await _waitUntil(() => events.isNotEmpty);

      // Assert.
      expect(events.last.collection, SongSchema.name);
      expect(events.last.documentIds, contains(10));
    });

    // Scenario: Link containers are manipulated before a generated schema binds
    // them to a database object.
    // Covers:
    // - Unbound load/save diagnostics.
    // - In-memory to-one reset.
    // - To-many identity de-duplication, removal, and reset.
    // Expected: Local container behavior is deterministic without touching
    // storage, and database operations still require generated binding.
    test('handles unbound and in-memory container operations.', () async {
      // Arrange.
      final link = CindelLink<Artist>();
      final links = CindelLinks<Artist>();
      final artist = Artist()
        ..dbId = 1
        ..name = 'Ana';
      final other = Artist()
        ..dbId = 2
        ..name = 'Ben';

      // Act / Assert.
      expect(link.value, isNull);
      link.value = artist;
      expect(link.value, same(artist));
      await link.reset();
      expect(link.value, isNull);
      await expectLater(link.load(), throwsStateError);
      expect(() => link.save(), throwsStateError);

      expect(links.add(artist), isTrue);
      expect(links.add(artist), isFalse);
      expect(links.add(other), isTrue);
      expect(links.toList(), [artist, other]);
      expect(links.remove(artist), isTrue);
      expect(links.toList(), [other]);
      await links.reset();
      expect(links, isEmpty);
      await expectLater(links.load(), throwsStateError);
      expect(() => links.save(), throwsStateError);
    });
  });
}

final ArtistSchema = CindelCollectionSchema<Artist>(
  name: 'artists',
  dartName: 'Artist',
  idField: 'dbId',
  fields: const [
    CindelFieldSchema(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'name',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
  ],
  links: const [
    CindelLinkSchema(
      name: 'songs',
      dartName: 'songs',
      targetCollection: 'songs',
      isToMany: true,
      isBacklink: true,
      backlinkTo: 'featuredArtists',
    ),
  ],
  toDocument: (object) => {'dbId': object.dbId, 'name': object.name},
  fromDocument: (document) => Artist()
    ..dbId = document['dbId']! as int
    ..name = document['name']! as String,
  toBinaryDocument: (object) => cindelEncodeSchemaBinaryDocument(
    [object.name],
    [CindelBinaryFieldType.stringValue],
  ),
  fromBinaryDocument: (bytes) {
    final document = cindelDecodeSchemaBinaryDocument(bytes, [
      CindelBinaryFieldType.stringValue,
    ]);
    return Artist()..name = document[0]! as String;
  },
  writeNativeDocument: (writer, object) => writer.writeString(0, object.name),
  readNativeDocument: (reader, index) => Artist()
    ..dbId = reader.readId(index)
    ..name = reader.readString(index, 0)!,
  getId: (object) => object.dbId,
  setId: (object, id) => object.dbId = id,
  bindLinks: _bindArtistLinks,
);

final SongSchema = CindelCollectionSchema<Song>(
  name: 'songs',
  dartName: 'Song',
  idField: 'dbId',
  fields: const [
    CindelFieldSchema(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'title',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
  ],
  links: const [
    CindelLinkSchema(
      name: 'featuredArtists',
      dartName: 'featuredArtists',
      targetCollection: 'artists',
      isToMany: true,
      isBacklink: false,
    ),
    CindelLinkSchema(
      name: 'primaryArtist',
      dartName: 'primaryArtist',
      targetCollection: 'artists',
      isToMany: false,
      isBacklink: false,
    ),
  ],
  toDocument: (object) => {'dbId': object.dbId, 'title': object.title},
  fromDocument: (document) => Song()
    ..dbId = document['dbId']! as int
    ..title = document['title']! as String,
  toBinaryDocument: (object) => cindelEncodeSchemaBinaryDocument(
    [object.title],
    [CindelBinaryFieldType.stringValue],
  ),
  fromBinaryDocument: (bytes) {
    final document = cindelDecodeSchemaBinaryDocument(bytes, [
      CindelBinaryFieldType.stringValue,
    ]);
    return Song()..title = document[0]! as String;
  },
  writeNativeDocument: (writer, object) => writer.writeString(0, object.title),
  readNativeDocument: (reader, index) => Song()
    ..dbId = reader.readId(index)
    ..title = reader.readString(index, 0)!,
  getId: (object) => object.dbId,
  setId: (object, id) => object.dbId = id,
  bindLinks: _bindSongLinks,
);

final PlaylistSchema = CindelCollectionSchema<Playlist>(
  name: 'playlists',
  dartName: 'Playlist',
  idField: 'dbId',
  fields: const [
    CindelFieldSchema(
      name: 'dbId',
      dartType: 'int',
      binaryType: 'int',
      isId: true,
      isIndexed: false,
    ),
    CindelFieldSchema(
      name: 'name',
      dartType: 'String',
      binaryType: 'string',
      isId: false,
      isIndexed: false,
    ),
  ],
  links: const [
    CindelLinkSchema(
      name: 'songs',
      dartName: 'songs',
      targetCollection: 'songs',
      isToMany: true,
      isBacklink: false,
    ),
  ],
  toDocument: (object) => {'dbId': object.dbId, 'name': object.name},
  fromDocument: (document) => Playlist()
    ..dbId = document['dbId']! as int
    ..name = document['name']! as String,
  toBinaryDocument: (object) => cindelEncodeSchemaBinaryDocument(
    [object.name],
    [CindelBinaryFieldType.stringValue],
  ),
  fromBinaryDocument: (bytes) {
    final document = cindelDecodeSchemaBinaryDocument(bytes, [
      CindelBinaryFieldType.stringValue,
    ]);
    return Playlist()..name = document[0]! as String;
  },
  writeNativeDocument: (writer, object) => writer.writeString(0, object.name),
  readNativeDocument: (reader, index) => Playlist()
    ..dbId = reader.readId(index)
    ..name = reader.readString(index, 0)!,
  getId: (object) => object.dbId,
  setId: (object, id) => object.dbId = id,
  bindLinks: _bindPlaylistLinks,
);

final class Artist {
  int dbId = autoIncrement;
  late String name;
  final songs = CindelLinks<Song>();
}

final class Song {
  int dbId = autoIncrement;
  late String title;
  final featuredArtists = CindelLinks<Artist>();
  final primaryArtist = CindelLink<Artist>();
}

final class Playlist {
  int dbId = autoIncrement;
  late String name;
  final songs = CindelLinks<Song>();
}

void _bindArtistLinks(
  Object database,
  CindelCollectionSchema<Artist> schema,
  Artist object,
) {
  object.songs.bind(
    database as CindelDatabase,
    schema as dynamic,
    object,
    _link(schema, 'songs'),
  );
}

void _bindSongLinks(
  Object database,
  CindelCollectionSchema<Song> schema,
  Song object,
) {
  final cindelDatabase = database as CindelDatabase;
  object.featuredArtists.bind(
    cindelDatabase,
    schema as dynamic,
    object,
    _link(schema, 'featuredArtists'),
  );
  object.primaryArtist.bind(
    cindelDatabase,
    schema as dynamic,
    object,
    _link(schema, 'primaryArtist'),
  );
}

void _bindPlaylistLinks(
  Object database,
  CindelCollectionSchema<Playlist> schema,
  Playlist object,
) {
  object.songs.bind(
    database as CindelDatabase,
    schema as dynamic,
    object,
    _link(schema, 'songs'),
  );
}

CindelLinkSchema _link(dynamic schema, String name) {
  return schema.links.singleWhere((link) => link.name == name);
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for watcher event.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
