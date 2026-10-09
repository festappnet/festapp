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

const WEB_CLIENT_INDEX = "/webclient";
const FLUTTER_ENTRY = "/flutter";
const AUTH_BRIDGE = "/auth_bridge";
const FORCED_OCCASION_PATH = null; // replaced from project.conf after generation
const SITE_NAME = "Festapp"; // replaced from project.conf after generation

// Web client SPA routes (form list handled by /form/<slug> below).
const WEB_CLIENT_EXACT = new Set(["/"]);

// Flutter SPA routes (login / admin / handover).
const FLUTTER_PREFIXES = ["/login", "/login-qr", "/admin", "/transfer", "/unit", "/signup", "/settings", "/install", "/instanceInstall", "/scan", "/check", "/map-editor", "/resetPassword", "/forgotPassword", "/reset-password", "/forgot-password"];

// auth_bridge.html alias — RouterService still posts to /auth_bridge.html.
const AUTH_BRIDGE_PATHS = new Set(["/auth_bridge", "/auth_bridge.html"]);

// Internal asset names (extension-less HTML entry points). Cloudflare serves
// these as application/octet-stream to direct hits, which triggers a browser
// download. They must never be reachable as a user-facing URL — redirect to /.
const INTERNAL_ASSET_PATHS = new Set(["/flutter", "/webclient"]);

// Flutter's entry/runtime files use stable, unversioned names that change on
// every deploy (main.dart.js, its main.dart.js_<n>.part.js deferred chunks,
// the bootstrap/loader, and the canvaskit/skwasm wasm runtime). These must be
// revalidated on every load so a client never mixes assets from two builds.
const MUTABLE_RUNTIME_ASSET = /(?:^|\/)(?:backend-activation\.json|client-sync-config\.json|festapp-version\.json|main\.dart\.js(?:_\d+\.part\.js)?|main\.dart\.mjs|flutter_bootstrap\.js|flutter\.js|flutter_service_worker\.js|festapp_service_worker\.js|festapp_update_prompt\.js|(?:canvaskit|skwasm)[\w.]*\.(?:js|mjs|wasm))$/;

function htmlResponse(body, originHeaders, status = 200) {
  const headers = new Headers(originHeaders || {});
  headers.set("content-type", "text/html; charset=utf-8");
  headers.set("cache-control", "no-cache, must-revalidate");
  headers.set("x-festapp-runtime", "cloudflare-pages");
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
  return slug ? `/${encodeURIComponent(slug)}/event` : null;
}

async function publicOccasions(env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return [];
  const rpc = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/get_available_occasions`, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: env.SUPABASE_ANON_KEY,
      authorization: `Bearer ${env.SUPABASE_ANON_KEY}` },
    body: JSON.stringify({ p_organization_id: env.ORGANIZATION_ID || 1, p_unit_id: null }),
    signal: AbortSignal.timeout(2500),
  });
  if (!rpc.ok) throw new Error(`Public catalog HTTP ${rpc.status}`);
  const data = await rpc.json();
  return Array.isArray(data) ? data : data?.occasions || data?.data?.occasions || [];
}

async function handleHome(request, env) {
  const base = await serveAsset(env, request, WEB_CLIENT_INDEX);
  let html = await base.text();
  try {
    const occasions = await publicOccasions(env);
    const links = occasions.map(occasion => {
      const href = occasionHref(occasion);
      return href ? `<li><a href="${escapeHtml(href)}">${escapeHtml(occasion.title)}</a></li>` : "";
    }).join("");
    if (links) html = html.replace('<div id="events-grid"></div>', `<div id="events-grid"><ul>${links}</ul></div>`);
  } catch (error) {
    console.error("Public catalog HTML unavailable", error.message);
  }
  return htmlResponse(html, base.headers);
}

function notFound() {
  return htmlResponse('<!doctype html><html lang="cs"><head><meta charset="utf-8"><meta name="robots" content="noindex"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Stránka nenalezena</title></head><body><main><h1>Stránka nenalezena</h1><p><a href="/">Zpět na hlavní stránku</a></p></main></body></html>', null, 404);
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
  const baseUrl = url.origin;
  const xmlHeaders = { "content-type": "application/xml", "cache-control": "public, max-age=0, s-maxage=3600" };

  const fallback = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${baseUrl}/</loc>
    <priority>1.0</priority>
  </url>
</urlset>`;

  try {
    const occasions = await publicOccasions(env);
    if (occasions.length === 0) return new Response(fallback, { headers: xmlHeaders });

    let xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`;
    xml += `  <url>\n    <loc>${escapeHtml(baseUrl)}/</loc>\n    <priority>1.0</priority>\n  </url>\n`;
    for (const occ of occasions) {
      const href = occasionHref(occ);
      if (!href || !href.startsWith("/")) continue;
      xml += `  <url>\n    <loc>${escapeHtml(baseUrl + href)}</loc>\n    <priority>0.8</priority>\n  </url>\n`;
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
async function handleForm(request, env, path) {
  // Fetch base HTML (web client index) so the rest of the SPA works as usual.
  const baseRes = await serveAsset(env, request, WEB_CLIENT_INDEX);
  const baseHtml = await baseRes.text();
  const baseHeaders = baseRes.headers;

  try {
    const url = new URL(request.url);
    const slug = path.replace(/^\/form\//, "").split("/")[0];
    if (!slug || path.split("/").filter(Boolean).length !== 2) return notFound();

    const supabaseUrl = env.SUPABASE_URL;
    const supabaseKey = env.SUPABASE_ANON_KEY;
    if (!supabaseUrl || !supabaseKey) return htmlResponse(baseHtml, baseHeaders);

    const rpc = await fetch(`${supabaseUrl}/rest/v1/rpc/get_occasion_seo_data`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: supabaseKey,
        authorization: `Bearer ${supabaseKey}`,
      },
      body: JSON.stringify({ p_link_slug: decodeURIComponent(slug) }),
      signal: AbortSignal.timeout(2500),
    });
    if (!rpc.ok) return htmlResponse(baseHtml, baseHeaders);
    const seo = await rpc.json();
    if (!seo) return notFound();

    const orgTitle = SITE_NAME;
    const title = seo.title || "Event";
    let description = seo.form_description || seo.description ||
      "Rychlé a jednoduché založení události, prodej vstupenek a registrace.";
    description = description.replace(/<[^>]+>/gm, " ").replace(/\s+/g, " ").trim();
    const imagePath = (seo.data && seo.data.image) || seo.image;
    let imageUrl;
    if (imagePath && /^https?:\/\//i.test(imagePath)) imageUrl = imagePath;
    else if (imagePath) imageUrl = `https://img.festapp.net/${imagePath}`;
    else imageUrl = `${url.origin}/android-chrome-512x512.png`;
    const fullTitle = `${title} - ${orgTitle}`;
    const canonicalUrl = new URL(url.pathname, url.origin).href;

    let page = baseHtml;
    page = page.replace(/<title[^>]*>.*?<\/title>/i, () => `<title>${escapeHtml(fullTitle)}</title>`);

    const replaceMeta = (attr, name, content) => {
      const re = new RegExp(`(<meta[^>]*${attr}=["']${name}["'][^>]*content=["'])([^"']*)(["'][^>]*>)`, "gi");
      if (re.test(page)) {
        page = page.replace(re, (_match, before, _old, after) => before + escapeHtml(content) + after);
      } else {
        const tagRe = new RegExp(`<meta[^>]*${attr}=["']${name}["'][^>]*>`, "gi");
        page = page.replace(tagRe, (m) => m.replace(/content=["'][^"']*["']/i, () => `content="${escapeHtml(content)}"`));
      }
    };

    replaceMeta("property", "og:title", fullTitle);
    replaceMeta("property", "twitter:title", fullTitle);
    replaceMeta("name", "description", description);
    replaceMeta("property", "og:description", description);
    replaceMeta("property", "twitter:description", description);
    replaceMeta("property", "og:image", imageUrl);
    replaceMeta("property", "twitter:image", imageUrl);
    replaceMeta("property", "og:url", canonicalUrl);
    replaceMeta("property", "twitter:url", canonicalUrl);
    page = page.replace(
      /<link[^>]*rel=["']canonical["'][^>]*href=["'][^"']*["'][^>]*>/i,
      () => `<link rel="canonical" href="${escapeHtml(canonicalUrl)}">`
    );

    return htmlResponse(page, baseHeaders);
  } catch (e) {
    console.error("form OG inject error", e);
    return htmlResponse(baseHtml, baseHeaders);
  }
}

// ---------------------------------------------------------------------------
// Entry-point
// ---------------------------------------------------------------------------
async function routeRequest(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/backend-activation.json" && request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: activationCorsHeaders(),
      });
    }

    if (path === "/sitemap.xml") return handleSitemap(request, env);

    if (path === "/" && FORCED_OCCASION_PATH) {
      return Response.redirect(new URL(FORCED_OCCASION_PATH, url).toString(), 302);
    }

    if (INTERNAL_ASSET_PATHS.has(path)) {
      if (url.searchParams.get("pwa-cache") === "1") {
        const res = await serveAsset(env, request, path);
        return htmlResponse(res.body, res.headers);
      }
      return Response.redirect(new URL("/", url).toString(), 301);
    }

    if (path.startsWith("/form/")) return handleForm(request, env, path);

    // OAuth handoffs must reach the correct adapter and never enter HTML caches.
    if (path === "/google-auth" || path === "/app/google-auth") {
      const entry = path === "/google-auth" ? WEB_CLIENT_INDEX : FLUTTER_ENTRY;
      const res = await serveAsset(env, request, entry);
      const response = htmlResponse(res.body, res.headers);
      response.headers.set("cache-control", "no-store");
      response.headers.set("referrer-policy", "no-referrer");
      return response;
    }

    if (["/.well-known/apple-app-site-association", "/apple-app-site-association", "/.well-known/assetlinks.json"].includes(path)) {
      const response = await env.ASSETS.fetch(request);
      const headers = new Headers(response.headers);
      headers.set("content-type", "application/json");
      return new Response(response.body, { status: response.status, headers });
    }

    if (WEB_CLIENT_EXACT.has(path)) {
      return handleHome(request, env);
    }

    if (AUTH_BRIDGE_PATHS.has(path)) {
      const res = await serveAsset(env, request, AUTH_BRIDGE);
      return htmlResponse(res.body, res.headers);
    }

    if (FLUTTER_PREFIXES.some(p => path === p || path.startsWith(p + "/"))) {
      const res = await serveAsset(env, request, FLUTTER_ENTRY);
      return htmlResponse(res.body, res.headers);
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
    return htmlResponse(fallback.body, fallback.headers);
}

export default {
  async fetch(request, env) {
    const response = await routeRequest(request, env);
    // Advanced-mode Pages routing bypasses _headers. Apply the shared policy
    // to the final response, retaining route-specific cache and CORS headers.
    const headers = new Headers(response.headers);
    headers.set("content-security-policy", "base-uri 'self'; object-src 'none'");
    headers.set("x-content-type-options", "nosniff");
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  },
};
WORKER

python3 - build/web/_worker.js automation/project.conf <<'PY'
import json
import pathlib
import re
import sys

worker_path, config_path = sys.argv[1:]
source = pathlib.Path(worker_path).read_text(encoding="utf-8")
config = pathlib.Path(config_path).read_text(encoding="utf-8")
match = re.search(r"^FORCE_OCCASION_LINK=(.*)$", config, re.MULTILINE)
occasion_link = match.group(1).strip().strip('"').strip("'") if match else ""
occasion_link = occasion_link.strip().strip("/")
replacement = json.dumps(f"/{occasion_link}/event" if occasion_link else None)
name_match = re.search(r'^APP_NAME=(.*)$', config, re.MULTILINE)
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
