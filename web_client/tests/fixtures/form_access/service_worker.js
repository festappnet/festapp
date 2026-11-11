// Valid inert worker for the form-access server. Vite's HTML fallback is not
// a service-worker script and creates a transient failed worker target. The
// generated production worker and its offline behavior have a separate real
// browser test in test_pwa_split_browser.mjs.
self.addEventListener('install', () => {});
