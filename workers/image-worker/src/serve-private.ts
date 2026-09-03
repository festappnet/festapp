import type { Env } from './types';
import { extractBearerToken, checkIsEditorOnAnyOccasion } from './auth';
import {
  assertControlHost,
  resolveControlProject,
  resolveProjectByHostname,
  ProjectResolutionError,
} from './project-registry';
import { errorResponse } from './responses';

/**
 * Serve private files from R2 with JWT authentication and editor permission check.
 *
 * Replicates the `get_is_editor_on_any_occasion()` RLS policy (Pitfall 7):
 * editor on ANY occasion can access private files.
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
  // Authenticate
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse(401, 'AUTH_REQUIRED', 'Missing authorization header');
  }

  let userJwt: string;
  try {
    userJwt = extractBearerToken(authHeader);
  } catch {
    return errorResponse(401, 'INVALID_TOKEN', 'Invalid token');
  }

  const url = new URL(request.url);
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
  const isEditor = await checkIsEditorOnAnyOccasion(userJwt, auth);
  if (!isEditor) {
    return errorResponse(403, 'FORBIDDEN', 'Forbidden');
  }

  // Extract key from path — keep the private/ prefix (matches R2 key from upload)
  const key = url.pathname.slice(1); // Remove leading /

  if (!key) {
    return new Response('Not found', { status: 404 });
  }

  if (!key.startsWith('private/') || key.includes('..')) return errorResponse(400, 'INVALID_PRIVATE_KEY', 'Invalid private key');
  let object = await project.privateBucket.get(key);
  if (!object && env.PRIVATE_MIGRATION_FALLBACK === 'enabled') {
    object = await project.publicBucket.get(key);
    if (object) console.log('image_operation', {
      operation: 'private_migration_fallback', status: 'hit', projectId: project.id,
    });
  }
  if (!object) {
    return new Response('Not found', { status: 404 });
  }

  // Build response with private cache headers
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Cache-Control', 'private, no-cache');

  return new Response(request.method === 'HEAD' ? null : object.body, { headers });
}
