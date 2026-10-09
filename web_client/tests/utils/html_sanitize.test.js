import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { sanitizeHtml, SafeHtml, html } from '../../src/utils/html.js';

const dom = new JSDOM('', { url: 'https://forms.example/' });
global.document = dom.window.document;
after(() => dom.window.close());
const render = value => {
    const node = document.createElement('div');
    node.innerHTML = sanitizeHtml(value);
    return node;
};

test('rich HTML retains editor formatting, links, images and layout attributes', () => {
    const value = `<h2>Title</h2><p class="description" style="color: red; text-align: center">Hello
        <strong>bold</strong><em>italic</em><u>underlined</u><s>removed</s><code>code</code></p>
        <a href="https://example.com/order?a=1&amp;b=2" target="_blank" rel="noopener">Link</a>
        <a href="mailto:info@example.com">Email</a><a href="tel:+420123456789">Call</a>
        <a href="/info">Relative</a><a href="#details">Anchor</a>
        <figure><img src="/image.jpg" alt="Photo" width="100" height="80" fetchpriority="high" loading="lazy"><figcaption>Photo</figcaption></figure>
        <img src="data:image/png;base64,iVBORw0KGgo=" alt="Inline">
        <ul><li>First</li></ul><table><tbody><tr><td colspan="2">Cell</td></tr></tbody></table>`;
    const result = sanitizeHtml(value);
    assert.ok(result instanceof SafeHtml);
    const node = render(value);
    for (const tag of ['h2', 'p', 'strong', 'em', 'u', 's', 'code', 'figure', 'figcaption', 'ul', 'li', 'table', 'tbody', 'td']) {
        assert.ok(node.querySelector(tag), `retains ${tag}`);
    }
    assert.equal(node.querySelector('p').style.color, 'red');
    assert.equal(node.querySelector('p').style.textAlign, 'center');
    assert.deepEqual([...node.querySelectorAll('a')].map(a => a.getAttribute('href')),
        ['https://example.com/order?a=1&b=2', 'mailto:info@example.com', 'tel:+420123456789', '/info', '#details']);
    assert.equal(node.querySelector('a').target, '_blank');
    assert.equal(node.querySelector('a').rel, 'noopener');
    assert.equal(node.querySelector('img').getAttribute('fetchpriority'), 'high');
    assert.equal(node.querySelector('td').colSpan, 2);
    assert.match(node.querySelectorAll('img')[1].src, /^data:image\/png/);
    assert.match(html`<div>${result}</div>`.toString(), /<strong>bold<\/strong>/);
});

for (const url of ['javascript:alert(1)', 'java&#x09;script:alert(1)', 'java&#10;script:alert(1)',
    '&#106;avascript:alert(1)', '  JAVASCRIPT:alert(1)', 'vbscript:alert(1)', 'data:text/html,<script>alert(1)</script>']) {
    test(`rejects dangerous link and image URL ${url}`, () => {
        const node = render(`<a href="${url}">Link</a><img src="${url}">`);
        assert.equal(node.querySelector('a').hasAttribute('href'), false);
        assert.equal(node.querySelector('img').hasAttribute('src'), false);
    });
}

test('removes active content, event handlers, foreign namespaces and clobbering attributes', () => {
    const node = render(`<p id="secret" data-token="abc" onclick="alert(1)">Safe</p>
        <script>alert(1)</script><iframe src="https://evil.example"></iframe>
        <form action="/steal"><input name="secret"></form><object data="evil"></object><embed src="evil">
        <svg><a href="javascript:alert(1)">bad</a></svg><math><mtext>bad</mtext></math>
        <img src="/safe.png" onerror="alert(1)"><span onmouseover="alert(1)">Text</span>`);
    assert.equal(node.querySelector('script, iframe, form, input, object, embed, svg, math'), null);
    for (const el of node.querySelectorAll('*')) {
        assert.equal([...el.attributes].some(attr => /^on|^id$|^data-/.test(attr.name)), false);
    }
    assert.ok(node.textContent.includes('Safe'));
    assert.ok(!node.textContent.includes('alert(1)'));
});

test('null and empty input return empty SafeHtml', () => {
    for (const value of [null, undefined, '']) assert.equal(sanitizeHtml(value).toString(), '');
});
