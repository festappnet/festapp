const VERSION_QUERY = 'FESTAPP_QUERY_BUILD_VERSION';
const ACTIVATE_WORKER = 'SKIP_WAITING';

function bounded(promise, timeoutMs, timers) {
    return new Promise((resolve) => {
        const timeout = timers.setTimeout(() => resolve(null), timeoutMs);
        Promise.resolve(promise).then(
            (value) => {
                timers.clearTimeout(timeout);
                resolve(value);
            },
            () => {
                timers.clearTimeout(timeout);
                resolve(null);
            },
        );
    });
}

async function queryWorkerVersion(worker, environment, timeoutMs) {
    if (!worker || !environment.MessageChannel) return null;
    return new Promise((resolve) => {
        const channel = new environment.MessageChannel();
        const timeout = environment.setTimeout(() => finish(null), timeoutMs);
        function finish(value) {
            environment.clearTimeout(timeout);
            channel.port1.close?.();
            resolve(value);
        }
        channel.port1.onmessage = (event) => finish(event.data?.version || null);
        try {
            worker.postMessage({ type: VERSION_QUERY }, [channel.port2]);
        } catch (_) {
            finish(null);
        }
    });
}

async function waitUntilInstalled(worker, environment, timeoutMs) {
    if (!worker) return null;
    if (worker.state === 'installed' || worker.state === 'activated') return worker;
    return new Promise((resolve) => {
        const timeout = environment.setTimeout(() => finish(null), timeoutMs);
        function finish(value) {
            environment.clearTimeout(timeout);
            worker.removeEventListener('statechange', onStateChange);
            resolve(value);
        }
        function onStateChange() {
            if (!['installed', 'activated', 'redundant'].includes(worker.state)) return;
            finish(worker.state === 'redundant' ? null : worker);
        }
        worker.addEventListener('statechange', onStateChange);
    });
}

async function activate(worker, serviceWorker, environment, timeoutMs) {
    if (worker.state === 'activated' && serviceWorker.controller === worker) return true;
    const controlled = new Promise((resolve) => {
        const timeout = environment.setTimeout(() => finish(false), timeoutMs);
        function finish(value) {
            environment.clearTimeout(timeout);
            serviceWorker.removeEventListener('controllerchange', onControllerChange);
            resolve(value);
        }
        function onControllerChange() {
            finish(serviceWorker.controller === worker);
        }
        serviceWorker.addEventListener('controllerchange', onControllerChange);
    });
    worker.postMessage(ACTIVATE_WORKER);
    return (await controlled) === true;
}

function browserEnvironment(overrides = {}) {
    const root = overrides.globalObject || globalThis;
    return {
        navigator: overrides.navigator || root.navigator,
        fetch: overrides.fetch || root.fetch.bind(root),
        MessageChannel: overrides.MessageChannel || root.MessageChannel,
        setTimeout: overrides.setTimeout || root.setTimeout.bind(root),
        clearTimeout: overrides.clearTimeout || root.clearTimeout.bind(root),
    };
}

/**
 * Establishes one coherent Flutter app-shell generation before leaving the web
 * client. It never removes offline state while offline and never touches auth
 * storage. If a stale worker cannot be upgraded promptly, unregistering that
 * registration makes the immediately following navigation use the network.
 */
export async function prepareFlutterRuntime(overrides = {}) {
    const environment = browserEnvironment(overrides);
    const serviceWorker = environment.navigator?.serviceWorker;
    if (!serviceWorker || environment.navigator.onLine === false) {
        return { strategy: 'preserved' };
    }

    const timeoutMs = overrides.timeoutMs || 2000;
    const response = await bounded(environment.fetch(
        `/festapp-version.json?handoff=${Date.now()}`,
        { cache: 'no-store', headers: { 'cache-control': 'no-cache' } },
    ), timeoutMs, environment);
    if (!response?.ok) return { strategy: 'network-version-unavailable' };
    const manifest = await bounded(response.json(), timeoutMs, environment);
    const expectedVersion = manifest?.version;
    if (!expectedVersion) return { strategy: 'network-version-unavailable' };

    const registration = await bounded(serviceWorker.getRegistration('/'), timeoutMs, environment);
    if (!registration) return { strategy: 'network', version: expectedVersion };

    await bounded(registration.update(), timeoutMs, environment);

    const activeVersion = await queryWorkerVersion(
        registration.active,
        environment,
        timeoutMs,
    );
    if (activeVersion === expectedVersion && serviceWorker.controller === registration.active) {
        return { strategy: 'current', version: expectedVersion };
    }

    const candidate = await waitUntilInstalled(
        registration.waiting || registration.installing,
        environment,
        timeoutMs,
    );
    if (candidate &&
        await queryWorkerVersion(candidate, environment, timeoutMs) === expectedVersion &&
        await activate(candidate, serviceWorker, environment, timeoutMs)) {
        return { strategy: 'activated', version: expectedVersion };
    }

    const unregistered = await bounded(registration.unregister(), timeoutMs, environment);
    return {
        strategy: unregistered === true ? 'stale-unregistered' : 'stale-unresolved',
        version: expectedVersion,
    };
}
