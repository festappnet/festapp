// Persistent storage is optional in embedded browsers. Keep failed writes and
// removals consistent for the lifetime of this page without changing globals.
export function createBrowserStorage(resolve = () => globalThis.localStorage) {
    const memory = new Map();
    return {
        getItem(key) {
            if (memory.has(key)) return memory.get(key);
            try { return resolve()?.getItem(key) ?? null; }
            catch { return null; }
        },
        setItem(key, value) {
            value = String(value);
            try {
                const storage = resolve();
                if (!storage) throw new Error('Browser storage unavailable');
                storage.setItem(key, value);
                memory.delete(key);
            } catch { memory.set(key, value); }
        },
        removeItem(key) {
            try {
                const storage = resolve();
                if (!storage) throw new Error('Browser storage unavailable');
                storage.removeItem(key);
                memory.delete(key);
            } catch { memory.set(key, null); }
        },
    };
}

export const browserStorage = createBrowserStorage();
