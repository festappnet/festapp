// A real destination for crawlers, keyboard navigation and opening a new tab.
// Plain clicks may still show the existing occasion dialog.
export function getOccasionHref(occasion) {
    const form = occasion.features?.find(feature =>
        feature.code === 'form' && (feature.is_enabled === true || feature.isEnabled === true));
    if (form) {
        const data = { ...form, ...form.data };
        if (data.use_external_form === true && data.external_form_link) {
            try {
                const url = new URL(data.external_form_link);
                if (['https:', 'http:'].includes(url.protocol)) return url.href;
            } catch { /* Invalid external links fall back to the internal form. */ }
        }
        const slug = (occasion.form?.link || occasion.link || '').split('?')[0].replace(/^\/+|\/+$/g, '');
        return slug ? `/form/${encodeURIComponent(slug)}` : null;
    }
    const slug = (occasion.link || '').split('?')[0].replace(/^\/+|\/+$/g, '');
    return slug ? `/${encodeURIComponent(slug)}/event` : null;
}
