// Server port of lib/components/forms/views/form_embed_code.dart. Both
// implementations are checked against packages/festapp_contracts/form-embed-code-cases.json.
import { readFileSync } from 'node:fs';
import { OperationError } from '../errors.mjs';
// The administration dialog uses these translated texts for its current language.
// They are read on first use: a missing file or key fails only the embed tool.
export const EMBED_LANGUAGES = Object.freeze(['cs', 'de', 'en', 'es', 'pl', 'sk', 'uk']);
const labels = new Map();
export function embedLabels(language) {
    if (!labels.has(language)) {
        let strings;
        try {
            strings = EMBED_LANGUAGES.includes(language)
                ? JSON.parse(readFileSync(new URL(`../../../../assets/translations/${language}.json`, import.meta.url), 'utf8')).FeatureFormSettings : null;
        } catch { strings = null; }
        if (typeof strings?.embedTitle !== 'string' || !strings.embedTitle || typeof strings.embedFallback !== 'string' || !strings.embedFallback)
            throw new OperationError('EMBED_LABELS_UNAVAILABLE');
        labels.set(language, Object.freeze({ title: strings.embedTitle, fallbackLabel: strings.embedFallback }));
    }
    return labels.get(language);
}
const ATTRIBUTE = { '&': '&amp;', '"': '&quot;', '<': '&lt;', '>': '&gt;' };
const ELEMENT = { ...ATTRIBUTE, "'": '&#39;', '/': '&#47;' };
// Dart HtmlEscape(HtmlEscapeMode.attribute) and the default HtmlEscape().
const attribute = value => value.replace(/[&"<>]/g, ch => ATTRIBUTE[ch]);
const text = value => value.replace(/[&"'<>/]/g, ch => ELEMENT[ch]);
const own = (value, key) => Object.hasOwn(value, key) ? value[key] : undefined;
const object = value => typeof value === 'object' && value !== null && !Array.isArray(value);
const positive = value => Number.isInteger(value) && value > 0 && value <= Number.MAX_SAFE_INTEGER;
export const CONSENT_PROVIDERS = Object.freeze(['complianz', 'cookiebot', 'cookieconsent', 'wix']);

// JSON.stringify moves integer-like keys first and formats non-integers
// differently from Dart. The server export contains neither, so fail closed
// rather than emit an attribute that differs from the administration dialog.
function portable(value) {
    if (typeof value === 'number') return Number.isSafeInteger(value) && !Object.is(value, -0);
    if (Array.isArray(value)) return value.every(portable);
    if (object(value)) return Object.keys(value).every(key => !/^(0|[1-9][0-9]*)$/.test(key)) && Object.values(value).every(portable);
    return true;
}
function exactOrigin(site) {
    try {
        const url = new URL(site);
        return url.protocol === 'https:' && url.origin === site;
    } catch { return false; }
}

/** Envelope validation only. Provider and current approval stay with SQL/runtime. */
export function parseFormConsentExport(raw, serviceOrigin) {
    if (typeof raw !== 'string' || raw.length === 0 || raw.length > 16384) return null;
    let v;
    try { v = JSON.parse(raw); } catch { return null; }
    if (!object(v) || own(v, 'schemaVersion') !== 1 || own(v, 'serviceOrigin') !== serviceOrigin) return null;
    const b = own(v, 'binding'), c = own(v, 'providerConfig'), site = own(v, 'websiteOrigin');
    // Integer checks follow the web administration, where JSON numbers are JS numbers.
    if (typeof site !== 'string' || !exactOrigin(site) || !object(b) ||
        typeof own(b, 'id') !== 'string' || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(own(b, 'id')) ||
        !positive(own(b, 'version')) || !object(c) || !CONSENT_PROVIDERS.includes(own(c, 'provider')) ||
        own(c, 'origin') !== site || !positive(own(c, 'organization')) || !positive(own(c, 'unit')) ||
        typeof own(c, 'consentRevision') !== 'string' || !/^[a-f0-9]{32}$/.test(own(c, 'consentRevision')) ||
        !portable(v)) return null;
    return v;
}

// message matches the Dart ArgumentError name; reason distinguishes a service
// address mismatch (organization DEFAULT_URL vs tenant WEB_LINK) from other rejects.
export class EmbedCodeError extends Error {
    constructor(name, reason = name) { super(name); this.reason = reason; }
}

/** Only call with the independently saved slug, never an editor draft. */
export function formEmbedCode({ tenantUrl, savedLink, title, fallbackLabel, automatic = true, hostDataLayer = true, consentExport = null, consentScope = null }) {
    if (!savedLink) throw new EmbedCodeError('savedLink');
    const base = tenantUrl.replace(/\/+$/, '');
    const imported = consentExport == null ? null : parseFormConsentExport(consentExport, base);
    if (consentExport != null && imported == null) {
        let service = null;
        try { service = JSON.parse(consentExport)?.serviceOrigin; } catch { service = null; }
        const mismatch = typeof service === 'string' && service !== base && parseFormConsentExport(consentExport, service) != null;
        throw new EmbedCodeError('consentExport', mismatch ? 'serviceOrigin' : 'consentExport');
    }
    if (imported != null && consentScope != null &&
        (imported.providerConfig.organization !== consentScope.organizationId || imported.providerConfig.unit !== consentScope.unitId)) {
        throw new EmbedCodeError('consentExport');
    }
    const publicUrl = `${base}/form/${encodeURIComponent(savedLink)}`;
    const marker = ` data-festapp-embed${automatic ? '' : ' data-festapp-height="fixed"'}${hostDataLayer ? ' data-festapp-datalayer' : ''}`;
    const frame = `<iframe${marker} src="${attribute(`${publicUrl}?embed=1`)}" title="${attribute(title)}" ` +
        'allow="clipboard-write" height="800" ' +
        'style="display:block;width:100%;max-width:100%;border:0;color-scheme:light dark" loading="lazy"></iframe>';
    const fallback = `<a href="${attribute(publicUrl)}" target="_blank" ` +
        `${imported == null ? 'rel="noopener noreferrer"' : 'data-festapp-consent-link'}>${text(fallbackLabel)}</a>`;
    const provider = imported?.providerConfig.provider;
    const importAttribute = imported == null ? '' : ` data-festapp-consent="${attribute(JSON.stringify(imported))}"` +
        (provider === 'cookiebot' ? ' data-cookieconsent="ignore"' : '') +
        (provider === 'complianz' ? ' data-category="functional"' : '');
    const script = `\n<script src="${attribute(`${base}/embed.js`)}"${importAttribute} defer></script>`;
    return `<div data-festapp-embed-host>\n${frame}\n${fallback}\n</div>${script}`;
}
