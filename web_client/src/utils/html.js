import createDOMPurify from 'dompurify';
import * as cssTree from 'css-tree';

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

// A separate DOMPurify instance keeps SVG hooks out of the rich HTML contract.
const svgPurifiers = new WeakMap();
const SVG_NS = 'http://www.w3.org/2000/svg';
const LOCAL_REFERENCE = /^#[a-zA-Z_][\w:.-]*$/;
const GRAPHIC_PROPERTIES = new Set([
    'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width', 'stroke-opacity',
    'stroke-linecap', 'stroke-linejoin', 'stroke-dasharray', 'stroke-dashoffset',
    'stroke-miterlimit', 'opacity', 'color', 'stop-color', 'stop-opacity',
    'font-family', 'font-size', 'font-weight', 'font-style', 'text-anchor',
    'dominant-baseline', 'letter-spacing', 'word-spacing', 'display', 'visibility',
    'clip-path', 'clip-rule', 'mask', 'filter', 'paint-order', 'vector-effect',
]);

function safeGraphicValue(ast) {
    let safe = true;
    cssTree.walk(ast, node => {
        if (node.type === 'Raw' || (node.type === 'Url' && !LOCAL_REFERENCE.test(node.value)) ||
            (node.type === 'Function' && ['expression', 'var', 'env'].includes(node.name.toLowerCase()))) safe = false;
    });
    return safe;
}

function sanitizeGraphicCss(source, context) {
    try {
        const ast = cssTree.parse(source, { context });
        cssTree.walk(ast, {
            enter(node, item, list) {
                if (node.type === 'Atrule' || node.type === 'Raw' ||
                    (node.type === 'Declaration' && (!GRAPHIC_PROPERTIES.has(node.property.toLowerCase()) || !safeGraphicValue(node.value)))) {
                    if (list) list.remove(item);
                    return cssTree.walk.skip;
                }
            },
        });
        return cssTree.generate(ast);
    } catch { return ''; }
}

/** Static SVG only. Parse XML first so malformed input fails closed. */
export function sanitizeSvg(source) {
    const win = globalThis.document?.defaultView ?? globalThis.window;
    if (!source || !win) return new SafeHtml('');
    const doc = new win.DOMParser().parseFromString(String(source), 'image/svg+xml');
    if (doc.querySelector('parsererror') || doc.documentElement.localName !== 'svg' ||
        (doc.documentElement.namespaceURI && doc.documentElement.namespaceURI !== SVG_NS) || doc.doctype) return new SafeHtml('');
    doc.documentElement.setAttribute('xmlns', SVG_NS);
    let purifier = svgPurifiers.get(win);
    if (!purifier) {
        purifier = createDOMPurify(win);
        if (!purifier.isSupported) throw new Error('SVG sanitization requires a supported browser DOM');
        purifier.addHook('uponSanitizeAttribute', (node, data) => {
            const name = data.attrName.toLowerCase();
            if (name === 'style') data.attrValue = sanitizeGraphicCss(data.attrValue, 'declarationList');
            else if (name === 'href' || name === 'xlink:href') {
                const value = data.attrValue.trim();
                // Local <use> and gradients are safe; external references are
                // limited to image elements, which are non-navigable resources.
                const imageUrl = node.localName === 'image' && /^https?:\/\//i.test(value);
                if (!LOCAL_REFERENCE.test(value) && !imageUrl) data.keepAttr = false;
            } else if (['fill', 'stroke', 'clip-path', 'mask', 'filter', 'cursor'].includes(name)) {
                try {
                    if (!safeGraphicValue(cssTree.parse(data.attrValue, { context: 'value' }))) data.keepAttr = false;
                } catch { data.keepAttr = false; }
            }
        });
        purifier.addHook('afterSanitizeElements', node => {
            if (node.localName === 'style') node.textContent = sanitizeGraphicCss(node.textContent, 'stylesheet');
        });
        svgPurifiers.set(win, purifier);
    }
    return new SafeHtml(purifier.sanitize(new win.XMLSerializer().serializeToString(doc.documentElement), {
        USE_PROFILES: { svg: true, svgFilters: true },
        NAMESPACE: SVG_NS, ADD_TAGS: ['use'], ADD_ATTR: ['href', 'xlink:href'],
        FORBID_TAGS: ['script', 'foreignObject', 'a', 'animate', 'animateMotion', 'animateTransform', 'set', 'discard'],
        FORBID_ATTR: ['xml:base'], ALLOW_DATA_ATTR: false,
    }));
}
