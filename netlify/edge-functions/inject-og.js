export default async (request, context) => {
  let response;
  let page;
  
  try {
    const url = new URL(request.url);
    const legacyCanonicalOrigins = {
      'hvezdamorska.netlify.app': 'https://hvezdamorska.festapp.net',
      'clovekavira.netlify.app': 'https://clovekavira.festapp.net',
      'vstupenkyonline.netlify.app': 'https://vstupenky.online',
    };
    const canonicalOrigin = legacyCanonicalOrigins[url.hostname];
    if (canonicalOrigin) {
      return Response.redirect(canonicalOrigin + url.pathname + url.search, 301);
    }
    const parts = url.pathname.split('/');
    const slug = parts[2];

    if (!slug) {
      return context.next();
    }

    // 1. Strip Range and If-Range Headers to ensure we get full content
    // We must invoke context.next() with a modified request
    const newRequestHeaders = new Headers(request.headers);
    newRequestHeaders.delete("Range");
    newRequestHeaders.delete("If-Range");
    
    // Create new request with stripped headers
    const fullContentRequest = new Request(request, {
      headers: newRequestHeaders
    });

    // 2. Get upstream content (Full 200 response)
    response = await context.next(fullContentRequest);
    page = await response.text();

    // 3. Prepare default "Fail Open" reponse (200 OK)
    const createResponse = (body) => {
        const headers = new Headers(response.headers);
        headers.delete("Content-Length");
        headers.delete("Content-Range");
        headers.delete("Accept-Ranges");
        headers.set("Cache-Control", "no-cache, no-store, must-revalidate");
        headers.set("Pragma", "no-cache");
        headers.set("Expires", "0");
        headers.set("X-Edge-Version", "v4-fix-fail-open");
        
        return new Response(body, {
            status: 200, 
            headers: headers
        });
    };
    
    // 4. Fetch SEO Data via REST
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseKey) {
       return createResponse(page);
    }

    const rpcUrl = `${supabaseUrl}/rest/v1/rpc/get_occasion_seo_data`;
    
    const rpcResp = await fetch(rpcUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": supabaseKey,
        "Authorization": `Bearer ${supabaseKey}`
      },
      body: JSON.stringify({ p_link_slug: slug })
    });

    if (!rpcResp.ok) {
        return createResponse(page);
    }

    const seoData = await rpcResp.json();
    if (!seoData) {
        return createResponse(page);
    }

    // 5. Prepare Metadata
    const unitTitle = seoData.unit_title;
    const orgTitle = seoData.org_title || 'Festapp'; 
    const title = seoData.title || 'Event';
    
    // Clean HTML from description (Prioritize form_description)
    let description = seoData.form_description || seoData.description || 'Rychlé a jednoduché založení události, prodej vstupenek a registrace.';
    if (description) { // Check variable, not seoData field directly
        // Replace tags with spaces to prevent word concatenation (e.g. Line1<br>Line2 -> Line1 Line2)
        description = description.replace(/<[^>]+>/gm, ' ');
        // Collapse whitespace
        description = description.replace(/\s+/g, ' ').trim();
    }
    
    const imagePath = seoData.data?.image || seoData.image; 

    // Resolve Image URL
    let imageUrl;
    if (imagePath && imagePath.startsWith('http')) {
        imageUrl = imagePath;
    } else if (imagePath) {
        imageUrl = `https://img.festapp.net/${imagePath}`;
    } else {
        imageUrl = `${url.origin}/android-chrome-512x512.png`;
    }
    
    // Title Format: Event - Unit (fallback to Org)
    const suffix = unitTitle || orgTitle;
    const fullTitle = `${title} - ${suffix}`;
    let updatedPage = page;

    // 6. Injection
    const replaceMeta = (property, content) => {
        const regex = new RegExp(`(<meta[^>]*property=["']${property}["'][^>]*content=["'])([^"']*)(["'][^>]*>)`, 'gi');
        if (regex.test(updatedPage)) {
             updatedPage = updatedPage.replace(regex, `$1${content}$3`);
        } else {
            const tagRegex = new RegExp(`<meta[^>]*property=["']${property}["'][^>]*>`, 'gi');
            updatedPage = updatedPage.replace(tagRegex, (match) => {
                return match.replace(/content=["'][^"']*["']/i, `content="${content}"`);
            });
        }
    };

    const replaceTitle = (newTitle) => {
         updatedPage = updatedPage.replace(/<title[^>]*>.*?<\/title>/i, `<title>${newTitle}</title>`);
         replaceMeta('og:title', newTitle);
         replaceMeta('twitter:title', newTitle);
    };

    const replaceDesc = (newDesc) => {
         const tagRegex = /<meta[^>]*name=["']description["'][^>]*>/i;
         updatedPage = updatedPage.replace(tagRegex, (match) => {
             return match.replace(/content=["'][^"']*["']/i, `content="${newDesc}"`);
         });
         replaceMeta('og:description', newDesc);
         replaceMeta('twitter:description', newDesc);
    };

    const replaceImage = (newImage) => {
         replaceMeta('og:image', newImage);
         replaceMeta('twitter:image', newImage);
    };

    replaceTitle(fullTitle);
    replaceDesc(description);
    replaceImage(imageUrl);
    
    // Inject correct URL to prevent crawlers from falling back to Homepage metadata
    const replaceUrl = (newUrl) => {
         replaceMeta('og:url', newUrl);
         replaceMeta('twitter:url', newUrl);
    };
    replaceUrl(url.href);

    updatedPage = updatedPage.replace(/<link[^>]*rel=["']canonical["'][^>]*href=["'][^"']*["'][^>]*>/i, `<link rel="canonical" href="${url.href}">`);

    // Ensure headers are clean
    const finalHeaders = new Headers(response.headers);
    finalHeaders.delete("Content-Length");
    finalHeaders.delete("Content-Range");
    finalHeaders.delete("Accept-Ranges");
    finalHeaders.set("Cache-Control", "no-cache, no-store, must-revalidate");
    finalHeaders.set("Pragma", "no-cache");
    finalHeaders.set("Expires", "0");
    finalHeaders.set("X-Edge-Version", "v3-fix-206");

    return new Response(updatedPage, {
        status: 200, 
        headers: finalHeaders
    });

  } catch (e) {
    console.log("Edge error:", e);
    // FAIL OPEN STRATEGY:
    // 1. If we successfully fetched the upstream page, return it despite the error in our logic
    if (response) {
        // We need to clone it or create new response if we already consumed body
        // But we already read 'page' text.
        if (page) {
             console.log("Failing open with cached page content.");
             return new Response(page, {
                 status: 200,
                 headers: response.headers // context.next headers
             });
        }
    }
    
    // 2. If we haven't even fetched upstream yet, or failed to read it, try to pass through.
    try {
        console.log("Failing open with context.next()");
        return context.next();
    } catch (z) {
        console.log("Critical Fail Open Error:", z);
        return new Response("Internal Error (Fail Open Failed)", { status: 500 });
    }
  }
};

export const config = {
  path: "/form/*"
};
