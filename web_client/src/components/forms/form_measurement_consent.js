// The same saved-choice adapter is used by standalone Klaro and embedding hosts.
// A changed draft is never a grant. Renewal preserves the transport's epoch.
export function bindKlaroConsent(manager, setConsent, {win = window, interval = 20000} = {}) {
    let disposed = false;
    const sync = () => {
        let granted = false;
        try {
            granted = manager.confirmed === true && manager.savedConsents?.analytics === true &&
                manager.getConsent('analytics') === true && !win.document.hidden;
        } catch { /* Missing/broken CMP remains denied. */ }
        if (!disposed) setConsent(granted);
    };
    const watcher = {update: sync};
    manager.watch(watcher);
    win.document.addEventListener('visibilitychange', sync);
    const timer = win.setInterval(sync, interval);
    sync();
    return () => {
        disposed = true;
        win.clearInterval(timer);
        manager.unwatch(watcher);
        win.document.removeEventListener('visibilitychange', sync);
        setConsent(false);
    };
}
