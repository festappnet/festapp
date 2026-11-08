import {envelope, namespace, protocol, validMessage} from './protocol.js';

// No DOM effects. The host dispatches one listener across its per-frame channels.
export class EmbedChannel {
    constructor({peer, destination, origin, instance, current = () => true}) {
        Object.assign(this, {peer, destination, origin, instance, current});
        this.closed = false;
    }
    receive(event) {
        if (this.closed || !this.current() || event.source !== this.peer() || !/^https?:\/\//.test(event.origin) ||
            !validMessage(event.data, this.destination)) return null;
        const data = event.data;
        if (this.origin && (event.origin !== this.origin || (data.type !== 'ready' && data.instance !== this.instance))) return null;
        if (!this.origin) {
            if (this.destination !== 'child' || data.type !== 'init') return null;
            this.origin = event.origin; this.instance = data.instance;
        }
        return data;
    }
    send(type, values) {
        if (!this.closed && this.origin && this.current()) this.peer()?.postMessage(envelope(type, this.instance, values), this.origin);
    }
    announce() {
        if (!this.closed && !this.origin) this.peer()?.postMessage({namespace, protocol, type:'ready'}, '*');
    }
    destroy() { this.closed = true; }
}
