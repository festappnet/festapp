import type { Env } from './types';
import { extractBearerToken, issuePrivateImageGrant } from './auth';
import { assertControlHost, resolveControlProject, ProjectResolutionError } from './project-registry';
import { errorResponse, jsonResponse } from './responses';
import { isPrivateKey } from './private-key';

const DEFAULT_EXPIRES_IN = 3600; // 1 hour
const MAX_EXPIRES_IN = 604800; // 7 days

/** Share a bounded private download that rechecks the issuing session. */
export async function handlePresign(
  request: Request,
  env: Env
): Promise<Response> {
  if (request.method !== 'POST') return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Method not allowed');
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

  // Extract key from path: /presign/{key}
  const url = new URL(request.url);
  const key = url.pathname.replace('/presign/', '');

  let project;
  try {
    project = resolveControlProject(env, {
      projectId: url.searchParams.get('projectId'),
      legacySupabaseUrl: url.searchParams.get('supabaseUrl'),
    });
    assertControlHost(project, request.url);
    if (!project.supportsPrivate) throw new ProjectResolutionError('Private images are not supported for this project');
  } catch (error) {
    if (error instanceof ProjectResolutionError) return errorResponse(400, error.code, error.message);
    throw error;
  }
  const auth = { supabaseUrl: project.supabaseUrl, anonKey: project.anonKey };

  if (!key) {
    return errorResponse(400, 'MISSING_KEY', 'Missing key');
  }
  if (!isPrivateKey(key)) {
    return errorResponse(400, 'INVALID_PRIVATE_KEY', 'Invalid private key');
  }

  // Parse optional expiresIn query param
  const expiresInRaw = url.searchParams.get('expiresIn');
  let expiresIn = DEFAULT_EXPIRES_IN;
  if (expiresInRaw) {
    const parsed = parseInt(expiresInRaw, 10);
    if (!/^\d+$/.test(expiresInRaw) || isNaN(parsed) || parsed <= 0 || parsed > MAX_EXPIRES_IN) {
      return errorResponse(400, 'INVALID_EXPIRY', 'expiresIn must be 1-604800 seconds');
    }
    expiresIn = parsed;
  }

  const grant = await issuePrivateImageGrant(userJwt, auth, project.id, key, expiresIn);
  if (!grant) return errorResponse(403, 'FORBIDDEN', 'Forbidden');

  const download = new URL(`/${key}`, url.origin);
  download.searchParams.set('projectId', project.id);
  download.searchParams.set('grant', grant.code);
  const response = jsonResponse({ url: download.href, expiresIn: grant.expiresIn, projectId: project.id });
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}
