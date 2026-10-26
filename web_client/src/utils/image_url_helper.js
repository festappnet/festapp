/**
 * Builds the bounded Cloudflare Images delivery contract.
 */

const IMAGE_HOSTS = new Set(['img.festapp.net', 'a.img.festapp.net']);
const IMAGE_PATH = /\.(jpe?g|png|webp|gif|avif|svg)$/i;

/** Standard thumbnail widths to maximize CDN cache hits. */
export const THUMBNAIL_WIDTH = 300;
export const MEDIUM_WIDTH = 600;
export const FULL_WIDTH = 1200;

/**
 * Transform an img.festapp.net URL to include resize query parameters.
 * Returns original URL unchanged if not an img.festapp.net URL or on error.
 *
 * @param {string} originalUrl - The image URL to transform.
 * @param {Object} [options]
 * @param {number} [options.width=300] - Target width in pixels.
 * @returns {string} Transformed URL or original if not applicable.
 */
export function transformImageUrl(originalUrl, { width = THUMBNAIL_WIDTH } = {}) {
    try {
        const url = new URL(originalUrl);
        const rawPath = originalUrl.split(/[?#]/, 1)[0];
        if (url.protocol !== 'https:' || url.username || url.password || url.port ||
            !IMAGE_HOSTS.has(url.hostname) || ![THUMBNAIL_WIDTH, MEDIUM_WIDTH, FULL_WIDTH].includes(width) ||
            !url.pathname.startsWith('/images/') || url.pathname.startsWith('/cdn-cgi/image/') ||
            rawPath.includes('%') || url.pathname.split('/').includes('..') || !IMAGE_PATH.test(url.pathname)) {
            return originalUrl;
        }
        const source = `https://${url.hostname}${url.pathname}`;
        const options = `width=${width},fit=scale-down,format=auto,quality=75,onerror=redirect`;
        return `https://${url.hostname}/cdn-cgi/image/${options}/${source}`;
    } catch {
        return originalUrl;
    }
}
