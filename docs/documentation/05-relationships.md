# Relationships

Cindel relationships connect objects from root collections. They are useful
when one stored object should point to another stored object by id, while each
object still keeps its own collection, lifecycle, and typed API.

Use:

- `CindelLink<T>` for a to-one relationship,
- `CindelLinks<T>` for a to-many relationship,
- `@Backlink(to: ...)` for a read-only inverse relationship.

Relationships are explicit. Store the related objects first, update the link
container in memory, call `save()` on the forward link, and later call `load()`
when you want to read the related objects.

## Model Example

The examples in this page use artists and songs.

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

This defines three relationship fields:

- `Song.primaryArtist`: one song points to one artist.
- `Song.featuredArtists`: one song points to many artists.
- `Artist.songs`: one artist can load songs whose `featuredArtists` link
  includes that artist.

Link containers must be `final` fields. The target type must be another root
Cindel collection. Embedded objects cannot be relationship targets.

## To-One Links

Use `CindelLink<T>` when an object points to zero or one object of another
collection.

```dart
@Collection(name: 'songs')
class Song {
  Id dbId = autoIncrement;

  late String title;

  final primaryArtist = CindelLink<Artist>();
}
```

Set the in-memory value through `value`:

```dart
song.primaryArtist.value = artist;
```

Then save the relationship:

```dart
await song.primaryArtist.save();
```

To clear a to-one relationship, set the value to `null` and save:

```dart
song.primaryArtist.value = null;
await song.primaryArtist.save();
```

To read the stored relationship later, load it from a hydrated object:

```dart
final song = await db.songs.get(songId);

await song!.primaryArtist.load();

final artist = song.primaryArtist.value;
```

`reset()` clears the currently loaded in-memory value without changing the
stored relationship:

```dart
await song.primaryArtist.reset();
```

Use `reset()` when you want to discard loaded relation state and load it again
later.

## To-Many Links

Use `CindelLinks<T>` when an object points to a set of objects in another
collection.

```dart
@Collection(name: 'songs')
class Song {
  Id dbId = autoIncrement;

  late String title;

  final featuredArtists = CindelLinks<Artist>();
}
```

Add and remove objects in memory:

```dart
song.featuredArtists.add(firstArtist);
song.featuredArtists.add(secondArtist);
song.featuredArtists.remove(firstArtist);
```

Then save the current set:

```dart
await song.featuredArtists.save();
```

`save()` replaces the stored ids for that link with the current contents of the
`CindelLinks<T>` container. If the container has two artists when you save, the
stored relationship has those two artists. If you remove one and save again,
the stored relationship is updated to match.

Load a to-many relationship explicitly:

```dart
final song = await db.songs.get(songId);

await song!.featuredArtists.load();

for (final artist in song.featuredArtists) {
  print(artist.name);
}
```

`CindelLinks<T>` is iterable after values are loaded. You can also turn it into
a list:

```dart
final artists = song.featuredArtists.toList();
```

`reset()` clears the in-memory set without changing the stored relationship:

```dart
await song.featuredArtists.reset();
```

## Backlinks

A backlink is the read-only inverse of a forward relationship. It lets an
object load other objects that point to it.

```dart
@Collection(name: 'artists')
class Artist {
  Id dbId = autoIncrement;

  late String name;

  @Backlink(to: 'featuredArtists')
  final songs = CindelLinks<Song>();
}
```

The `to` value is the Dart field name of the forward link on the other
collection. In this example, `Artist.songs` points to
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

Load a backlink the same way you load a to-many link:

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

To change what appears in a backlink, change and save the forward link instead:

```dart
song.featuredArtists.add(artist);
await song.featuredArtists.save();
```

## Saving Relationships

Save the source and target objects before saving the relationship between them.

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

The normal write order is:

1. Store the target object.
2. Store the source object.
3. Update the link container in memory.
4. Call `save()` on the forward link.

Saving validates that the source id and target ids exist. If either side has
not been stored yet, saving the relationship fails instead of creating a
relation to missing data.

## Loading Relationships

Reading an object does not automatically load its relationships. Load each
relationship explicitly from the object you read.

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

The owner object must be database-backed. A newly constructed object that has
never been stored is not enough to load persisted relationships.

## Common Mistakes

### Link Fields Must Be Final

Declare link containers as `final` fields:

```dart
final featuredArtists = CindelLinks<Artist>();
final primaryArtist = CindelLink<Artist>();
```

Do not replace the container object itself. Modify its contents instead.

### Targets Must Be Root Collections

Relationship targets must be root Cindel collections.

```dart
final primaryArtist = CindelLink<Artist>();
```

Embedded objects cannot be link targets. If a value needs to be linked from
another collection, model it as a root collection.

### Save Objects Before Links

Saving a relationship validates that the source and target ids already exist.
This fails when the objects have not been stored yet.

```dart
final artist = Artist()..name = 'Ana';
final song = Song()..title = 'Ship It';

song.featuredArtists.add(artist);

await song.featuredArtists.save(); // Fails.
```

Store the objects first, then save the forward relationship:

```dart
await db.artists.put(artist);
await db.songs.put(song);

song.featuredArtists.add(artist);
await song.featuredArtists.save();
```

### Save Forward Links, Not Backlinks

Backlinks are read-only and throw when `save()` is called.

```dart
await artist.songs.save(); // Fails.
```

Save the forward link instead:

```dart
song.featuredArtists.add(artist);
await song.featuredArtists.save();
```

### Use The Dart Field Name In `@Backlink(to: ...)`

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

### Load Relationships Explicitly

Reading an object does not automatically load its link values.

```dart
final song = await db.songs.get(songId);

await song!.featuredArtists.load();
await song.primaryArtist.load();
```

If a relationship looks empty in memory, check whether it has been loaded and
whether the forward relationship was saved after being changed.

### Link Fields Are Not Normal Stored Fields

Link fields describe relationships. They are not regular document fields like
`title`, `name`, or `createdAt`.

Use normal collection fields for values that belong directly to the object. Use
`CindelLink<T>` and `CindelLinks<T>` only for relationships to other root
collection objects.

## Backend Behavior

SQLite native, MDBX, and SQLite Web/OPFS share the same relationship behavior:

- save objects first,
- save forward relationships explicitly,
- load relationships explicitly,
- treat backlinks as read-only.
