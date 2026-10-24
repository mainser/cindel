// Imported before the real Worker installs its message handler, only by the
// disposable browser test runner. All successful requests use the real engine.
let failNextRevision = false;
self.addEventListener('message', (event) => {
  const message = event.data;
  if (message.type !== 'request') return;
  if (message.operation === 'open') {
    failNextRevision = message.payload.dbName.startsWith('cindel-watch-error-');
  }
  if (message.operation === 'collectionRevision' && failNextRevision) {
    failNextRevision = false;
    event.stopImmediatePropagation();
    self.postMessage({
      type: 'error',
      requestId: message.requestId,
      error: {
        code: 'operation_failed',
        message: 'controlled watcher revision failure',
      },
    });
  }
});
