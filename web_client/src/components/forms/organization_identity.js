/** Only the authorized projection is accepted; no guessed identity or status. */
export function parseOrganizationIdentity(value) {
    const text = v => typeof v === 'string' && v.trim().length > 0;
    if (!value || !Number.isSafeInteger(value.unitId) || value.unitId <= 0 ||
        !Number.isSafeInteger(value.revision) || value.revision <= 0 ||
        !['legalName', 'countryCode', 'registrationNumber', 'contactEmail'].every(k => text(value[k])) ||
        !/^[A-Z]{2}$/.test(value.countryCode) || !value.address ||
        !['street', 'city', 'postalCode'].every(k => text(value.address[k])) ||
        ['vatId', 'phone', 'website'].some(k => value[k] != null && typeof value[k] !== 'string')) return null;
    if (value.verifiedAt != null && (typeof value.verifiedAt !== 'string' || !Number.isFinite(Date.parse(value.verifiedAt)))) return null;
    return Object.freeze(Object.fromEntries([
        ...['unitId','revision','legalName','countryCode','registrationNumber','contactEmail','vatId','phone','website','verifiedAt'].map(k => [k, value[k] ?? null]),
        ['address', Object.freeze(Object.fromEntries(['street','city','postalCode'].map(k => [k,value.address[k]])))],
    ]));
}
