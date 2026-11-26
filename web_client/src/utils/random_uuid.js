export function randomUuid(crypto = globalThis.crypto) {
    if (typeof crypto?.randomUUID === 'function') return crypto.randomUUID();
    if (globalThis.isSecureContext === false) {
        throw new Error('A secure context is required to generate a random UUID');
    }

    const bytes = crypto.getRandomValues(new Uint8Array(16));
    // UUID v4 version and variant bits, as in Web Crypto's randomUUID.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
    return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
}
