// Sitemap Generator Edge Function
// Fetches active occasions from Supabase and generates dynamic XML.
// Implements Fail-Open Strategy (returns fallback minimal sitemap upon failure).

export default async (request, context) => {
    const defaultSitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://vstupenky.online/</loc>
    <priority>1.0</priority>
  </url>
</urlset>`;

    try {
        const url = new URL(request.url);
        const baseUrl = url.origin;
        
        // 1. Supabase Check
        const supabaseUrl = Deno.env.get("SUPABASE_URL");
        const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY");
        const orgId = Deno.env.get("ORGANIZATION_ID") || 1; // Use Env Var or Default

        if (!supabaseUrl || !supabaseKey) {
            console.warn("Missing Supabase credentials, falling back to static sitemap.");
            return new Response(defaultSitemap, {
                headers: { "Content-Type": "application/xml" }
            });
        }

        // 2. Fetch Public Occasions
        const rpcUrl = `${supabaseUrl}/rest/v1/rpc/get_available_occasions`;
        const rpcResp = await fetch(rpcUrl, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "apikey": supabaseKey,
                "Authorization": `Bearer ${supabaseKey}`
            },
            body: JSON.stringify({ 
                p_organization_id: orgId,
                p_unit_id: null 
            })
        });

        if (!rpcResp.ok) {
            console.error(`Supabase RPC Error: ${rpcResp.status} ${rpcResp.statusText}`);
            return new Response(defaultSitemap, {
                headers: { "Content-Type": "application/xml" }
            });
        }

        // 3. Parse Data (Handle various wrapper structures)
        const data = await rpcResp.json();
        let occasions = [];
        
        if (Array.isArray(data)) {
            occasions = data;
        } else if (data && Array.isArray(data.occasions)) {
            occasions = data.occasions;
        } else if (data && data.data && Array.isArray(data.data.occasions)) {
            occasions = data.data.occasions;
        }

        if (occasions.length === 0) {
             return new Response(defaultSitemap, {
                headers: { "Content-Type": "application/xml" }
            });
        }

        // 4. Build XML
        const today = new Date().toISOString().split('T')[0];
        let xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n`;
        
        // Root
        xml += `  <url>\n    <loc>${baseUrl}/</loc>\n    <lastmod>${today}</lastmod>\n    <priority>1.0</priority>\n  </url>\n`;

        // Occasions
        occasions.forEach(occ => {
            if (occ && occ.link) {
                // Ensure slug is clean
                const cleanLink = occ.link.trim();
                if (cleanLink) {
                    xml += `  <url>\n    <loc>${baseUrl}/form/${cleanLink}</loc>\n    <lastmod>${today}</lastmod>\n    <priority>0.8</priority>\n  </url>\n`;
                }
            }
        });

        xml += `</urlset>`;

        // 5. Return Response with Caching
        const headers = new Headers();
        headers.set("Content-Type", "application/xml");
        // Cache for 1 hour on CDN, revalidate immediately on browser
        headers.set("Cache-Control", "public, max-age=0, s-maxage=3600"); 

        return new Response(xml, { 
            status: 200, 
            headers: headers 
        });

    } catch (e) {
        console.error("Sitemap Generation Error:", e);
        // Fail Open
        return new Response(defaultSitemap, {
            headers: { "Content-Type": "application/xml" }
        });
    }
};

export const config = {
  path: "/sitemap.xml"
};
