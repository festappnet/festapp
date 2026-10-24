// Keep in sync with festapp_core EmailAddress; shared/email/address-cases.json
// exercises both implementations. Syntax only, never a deliverability check.
export function isValidEmail(value) {
    if (typeof value !== 'string' || value.length > 254 || /\s/.test(value)) return false;
    const parts = value.split('@');
    if (parts.length !== 2) return false;
    const [local, host] = parts;
    const domain = host.split('.');
    return local.length > 0 && local.length <= 64 &&
        /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(local) &&
        !local.startsWith('.') && !local.endsWith('.') && !local.includes('..') &&
        domain.length >= 2 && domain.every(label =>
            /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(label)) &&
        !/^[0-9]+$/.test(domain.at(-1));
}
