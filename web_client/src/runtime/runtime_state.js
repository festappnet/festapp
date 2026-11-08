import {queryWorkerBuildVersion} from './worker_shell.js';
import {pageContext} from './page_context.js';
import {allowUpdate} from './update_policy.js';
// Installed before paint and reused by the standalone recovery controller.
export function installRuntimeState(win) {
    if (win.FestappRuntime) return win.FestappRuntime;
    let phase = win.__FESTAPP_APP_READY__ === true ? 'ready' : 'starting';
    let retrying = false;
    let navigating = false;
    let draftProtected = false;
    const runtime = {
        async prepareFlutterOffline(registration) {
            for (const worker of [...new Set([registration.waiting, registration.installing, registration.active])]) {
                if (worker && await queryWorkerBuildVersion(worker, 'flutter', win) === win.__FESTAPP_BUILD_VERSION__) return true;
            }
            throw new Error('Flutter offline shell is not ready for this build');
        },
        get retrying() { return retrying; },
        protectDraft() { draftProtected = true; },
        allowed(reason) { return !navigating && allowUpdate(reason, {context:pageContext(win.location), phase:runtime.phase,
            publicWeb:win.__FESTAPP_CLIENT_RUNTIME__ === 'web', draftProtected}); },
        navigate(reason, effect) {
            if (!runtime.allowed(reason)) return false;
            navigating = true;
            effect();
            return true;
        },
        get phase() { return win.__FESTAPP_APP_READY__ === true ? 'ready' : phase; },
        markReady() {
            if (runtime.phase === 'ready') return false;
            phase = 'ready';
            win.__FESTAPP_APP_READY__ = true;
            delete win.__FESTAPP_WEB_STARTUP_FAILURE__;
            win.dispatchEvent(new win.Event('festapp-app-ready'));
            return true;
        },
        fail(reason) {
            if (runtime.phase === 'ready') return false;
            phase = 'failed';
            win.__FESTAPP_WEB_STARTUP_FAILURE__ = reason;
            return true;
        },
        async retry(prepare, navigate) {
            if (retrying || !runtime.allowed('manual-startup')) return false;
            retrying = true;
            try {
                await prepare();
                return runtime.navigate('manual-startup', navigate);
            } finally { retrying = false; }
        }
    };
    win.FestappRuntime = runtime;
    // Native forms include the sale-opening email field. Synthetic initialization
    // does not protect an untouched page; custom form fields use protectDraft().
    for (const type of ['beforeinput', 'input', 'change', 'submit']) {
        win.addEventListener(type, event => {
            if (event.isTrusted) runtime.protectDraft();
        }, true);
    }
    return runtime;
}
