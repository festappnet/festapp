import { appHtmlPolicy } from './app_content_policy.g.js';

const blocks = new Set(appHtmlPolicy.blockElements);
const removed = new Set(appHtmlPolicy.removedProperties);

// DOM adapter for the shared app-content policy. Convert CSS emphasis to HTML
// before stripping theme overrides, so both display and the editor retain it.
export function normalizeAppElementStyles(node) {
    if (!node.style) return;
    const tags = [];
    const converted = new Set();
    for (const rule of appHtmlPolicy.emphasis) {
        let value = node.style.getPropertyValue(rule.property);
        if (rule.property === 'text-decoration-line' && !value) value = node.style.textDecoration;
        if (value.toLowerCase().split(/\s+/).some(token => rule.values.includes(token))) {
            tags.push(rule.tag);
            converted.add(rule.property);
            if (rule.property === 'text-decoration-line') converted.add('text-decoration');
        }
    }
    for (const property of [...removed, ...converted]) node.style.removeProperty(property);
    if (!node.style.cssText) node.removeAttribute('style');
    for (const attribute of appHtmlPolicy.removedAttributes) node.removeAttribute(attribute);
    wrapEmphasis(node, tags);
}

function wrapEmphasis(node, tags) {
    if (!tags.length) return;
    let run = [];
    const flush = () => {
        if (!run.length) return;
        let outer;
        let inner;
        for (const tag of tags) {
            const wrapper = node.ownerDocument.createElement(tag);
            if (inner) inner.append(wrapper);
            outer ??= wrapper;
            inner = wrapper;
        }
        node.insertBefore(outer, run[0]);
        inner.append(...run);
        run = [];
    };
    for (const child of [...node.childNodes]) {
        if (child.nodeType === 1 && blocks.has(child.localName)) {
            flush();
            wrapEmphasis(child, tags);
        } else run.push(child);
    }
    flush();
}
