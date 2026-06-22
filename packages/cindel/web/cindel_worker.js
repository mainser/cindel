import init, { CindelWebEngine } from './pkg/cindel_native.js';

let initPromise;
let engine;
let activeTransaction = null;
let closed = false;
let queue = Promise.resolve();

function errorMessage(error) {
  return error?.message || error?.stack || String(error);
}

function bytes(value) {
  if (value instanceof Uint8Array) {
    return value;
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  throw new Error('Expected binary payload.');
}

function optionalVersion(value) {
  return value === 0 ? null : value;
}

function response(requestId, payload) {
  if (payload instanceof Uint8Array) {
    self.postMessage({ type: 'response', requestId, payload }, [
      payload.buffer,
    ]);
    return;
  }
  self.postMessage({ type: 'response', requestId, payload });
}

function failure(requestId, code, message) {
  self.postMessage({
    type: 'error',
    requestId: requestId ?? 0,
    error: { code, message },
  });
}

async function ensureWasm(payload) {
  initPromise ??= init(
    new URL(payload?.wasmUrl || './pkg/cindel_native_bg.wasm', import.meta.url),
  );
  await initPromise;
}

function requireEngine() {
  if (!engine) {
    throw new Error('Cindel Web engine is not open.');
  }
  return engine;
}

function beginTransaction(kind) {
  if (activeTransaction != null) {
    throw new Error('a transaction is already active');
  }
  if (kind === 'read') {
    requireEngine().beginReadTransaction();
  } else {
    requireEngine().beginWriteTransaction();
  }
  activeTransaction = kind;
}

function commitTransaction() {
  requireEngine().commitTransaction();
  activeTransaction = null;
}

function rollbackTransaction() {
  requireEngine().rollbackTransaction();
  activeTransaction = null;
}

function rollbackActiveTransaction() {
  if (!engine || activeTransaction == null) {
    return;
  }
  try {
    engine.rollbackTransaction();
  } finally {
    activeTransaction = null;
  }
}

async function execute(message) {
  if (closed) {
    failure(message.requestId, 'closed', 'Worker is closed.');
    return;
  }

  try {
    const payload = message.payload || {};
    switch (message.operation) {
      case 'open':
        await ensureWasm(payload);
        engine = await CindelWebEngine.openWithSchemas(
          payload.dbName,
          bytes(payload.manifest),
        );
        activeTransaction = null;
        response(message.requestId, null);
        return;
      case 'schemaVersion':
        response(message.requestId, optionalVersion(requireEngine().schemaVersion(payload.collection)));
        return;
      case 'migrationVersion':
        response(message.requestId, optionalVersion(requireEngine().migrationVersion()));
        return;
      case 'setMigrationVersion':
        requireEngine().setMigrationVersion(payload.version);
        response(message.requestId, null);
        return;
      case 'registerMigratedSchemas':
        requireEngine().registerMigratedSchemas(bytes(payload.manifest));
        response(message.requestId, null);
        return;
      case 'compact':
        requireEngine().compact();
        response(message.requestId, null);
        return;
      case 'storageMetadata':
        response(message.requestId, requireEngine().storageMetadataJson());
        return;
      case 'beginReadTransaction':
        beginTransaction('read');
        response(message.requestId, null);
        return;
      case 'beginWriteTransaction':
        beginTransaction('write');
        response(message.requestId, null);
        return;
      case 'commitTransaction':
        commitTransaction();
        response(message.requestId, null);
        return;
      case 'rollbackTransaction':
        rollbackTransaction();
        response(message.requestId, null);
        return;
      case 'allocateId':
        response(message.requestId, requireEngine().allocateId(payload.collection));
        return;
      case 'allocateIds':
        response(
          message.requestId,
          requireEngine().allocateIds(payload.collection, payload.count),
        );
        return;
      case 'put':
        requireEngine().put(payload.collection, bytes(payload.documents));
        response(message.requestId, null);
        return;
      case 'putAll':
        requireEngine().putAll(payload.collection, bytes(payload.documents));
        response(message.requestId, null);
        return;
      case 'putNativeAll':
        response(
          message.requestId,
          requireEngine().putNativeAll(payload.collection, bytes(payload.documents)),
        );
        return;
      case 'get':
        response(message.requestId, requireEngine().get(payload.collection, bytes(payload.ids)));
        return;
      case 'getAll':
        response(
          message.requestId,
          requireEngine().getAll(payload.collection, bytes(payload.ids)),
        );
        return;
      case 'getStored':
        response(
          message.requestId,
          requireEngine().getStored(payload.collection, bytes(payload.ids)),
        );
        return;
      case 'getAllStored':
        response(
          message.requestId,
          requireEngine().getAllStored(payload.collection, bytes(payload.ids)),
        );
        return;
      case 'delete':
        requireEngine().delete(payload.collection, bytes(payload.ids));
        response(message.requestId, null);
        return;
      case 'deleteAll':
        requireEngine().deleteAll(payload.collection, bytes(payload.ids));
        response(message.requestId, null);
        return;
      case 'deleteNativeAll':
        response(
          message.requestId,
          requireEngine().deleteNativeAll(payload.collection, bytes(payload.ids)),
        );
        return;
      case 'replaceLinks':
        requireEngine().replaceLinks(
          payload.sourceCollection,
          Number(payload.sourceId),
          payload.linkName,
          payload.targetCollection,
          bytes(payload.targetIds),
        );
        response(message.requestId, null);
        return;
      case 'forwardLinkIds':
        response(
          message.requestId,
          requireEngine().forwardLinkIds(
            payload.sourceCollection,
            Number(payload.sourceId),
            payload.linkName,
            payload.targetCollection,
          ),
        );
        return;
      case 'backlinkSourceIds':
        response(
          message.requestId,
          requireEngine().backlinkSourceIds(
            payload.targetCollection,
            Number(payload.targetId),
            payload.sourceCollection,
            payload.linkName,
          ),
        );
        return;
      case 'documentIds':
        response(message.requestId, requireEngine().documentIds(payload.collection));
        return;
      case 'documentIdsPage':
        response(
          message.requestId,
          requireEngine().documentIdsPage(
            payload.collection,
            Number(payload.afterId ?? 0),
            payload.afterId !== null && payload.afterId !== undefined,
            Number(payload.limit),
          ),
        );
        return;
      case 'collectionRevision':
        response(
          message.requestId,
          requireEngine().collectionRevision(payload.collection),
        );
        return;
      case 'takeChanges':
        response(message.requestId, requireEngine().takeChanges());
        return;
      case 'queryIndexEqual':
        response(
          message.requestId,
          requireEngine().queryIndexEqual(
            payload.collection,
            payload.index,
            bytes(payload.value),
          ),
        );
        return;
      case 'queryIndexRange':
        response(
          message.requestId,
          requireEngine().queryIndexRange(
            payload.collection,
            payload.index,
            payload.lower != null,
            payload.lower == null ? new Uint8Array() : bytes(payload.lower),
            payload.upper != null,
            payload.upper == null ? new Uint8Array() : bytes(payload.upper),
          ),
        );
        return;
      case 'queryPlanIds':
        response(
          message.requestId,
          requireEngine().queryPlanIds(payload.collection, bytes(payload.plan)),
        );
        return;
      case 'queryPlanDocuments':
        response(
          message.requestId,
          requireEngine().queryPlanDocuments(payload.collection, bytes(payload.plan)),
        );
        return;
      case 'queryPlanCount':
        response(
          message.requestId,
          requireEngine().queryPlanCount(payload.collection, bytes(payload.plan)),
        );
        return;
      case 'queryPlanProject':
        response(
          message.requestId,
          requireEngine().queryPlanProject(
            payload.collection,
            bytes(payload.plan),
            payload.field,
          ),
        );
        return;
      case 'queryPlanAggregate':
        response(
          message.requestId,
          requireEngine().queryPlanAggregate(
            payload.collection,
            bytes(payload.plan),
            payload.field,
            payload.operation,
          ),
        );
        return;
      case 'queryPlanDelete':
        response(
          message.requestId,
          requireEngine().queryPlanDelete(payload.collection, bytes(payload.plan)),
        );
        return;
      case 'queryPlanUpdate':
        response(
          message.requestId,
          requireEngine().queryPlanUpdate(
            payload.collection,
            bytes(payload.plan),
            bytes(payload.updates),
            payload.collectChanges !== false,
          ),
        );
        return;
      default:
        failure(
          message.requestId,
          'unsupported_operation',
          `Unsupported operation: ${message.operation}`,
        );
    }
  } catch (error) {
    failure(message.requestId, 'operation_failed', errorMessage(error));
  }
}

async function closeWorker() {
  if (closed) {
    self.postMessage({ type: 'closed' });
    self.close();
    return;
  }
  closed = true;
  try {
    await queue.catch(() => {});
    rollbackActiveTransaction();
  } catch (error) {
    failure(0, 'close_failed', errorMessage(error));
  } finally {
    engine = undefined;
    self.postMessage({ type: 'closed' });
    self.close();
  }
}

self.onmessage = async (event) => {
  const message = event.data;
  try {
    if (message.type === 'init') {
      await ensureWasm(message.payload);
      self.postMessage({ type: 'ready' });
      return;
    }

    if (message.type === 'close') {
      await closeWorker();
      return;
    }

    if (message.type !== 'request') {
      failure(message.requestId, 'invalid_message', 'Unknown message type.');
      return;
    }

    queue = queue.then(
      () => execute(message),
      () => execute(message),
    );
  } catch (error) {
    failure(message.requestId, 'worker_error', errorMessage(error));
  }
};
