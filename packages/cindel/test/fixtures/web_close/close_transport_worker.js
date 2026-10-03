// Controlled protocol fixture for actual browser Worker lifecycle tests.
// Database integration tests separately load the packaged SQLite/Wasm engine;
// this fixture models only request delivery and shutdown acknowledgements.
const mode = new URL(self.location.href).searchParams.get('mode') || 'normal';
let receivedRequests = 0;

function failClose() {
  self.postMessage({
    type: 'error',
    requestId: 0,
    error: {
      code: 'close_failed',
      message: 'Controlled worker cleanup failure.',
    },
  });
}

self.onmessage = (event) => {
  const message = event.data;
  if (message.type === 'init') {
    self.postMessage({ type: 'ready' });
    return;
  }
  if (message.type === 'request') {
    const order = receivedRequests++;
    if (mode !== 'silent-request') {
      self.postMessage({
        type: 'response',
        requestId: message.requestId,
        payload: `${order}:${message.operation}`,
      });
    }
    return;
  }
  if (message.type !== 'close') return;
  if (mode === 'close-error-ack' || mode === 'close-error-no-ack') {
    failClose();
  }
  if (mode === 'close-error-no-ack' || mode === 'close-no-ack') return;
  self.postMessage({ type: 'closed' });
  self.close();
};
