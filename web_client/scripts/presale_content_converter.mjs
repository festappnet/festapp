import {parseFragment, serialize} from 'parse5';

export const timerSlot = '<div class="html-editor-block form-countdown"></div>';
export const emailSlot = '<div class="html-editor-block form-sale-opening-notification"></div>';
const classes = n => (n.attrs?.find(a => a.name === 'class')?.value ?? '').split(/\s+/u);
function walk(root) { return (root.childNodes ?? []).flatMap(n => [n, ...walk(n)]); }
function remove(node) { const nodes = node.parentNode.childNodes; nodes.splice(nodes.indexOf(node), 1); }
function append(root, html) { const fragment = parseFragment(html); for (const node of fragment.childNodes) { node.parentNode = root; root.childNodes.push(node); } }
export function inertLegacyHtml(html) {
    const root = parseFragment(html ?? '');
    for (const node of walk(root)) {
        if (!node.attrs) continue;
        const names = classes(node).filter(c => !['html-editor-block','form-countdown','form-sale-opening-notification','form-presale-system-title'].includes(c));
        node.attrs = node.attrs.filter(a => a.name !== 'class');
        if (names.length) node.attrs.push({name:'class',value:names.join(' ')});
    }
    return serialize(root);
}
// Pure conversion: no clocks, writes or hidden fallback. The system paragraph
// retains a tenant-localized fallback for released readers. Current readers
// localize its named marker in the visitor's locale, without authored dates.
export function convertLegacyPresale(data, {registrationStart = 'Registration opens'} = {}) {
    if (Array.isArray(data)) {
        data = data.filter(v => v != null).reduce((result, item) => {
            if (typeof item !== 'object' || Array.isArray(item)) throw new Error('Invalid legacy metadata');
            return {...result,...item};
        },{});
    }
    const schedule = data?.schedule ?? {};
    const primary = schedule.countdown_title;
    const timer = schedule.enable_countdown === true;
    const reachable = timer || Boolean(primary) || data?.sale_opening_notifications?.enabled === true;
    const root = parseFragment(primary ?? '');
    if (primary == null && timer) {
        const p = parseFragment('<p class="form-presale-system-title"></p>').childNodes[0];
        p.childNodes = [{nodeName:'#text',value:registrationStart,parentNode:p}];
        p.parentNode = root; root.childNodes.push(p);
    }
    for (const type of ['form-countdown','form-sale-opening-notification']) {
        const slots = walk(root).filter(n => n.tagName === 'div' && classes(n).includes('html-editor-block') && classes(n).includes(type));
        for (const duplicate of slots.slice(1)) remove(duplicate);
        if (type === 'form-countdown' && timer && !slots.length) append(root, timerSlot);
    }
    if (reachable && schedule.show_before_start_message === true && schedule.before_start_message) {
        const wrapper = parseFragment('<div class="form-presale-legacy-secondary" style="text-align:left;font-size:18px;margin:12px;line-height:1.5"></div>').childNodes[0];
        append(wrapper, inertLegacyHtml(schedule.before_start_message));
        wrapper.parentNode = root; root.childNodes.push(wrapper);
    }
    const html = serialize(root);
    const metadata = structuredClone(data ?? {});
    metadata.schedule = {...schedule, countdown_title: html};
    delete metadata.schedule.before_start_message; delete metadata.schedule.show_before_start_message;
    metadata.design = {...metadata.design, presale_header: timer ? 'date' : 'none'};
    return {html, metadata, includedSecondary: reachable && schedule.show_before_start_message === true && Boolean(schedule.before_start_message)};
}
