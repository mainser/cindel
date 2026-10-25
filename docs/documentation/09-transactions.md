# Transactions

Transactions group database work into one consistent operation. Use them when
several reads or writes belong together and should see a consistent state or
commit as one local change.

Use:

- `readTxn` for grouped reads,
- `writeTxn` for writes that must commit together or roll back together.

Single collection calls such as one `put` or one `delete` do not usually need
an explicit transaction. Reach for transactions when a local workflow has more
than one database step that must stay consistent.

## Read Transactions

`readTxn` runs a callback inside a read transaction.

```dart
final openTodos = await db.readTxn(() {
  return db.todos
      .filter()
      .completedEqualTo(false)
      .findAll();
});
```

Use `readTxn` when a read flow needs a consistent view across multiple queries:

```dart
final summary = await db.readTxn(() async {
  final open = await db.todos
      .filter()
      .completedEqualTo(false)
      .count();

  final done = await db.todos
      .filter()
      .completedEqualTo(true)
      .count();

  return (open: open, done: done);
});
```

Do not write inside `readTxn`. Writes inside a read transaction throw
`CindelTransactionError`.

```dart
await db.readTxn(() async {
  await db.todos.put(todo); // Throws.
});
```

Use `readTxn` for grouped reads, not for changes.

### Snapshots And Allocation

Reads issued through an active `readTxn` use that transaction's snapshot,
including MDBX query and paged-ID reads. A later commit through another native
handle does not become visible midway through the snapshot. Keep related page
reads inside one `readTxn` when the scan must be consistent.

Allocating IDs changes persisted state and is not allowed inside `readTxn`.
In a write transaction, ID reservations use the active transactional counter;
separate native handles do not rely on a stale per-handle counter. The storage
engine coordinates their writes. This does not permit nesting or overlapping
explicit transactions on the same Cindel handle.

## Write Transactions

`writeTxn` runs writes atomically.

```dart
await db.writeTxn(() async {
  await db.todos.put(todo);
  await db.auditEvents.put(event);
});
```

If every operation in the callback succeeds, the transaction commits. If the
callback throws, Cindel rolls the transaction back.

Use `writeTxn` when related changes must be saved together:

```dart
await db.writeTxn(() async {
  await db.orders.put(order);
  await db.orderLines.putAll(lines);
});
```

Use it when a write depends on a read:

```dart
await db.writeTxn(() async {
  final todo = await db.todos.get(todoId);
  if (todo == null) {
    throw StateError('Todo not found.');
  }

  todo.completed = true;
  await db.todos.put(todo);
});
```

Use it when writing relationship data after storing related objects:

```dart
await db.writeTxn(() async {
  await db.artists.put(artist);
  await db.songs.put(song);

  song.featuredArtists.add(artist);
  await song.featuredArtists.save();
});
```

## Rollback Behavior

Rollback happens when the transaction callback throws.

```dart
try {
  await db.writeTxn(() async {
    await db.todos.put(todo);
    throw StateError('Stop the write.');
  });
} catch (_) {
  // The write was rolled back.
}
```

When a write transaction rolls back:

- writes made inside the transaction are not committed,
- watcher notifications for those rolled-back writes are not emitted,
- the error from the callback is returned to the caller,
- transactional ID counters and SQLite change revisions are rolled back.

Dart object mutations, assigned IDs, and external side effects are not rolled
back. If a retry needs fresh automatic IDs, reset or recreate those objects
explicitly rather than assuming rollback changed them in memory.

Use normal Dart error handling to decide whether the caller should retry, show
an error message, or abandon the operation.

### Closing a Database During a Transaction

Closing a database rolls back the active transaction without waiting for
its application callback to finish. When a suspended callback resumes and returns,
the transaction fails with `CindelDatabaseClosedError` instead of committing. If
the callback throws, its original exception is preserved. Pending writes remain
uncommitted, and their watcher notifications are not emitted.

The callback can still perform other application work, but further database
operations fail after the database handle is retired. Awaiting `db.close()` inside
the callback completes the close; it does not commit that transaction.

Web follows the same callback contract through its Worker/Wasm backend. Requests
already admitted run in order before rollback; a commit dispatched before the
handle is retired may already have completed and retains its successful result.

## Checkout-Style Example

This example reads stock and writes an updated product inside one write
transaction.

```dart
await db.writeTxn(() async {
  final product = await db.products.get(productId);

  if (product == null || product.stock < quantity) {
    throw StateError('Not enough stock.');
  }

  await db.products.put(
    product.copyWith(stock: product.stock - quantity),
  );
});
```

The read and write belong to the same business operation. If the stock check
fails, the callback throws and no write is committed.

A checkout flow can also write an order and order lines in the same
transaction:

```dart
await db.writeTxn(() async {
  final product = await db.products.get(productId);

  if (product == null || product.stock < quantity) {
    throw StateError('Not enough stock.');
  }

  await db.products.put(
    product.copyWith(stock: product.stock - quantity),
  );

  await db.orders.put(order);
  await db.orderLines.putAll(lines);
});
```

Use one transaction for the complete local change that must remain consistent.

## Common Mistakes

### Await Every Operation And Control Handle Ownership

The active transaction belongs to the database handle. It is not an isolated
Dart zone for the callback: another asynchronous task using the same handle
while the callback is suspended can join its active transaction. Serialize
access during an explicit transaction instead of letting unrelated work use
that handle concurrently.

Await every database future before the callback returns. A fire-and-forget
write can outlive the transaction and its errors will not reliably control
rollback. Prepare slow external inputs before starting the transaction, then
keep its database work together:

```dart
await db.writeTxn(() async {
  await db.todos.putAll(todos);
  final saved = await db.todos.getAll(todos.map((todo) => todo.dbId));
  if (saved.any((todo) => todo == null)) {
    throw StateError('A written todo could not be read.');
  }
});
```

`getAll` inside `writeTxn` reads this handle's pending inserts and updates;
pending deletions return null. Input order, duplicate IDs, and missing entries
are preserved on MDBX, SQLite native, and Web. Returned objects are detached
values: later writes or rollback do not mutate a previously returned list.

### Writing Inside `readTxn`

`readTxn` is for reads only.

```dart
await db.readTxn(() async {
  await db.todos.put(todo); // Throws.
});
```

Use `writeTxn` when the callback writes.

### Nesting Explicit Transactions

Nested explicit transactions are rejected.

```dart
await db.writeTxn(() async {
  await db.writeTxn(() async {
    await db.todos.put(todo);
  });
});
```

Keep transaction boundaries at the caller level. If a helper can be called from
inside an existing transaction, let the caller own the transaction and keep the
helper focused on the reads or writes.

### Swallowing Errors Inside A Transaction

Rollback depends on the callback throwing. If you catch an error inside the
callback and do not rethrow, Cindel treats the callback as successful.

```dart
await db.writeTxn(() async {
  try {
    await db.todos.put(todo);
    throw StateError('Invalid follow-up step.');
  } catch (_) {
    // The callback continues and may commit unless the error is rethrown.
  }
});
```

Rethrow when the transaction should roll back:

```dart
await db.writeTxn(() async {
  try {
    await db.todos.put(todo);
    throw StateError('Invalid follow-up step.');
  } catch (_) {
    rethrow;
  }
});
```

### Doing Unrelated Work Inside A Transaction

Keep transactions short and scoped to database work. Avoid waiting on unrelated
network calls, UI prompts, or long-running non-database tasks inside the
transaction callback.

Prepare inputs before the transaction, then perform the database reads and
writes that must be atomic inside the transaction.
