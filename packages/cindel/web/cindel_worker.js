import init, { CindelWebEngine } from './pkg/cindel_native.js';

let initPromise;
let engine;
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
        response(message.requestId, null);
        return;
      case 'schemaVersion':
        response(
          message.requestId,
          requireEngine().schemaVersion(payload.collection),
        );
        return;
      case 'storageMetadata':
        response(message.requestId, requireEngine().storageMetadataJson());
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
      case 'documentIds':
        response(message.requestId, requireEngine().documentIds(payload.collection));
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

self.onmessage = async (event) => {
  const message = event.data;
  try {
    if (message.type === 'init') {
      await ensureWasm(message.payload);
      self.postMessage({ type: 'ready' });
      return;
    }

    if (message.type === 'close') {
      closed = true;
      engine = undefined;
      self.postMessage({ type: 'closed' });
      self.close();
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
