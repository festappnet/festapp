const CANONICAL_ORIGINS = new Map([
  ['festivalslunovrat.netlify.app', 'https://app.festivalslunovrat.cz'],
]);

const RETIREMENT_WORKER_PATHS = new Set([
  '/festapp_service_worker.js',
  '/flutter_service_worker.js',
]);

export default function canonicalProviderOrigin(request, context) {
  const url = new URL(request.url);
  const canonicalOrigin = CANONICAL_ORIGINS.get(url.hostname);
  if (!canonicalOrigin) return context.next();

  // Replace cached application and push workers without relying on Netlify's
  // host-wildcard redirect syntax. context.next() fetches the static worker
  // asset while preserving this request's provider-origin boundary.
  if (RETIREMENT_WORKER_PATHS.has(url.pathname) || url.pathname.startsWith('/push/')) {
    url.pathname = '/netlify-retire-worker.js';
    url.search = '';
    return context.next(new Request(url, request));
  }

  return Response.redirect(canonicalOrigin + url.pathname + url.search, 301);
}

export const config = { path: '/*' };
