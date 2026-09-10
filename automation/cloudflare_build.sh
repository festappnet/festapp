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

// Web client SPA routes (form list handled by /form/<slug> below).
const WEB_CLIENT_EXACT = new Set(["/"]);

// Flutter SPA routes (login / admin / handover).
const FLUTTER_PREFIXES = ["/login", "/admin", "/transfer"];

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

function htmlResponse(body, originHeaders) {
  const headers = new Headers(originHeaders || {});
  headers.set("content-type", "text/html; charset=utf-8");
  headers.set("cache-control", "no-cache, must-revalidate");
  headers.set("x-festapp-runtime", "cloudflare-pages");
  headers.delete("location");
  headers.delete("content-length");
  headers.delete("content-range");
  headers.delete("accept-ranges");
  return new Response(body, { status: 200, headers });
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
  const today = new Date().toISOString().split("T")[0];
  const xmlHeaders = { "content-type": "application/xml", "cache-control": "public, max-age=0, s-maxage=3600" };

  const fallback = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${baseUrl}/</loc>
    <lastmod>${today}</lastmod>
    <priority>1.0</priority>
  </url>
</urlset>`;

  try {
    const supabaseUrl = env.SUPABASE_URL;
    const supabaseKey = env.SUPABASE_ANON_KEY;
    const orgId = env.ORGANIZATION_ID || 1;
    if (!supabaseUrl || !supabaseKey) return new Response(fallback, { headers: xmlHeaders });

    const rpc = await fetch(`${supabaseUrl}/rest/v1/rpc/get_available_occasions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: supabaseKey,
        authorization: `Bearer ${supabaseKey}`,
      },
      body: JSON.stringify({ p_organization_id: orgId, p_unit_id: null }),
    });
    if (!rpc.ok) return new Response(fallback, { headers: xmlHeaders });

    const data = await rpc.json();
    let occasions = [];
    if (Array.isArray(data)) occasions = data;
    else if (data && Array.isArray(data.occasions)) occasions = data.occasions;
    else if (data && data.data && Array.isArray(data.data.occasions)) occasions = data.data.occasions;
    if (occasions.length === 0) return new Response(fallback, { headers: xmlHeaders });

    let xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`;
    xml += `  <url>\n    <loc>${baseUrl}/</loc>\n    <lastmod>${today}</lastmod>\n    <priority>1.0</priority>\n  </url>\n`;
    for (const occ of occasions) {
      const link = (occ && occ.link || "").trim();
      if (!link) continue;
      xml += `  <url>\n    <loc>${baseUrl}/form/${link}</loc>\n    <lastmod>${today}</lastmod>\n    <priority>0.8</priority>\n  </url>\n`;
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
    if (!slug) return htmlResponse(baseHtml, baseHeaders);

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
      body: JSON.stringify({ p_link_slug: slug }),
    });
    if (!rpc.ok) return htmlResponse(baseHtml, baseHeaders);
    const seo = await rpc.json();
    if (!seo) return htmlResponse(baseHtml, baseHeaders);

    const unitTitle = seo.unit_title;
    const orgTitle = seo.org_title || "Festapp";
    const title = seo.title || "Event";
    let description = seo.form_description || seo.description ||
      "Rychlé a jednoduché založení události, prodej vstupenek a registrace.";
    description = description.replace(/<[^>]+>/gm, " ").replace(/\s+/g, " ").trim();
    const imagePath = (seo.data && seo.data.image) || seo.image;
    let imageUrl;
    if (imagePath && imagePath.startsWith("http")) imageUrl = imagePath;
    else if (imagePath) imageUrl = `https://img.festapp.net/${imagePath}`;
    else imageUrl = `${url.origin}/android-chrome-512x512.png`;
    const fullTitle = `${title} - ${unitTitle || orgTitle}`;

    let page = baseHtml;
    page = page.replace(/<title[^>]*>.*?<\/title>/i, `<title>${fullTitle}</title>`);

    const replaceMeta = (attr, name, content) => {
      const re = new RegExp(`(<meta[^>]*${attr}=["']${name}["'][^>]*content=["'])([^"']*)(["'][^>]*>)`, "gi");
      if (re.test(page)) {
        page = page.replace(re, `$1${content}$3`);
      } else {
        const tagRe = new RegExp(`<meta[^>]*${attr}=["']${name}["'][^>]*>`, "gi");
        page = page.replace(tagRe, (m) => m.replace(/content=["'][^"']*["']/i, `content="${content}"`));
      }
    };

    replaceMeta("property", "og:title", fullTitle);
    replaceMeta("property", "twitter:title", fullTitle);
    replaceMeta("name", "description", description);
    replaceMeta("property", "og:description", description);
    replaceMeta("property", "twitter:description", description);
    replaceMeta("property", "og:image", imageUrl);
    replaceMeta("property", "twitter:image", imageUrl);
    replaceMeta("property", "og:url", url.href);
    replaceMeta("property", "twitter:url", url.href);
    page = page.replace(
      /<link[^>]*rel=["']canonical["'][^>]*href=["'][^"']*["'][^>]*>/i,
      `<link rel="canonical" href="${url.href}">`
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
export default {
  async fetch(request, env) {
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

    if (WEB_CLIENT_EXACT.has(path)) {
      const res = await serveAsset(env, request, WEB_CLIENT_INDEX);
      return htmlResponse(res.body, res.headers);
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

    // Unknown path -> Flutter SPA fallback (lets Flutter router handle it).
    const fallback = await serveAsset(env, request, FLUTTER_ENTRY);
    return htmlResponse(fallback.body, fallback.headers);
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
