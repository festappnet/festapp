// Stable identities and internal assets. Public paths and copy belong to profiles.
export const pageDefinitions = Object.freeze({
  home: { asset: '/organizers-page' },
  'seating-reservations': { asset: '/organizers/seating-reservations' },
});
const reserved = /^\/(?:napoveda|bank-accounts|events|login|login-qr|admin|transfer|unit|signup|settings|install|map-editor|reset-password|forgot-password|google-auth|app|auth_bridge|form|stripe|scan|check|web-assets|organizers-media|assets|canvaskit|privacy|terms|support|delete-account|flutter|webclient|organizers|organizers-page|pro-poradatele|sitemap\.xml|robots\.txt)(?:\/|$)/;
export function resolvePages(pages, origin) {
  if (!Array.isArray(pages) || pages[0]?.id !== 'home') throw new Error('Marketing profile needs home first');
  const ids = new Set(), paths = new Set();
  return pages.map(page => {
    const definition = pageDefinitions[page.id];
    if (!definition || ids.has(page.id) || paths.has(page.path)) throw new Error('Unknown or duplicate marketing page');
    if (typeof page.path !== 'string' || !/^\/(?:[a-z0-9]+(?:-[a-z0-9]+)*)?$/.test(page.path) || reserved.test(page.path)) throw new Error('Invalid/reserved marketing path');
    if ((page.id === 'home') !== (page.path === '/')) throw new Error('Home must own root');
    for (const key of ['title','description']) if (!page[key]?.trim()) throw new Error(`Page requires ${key}`);
    if (page.id !== 'home') {
      for (const key of ['heading','intro']) if (!page[key]?.trim()) throw new Error(`Page requires ${key}`);
      if (page.feature) {
        if (!page.feature.layouts?.length || !page.feature.editor || !page.feature.buyer) throw new Error('Feature requires examples and demonstrations');
      } else if (!page.stepsHeading || !page.steps?.length || !page.faq?.length || !page.faqHeading) throw new Error('Topic requires steps and questions');
    }
    ids.add(page.id); paths.add(page.path);
    return { ...page, ...definition, canonical: new URL(page.path, origin).href };
  });
}

// Previous generated document is removed on every render, including tenant switches.
export const retiredPageAssets = ['/organizers/ball-ticket-sales'];
export function resolveRedirects(redirects = [], pages) {
  const sources = new Set();
  return redirects.map(({from,to}) => {
    if (typeof from !== 'string' || !/^\/[a-z0-9]+(?:-[a-z0-9]+)*$/.test(from) || reserved.test(from) || sources.has(from) || pages.some(page=>page.path===from) || !pages.some(page=>page.path===to)) throw new Error('Invalid marketing redirect');
    sources.add(from);
    return {from,to};
  });
}
