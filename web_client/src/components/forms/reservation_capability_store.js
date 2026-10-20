import { createBrowserStorage } from '../../services/browser_storage.js';

const sessionStorage = createBrowserStorage(() => globalThis.sessionStorage);

/** Only a hold capability survives reload. Seat states always come from SQL. */
export class ReservationCapabilityStore {
    constructor(backend, formKey, {storage = sessionStorage, now = () => Date.now()} = {}) {
        this.storage = storage;
        this.now = now;
        this.key = `festapp:hold-capability:${JSON.stringify([backend, formKey])}`;
        this.raw = null;
    }
    restore() {
        const raw = this.storage.getItem(this.key);
        this.raw = raw;
        if (!raw) return null;
        try {
            const capability = JSON.parse(raw);
            if (typeof capability.secret !== 'string' || !capability.secret || typeof capability.generation !== 'string' ||
                (capability.expiresAt != null && (!Number.isFinite(Date.parse(capability.expiresAt)) || Date.parse(capability.expiresAt) <= this.now()))) {
                this.clear(capability); return null;
            }
            return capability;
        } catch { this.storage.removeItem(this.key); this.raw = null; return null; }
    }
    save(secret, expiresAt = null) {
        // An obsolete form instance cannot overwrite a newer capability.
        if (this.storage.getItem(this.key) !== this.raw) return null;
        const capability = {secret, expiresAt, generation: crypto.randomUUID()};
        this.raw = JSON.stringify(capability);
        this.storage.setItem(this.key, this.raw);
        return capability;
    }
    clear(capability) {
        if (!capability || this.storage.getItem(this.key) !== JSON.stringify(capability)) return false;
        this.storage.removeItem(this.key);
        this.raw = null;
        return true;
    }
}
