// Stable identities and internal assets. Public paths and copy belong to profiles.
export const pageDefinitions = Object.freeze({
  home: { asset: '/organizers-page' },
  'ball-ticket-sales': { asset: '/organizers/ball-ticket-sales' },
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
      for (const key of ['heading','intro','faqHeading']) if (!page[key]?.trim()) throw new Error(`Page requires ${key}`);
      if (!page.faq?.length) throw new Error('Topic needs questions');
      if (page.guide) {
        if (!page.guide.chapters?.length || !page.guide.checklist?.items?.length) throw new Error('Guide requires chapters and checklist');
        const anchors = [...page.guide.chapters.map(chapter=>chapter.id),page.guide.checklist.id,'otazky'];
        if (new Set(anchors).size !== anchors.length || anchors.some(id=>!(/^[a-z]+(?:-[a-z]+)*$/).test(id))) throw new Error('Invalid guide chapter anchors');
      } else if (!page.stepsHeading || !page.steps?.length) throw new Error('Feature needs preparation steps');
    }
    ids.add(page.id); paths.add(page.path);
    return { ...page, ...definition, canonical: new URL(page.path, origin).href };
  });
}
