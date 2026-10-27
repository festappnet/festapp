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
// One bounded, expiring private artifact cache for canonical previews and exports.
// The hosted app shares one instance across HTTP requests; every read reauthorizes.
export class PreviewArtifacts {
    #items = new Map();
    #bytes = 0;
    put(key, value) {
        const extension = value.extension ?? 'pdf';
        const bytes = Buffer.from(value.bytes ?? value.pdf);
        check(['pdf', 'csv', 'json'].includes(extension) && bytes.length <= 8 * 1024 * 1024, 'ARTIFACT_TOO_LARGE');
        const uri = `festapp-${extension === 'pdf' ? 'preview' : 'export'}://artifact/${key}.${extension}`;
        const previous = this.#items.get(uri);
        if (previous) this.#bytes -= previous.bytes.length;
        this.#items.delete(uri);
        this.#items.set(uri, { ...value, bytes, extension,
            mimeType: value.mimeType ?? 'application/pdf', expires: Date.now() + 15 * 60 * 1000 });
        this.#bytes += bytes.length;
        for (const [name, item] of this.#items) {
            if (item.expires > Date.now() && this.#items.size <= 8 && this.#bytes <= 16 * 1024 * 1024) break;
            this.#items.delete(name); this.#bytes -= item.bytes.length;
        }
        return uri;
    }
    get(uri) {
        check(/^festapp-(?:preview|export):\/\/artifact\/[a-f0-9]{64}\.(?:pdf|csv|json)$/.test(uri), 'NOT_FOUND_OR_INACCESSIBLE');
        const item = this.#items.get(uri);
        check(item && item.expires > Date.now(), 'NOT_FOUND_OR_INACCESSIBLE');
        return item;
    }
}
