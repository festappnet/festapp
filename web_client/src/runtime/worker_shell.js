// Readiness belongs to a runtime shell, not merely to an installed worker.
export function queryWorkerBuildVersion(worker, runtime, win = window, timeoutMs = runtime === 'flutter' ? 120000 : 3000) {
    const Channel = win.MessageChannel ?? globalThis.MessageChannel;
    if (!worker || !Channel) return Promise.resolve(null);
    return new Promise(resolve => {
        const channel = new Channel();
        let finished = false;
        const timeout = win.setTimeout(() => finish(null), timeoutMs);
        function finish(version) {
            if (finished) return;
            finished = true; win.clearTimeout(timeout); channel.port1.close?.(); resolve(version);
        }
        channel.port1.onmessage = event => finish(event.data?.version || null);
        try { worker.postMessage({type:'FESTAPP_QUERY_BUILD_VERSION', runtime}, [channel.port2]); }
        catch { finish(null); }
    });
}
