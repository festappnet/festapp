import {pageContext} from '../runtime/page_context.js';
// Explicit public presentation context. Never changes the checkout principal.
export function isEmbed(location = globalThis.location ?? globalThis.window?.location) {
    return pageContext(location) === 'public-embed';
}
export function applyEmbedContext(doc = document, location = globalThis.location ?? globalThis.window?.location) {
    if (isEmbed(location)) doc.documentElement.classList.add('festapp-embed');
}
