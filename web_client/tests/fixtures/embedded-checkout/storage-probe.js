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
window.parent.postMessage({namespace:'festapp-qa-storage', result}, 'http://localhost:' + location.port);
