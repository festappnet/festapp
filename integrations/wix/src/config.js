export const SERVICE_ORIGIN = 'https://vstupenky.online';
export const HELP_URL = 'https://festapp-wix.pages.dev/help';
export const TAG_NAME = 'vstupenky-online-form';
export const DEFAULT_TITLE = 'Prodej vstupenek - vstupenky.online';
export const PROPERTIES = ['form-url', 'form-title', 'inherit-style'];

// This is a public form URL, never an authentication or editor URL.
export function formUrl(value) {
  if (typeof value !== 'string' || value.length > 2048) return null;
  const candidate = value.trim();
  if (!candidate.startsWith(`${SERVICE_ORIGIN}/form/`)) return null;
  let url, slug;
  try {
    url = new URL(candidate);
    slug = decodeURIComponent(url.pathname.slice('/form/'.length));
  } catch { return null; }
  if (url.origin !== SERVICE_ORIGIN || url.username || url.password || url.search || url.hash ||
      !/^[\p{L}\p{N}_-]+$/u.test(slug) || url.pathname !== `/form/${encodeURIComponent(slug)}` ||
      ![`${SERVICE_ORIGIN}/form/${slug}`, `${SERVICE_ORIGIN}/form/${encodeURIComponent(slug)}`].includes(candidate)) return null;
  return url.href;
}

export function settingsFrom(values) {
  const url = formUrl(values['form-url']);
  if (!url) throw new Error('Vložte veřejný odkaz https://vstupenky.online/form/… bez dalších parametrů.');
  const title = String(values['form-title'] || DEFAULT_TITLE).trim().slice(0, 200) || DEFAULT_TITLE;
  return {'form-url': url, 'form-title': title, 'inherit-style': values['inherit-style'] === 'false' ? 'false' : 'true'};
}
