// Loaded only by the explicitly launched disposable Vite fixture with qaStorage.
const result = {};
for (const name of ['localStorage', 'sessionStorage']) {
    const key = 'festapp-qa-storage-probe';
    try {
        const storage = window[name];
        storage.setItem(key, 'probe');
        result[name] = storage.getItem(key) === 'probe' ? 'available' : 'write-not-retained';
        storage.removeItem(key);
    } catch (error) {
        result[name] = error.name;
    }
}
// Counts completed ResourceTiming entries, not every attempted network request.
const report = () => {
    const resources = performance.getEntriesByType('resource');
    result.holdRequests = resources.filter(entry => entry.name.includes('/rest/v1/rpc/select_spot')).length;
    result.orderRequests = resources.filter(entry => entry.name.includes('/functions/v1/send-ticket-order')).length;
    window.parent.postMessage({namespace:'festapp-qa-storage', result}, 'http://localhost:' + location.port);
};
const observer = new PerformanceObserver(list => {
    if (list.getEntries().some(entry => entry.name.includes('/rest/v1/rpc/') || entry.name.includes('/functions/v1/send-ticket-order'))) report();
});
observer.observe({type:'resource', buffered:true});
report();
