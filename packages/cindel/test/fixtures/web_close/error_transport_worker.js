// Controlled operation failures exercise the real Worker transport without
// enabling fault-injection commands in the production runtime.
self.onmessage = ({ data }) => {
  if (data.type === 'init') {
    self.postMessage({ type: 'ready' });
  } else if (data.type === 'close') {
    self.postMessage({ type: 'closed' });
    self.close();
  } else if (data.type === 'request') {
    if (data.operation === 'healthy') {
      self.postMessage({ type: 'response', requestId: data.requestId, payload: 'ok' });
    } else {
      self.postMessage({ type: 'error', requestId: data.requestId,
        error: { code: 'operation_failed', message: `controlled ${data.operation} failure` } });
    }
  }
};
