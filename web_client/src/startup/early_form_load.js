import { publicFormLocation } from '../utils/public_form_location.js';

// Document-start optimization only: never a cache for subsequent navigation.
export class EarlyFormLoad {
    eligible(win, link = null) {
        return !win.__festappSaleOpeningLink && publicFormLocation(win.location, {entry: true}) &&
            (link === null || win.location.pathname.split('/')[2] === link);
    }

    start({win, service, load}) {
        if (this.started) return;
        this.started = true;
        try {
            if (!this.eligible(win) || !service.isCanonicalBackend) return;
            const link = win.location.pathname.split('/')[2];
            const client = service.getClient();
            const entry = this.entry = {link, client, startedAt: Date.now()};
            entry.promise = (async () => {
                if (!await service.isAnonymousClient(client) || !this.eligible(win, link)) return null;
                return await load(link);
            })().catch(() => null);
        } catch { this.entry = null; }
    }

    consume(link, {win, service, disabled = false}) {
        const entry = this.entry;
        this.entry = null; // Even a mismatch or failed attempt is consumed once.
        try {
            if (!entry || disabled || entry.link !== link || !this.eligible(win, link) ||
                !service.isCanonicalBackend || service.getClient() !== entry.client) return null;
            return this.resolve(entry, link, win, service);
        } catch { return null; }
    }

    async resolve(entry, link, win, service) {
        try {
            const model = await entry.promise;
            if (!await service.isAnonymousClient(entry.client) || !this.eligible(win, link) ||
                service.getClient() !== entry.client) return null;
            const now = Date.now();
            // Request start is a conservative lower bound, not the server snapshot
            // time. A crossed window requires the existing fresh-RPC fallback.
            if (now < entry.startedAt || [model?.startTime, model?.endTime].some(boundary => {
                const at = boundary instanceof Date ? boundary.getTime() : NaN;
                return entry.startedAt <= at && at <= now;
            })) return null;
            return model;
        } catch { return null; }
    }
}

export const earlyFormLoad = new EarlyFormLoad();
