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

Reads inside one `readTxn` see a consistent database state. Changes committed
through another connection do not appear midway through that transaction.
Keep related pages or totals inside the same callback when they must agree.

`allocateId` and `allocateIds` also change database state, so they cannot run
inside `readTxn`. Use `writeTxn` when reserving IDs and writing the objects
must succeed together. Explicit transactions cannot be nested or overlap on
the same database handle.

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
- database ID reservations made inside the transaction are rolled back.

Dart object mutations, assigned IDs, and external side effects are not rolled
back. If a retry needs fresh automatic IDs, reset or recreate those objects
explicitly rather than assuming rollback changed them in memory.

Use normal Dart error handling to decide whether the caller should retry, show
an error message, or abandon the operation.

### Closing a Database During a Transaction

Await the transaction before closing its database:

```dart
await db.writeTxn(() async {
  await db.todos.putAll(todos);
});
await db.close();
```

Closing while a transaction is still active rolls it back. The callback may
resume after an `await`, but it can no longer use the closed database or commit
its pending changes. If it returns normally, the transaction reports
`CindelDatabaseClosedError`; if it throws, its original error is preserved.
Closing does not undo a transaction that already committed.

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

Keep unrelated asynchronous work from using the same database handle while a
transaction is active: its operations can join that transaction. Let one caller
own the transaction and await it before starting another workflow on that handle.

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
