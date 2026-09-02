import { encode as base64Encode } from "https://deno.land/std@0.170.0/encoding/base64.ts";
import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { fetchPublicImage, UnsafeTargetError } from "./safeFetch.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    const body = await req.json();
    const { targetUrl, occasionId } = body ?? {};

    if (!targetUrl || !Number.isSafeInteger(occasionId) || occasionId <= 0) {
      return new Response(JSON.stringify({ error: "Invalid request" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }
    await authorizeRequest({
      authorizationHeader: req.headers.get("Authorization"),
      occasionId,
    });

    const image = await fetchPublicImage(targetUrl);
    const base64Data = base64Encode(Uint8Array.from(image.bytes).buffer);

    // Return the data as JSON.
    return new Response(
      JSON.stringify({ data: base64Data, contentType: image.contentType }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
        status: 200,
      }
    );
  } catch (error) {
    const status = error instanceof AuthError ? error.status
      : error instanceof UnsafeTargetError ? 400 : 500;
    console.error("fetch_http_data_failed", { status });
    return new Response(
      JSON.stringify({ error: status === 500 ? "Unexpected error occurred" : "Request rejected" }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status,
      }
    );
  }
});
