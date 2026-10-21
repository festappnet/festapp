/**
 * HTML-aware URL replacement using cheerio.
 * Rewrites img[src] and a[href] attributes containing Supabase Storage URLs.
 */

import * as cheerio from 'cheerio';
import { rewriteUrl } from './url-rewriter.js';

/**
 * Rewrite Supabase Storage URLs in HTML content.
 * Finds all img[src] and a[href] attributes containing Supabase Storage URLs
 * and replaces with R2 URLs using the shared rewriteUrl() logic.
 *
 * @param {string} html - HTML content to rewrite
 * @returns {{ html: string, changed: boolean, count: number }}
 */
export function rewriteHtml(html) {
  if (!html || !html.includes('supabase.co/storage')) {
    return { html, changed: false, count: 0 };
  }

  const $ = cheerio.load(html, { xmlMode: false, decodeEntities: false });
  let count = 0;

  // Rewrite img[src] attributes
  $('img[src]').each((_, el) => {
    const src = $(el).attr('src');
    if (src) {
      const { newUrl, changed } = rewriteUrl(src);
      if (changed) {
        $(el).attr('src', newUrl);
        count++;
      }
    }
  });

  // Rewrite a[href] attributes pointing to images
  $('a[href]').each((_, el) => {
    const href = $(el).attr('href');
    if (href) {
      const { newUrl, changed } = rewriteUrl(href);
      if (changed) {
        $(el).attr('href', newUrl);
        count++;
      }
    }
  });

  // Get the body content (not the full HTML document wrapper cheerio adds)
  const result = $('body').html() || $.html();

  return {
    html: result,
    changed: count > 0,
    count,
  };
}
