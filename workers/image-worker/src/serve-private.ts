import type { Env } from './types';
import { extractBearerToken, checkImageProjectAccess, redeemPrivateImageGrant } from './auth';
import {
  assertControlHost,
  resolveControlProject,
  resolveProjectByHostname,
  ProjectResolutionError,
} from './project-registry';
import { errorResponse } from './responses';
import { isPrivateKey } from './private-key';
import { assetKey } from './asset-key';

/**
 * Serve private files from R2 with JWT authentication and editor permission check.
 *
 * Preserves editor sharing inside the original project through the canonical
 * SQL project boundary; sharing must not expand after backend consolidation.
 *
 * Private files are served with no-cache headers to prevent CDN caching.
 */
export async function handlePrivate(
  request: Request,
  env: Env
): Promise<Response> {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Method not allowed');
  }
  const url = new URL(request.url);
  const grant = url.searchParams.get('grant');
  const authHeader = request.headers.get('Authorization');
  let userJwt: string | undefined;
  if (authHeader) {
    try {
      userJwt = extractBearerToken(authHeader);
    } catch {
      return errorResponse(401, 'INVALID_TOKEN', 'Invalid token');
    }
  } else if (grant === null) {
    return errorResponse(401, 'AUTH_REQUIRED', 'Missing authorization header');
  }

  let project;
  try {
    const projectId = url.searchParams.get('projectId');
    const legacySupabaseUrl = url.searchParams.get('supabaseUrl');
    project = projectId || legacySupabaseUrl
      ? resolveControlProject(env, { projectId, legacySupabaseUrl })
      : resolveProjectByHostname(env, url.hostname);
    assertControlHost(project, request.url);
    if (!project.supportsPrivate) throw new ProjectResolutionError('Private images are not supported for this project');
  } catch (error) {
    if (error instanceof ProjectResolutionError) return errorResponse(400, error.code, error.message);
    throw error;
  }
  const auth = { supabaseUrl: project.supabaseUrl, anonKey: project.anonKey };
  const key = url.pathname.slice(1);
  if (!isPrivateKey(key)) return errorResponse(400, 'INVALID_PRIVATE_KEY', 'Invalid private key');

  const allowed = userJwt
    ? await checkImageProjectAccess(userJwt, auth, project.id)
    : grant !== null && await redeemPrivateImageGrant(grant, auth, project.id, key);
  if (!allowed) return errorResponse(403, 'FORBIDDEN', 'Forbidden');

  const object = await project.privateBucket.get(assetKey(project, key));
  if (!object) {
    return new Response('Not found', { status: 404 });
  }

  // Build response with private cache headers
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Cache-Control', 'private, no-store');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'no-referrer');
  if (!userJwt) headers.set('Content-Security-Policy', 'sandbox');

  return new Response(request.method === 'HEAD' ? null : object.body, { headers });
}
