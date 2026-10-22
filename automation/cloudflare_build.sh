#!/bin/bash
# ==============================================================================
# CLOUDFLARE PAGES BUILD
# Purpose: shared build script for Cloudflare Pages — runs project.conf
#          propagation, installs Flutter (if missing), builds Flutter web +
#          Web Client, merges them, and emits a single _worker.js that owns
#          all routing (web client, Flutter SPA, /sitemap.xml, /form/<slug>
#          OG inject, auth_bridge, static fallback).
#
# Used by automation/deploy_direct.sh before every production upload.
#
# Required env vars on the CF Pages project (Production + Preview) for the
# dynamic sitemap and OG inject to work at runtime:
#   - SUPABASE_URL
#   - SUPABASE_ANON_KEY
#   - ORGANIZATION_ID
# ==============================================================================
set -euo pipefail

echo "Cloudflare Pages build starting..."

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
bash "$PROJECT_ROOT/automation/build_web_bundle.sh" cloudflare

# 6. Cloudflare-specific routing via Pages Function (_worker.js).
#    Cloudflare Pages applies _redirects BEFORE static assets, so a catch-all
#    "/* /flutter 200" rewrite would hijack every URL (favicon, JS chunks,
#    canvaskit/...) and serve the Flutter HTML for everything. A worker gives
#    us explicit routing AND lets us host the dynamic sitemap and OG inject
#    (the old functions/ Pages Functions are mutually exclusive with
#    _worker.js, so they would not be deployed alongside it).
rm -f build/web/_redirects build/web/_headers

cat > build/web/_worker.js <<'WORKER'
// =============================================================================
// Cloudflare Pages worker — single routing source for the Festapp deployment.
//
// Required env vars on the Pages project (Production + Preview):
//   SUPABASE_URL, SUPABASE_ANON_KEY, ORGANIZATION_ID
//
// All HTML entry-points are kept extension-less so Cloudflare's .html-strip
// does not turn ASSETS.fetch into a 308 redirect (which would corrupt the
// response body and query string).
// =============================================================================

// Replaced with the manifest computed from the final deployed documents.
const CSP_MANIFEST = { profiles: {}, documents: {} };
const CSP_BASE = CSP_MANIFEST.basePolicy || "base-uri 'self'; object-src 'none'";
function cspHeaders(headers, profile = 'none') {
  const policy = CSP_MANIFEST.profiles[profile]?.policy || `${CSP_BASE}; script-src 'self'; script-src-attr 'none'; report-uri /_security/csp-report?profile=none; report-to csp-none`;
  headers.set('content-security-policy', CSP_MANIFEST.mode === 'enforce' ? policy : CSP_BASE);
  headers.delete('content-security-policy-report-only');
  if (CSP_MANIFEST.mode !== 'enforce') headers.set('content-security-policy-report-only', policy);
  headers.set('reporting-endpoints', `csp-${profile}="/_security/csp-report?profile=${profile}"`);
  headers.set('x-content-type-options', 'nosniff');
}
// A per-isolate bounded diagnostic budget avoids unbounded attacker-controlled
// logs. Reports never authorize actions and no request headers/body are logged.
let cspLogWindow = 0;
let cspLogCount = 0;
function sourceOrigin(value) {
  if (['inline', 'eval', 'wasm-eval', 'self', 'none'].includes(value)) return value;
  try {
    const url = new URL(value);
    return ['https:', 'http:'].includes(url.protocol) && url.origin.length <= 160 ? url.origin : 'other';
  } catch { return 'other'; }
}
async function cspReport(request) {
  const reply = status => new Response(null, { status, headers: { 'cache-control': 'no-store', 'allow': 'POST' } });
  if (request.method !== 'POST') return reply(405);
  const mime = (request.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  if (!['application/csp-report', 'application/reports+json', 'application/json'].includes(mime)) return reply(415);
  if (Number(request.headers.get('content-length')) > 32768) return reply(413);
  const reader = request.body?.getReader();
  if (!reader) return reply(400);
  let size = 0;
  const chunks = [];
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 32768) { await reader.cancel(); return reply(413); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const json = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    const batch = Array.isArray(json) ? json : [{ type: 'csp-violation', body: json['csp-report'] }];
    if (!batch.length || batch.length > 10 || batch.some(r => r?.type !== 'csp-violation' || !r.body || typeof r.body !== 'object' || Array.isArray(r.body))) return reply(400);
    const profileParam = new URL(request.url).searchParams.get('profile');
    const profile = Object.hasOwn(CSP_MANIFEST.profiles, profileParam) ? profileParam : 'none';
    const records = batch.map(({ body }) => {
      const directive = body.effectiveDirective || body['effective-directive'] || body['violated-directive'];
      if (typeof directive !== 'string' || !/^[a-z-]{1,50}$/.test(directive)) throw new Error('invalid directive');
      return { directive, disposition: body.disposition === 'enforce' ? 'enforce' : 'report', profile,
        source: sourceOrigin(body.blockedURL || body['blocked-uri']) };
    });
    const minute = Math.floor(Date.now() / 60000);
    if (cspLogWindow !== minute) { cspLogWindow = minute; cspLogCount = 0; }
    for (const record of records) if (cspLogCount++ < 20) console.info('csp-violation', record);
    return reply(204);
  } catch { return reply(400); }
}

const WEB_CLIENT_INDEX = "/webclient";
const FLUTTER_ENTRY = "/flutter";
const AUTH_BRIDGE = "/auth_bridge";
const FORCED_OCCASION_PATH = null; // replaced from project.conf after generation
const CANONICAL_ORIGIN = null; // stamped from tenant WEB_LINK
const ORGANIZERS_ENABLED = false; // stamped from tenant domain
const SITE_NAME = "Festapp"; // replaced from project.conf after generation
const IS_APP_SUPPORTED = true; // replaced from project.conf after generation
// PUBLIC_OCCASION_ROUTE_POLICY

// Web client SPA routes (form list handled by /form/<slug> below).
const WEB_CLIENT_EXACT = new Set(["/"]);

// Flutter SPA routes (login / admin / handover).
const FLUTTER_PREFIXES = ["/login", "/login-qr", "/admin", "/bank-accounts", "/transfer", "/organizationEdit", "/unit", "/signup", "/settings", "/install", "/scan", "/check", "/map-editor", "/resetPassword", "/forgotPassword", "/reset-password", "/forgot-password"];

// auth_bridge.html alias — RouterService still posts to /auth_bridge.html.
const AUTH_BRIDGE_PATHS = new Set(["/auth_bridge", "/auth_bridge.html"]);

// Internal asset names (extension-less HTML entry points). Cloudflare serves
// these as application/octet-stream to direct hits, which triggers a browser
// download. They must never be reachable as a user-facing URL — redirect to /.
const INTERNAL_ASSET_PATHS = new Set(["/flutter", "/webclient", "/organizers-page"]);

// Flutter's entry/runtime files use stable, unversioned names that change on
// every deploy (main.dart.js, its main.dart.js_<n>.part.js deferred chunks,
// the bootstrap/loader, and the canvaskit/skwasm wasm runtime). These must be
// revalidated on every load so a client never mixes assets from two builds.
const MUTABLE_RUNTIME_ASSET = /(?:^|\/)(?:backend-activation\.json|client-sync-config\.json|festapp-version\.json|main\.dart\.js(?:_\d+\.part\.js)?|main\.dart\.mjs|flutter_bootstrap\.js|flutter\.js|flutter_service_worker\.js|festapp_service_worker\.js|festapp_update_prompt\.js|(?:canvaskit|skwasm)[\w.]*\.(?:js|mjs|wasm))$/;

function htmlResponse(body, originHeaders, status = 200, profile = "webclient") {
  const headers = new Headers(originHeaders || {});
  headers.set("content-type", "text/html; charset=utf-8");
  headers.set("cache-control", "no-cache, must-revalidate");
  headers.set("x-festapp-runtime", "cloudflare-pages");
  cspHeaders(headers, profile);
  headers.delete("location");
  headers.delete("content-length");
  headers.delete("content-range");
  headers.delete("accept-ranges");
  return new Response(body, { status, headers });
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

// Must match the native links on OccasionCard (covered by contract tests).
function occasionHref(occasion) {
  const form = occasion.features?.find(feature => feature.code === "form" &&
    (feature.is_enabled === true || feature.isEnabled === true));
  if (form) {
    const data = { ...form, ...form.data };
    if (data.use_external_form === true && data.external_form_link) {
      try {
        const url = new URL(data.external_form_link);
        if (["https:", "http:"].includes(url.protocol)) return url.href;
      } catch { /* Fall back to an internal destination. */ }
    }
    const slug = (occasion.form?.link || occasion.link || "").split("?")[0].replace(/^\/+|\/+$/g, "");
    return slug ? `/form/${encodeURIComponent(slug)}` : null;
  }
  const slug = (occasion.link || "").split("?")[0].replace(/^\/+|\/+$/g, "");
  return IS_APP_SUPPORTED && slug ? `/${encodeURIComponent(slug)}/event` : null;
}

async function publicCatalogue(env, unitId = null) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) throw new Error("Public catalog is not configured");
  const rpc = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/get_available_occasions`, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: env.SUPABASE_ANON_KEY,
      authorization: `Bearer ${env.SUPABASE_ANON_KEY}` },
    body: JSON.stringify({ p_organization_id: env.ORGANIZATION_ID || 1, p_unit_id: unitId }),
    signal: AbortSignal.timeout(2500),
  });
  if (!rpc.ok) throw new Error(`Public catalog HTTP ${rpc.status}`);
  const data = await rpc.json();
  return { title: typeof data?.title === "string" ? data.title : null, occasions: extractPublicOccasions(data) };
}

async function publicOccasions(env, unitId = null) {
  return (await publicCatalogue(env, unitId)).occasions;
}

// SHARED_CATALOG_CLASSIFICATION

async function handleHome(request, env) {
  const base = await serveAsset(env, request, WEB_CLIENT_INDEX);
  let html = await base.text();
  const unitMatch = new URL(request.url).pathname.match(/^\/unit\/([1-9]\d*)\/?$/);
  if (ORGANIZERS_ENABLED && !unitMatch) {
    const canonical = (CANONICAL_ORIGIN || new URL(request.url).origin) + "/events";
    html = html.replace(/(<link[^>]*rel="canonical"[^>]*href=")[^"]*/i, (_, prefix) => prefix + canonical)
      .replace(/(<meta[^>]*property="(?:og:url|twitter:url)"[^>]*content=")[^"]*/gi, (_, prefix) => prefix + canonical);
  }
  if (unitMatch) html = html.replace(/<!-- ORGANIZERS_NAV_START -->[\s\S]*?<!-- ORGANIZERS_NAV_END -->/, '');
  try {
    const { occasions, title } = await publicCatalogue(env, unitMatch ? Number(unitMatch[1]) : null);
    if (unitMatch && title) {
      html = html.replace(/<section id="unit-introduction"[^>]*>[\s\S]*?<\/section>/,
        () => `<section id="unit-introduction" class="unit-introduction"><h1>${escapeHtml(title)}</h1><p>Akce a vstupenky tohoto pořadatele</p></section>`);
      html = html.replace(/<title>[\s\S]*?<\/title>/, () => `<title>${escapeHtml(title)} | ${escapeHtml(SITE_NAME)}</title>`);
    }
    const groups = classifyOccasions(occasions);
    const date = value => {
      if (!value || !Number.isFinite(new Date(value).getTime())) return "";
      return `<time datetime="${escapeHtml(new Date(value).toISOString())}">${escapeHtml(new Date(value).toLocaleDateString("cs-CZ", { timeZone: "Europe/Prague" }))}</time>`;
    };
    const section = (title, list, archive = false) => {
      if (!list.length) return "";
      const links = occasions => occasions.map(occasion => {
        const href = occasionHref(occasion);
        return href ? `<li><a href="${escapeHtml(href)}">${escapeHtml(occasion.title)}</a> ${date(occasion.start_time)}</li>` : "";
      }).join("");
      const years = archive ? groupPastOccasionsByYear(list) : [];
      const body = years.length
        ? years.map(({year, occasions}) => `<h3>${year}</h3><ul>${links(occasions)}</ul>`).join("")
        : `<ul>${links(list)}</ul>`;
      return `<section${archive ? ' class="catalog-archive"' : ""}><h2>${title}</h2>${body}</section>`;
    };
    const content = section("Právě probíhá", groups.present) + section("Nadcházející akce", groups.upcoming) +
      section("Další akce", groups.undated) + section("Proběhlé události", groups.past, true);
    html = html.replace('<div id="events-grid"></div>', () => `<div id="events-grid" data-server-catalog="ready">${content || '<p>Zatím zde nejsou žádné akce.</p>'}</div>`);
  } catch (error) {
    console.error("Public catalog HTML unavailable", error.message);
    html = html.replace('<div id="events-grid"></div>', '<div id="events-grid" data-server-catalog="unavailable"><p role="status">Akce se nepodařilo načíst. Zkuste stránku znovu načíst.</p></div>');
  }
  return htmlResponse(html, base.headers);
}

function notFound() {
  return htmlResponse('<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="robots" content="noindex"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Stránka nenalezena</title></head><body><main><h1>Stránka nenalezena</h1><p><a href="/">Zpět na hlavní stránku</a></p></main></body></html>', null, 404, "none");
}

function activationCorsHeaders(originHeaders) {
  const headers = new Headers(originHeaders || {});
  // The activation document is public, contains no credential, and is fetched
  // by immutable preview builds from the tenant's production origin. Keep that
  // cross-origin lookup explicit so previews exercise the real activation gate
  // instead of silently falling back after a failed browser preflight.
  headers.set("access-control-allow-origin", "*");
  headers.set("access-control-allow-methods", "GET, HEAD, OPTIONS");
  headers.set("access-control-allow-headers", "cache-control");
  headers.set("access-control-max-age", "86400");
  return headers;
}

async function serveAsset(env, request, path) {
  const url = new URL(request.url);
  url.pathname = path;
  // Preserve original query so downstream HTML scripts can read it.
  return env.ASSETS.fetch(new Request(url.toString(), { method: "GET" }));
}

// ---------------------------------------------------------------------------
// /sitemap.xml — dynamic from Supabase get_available_occasions
// ---------------------------------------------------------------------------
async function handleSitemap(request, env) {
  const url = new URL(request.url);
  const baseUrl = CANONICAL_ORIGIN || url.origin;
  const xmlHeaders = { "content-type": "application/xml", "cache-control": "public, max-age=0, s-maxage=3600" };

  const organizerEntry = ORGANIZERS_ENABLED ? `<url><loc>${escapeHtml(baseUrl)}/events</loc></url>` : "";
  const fallback = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${baseUrl}/</loc>
    <priority>1.0</priority>
  </url>
${organizerEntry}
</urlset>`;

  try {
    const unitMatch = new URL(request.url).pathname.match(/^\/unit\/([1-9]\d*)\/?$/);
    const occasions = await publicOccasions(env, unitMatch ? Number(unitMatch[1]) : null);
    if (occasions.length === 0) return new Response(fallback, { headers: xmlHeaders });

    let xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`;
    xml += `  <url>\n    <loc>${escapeHtml(baseUrl)}/</loc>\n    <priority>1.0</priority>\n  </url>\n`;
    xml += organizerEntry;
    const seen = new Set();
    for (const occ of occasions) {
      const href = occasionHref(occ);
      if (!href) continue;
      const destination = new URL(href, baseUrl);
      if (destination.origin !== baseUrl) continue;
      const canonical = baseUrl + destination.pathname;
      if (seen.has(canonical)) continue;
      seen.add(canonical);
      xml += `  <url>\n    <loc>${escapeHtml(canonical)}</loc>\n    <priority>0.8</priority>\n  </url>\n`;
    }
    xml += `</urlset>`;
    return new Response(xml, { headers: xmlHeaders });
  } catch (e) {
    console.error("sitemap error", e);
    return new Response(fallback, { headers: xmlHeaders });
  }
}

// ---------------------------------------------------------------------------
// /form/<slug> — web client HTML with OG / twitter / canonical meta injected
// ---------------------------------------------------------------------------
// SHARED_PUBLIC_PAGE_SEO
function publicSeoHtml(baseHtml, seo) {
  let page = baseHtml.replace(/<title[^>]*>[\s\S]*?<\/title>/i, () => `<title>${escapeHtml(seo.title)}</title>`);
  // Remove both attribute orders and stale catalog structured data, then emit one identity.
  page = page.replace(/<meta\b[^>]*(?:name|property)=["'](?:description|(?:og|twitter):(?:title|description|image(?::(?:width|height))?|url))["'][^>]*>/gi, '')
    .replace(/<link\b[^>]*rel=["']canonical["'][^>]*>/gi, '')
    .replace(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi, '');
  const tags = `<link rel="canonical" href="${escapeHtml(seo.canonical)}"><meta name="description" content="${escapeHtml(seo.description)}">`
    + ['og', 'twitter'].map(prefix => Object.entries({ title: seo.title, description: seo.description, image: seo.image, url: seo.canonical })
      .map(([name, value]) => `<meta ${prefix === 'twitter' ? 'name' : 'property'}="${prefix}:${name}" content="${escapeHtml(value)}">`).join('')).join('');
  return page.replace('</head>', () => tags + '</head>');
}

// A backend outage is temporary, never an unrelated successful catalog page.
function publicSeoUnavailable(baseHtml, headers, url, kind) {
  const seo = publicPageSeo({ title: 'Informace o akci jsou dočasně nedostupné' }, {
    origin: CANONICAL_ORIGIN || url.origin, siteName: SITE_NAME, path: url.pathname, kind,
  });
  const response = htmlResponse(publicSeoHtml(baseHtml, seo), headers, 503, kind === "event" ? "flutter" : "webclient");
  response.headers.set('cache-control', 'no-store, max-age=0');
  response.headers.set('retry-after', '60');
  return response;
}

async function handlePublicPage(request, env, path, kind) {
  const baseRes = await serveAsset(env, request, kind === 'form' ? WEB_CLIENT_INDEX : FLUTTER_ENTRY);
  const baseHtml = await baseRes.text();
  const url = new URL(request.url);
  const parts = path.split('/').filter(Boolean);
  if (parts.length !== 2) return notFound();
  let slug;
  try { slug = decodeURIComponent(parts[kind === 'form' ? 1 : 0]); } catch { return notFound(); }
  if (!slug || /[\/\u0000-\u001f]/.test(slug)) return notFound();
  try {
    if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) throw new Error('SEO backend configuration unavailable');
    const rpc = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/get_occasion_seo_data`, {
      method: 'POST', headers: { 'content-type': 'application/json', apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}` },
      body: JSON.stringify({ p_link_slug: slug, p_route_type: kind }), signal: AbortSignal.timeout(2500),
    });
    if (!rpc.ok) throw new Error(`SEO backend HTTP ${rpc.status}`);
    const data = await rpc.json();
    if (data === null) return notFound();
    if (typeof data !== 'object' || Array.isArray(data) || typeof data.title !== 'string') throw new Error('Invalid SEO backend response');
    const seo = publicPageSeo(data, { origin: CANONICAL_ORIGIN || url.origin, siteName: SITE_NAME, path, kind });
    // Only a resolved saved identity can redirect an alias. Preserve payment/OAuth queries.
    if ((kind === 'form' ? data.form_link : data.occasion_link) && url.pathname !== new URL(seo.canonical).pathname) {
      const target = new URL(seo.canonical); target.search = url.search;
      return Response.redirect(target.href, 308);
    }
    let page = publicSeoHtml(baseHtml, seo);
    const summary = `<section id="public-seo-summary" style="max-width:48rem;margin:2rem auto;padding:1rem"><h1>${escapeHtml(seo.name)}</h1><p>${escapeHtml(seo.description)}</p>${data.start_time && Number.isFinite(Date.parse(data.start_time)) ? `<p><time datetime="${escapeHtml(data.start_time)}">${escapeHtml(new Intl.DateTimeFormat('cs-CZ', {dateStyle:'long', timeStyle:'short', timeZone:'Europe/Prague'}).format(new Date(data.start_time)))}</time></p>` : ''}</section>`;
    page = page.replace(/<body\b[^>]*>/i, match => match + summary);

    return htmlResponse(page, baseRes.headers, 200, kind === "event" ? "flutter" : "webclient");
  } catch (error) {
    console.error('Public SEO unavailable', error.message);
    return publicSeoUnavailable(baseHtml, baseRes.headers, url, kind);
  }
}

// ---------------------------------------------------------------------------
// Entry-point
// ---------------------------------------------------------------------------
async function routeRequest(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (path === "/_security/csp-report") return cspReport(request);

    const appRedirect = !IS_APP_SUPPORTED ? unsupportedOccasionAppRedirect(path) : null;
    if (appRedirect) {
      return Response.redirect(new URL(appRedirect, url).toString(), 302);
    }

    if (path === "/backend-activation.json" && request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: activationCorsHeaders(),
      });
    }

    if (path === "/pro-poradatele" || path === "/pro-poradatele/") {
      if (!ORGANIZERS_ENABLED) return notFound();
      return Response.redirect(new URL("/" + url.search, url).href, 308);
    }
    if (ORGANIZERS_ENABLED) {
      if (["/", "/events", "/events/"].includes(path) && url.searchParams.get("create") === "1") {
        const target = new URL("/login", url); target.search = url.search; target.searchParams.delete("create");
        return Response.redirect(target.href, 308);
      }
      if (path === "/events/" || (path === "/" && url.searchParams.has("q"))) {
        return Response.redirect(new URL("/events" + url.search, url).href, 308);
      }
      if (path === "/") {
        const res = await serveAsset(env, request, "/organizers-page");
        const response = res.ok ? htmlResponse(res.body, res.headers, 200, "organizers") : notFound();
        response.headers.set("referrer-policy", "no-referrer");
        return response;
      }
      if (path === "/events") return handleHome(request, env);
    }

    if (path === "/sitemap.xml") return handleSitemap(request, env);

    if (path === "/" && FORCED_OCCASION_PATH) {
      const res = await serveAsset(env, request, WEB_CLIENT_INDEX);
      return htmlResponse(res.body, res.headers);
    }

    if (INTERNAL_ASSET_PATHS.has(path)) {
      if (url.searchParams.get("pwa-cache") === "1") {
        const res = await serveAsset(env, request, path);
        return htmlResponse(res.body, res.headers, 200, path === "/flutter" ? "flutter" : path === "/organizers-page" ? "organizers" : "webclient");
      }
      return Response.redirect(new URL("/", url).toString(), 301);
    }

    if (path === "/order") {
      const res = await serveAsset(env, request, WEB_CLIENT_INDEX);
      const response = htmlResponse(res.body, res.headers);
      response.headers.set("cache-control", "no-store");
      response.headers.set("referrer-policy", "no-referrer");
      response.headers.set("x-robots-tag", "noindex, nofollow");
      return response;
    }

    if (path.startsWith("/form/") &&
        ["order_id", "offer_id", "token", "waitlist"].some(key => url.searchParams.has(key))) {
      return new Response("Tento odkaz již není podporován.", { status: 410, headers: {
        "content-type": "text/plain; charset=utf-8", "cache-control": "no-store",
        "referrer-policy": "no-referrer", "x-robots-tag": "noindex, nofollow",
      }});
    }
    if (resolveScannerRoute(path)) {
      const res = await serveAsset(env, request, WEB_CLIENT_INDEX);
      const response = htmlResponse(res.body, res.headers);
      response.headers.set("cache-control", "no-store");
      response.headers.set("referrer-policy", "no-referrer");
      return response;
    }
    if (path.startsWith("/form/")) return handlePublicPage(request, env, path, 'form');
    if (/^\/[^/]+\/event\/?$/.test(path) && IS_APP_SUPPORTED) return handlePublicPage(request, env, path, 'event');

    // OAuth handoffs must reach the correct adapter and never enter HTML caches.
    const stripePrivateRoute = /^\/(?:app\/)?stripe\/(?:connect\/callback|pay|return)$/.test(path);
    if (stripePrivateRoute || path === "/google-auth" || path === "/app/google-auth" || path === "/settings/mcp-connect") {
      const entry = stripePrivateRoute || path === "/app/google-auth" ? FLUTTER_ENTRY : WEB_CLIENT_INDEX;
      // The browser retains callback parameters; the static asset fetch needs none.
      const assetUrl = new URL(request.url);
      assetUrl.search = "";
      const res = await serveAsset(env, stripePrivateRoute ? new Request(assetUrl) : request, entry);
      const response = htmlResponse(res.body, res.headers, 200, entry === FLUTTER_ENTRY ? "flutter" : "webclient");
      response.headers.set("cache-control", "no-store");
      response.headers.set("referrer-policy", "no-referrer");
      response.headers.set("x-robots-tag", "noindex, nofollow");
      return response;
    }

    if (["/.well-known/apple-app-site-association", "/apple-app-site-association", "/.well-known/assetlinks.json"].includes(path)) {
      const response = await env.ASSETS.fetch(request);
      const headers = new Headers(response.headers);
      headers.set("content-type", "application/json");
      return new Response(response.body, { status: response.status, headers });
    }

    if (WEB_CLIENT_EXACT.has(path) || /^\/unit\/[1-9]\d*\/?$/.test(path)) {
      return handleHome(request, env);
    }

    if (AUTH_BRIDGE_PATHS.has(path)) {
      const res = await serveAsset(env, request, AUTH_BRIDGE);
      return htmlResponse(res.body, res.headers, 200, "auth_bridge");
    }

    if (FLUTTER_PREFIXES.some(p => path === p || path.startsWith(p + "/"))) {
      const res = await serveAsset(env, request, FLUTTER_ENTRY);
      return htmlResponse(res.body, res.headers, 200, "flutter");
    }

    // Real static asset (favicon, web-assets/*, canvaskit/*, main.dart.js, ...).
    const assetRes = await env.ASSETS.fetch(request);
    if (assetRes.status !== 404) {
      // Flutter ships main.dart.js, its deferred *.part.js chunks and the wasm
      // runtime under STABLE, unversioned filenames that are overwritten on every
      // deploy. Cloudflare Pages serves them with max-age=14400, so after a deploy
      // a browser can hold e.g. a fresh main.dart.js next to a stale .part.js from
      // the previous build — an incompatible mix that crashes the app in a
      // render/paint loop. Force these runtime files to revalidate on every load
      // (index.html is already no-cache) so the whole JS/wasm graph always matches.
      if (MUTABLE_RUNTIME_ASSET.test(path)) {
        const headers = path === "/backend-activation.json"
          ? activationCorsHeaders(assetRes.headers)
          : new Headers(assetRes.headers);
        headers.set(
          "cache-control",
          path === "/backend-activation.json" || path === "/client-sync-config.json"
            ? "no-store, max-age=0"
            : "no-cache, must-revalidate",
        );
        return new Response(assetRes.body, {
          status: assetRes.status,
          statusText: assetRes.statusText,
          headers,
        });
      }
      if ((assetRes.headers.get('content-type') || '').includes('text/html')) {
        const file = path.slice(1);
        const doc = CSP_MANIFEST.documents[file] || CSP_MANIFEST.documents[file + 'index.html'] || CSP_MANIFEST.documents[file + '/index.html'];
        return htmlResponse(assetRes.body, assetRes.headers, assetRes.status, doc?.profile || 'none');
      }
      return assetRes;
    }

    // Missing images/scripts must never be returned as a successful HTML asset.
    if (/\.(?:png|svg|ico|jpg|jpeg|webp|gif|js|mjs|css|wasm|woff2?|ttf|json|xml|txt)$/i.test(path)) return notFound();

    // Preserve real occasion/private app deep links. Only a successful backend
    // answer may establish non-existence; an outage must not become a 404.
    if (env.SUPABASE_URL && env.SUPABASE_ANON_KEY) {
      try {
        const slug = decodeURIComponent(path.split('/').filter(Boolean)[0] || '');
        const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/get_occasion_seo_data`, {
          method: "POST", headers: { "content-type": "application/json",
            apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}` },
          body: JSON.stringify({ p_link_slug: slug }), signal: AbortSignal.timeout(2500),
        });
        if (response.ok && await response.json() === null) return notFound();
      } catch { /* Keep the established Flutter fallback during an outage. */ }
    }
    const fallback = await serveAsset(env, request, FLUTTER_ENTRY);
    return htmlResponse(fallback.body, fallback.headers, 200, "flutter");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const production = CANONICAL_ORIGIN && [new URL(CANONICAL_ORIGIN).hostname, "www." + new URL(CANONICAL_ORIGIN).hostname].includes(url.hostname);
    let response;
    if (production && (url.origin !== CANONICAL_ORIGIN)) {
      const target = new URL(CANONICAL_ORIGIN);
      target.pathname = url.pathname;
      target.search = url.search;
      response = Response.redirect(target.href, 308);
    } else {
      try { response = await routeRequest(request, env); }
      catch (error) {
        console.error("Public route unavailable", error.message);
        response = new Response("Service temporarily unavailable", { status: 503 });
      }
    }
    const headers = new Headers(response.headers);
    if (!headers.has("content-security-policy")) headers.set("content-security-policy", CSP_BASE);
    headers.set("x-content-type-options", "nosniff");
    if (production && url.protocol === "https:") headers.set("strict-transport-security", "max-age=300");
    return new Response(request.method === "HEAD" ? null : response.body, { status: response.status, statusText: response.statusText, headers });
  },
};
WORKER

node --input-type=module - <<'CSP'
import {readFile, writeFile} from 'node:fs/promises';
const file = 'build/web/_worker.js';
const manifest = JSON.parse(await readFile('build/web/csp-manifest.json', 'utf8'));
const source = await readFile(file, 'utf8');
await writeFile(file, source.replace('const CSP_MANIFEST = { profiles: {}, documents: {} };', () => 'const CSP_MANIFEST = ' + JSON.stringify(manifest) + ';'));
CSP
python3 - build/web/_worker.js automation/project.conf <<'PY'
import json
import pathlib
import re
import sys

worker_path, config_path = sys.argv[1:]
source = pathlib.Path(worker_path).read_text(encoding="utf-8")
scanner_routes = pathlib.Path("web_client/src/services/scanner_routes.js").read_text(encoding="utf-8").replace("export function", "function")
source = scanner_routes + "\n" + source
catalog = pathlib.Path("web_client/src/components/occasion/catalog.js").read_text(encoding="utf-8").replace("export function", "function")
source = source.replace("// SHARED_CATALOG_CLASSIFICATION", catalog)
public_seo = pathlib.Path("web_client/src/services/public_page_seo.js").read_text(encoding="utf-8").replace("export function", "function")
source = source.replace("// SHARED_PUBLIC_PAGE_SEO", public_seo)
config = pathlib.Path(config_path).read_text(encoding="utf-8")
app_supported = re.search(r'^IS_APP_SUPPORTED=(true|false)\s*$', config, re.MULTILINE)
if not app_supported:
    raise SystemExit("IS_APP_SUPPORTED must be true or false")
source = source.replace('const IS_APP_SUPPORTED = true;', 'const IS_APP_SUPPORTED = ' + app_supported.group(1) + ';', 1)
policy = pathlib.Path('web_client/src/services/public_occasion_routes.js').read_text(encoding="utf-8")
source = source.replace('// PUBLIC_OCCASION_ROUTE_POLICY', policy.replace('export function ', 'function '), 1)
match = re.search(r"^FORCE_OCCASION_LINK=(.*)$", config, re.MULTILINE)
occasion_link = match.group(1).strip().strip('"').strip("'") if match else ""
occasion_link = occasion_link.strip().strip("/")
replacement = json.dumps(f"/{occasion_link}/event" if occasion_link and app_supported.group(1) == 'true' else None)
web_link_match = re.search(r'^WEB_LINK=(.*)$', config, re.MULTILINE)
web_link = web_link_match.group(1).strip().strip('"').strip("'").rstrip('/') if web_link_match else ''
from urllib.parse import urlparse
canonical = urlparse(web_link)
if canonical.scheme != 'https' or not canonical.hostname or canonical.path or canonical.query or canonical.fragment or canonical.username or canonical.port:
    raise SystemExit("WEB_LINK must be a bare HTTPS origin for canonical routing")
source = source.replace('const CANONICAL_ORIGIN = null;', 'const CANONICAL_ORIGIN = ' + json.dumps(web_link) + ';', 1)
source = source.replace('const ORGANIZERS_ENABLED = false;', 'const ORGANIZERS_ENABLED = ' + ('true' if canonical.hostname == 'vstupenky.online' else 'false') + ';', 1)
name_match = re.search(r'^APP_TITLE_SHORT=(.*)$', config, re.MULTILINE) or re.search(r'^APP_NAME=(.*)$', config, re.MULTILINE)
site_name = name_match.group(1).strip().strip('"').strip("'") if name_match else 'Festapp'
source = source.replace('const SITE_NAME = "Festapp";', 'const SITE_NAME = ' + json.dumps(site_name, ensure_ascii=False) + ';', 1)
source, count = re.subn(
    r"const FORCED_OCCASION_PATH = null;",
    f"const FORCED_OCCASION_PATH = {replacement};",
    source,
    count=1,
)
if count != 1:
    raise SystemExit("Could not stamp FORCE_OCCASION_LINK into _worker.js")
pathlib.Path(worker_path).write_text(source, encoding="utf-8")
PY

node automation/verify_web_build.mjs build/web \
  "$(grep -m1 '^VERSION=' automation/project.conf | cut -d= -f2 | tr -d '[:space:]')" \
  automation/project.conf cloudflare

echo "Build complete. Output in build/web"
ls -la build/web | head -25
