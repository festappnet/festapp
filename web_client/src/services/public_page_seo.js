// Shared by the edge HTML response and the hydrated public form.
export function publicSeoText(value) {
    const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '\u2013', mdash: '\u2014', hellip: '\u2026', copy: '\u00a9' };
    return String(value || '')
        .replace(/<(script|style|template)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
        .replace(/<[^>]*>/g, ' ')
        .replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (match, key) => {
            if (!key.startsWith('#')) return entities[key.toLowerCase()] ?? match;
            const code = key[1].toLowerCase() === 'x' ? parseInt(key.slice(2), 16) : Number(key.slice(1));
            return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : '\ufffd';
        }).replace(/\s+/g, ' ').trim();
}

export function publicPageSeo(data, { origin, siteName, path, kind = 'form' }) {
    const link = kind === 'form' ? data.form_link : data.occasion_link;
    const canonicalPath = link ? (kind === 'form' ? '/form/' + encodeURIComponent(link) : '/' + encodeURIComponent(link) + '/event') : path.replace(/\/$/, '');
    const canonical = new URL(canonicalPath, origin).href;
    const formTitle = kind === 'form' ? data.form_title : null;
    const occasionTitle = data.title;
    // Form labels such as "Registration" are shared across unrelated events.
    // Keep the event identity in both the server HTML and hydrated metadata,
    // while retaining specific form names (for example dinner or VIP tickets).
    const title = occasionTitle && formTitle && !formTitle.toLowerCase().includes(occasionTitle.toLowerCase())
        ? `${occasionTitle} - ${formTitle}`
        : formTitle || occasionTitle || siteName;
    const description = publicSeoText((kind === 'form' ? data.form_description : null) || data.description)
        || 'Informace o akci a vstupenkách.';
    let image = new URL('/android-chrome-512x512.png', origin).href;
    if (typeof data.image === 'string' && data.image.trim()) {
        try {
            const candidate = new URL(data.image, 'https://img.festapp.net/');
            if (/^https?:$/.test(candidate.protocol)) image = candidate.href;
        } catch { /* Invalid stored images use the site icon. */ }
    }
    return { title: `${title} - ${siteName}`, name: title, description: description.length > 300 ? description.slice(0, 297) + '...' : description, image, canonical };
}
