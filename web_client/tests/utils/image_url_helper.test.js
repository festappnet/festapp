import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { transformImageUrl, THUMBNAIL_WIDTH, MEDIUM_WIDTH, FULL_WIDTH } from '../../src/utils/image_url_helper.js';

const source = 'https://img.festapp.net/images/42/photo.jpg';
const options = 'width=300,fit=scale-down,format=auto,quality=75,onerror=redirect';

describe('bounded image transform URL', () => {
    it('builds the canonical transform and strips source query/fragment', () => {
        assert.equal(transformImageUrl(`${source}?legacy=1#x`),
            `https://img.festapp.net/cdn-cgi/image/${options}/${source}`);
    });
    it('supports project A and exact presets', () => {
        const projectA = 'https://a.img.festapp.net/images/1/a.png';
        assert.equal(transformImageUrl(projectA, { width: MEDIUM_WIDTH }),
            `https://a.img.festapp.net/cdn-cgi/image/width=600,fit=scale-down,format=auto,quality=75,onerror=redirect/${projectA}`);
        assert.deepEqual([THUMBNAIL_WIDTH, MEDIUM_WIDTH, FULL_WIDTH], [300, 600, 1200]);
    });
    it('leaves noncanonical inputs unchanged', () => {
        for (const value of [
            'https://evil-img.festapp.net/images/1/a.jpg',
            'https://img.festapp.net/private/a.jpg',
            'https://img.festapp.net/images/1/file.pdf',
            'https://img.festapp.net/images%2f1/a.jpg',
            'not-a-url',
        ]) assert.equal(transformImageUrl(value), value);
        assert.equal(transformImageUrl(source, { width: 301 }), source);
    });
});
