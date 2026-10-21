/**
 * URL transformation logic for Supabase Storage to R2 migration.
 *
 * The Supabase project reference is read from SUPABASE_PROJECT_REF env var.
 */
import 'dotenv/config';

const PROJECT_REF = process.env.SUPABASE_PROJECT_REF;
if (!PROJECT_REF) {
  console.error('ERROR: SUPABASE_PROJECT_REF is required in .env');
  process.exit(1);
}

/** Supabase Storage public URL prefixes for the target project */
const SUPABASE_PREFIXES = [
  `https://${PROJECT_REF}.supabase.co/storage/v1/object/public/public-files/`,
  `https://${PROJECT_REF}.supabase.co/storage/v1/object/public/custom-files/`,
];

/** Legacy: primary prefix for migrate-files.js */
export const SUPABASE_STORAGE_PREFIX = SUPABASE_PREFIXES[0];

/** R2 public URL prefix */
export const R2_PREFIX = 'https://img.festapp.net/';

/** SQL LIKE pattern for finding Supabase URLs */
export const SUPABASE_PATTERN = '%supabase.co/storage%';

/** Pattern scoped to this project only */
export const THIS_PROJECT_PATTERN = `%${PROJECT_REF}%supabase.co/storage%`;

/** Regex for finding Supabase URLs in text (used by migrate-files.js) */
export const SUPABASE_URL_REGEX = new RegExp(
  `https://${PROJECT_REF}\\.supabase\\.co/storage/v1/object/(?:public|sign)/[^"'\\s<>]+`,
  'g'
);

/**
 * Rewrite a single URL from Supabase Storage to R2.
 * Handles: public-files, custom-files, and signed editor-files URLs.
 *
 * @param {string} url - The URL to rewrite
 * @returns {{ newUrl: string, changed: boolean }}
 */
export function rewriteUrl(url) {
  if (!url || !url.includes(`${PROJECT_REF}.supabase.co/storage`)) {
    return { newUrl: url, changed: false };
  }

  // Try each known prefix
  for (const prefix of SUPABASE_PREFIXES) {
    if (url.startsWith(prefix)) {
      return { newUrl: R2_PREFIX + url.substring(prefix.length), changed: true };
    }
  }

  // Handle signed URLs: /object/sign/editor-files/filename?token=...
  const signedRegex = new RegExp(
    `https://${PROJECT_REF}\\.supabase\\.co/storage/v1/object/sign/editor-files/([^?]+)`
  );
  const signedMatch = url.match(signedRegex);
  if (signedMatch) {
    return { newUrl: R2_PREFIX + 'editor/' + signedMatch[1], changed: true };
  }

  return { newUrl: url, changed: false };
}

/**
 * Check if text contains a Supabase Storage URL.
 *
 * @param {string} text
 * @returns {boolean}
 */
export function containsSupabaseUrl(text) {
  return typeof text === 'string' && text.includes('supabase.co/storage');
}
