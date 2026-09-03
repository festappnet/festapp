import { AwsClient } from 'aws4fetch';
import type { Env } from './types';
import { extractBearerToken, checkIsEditorOnAnyOccasion } from './auth';
import { assertControlHost, resolveControlProject, ProjectResolutionError } from './project-registry';
import { errorResponse, jsonResponse } from './responses';

const DEFAULT_EXPIRES_IN = 3600; // 1 hour
const MAX_EXPIRES_IN = 604800; // 7 days

/**
 * Generate presigned S3-compatible URLs for private R2 files.
 *
 * Uses aws4fetch AwsClient with signQuery: true (Pitfall 4) to produce
 * time-limited signed URLs that can be shared for direct file access.
 */
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

  // Check editor-on-any-occasion permission via RPC
  const isEditor = await checkIsEditorOnAnyOccasion(userJwt, auth);
  if (!isEditor) {
    return errorResponse(403, 'FORBIDDEN', 'Forbidden');
  }

  if (!key) {
    return errorResponse(400, 'MISSING_KEY', 'Missing key');
  }
  if (key.length > 1024 || !key.startsWith('private/') || key.includes('..') || key.includes('%')) {
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

  // Create AWS client for R2 S3-compatible API
  const client = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
  });

  // Construct R2 S3-compatible URL
  const r2Url = new URL(
    `https://${env.CF_ACCOUNT_ID}.r2.cloudflarestorage.com/${project.privateBucketName}/${key}`
  );
  r2Url.searchParams.set('X-Amz-Expires', String(expiresIn));

  // Sign with signQuery to avoid Content-Type mismatch (Pitfall 4)
  const signed = await client.sign(r2Url.toString(), {
    method: 'GET',
    aws: { signQuery: true },
  });

  return jsonResponse({ url: signed.url, expiresIn, projectId: project.id });
}
