import { check } from '../errors.mjs';
// Rasterize the canonical PDF. Never maintain a second ticket renderer here.
export async function rasterizePdf(bytes) {
    check(
        bytes.length <= 8 * 1024 * 1024 &&
            bytes.subarray(0, 5).toString() === '%PDF-',
    );
    const { createCanvas, DOMMatrix, ImageData, Path2D } =
        await import('@napi-rs/canvas');
    Object.assign(globalThis, { DOMMatrix, ImageData, Path2D });
    const { getDocument } = await import('pdfjs-dist/legacy/build/pdf.mjs');
    const task = getDocument({
        data: new Uint8Array(bytes),
        isEvalSupported: false,
        useSystemFonts: false,
        verbosity: 0,
    });
    const doc = await task.promise;
    try {
        check(doc.numPages === 1);
        const page = await doc.getPage(1);
        const natural = page.getViewport({ scale: 1 });
        const scale = Math.min(2, 1024 / natural.width, 1536 / natural.height);
        check(Number.isFinite(scale) && scale > 0);
        const viewport = page.getViewport({ scale });
        const canvas = createCanvas(
            Math.ceil(viewport.width),
            Math.ceil(viewport.height),
        );
        await page.render({ canvasContext: canvas.getContext('2d'), viewport })
            .promise;
        const png = await canvas.encode('png');
        check(png.length <= 4 * 1024 * 1024);
        return png;
    } finally {
        await task.destroy();
    }
}
export class PreviewArtifacts {
    #items = new Map();
    put(key, value) {
        this.#items.set(key, {
            ...value,
            expires: Date.now() + 15 * 60 * 1000,
        });
        while (this.#items.size > 4)
            this.#items.delete(this.#items.keys().next().value);
        return `festapp-preview://artifact/${key}.pdf`;
    }
    get(uri) {
        check(
            /^festapp-preview:\/\/artifact\/[a-f0-9]{64}\.pdf$/.test(uri),
            'NOT_FOUND_OR_INACCESSIBLE',
        );
        const item = this.#items.get(uri.split('/').pop().slice(0, -4));
        check(item && item.expires > Date.now(), 'NOT_FOUND_OR_INACCESSIBLE');
        return item;
    }
}
