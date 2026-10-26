import type { Env } from './types';
import { errorResponse } from './responses';

function allowedOrigin(request: Request, env: Env): string | null {
  const origin = request.headers.get('Origin');
  if (!origin) return null;
  const allowed = new Set((env.CONTROL_ALLOWED_ORIGINS || '').split(',').map((v) => v.trim()).filter(Boolean));
  return allowed.has(origin) ? origin : null;
}

/**
 * Handle CORS preflight (OPTIONS) requests.
 */
export function handleCors(request: Request, env: Env): Response {
  const origin = allowedOrigin(request, env);
  if (!origin) return errorResponse(403, 'ORIGIN_NOT_ALLOWED', 'Origin is not allowed');
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Max-Age': '86400',
      'Vary': 'Origin',
    },
  });
}

/**
 * Public image reads are intentionally credential-free and may be embedded by
 * any web client. They therefore do not depend on the control-plane allowlist.
 */
export function handlePublicReadCors(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Max-Age': '86400',
    },
  });
}

/**
 * Add CORS headers to an existing response.
 */
export function addCorsHeaders(request: Request, env: Env, response: Response): Response {
  const origin = allowedOrigin(request, env);
  if (!origin) return response;
  const newResponse = new Response(response.body, response);
  newResponse.headers.set('Access-Control-Allow-Origin', origin);
  newResponse.headers.append('Vary', 'Origin');
  return newResponse;
}

export function addPublicReadCorsHeaders(response: Response): Response {
  const newResponse = new Response(response.body, response);
  newResponse.headers.set('Access-Control-Allow-Origin', '*');
  return newResponse;
}
