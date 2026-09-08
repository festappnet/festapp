const GUARDED_HOST = "api.festapp.net";
const GUARDED_PREFIX = "/functions/v1/";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.hostname !== GUARDED_HOST || !url.pathname.startsWith(GUARDED_PREFIX)) {
      return new Response("Not Found", { status: 404 });
    }
    return new Response(JSON.stringify({ error: "canonical_functions_not_activated" }), {
      status: 503,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "Retry-After": "300",
      },
    });
  },
};
