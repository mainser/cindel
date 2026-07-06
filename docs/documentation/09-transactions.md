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
- the error from the callback is returned to the caller.

Use normal Dart error handling to decide whether the caller should retry, show
an error message, or abandon the operation.

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
