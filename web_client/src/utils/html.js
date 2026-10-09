import createDOMPurify from 'dompurify';

/**
 * Lightweight HTML Tagged Template Literal Helper
 * 
 * Usage:
 * const content = html`<div class="user">${userName}</div>`;
 * 
 * Features:
 * - Automatically sanitizes interpolated strings to prevent XSS.
 * - Joins arrays automatically.
 * - Returns a SafeHtml object that can be nested in other html templates without re-escaping.
 * - Use .toString() or implicit string conversion to get the final HTML string.
 */

export class SafeHtml {
    constructor(value) {
        this.value = value;
    }
    toString() {
        return this.value;
    }
}

export function html(strings, ...values) {
    let result = '';
    
    strings.forEach((string, i) => {
        result += string;
        
        if (i < values.length) {
            const val = values[i];
            result += sanitize(val);
        }
    });

    return new SafeHtml(result);
}

/**
 * Marks a string as "Safe" (Raw HTML), bypassing sanitization.
 * Use with caution: html`<div>${unsafe(rawHtml)}</div>`
 */
export function unsafe(str) {
    return new SafeHtml(str);
}

// Keep the rich-description editor's formatting, images and links, but exclude
// active content and form controls. URL validation is owned by DOMPurify.
const RICH_HTML_CONFIG = {
    ALLOWED_TAGS: [
        'p', 'br', 'b', 'i', 'u', 'strong', 'em', 'a', 'img', 'div', 'span',
        'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li',
        'table', 'tr', 'td', 'th', 'thead', 'tbody', 'tfoot', 'caption',
        'blockquote', 'hr', 'sub', 'sup', 'figure', 'figcaption',
        's', 'strike', 'del', 'ins', 'pre', 'code',
    ],
    ALLOWED_ATTR: [
        'href', 'src', 'alt', 'class', 'style', 'width', 'height', 'target',
        'rel', 'title', 'fetchpriority', 'loading', 'decoding', 'colspan', 'rowspan',
    ],
    ALLOW_DATA_ATTR: false,
    ALLOW_ARIA_ATTR: false,
};
const purifiers = new WeakMap();

/** Sanitize rich HTML before insertion. Returns a SafeHtml for html templates. */
export function sanitizeHtml(str) {
    if (!str) return new SafeHtml('');

    // Initialize against the rendering document, including isolated test DOMs.
    const renderingWindow = globalThis.document?.defaultView ?? globalThis.window;
    let purifier = purifiers.get(renderingWindow);
    if (!purifier) {
        purifier = createDOMPurify(renderingWindow);
        if (!purifier.isSupported) {
            throw new Error('HTML sanitization requires a supported browser DOM');
        }
        purifiers.set(renderingWindow, purifier);
    }
    return new SafeHtml(purifier.sanitize(String(str), RICH_HTML_CONFIG));
}

/**
 * Sanitizes a value for safe insertion into HTML.
 */
function sanitize(val) {
    if (val === null || val === undefined) {
        return '';
    }
    
    if (val instanceof SafeHtml) {
        return val.value;
    }

    if (Array.isArray(val)) {
        return val.map(sanitize).join('');
    }
    
    // If it's a number/boolean, safe to stringify
    if (typeof val === 'number' || typeof val === 'boolean') {
        return String(val);
    }

    // Basic escaping
    return String(val)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
