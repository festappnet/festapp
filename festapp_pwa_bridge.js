(function initFestappPwaBridge() {
  const timeoutMs = 3000;

  function workerRequest(type) {
    return new Promise(function(resolve) {
      const worker = navigator.serviceWorker?.controller;
      if (!worker || typeof MessageChannel === 'undefined') {
        resolve({ blocker: 'unsupported-browser', partial: true });
        return;
      }
      const channel = new MessageChannel();
      const timeout = window.setTimeout(function() {
        resolve({ blocker: 'worker-timeout', partial: true });
      }, timeoutMs);
      channel.port1.onmessage = function(event) {
        window.clearTimeout(timeout);
        resolve(event.data || { blocker: 'invalid-worker-response', partial: true });
      };
      try {
        worker.postMessage({ type: type }, [channel.port2]);
      } catch (_) {
        window.clearTimeout(timeout);
        resolve({ blocker: 'worker-message-error', partial: true });
      }
    });
  }

  async function inspect() {
    let estimate = {};
    try {
      if (navigator.storage?.estimate) {
        const raw = await navigator.storage.estimate();
        estimate = {
          usage: Number.isFinite(raw.usage) ? raw.usage : null,
          quota: Number.isFinite(raw.quota) ? raw.quota : null,
          usageDetails: raw.usageDetails && typeof raw.usageDetails === 'object'
            ? Object.fromEntries(Object.entries(raw.usageDetails)
              .filter((entry) => Number.isFinite(entry[1])))
            : null,
        };
      }
    } catch (_) {}
    const shells = await workerRequest('FESTAPP_INSPECT_SHELLS');
    return { estimate: estimate, shells: shells };
  }

  function callback(promise, resolve, reject) {
    promise.then(resolve).catch(function(error) {
      reject(String(error?.message || error));
    });
  }

  window.festappInspectPwaStorage = function(resolve, reject) {
    callback(inspect(), resolve, reject);
  };
  window.festappPruneUnusedShells = function(resolve, reject) {
    callback(workerRequest('FESTAPP_PRUNE_UNUSED_SHELLS'), resolve, reject);
  };
})();
