// The same saved-choice adapter is used by standalone Klaro and embedding hosts.
// It only reports the saved choice; a changed draft is never reported as a grant.
export function bindKlaroConsent(manager, setConsent) {
    let disposed = false;
    const saved = service => manager.confirmed === true && manager.savedConsents?.[service] === true &&
        manager.getConsent(service) === true;
    const sync = () => {
        const granted = {analytics: false, marketing: false};
        try {
            granted.analytics = saved('analytics');
            // Optional: a host manager without this service grants analytics only.
            granted.marketing = saved('marketing');
        } catch { granted.analytics = granted.marketing = false; /* Missing/broken CMP remains denied. */ }
        if (!disposed) setConsent(granted);
    };
    const watcher = {update: sync};
    manager.watch(watcher);
    sync();
    return () => {
        disposed = true;
        manager.unwatch(watcher);
        setConsent(false);
    };
}
