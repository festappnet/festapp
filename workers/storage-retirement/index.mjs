// Reject retired Storage paths before Cloudflare can serve old cached objects.
export default {
  fetch(request) {
    const url = new URL(request.url);
    const retired = url.hostname === 'api.festapp.net' &&
      (url.pathname === '/storage/v1' || url.pathname.startsWith('/storage/v1/'));
    return new Response(retired ? 'Gone' : 'Not found', {
      status: retired ? 410 : 404,
      headers: { 'Cache-Control': 'no-store', 'Content-Type': 'text/plain; charset=utf-8' },
    });
  },
};
