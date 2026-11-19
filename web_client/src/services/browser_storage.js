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
        keys(prefix) {
            const keys = new Set();
            try {
                const storage = resolve();
                for (let i = 0; i < (storage?.length ?? 0); i++) {
                    const key = storage.key(i);
                    if (key?.startsWith(prefix)) keys.add(key);
                }
            } catch { /* The current page can still recover its in-memory commands. */ }
            for (const [key, value] of memory) {
                if (!key.startsWith(prefix)) continue;
                if (value === null) keys.delete(key);
                else keys.add(key);
            }
            return [...keys];
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
