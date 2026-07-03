# Relationships

Cindel supports typed relationships between root collections. Use
`CindelLink<T>` for a to-one relationship, `CindelLinks<T>` for a to-many
relationship, and `@Backlink(to: ...)` for a read-only inverse relationship.

Relationships connect persisted objects by id. The related objects must be
stored first, and the relationship must be saved explicitly.

## Model Example

The examples in this page use artists and songs:

```dart
import 'package:cindel/cindel.dart';

part 'music.g.dart';

@Collection(name: 'artists')
class Artist {
  Id dbId = autoIncrement;

  late String name;

  @Backlink(to: 'featuredArtists')
  final songs = CindelLinks<Song>();
}

@Collection(name: 'songs')
class Song {
  Id dbId = autoIncrement;

  late String title;

  final featuredArtists = CindelLinks<Artist>();

  final primaryArtist = CindelLink<Artist>();
}
```

This model defines:

- `Song.primaryArtist`: a to-one relationship from one song to one artist.
- `Song.featuredArtists`: a to-many relationship from one song to many artists.
- `Artist.songs`: a read-only backlink that loads songs whose
  `featuredArtists` relationship contains that artist.

Link containers must be `final` fields. The target type must be another root
Cindel collection. Embedded objects cannot be relationship targets.

## `CindelLink`

`CindelLink<T>` represents a to-one relationship.

```dart
@Collection(name: 'songs')
class Song {
  Id dbId = autoIncrement;

  late String title;

  final primaryArtist = CindelLink<Artist>();
}
```

Use the `value` property to set or read the in-memory linked object:

```dart
song.primaryArtist.value = artist;

final primary = song.primaryArtist.value;
```

Setting `value` changes the in-memory relationship. Call `save()` to persist
that relationship:

```dart
song.primaryArtist.value = artist;
await song.primaryArtist.save();
```

Set `value` to `null` and save when the to-one relationship should be cleared:

```dart
song.primaryArtist.value = null;
await song.primaryArtist.save();
```

Load the stored linked object with `load()`:

```dart
final song = await db.songs.get(songId);

await song!.primaryArtist.load();

final artist = song.primaryArtist.value;
```

`CindelLink<T>` also supports `reset()`, which clears the in-memory value
without deleting the persisted relationship:

```dart
await song.primaryArtist.reset();
```

Use `reset()` when you want to discard currently loaded relation state and load
it again later.

## `CindelLinks`

`CindelLinks<T>` represents a to-many relationship.

```dart
@Collection(name: 'songs')
class Song {
  Id dbId = autoIncrement;

  late String title;

  final featuredArtists = CindelLinks<Artist>();
}
```

Add objects to the in-memory set with `add`:

```dart
song.featuredArtists.add(artist);
```

Remove objects from the in-memory set with `remove`:

```dart
song.featuredArtists.remove(artist);
```

`CindelLinks<T>` is iterable, so loaded values can be used like a normal
collection:

```dart
for (final artist in song.featuredArtists) {
  print(artist.name);
}
```

Call `save()` to persist the current set of linked objects:

```dart
song.featuredArtists.add(artist);
await song.featuredArtists.save();
```

Load the stored linked objects with `load()`:

```dart
final song = await db.songs.get(songId);

await song!.featuredArtists.load();

final artists = song.featuredArtists.toList();
```

`CindelLinks<T>` also supports `reset()`, which clears the in-memory set
without deleting the persisted relationship:

```dart
await song.featuredArtists.reset();
```

## Backlinks

A backlink is a read-only inverse relationship. It lets one collection load
objects that point to it through a forward link.

```dart
@Collection(name: 'artists')
class Artist {
  Id dbId = autoIncrement;

  late String name;

  @Backlink(to: 'featuredArtists')
  final songs = CindelLinks<Song>();
}
```

The `to` value must be the Dart field name of the forward link on the linked
collection. In the example above, `Artist.songs` points to
`Song.featuredArtists`.

This is the forward link:

```dart
@Collection(name: 'songs')
class Song {
  Id dbId = autoIncrement;

  late String title;

  final featuredArtists = CindelLinks<Artist>();
}
```

Load a backlink the same way you load a normal to-many relationship:

```dart
final artist = await db.artists.get(artistId);

await artist!.songs.load();

for (final song in artist.songs) {
  print(song.title);
}
```

Backlinks are read-only. Do not call `save()` on a backlink:

```dart
await artist.songs.save(); // Throws.
```

To change what appears in a backlink, modify and save the forward relationship
instead:

```dart
song.featuredArtists.add(artist);
await song.featuredArtists.save();
```

## Saving Relationships

Save related objects before saving the relationship between them.

```dart
final artist = Artist()
  ..name = 'Ana';

final song = Song()
  ..title = 'Ship It';

await db.writeTxn(() async {
  await db.artists.put(artist);
  await db.songs.put(song);

  song.featuredArtists.add(artist);
  song.primaryArtist.value = artist;

  await song.featuredArtists.save();
  await song.primaryArtist.save();
});
```

The write order matters:

1. Store the target object.
2. Store the source object.
3. Update the link container in memory.
4. Call `save()` on the forward link.

Saving a forward link replaces the persisted ids for that link. For a to-one
link, the saved value is either one linked object or no linked object. For a
to-many link, the saved value is the current set of linked objects in the
`CindelLinks<T>` container.

For example, this replaces the full featured artist set for the song:

```dart
song.featuredArtists
  ..add(firstArtist)
  ..add(secondArtist);

await song.featuredArtists.save();
```

If you later remove one artist and save again, the persisted relationship is
updated to match the in-memory set:

```dart
song.featuredArtists.remove(firstArtist);

await song.featuredArtists.save();
```

## Loading Relationships

Cindel does not automatically hydrate relationship values when an object is
read. Load each relationship explicitly from the hydrated object.

```dart
final song = await db.songs.get(songId);

await song!.featuredArtists.load();
await song.primaryArtist.load();
```

After loading, use the relation containers:

```dart
final primary = song.primaryArtist.value;
final featured = song.featuredArtists.toList();
```

Backlinks are also loaded explicitly:

```dart
final artist = await db.artists.get(artistId);

await artist!.songs.load();

final songs = artist.songs.toList();
```

When loading relationships, the owner object must come from a database-backed
read or have been stored so Cindel can identify it. A newly constructed object
that has never been stored is not enough to load persisted relationships.

## Limitations And Common Errors

### Link fields must be final

Declare link containers as `final` fields:

```dart
final featuredArtists = CindelLinks<Artist>();
final primaryArtist = CindelLink<Artist>();
```

Do not replace the link container object itself. Modify its contents instead.

### Targets must be root collections

Relationship targets must be root Cindel collections.

```dart
final primaryArtist = CindelLink<Artist>();
```

Embedded objects cannot be link targets. If a value needs to be linked from
another collection, model it as a root collection.

### Save objects before saving links

Saving a relationship validates that the source and target ids already exist.
This fails when the objects have not been persisted yet.

```dart
final artist = Artist()..name = 'Ana';
final song = Song()..title = 'Ship It';

song.featuredArtists.add(artist);

await song.featuredArtists.save(); // Fails: objects were not stored first.
```

Store the objects first:

```dart
await db.artists.put(artist);
await db.songs.put(song);

song.featuredArtists.add(artist);
await song.featuredArtists.save();
```

### Save forward links, not backlinks

Backlinks are read-only and throw when `save()` is called.

```dart
await artist.songs.save(); // Fails.
```

Save the forward link instead:

```dart
song.featuredArtists.add(artist);
await song.featuredArtists.save();
```

### Use the Dart field name in `@Backlink(to: ...)`

The `to` value is not the collection name. It is the Dart field name of the
forward link.

Correct:

```dart
@Backlink(to: 'featuredArtists')
final songs = CindelLinks<Song>();
```

Incorrect:

```dart
@Backlink(to: 'artists')
final songs = CindelLinks<Song>();
```

### Load relationships explicitly

Reading an object does not automatically load its link values.

```dart
final song = await db.songs.get(songId);

await song!.featuredArtists.load();
await song.primaryArtist.load();
```

If a relationship appears empty in memory, check whether it has been loaded and
whether the forward relationship was saved after being changed.

### Link fields are not normal persisted fields

Link fields describe relationships. They are not regular document fields like
`title`, `name`, or `createdAt`.

Use normal collection fields for data that belongs directly to the object. Use
`CindelLink<T>` and `CindelLinks<T>` only when the value is a relationship to
another root collection object.

### Backend behavior is consistent

SQLite native, MDBX, and SQLite Web/OPFS share the same relationship semantics:
save objects first, save forward relationships explicitly, load relationships
explicitly, and treat backlinks as read-only.
