# Sync

Cindel Sync is an experimental local-first replication layer. It lets an app
keep using normal typed collections while Cindel records supported local
changes, sends them through an application-provided adapter, pulls remote
changes, and applies backend truth back into the local database.

The application still reads from Cindel. Sync status callbacks are for UI
indicators and logging; they are not a replacement for typed reads and
watchers.

## What Sync Is

Sync is useful when an application needs local-first behavior:

- users can keep working while offline,
- writes show up locally before the network round trip finishes,
- pending changes survive app restart,
- a backend can later confirm or correct local state,
- another device can pull confirmed changes.

A typical flow is:

1. The app writes to Cindel normally.
2. The local write is visible immediately.
3. Cindel sends a pending mutation to your adapter.
4. Your backend accepts, rejects, or corrects the mutation.
5. Cindel applies remote changes locally.
6. Watchers emit updated objects and collections.

Example: a shopping app lets a user add five items to a cart while offline. The
backend later corrects the quantity to two because only two are in stock.
Cindel applies that corrected row locally and collection watchers update the
UI.

## What Sync Is Not

Cindel does not include a hosted sync server. You provide the backend through a
`CindelSyncAdapter`.

Cindel also does not decide business rules. Your backend decides:

- whether a user can write a document,
- whether a product has enough stock,
- whether a mutation should be accepted,
- what the final corrected document should be,
- how conflicts between devices are resolved.

There are no public push, pull, pause, resume, or flush methods. Configure sync
when opening the database, then keep using typed collections.

## Enabling Sync

Pass `sync: CindelSyncConfig(...)` to `Cindel.open`.

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [ProductSchema, OrderSchema, OrderLineSchema],
  sync: CindelSyncConfig(
    adapter: AppSyncAdapter(serverBaseUri),
    clientId: deviceId,
    interval: const Duration(seconds: 5),
    batchSize: 100,
    onStatusChanged: (status) {
      print('${status.phase} pending=${status.pendingCount}');
    },
    onError: (error, stackTrace) {
      // Log or report background sync failures.
    },
  ),
);
```

After opening, read and write normally:

```dart
await db.orders.put(order);
await db.orderLines.put(line);

final currentLines = await db.orderLines.all().findAll();

final sub = db.orderLines.watchCollection().listen((lines) {
  // Fires for local optimistic writes and later remote corrections.
});
```

Do not manually create sync mutations. Cindel captures supported local writes
when sync is enabled.

## `CindelSyncConfig`

`CindelSyncConfig` controls the adapter and scheduler behavior.

```dart
final config = CindelSyncConfig(
  adapter: AppSyncAdapter(serverBaseUri),
  clientId: deviceId,
  autoStart: true,
  interval: const Duration(seconds: 5),
  batchSize: 100,
  onStatusChanged: (status) {},
  onError: (error, stackTrace) {},
);
```

Fields:

- `adapter`: required backend adapter.
- `clientId`: stable id for this installation or device. If omitted, Cindel
  persists an internal id for this local database.
- `autoStart`: starts the scheduler automatically after open.
- `interval`: how often the scheduler retries in the background.
- `batchSize`: maximum pending mutations sent in one push call.
- `onStatusChanged`: optional callback for UI and logging.
- `onError`: optional callback for background sync errors.

Use a stable `clientId` when your backend needs to understand which device sent
the mutation. Do not generate a new random id every app start unless every run
should be treated as a different client.

## Sync Status

`onStatusChanged` receives a `CindelSyncStatus`:

```dart
final class CindelSyncStatus {
  final CindelSyncPhase phase;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final Object? lastError;
}
```

Phases:

- `idle`: no sync call is currently running.
- `syncing`: Cindel is calling the adapter.
- `offline`: the adapter failed with an offline-style error.
- `error`: the adapter or remote apply failed for another reason.

`pendingCount` is the number of local mutations waiting to be sent or accepted.
It can be greater than zero while offline.

Use status for small indicators such as "syncing", "offline", or "2 changes
pending". Use typed reads and watchers as the source of application data.

## Writing A Sync Adapter

Implement `CindelSyncAdapter`.

```dart
final class AppSyncAdapter implements CindelSyncAdapter {
  AppSyncAdapter(this.serverBaseUri);

  final Uri serverBaseUri;

  @override
  Future<CindelPushResult> push(CindelPushRequest request) async {
    final response = await postJson('/sync/push', {
      'clientId': request.clientId,
      'lastPulledCheckpoint': request.lastPulledCheckpoint,
      'schemaVersionByCollection': request.schemaVersionByCollection,
      'mutations': [
        for (final mutation in request.mutations)
          {
            'mutationId': mutation.mutationId,
            'clientId': mutation.clientId,
            'sequence': mutation.sequence,
            'collection': mutation.collection,
            'operation': mutation.operation.name,
            'documentId': mutation.documentId,
            'document': mutation.document,
            'linkName': mutation.linkName,
            'targetCollection': mutation.targetCollection,
            'targetIds': mutation.targetIds,
            'baseCheckpoint': mutation.baseCheckpoint,
          },
      ],
    });

    return CindelPushResult(
      acceptedMutationIds: {
        for (final id in response['acceptedMutationIds'] as List) id as String,
      },
      correctedChanges: decodeRemoteChanges(response['correctedChanges']),
      checkpoint: response['checkpoint'] as String?,
    );
  }

  @override
  Future<CindelPullResult> pull(CindelPullRequest request) async {
    final response = await postJson('/sync/pull', {
      'clientId': request.clientId,
      'checkpoint': request.checkpoint,
      'collections': request.collections.toList(),
      'schemaVersionByCollection': request.schemaVersionByCollection,
    });

    return CindelPullResult(
      checkpoint: response['checkpoint'] as String,
      changes: decodeRemoteChanges(response['changes']),
    );
  }
}
```

`postJson` and `decodeRemoteChanges` are application helpers in this example.
Cindel does not require HTTP or a specific JSON shape. The adapter contract is
what matters:

- `push` receives pending local mutations and returns which mutation ids were
  accepted.
- `pull` receives the last local checkpoint and returns every remote change
  after that checkpoint.

The backend must treat `mutationId` as idempotent. If the same mutation arrives
twice, the backend should not apply it twice; it should return the mutation id
as accepted again.

## Push

Push sends local pending mutations to your backend.

### Push Requests

`CindelPushRequest` contains:

- `clientId`: the local client/device id.
- `lastPulledCheckpoint`: the last checkpoint this database pulled.
- `schemaVersionByCollection`: current local schema versions by collection.
- `mutations`: pending local mutations.

Each `CindelSyncMutation` contains:

- `mutationId`: stable id for retry and deduplication.
- `clientId`: client that created the mutation.
- `sequence`: local sequence number for this client.
- `collection`: collection name, such as `orders` or `orderLines`.
- `operation`: `upsert`, `delete`, or `replaceLinks`.
- `documentId`: document id for document mutations.
- `document`: stored document map for upserts.
- `linkName`, `targetCollection`, and `targetIds`: link replacement data.
- `baseCheckpoint`: checkpoint known when the local mutation was recorded.

For a typed `put`, the backend receives an `upsert` mutation. For a typed
`delete`, it receives a `delete` mutation.

### Push Results

Return `CindelPushResult` from `push`.

```dart
return CindelPushResult(
  acceptedMutationIds: {'device-a:1', 'device-a:2'},
  rejectedMutations: [
    CindelSyncRejectedMutation(
      mutationId: 'device-a:3',
      reason: 'product_not_available',
    ),
  ],
  correctedChanges: [
    CindelRemoteUpsert(
      collection: 'orderLines',
      id: 900,
      document: {
        'dbId': 900,
        'orderId': 500,
        'productId': 10,
        'quantity': 2,
        'state': 'corrected',
        'reason': 'stock_limited',
      },
    ),
  ],
  checkpoint: '42',
);
```

`acceptedMutationIds` tells Cindel which pending mutations can be removed.

`rejectedMutations` is for mutations the backend will never accept. Include a
short reason that your application can log or inspect while debugging. A
rejection should be reserved for permanent business failures, not temporary
network errors.

`correctedChanges` lets the backend return final truth immediately, such as a
corrected quantity or server-normalized document.

`checkpoint` is optional on push. If provided, Cindel stores it as the newest
known checkpoint.

## Pull

Pull asks the backend for remote changes after the local checkpoint.

### Pull Requests

`pull` receives:

- `clientId`
- `checkpoint`
- `schemaVersionByCollection`
- `collections`

### Pull Results

Return every remote change after the checkpoint.

```dart
return CindelPullResult(
  checkpoint: '43',
  changes: [
    CindelRemoteUpsert(
      collection: 'products',
      id: 10,
      document: {
        'dbId': 10,
        'sku': 'USB-C-1M',
        'title': 'USB-C cable',
        'priceCents': 1299,
        'stock': 8,
      },
    ),
    CindelRemoteDelete(collection: 'orderLines', id: 900),
  ],
);
```

Set `resetRequired: true` only when the backend cannot safely continue from the
client checkpoint. For normal incremental sync, leave it as the default
`false`.

Remote changes are applied inside Cindel. They update the database and notify
watchers, but they are not recorded again as local pending mutations.

## Remote Changes

Use these classes in `CindelPullResult.changes` and
`CindelPushResult.correctedChanges`:

- `CindelRemoteUpsert`: writes or replaces a document in a collection.
- `CindelRemoteDelete`: deletes a document by id.
- `CindelRemoteReplaceLinks`: replaces a persisted link id set.

The remote `collection` must match a schema registered in `Cindel.open`.
Unknown collections fail because Cindel cannot safely apply them.

Documents are map-shaped stored values. Send the same keys and value shapes
produced by the generated schema document conversion. Include the id field,
such as `dbId`, when possible. Cindel also receives the id separately through
`CindelRemoteUpsert.id`.

## Multiple Collections

Sync is not limited to one collection. Each mutation and remote change includes
its collection name.

```dart
await db.writeTxn(() async {
  await db.orders.put(order);
  await db.orderLines.put(firstLine);
  await db.orderLines.put(secondLine);
});
```

The adapter may later receive separate mutations:

- `upsert orders.500`
- `upsert orderLines.900`
- `upsert orderLines.901`

Your backend should validate and store each collection according to your app
rules.

## Supported Local Operations

When sync is enabled, Cindel records these local operations:

- typed `put`
- typed `putAll`
- typed `delete`
- typed `deleteAll`
- query deletes
- link replacements

Query updates are currently rejected while sync is enabled. Instead of:

```dart
await db.todos.all().updateAll({'completed': true});
```

read the objects, change them in Dart, and write them back:

```dart
final todos = await db.todos.all().findAll();
for (final todo in todos) {
  todo.completed = true;
}
await db.todos.putAll(todos);
```

This gives Cindel complete document snapshots to send to the adapter.

Most application code should use generated typed collections. Low-level raw
document writes are for generated code and advanced tooling; with sync enabled,
raw writes need canonical document data so Cindel can build a valid mutation.

## Offline Behavior

If the adapter cannot reach the server, throw an error from `push` or `pull`.
Cindel keeps pending mutations and retries later.

Expected behavior while offline:

- local writes still commit,
- typed reads return local optimistic data,
- watchers emit local changes,
- `pendingCount` increases,
- status may become `offline`,
- pending mutations survive close and reopen.

When the server is reachable again, the scheduler retries automatically.

## Backend Requirements

A production backend should provide:

- durable storage for accepted mutation ids,
- idempotent mutation handling by `mutationId`,
- ordered or otherwise deterministic handling per client,
- stable checkpoints for pull,
- a way to return all changes after a checkpoint,
- access control and authentication,
- collection-specific validation,
- conflict and correction rules.

Realtime is optional. If you add sockets or push notifications, use them only
as a wake-up signal to pull. The checkpointed `pull` result should remain the
source of truth.

## Minimal Server Flow

A simple backend can start with two endpoints:

- `POST /sync/push`: accepts local mutations and returns accepted ids plus
  optional corrections.
- `POST /sync/pull`: returns remote changes after a checkpoint.

For `push`:

1. Authenticate the user.
2. For each mutation, check whether `mutationId` was already accepted.
3. If it is new, validate the target collection and operation.
4. Apply business rules.
5. Store the final document or delete.
6. Append a remote change with a new checkpoint sequence.
7. Return the accepted mutation id.

For `pull`:

1. Authenticate the user.
2. Read the caller checkpoint.
3. Return every visible change after that checkpoint.
4. Return the newest checkpoint.

## Common Mistakes

Avoid these patterns:

- creating a new `clientId` on every app start when your backend expects stable
  devices,
- updating UI from sync callback payloads instead of from Cindel watchers,
- accepting the same `mutationId` twice on the backend,
- returning remote changes for collections that were not registered at open,
- using query updates while sync is enabled,
- assuming Cindel provides server-side auth or conflict rules,
- assuming Web multi-tab sync coordination is part of the current preview.

## Testing Sync

For tests, use a small fake adapter:

```dart
final adapter = FakeSyncAdapter()..online = false;
final statuses = <CindelSyncStatus>[];

final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  sync: CindelSyncConfig(
    adapter: adapter,
    interval: const Duration(milliseconds: 10),
    onStatusChanged: statuses.add,
  ),
);

await db.users.put(user);

expect(await db.users.get(user.dbId), isNotNull);

adapter.online = true;
```

Useful cases to test in an app:

- local write is visible immediately,
- pending write survives close and reopen,
- backend correction applies locally,
- another client can pull the change,
- delete replicates,
- remote apply does not create another local pending mutation,
- unsupported operations fail clearly.
