# Persistent help navigation

Public help remains a set of crawlable, directly addressable documents. Its
compiled help entry progressively enhances same-origin guide links: fetch the
next document, retain the current content until ready, and replace only the help
layout. The existing account header, theme, search dialog and footer stay mounted.

Navigation updates title, description, canonical/OG metadata and structured data,
focuses the new heading and supports fragments, history and reading positions.
Modifier clicks, downloads and external/new-tab links keep native behavior. A
failed request or changed runtime/style release falls back to normal navigation.
At most 12 verified documents are cached; hover/focus prefetch respects Save-Data.
The generator initializes for each newly inserted form; search closes before
navigation without restoring focus to a removed link.

The initial static account placeholder hides both guest actions until account
initialization completes, reserving their space. No unverified identity/avatar is
stored or rendered. No-JavaScript and initialization-failure fallbacks remain.

Verification:
- Full web suite before the final scroll/anchor refinements: 760 collected,
  730 passed, 30 skipped, no failures. Final navigation suite: 6 passed, including
  history reading positions, rapid-click races, identity preservation, native
  links, generator rebinding and release-change fallback.
- Help runtime/rendering/hosting and organizer rendering tests: 8 passed.
- Real isolated Chrome with an unchanged installed production worker and real
  disposable local Supabase login: avatar A and My events survive multiple guide
  changes, Back, search result navigation and generator submit. Exact header and
  search DOM identities persist; navigation timing still contains one document.
- CLI pointer dispatch was unreliable for sidebar links in this headless session;
  verified transitions invoked actual anchor click handlers with HTMLElement.click.
- Search closes and releases body scroll lock; screenshots inspected. Existing
  pending-account CSS detector returned no findings.
