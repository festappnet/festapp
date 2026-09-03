import type { Env } from './types';
import {
  authorizeImageDeletion,
  checkAkhEventManagerPermission,
  checkIsEditorOnAnyOccasion,
  extractBearerToken,
  removeImageRecords,
  type SupabaseAuth,
} from './auth';
import { assertControlHost, ProjectResolutionError, resolveControlProject } from './project-registry';
import { purgeSourceUrl } from './purge';
import { errorResponse, jsonResponse } from './responses';

const MAX_DELETE_LINKS = 50;

interface DeleteBody {
  projectId?: string;
  links?: string[];
  link?: string;
  key?: string;
  supabaseUrl?: string;
}

export async function handleDelete(request: Request, env: Env): Promise<Response> {
  if (request.method !== 'POST') return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Method not allowed');
  if (Number(request.headers.get('Content-Length') || 0) > 64 * 1024) {
    return errorResponse(413, 'REQUEST_TOO_LARGE', 'Delete request is too large');
  }
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) return errorResponse(401, 'AUTH_REQUIRED', 'Missing authorization header');

  let jwt: string;
  try { jwt = extractBearerToken(authHeader); }
  catch { return errorResponse(401, 'INVALID_TOKEN', 'Invalid token'); }

  let body: DeleteBody;
  try { body = await request.json() as DeleteBody; }
  catch { return errorResponse(400, 'INVALID_JSON', 'Invalid JSON body'); }

  let project;
  try {
    project = resolveControlProject(env, {
      projectId: body.projectId,
      legacySupabaseUrl: body.supabaseUrl,
    });
    assertControlHost(project, request.url);
  } catch (error) {
    if (error instanceof ProjectResolutionError) return errorResponse(400, error.code, error.message);
    throw error;
  }
  const auth: SupabaseAuth = { supabaseUrl: project.supabaseUrl, anonKey: project.anonKey };

  if (body.key !== undefined && body.key.startsWith('private/')) {
    if (!project.supportsPrivate) {
      return errorResponse(400, 'PRIVATE_NOT_SUPPORTED', 'Private images are not supported for this project');
    }
    if (!/^private\/[A-Za-z0-9._/-]+$/.test(body.key) || body.key.includes('..')) {
      return errorResponse(400, 'INVALID_PRIVATE_KEY', 'Only canonical private keys may be deleted by key');
    }
    if (!await checkIsEditorOnAnyOccasion(jwt, auth)) return errorResponse(403, 'FORBIDDEN', 'Forbidden');
    await project.privateBucket.delete(body.key);
    return jsonResponse({ deleted: true, key: body.key, projectId: project.id });
  }

  // Temporary measured-adoption alias for released clients that still send a
  // public object key. Reconstruct the exact stored link and use the same
  // database authorization as the canonical URL contract.
  const legacyLink = body.key !== undefined && /^images\/[A-Za-z0-9._/-]+$/.test(body.key) && !body.key.includes('..')
    ? `https://${project.publicHostname}/${body.key}`
    : null;
  if (body.key !== undefined && legacyLink === null) {
    return errorResponse(400, 'INVALID_IMAGE_KEY', 'Image key is not canonical');
  }
  const links = body.links ?? (body.link ? [body.link] : legacyLink ? [legacyLink] : []);
  if (!Array.isArray(links) || links.length === 0 || links.length > MAX_DELETE_LINKS ||
      links.some((link) => typeof link !== 'string')) {
    return errorResponse(400, 'INVALID_LINK_BATCH', `links must contain 1-${MAX_DELETE_LINKS} URLs`);
  }
  const uniqueLinks = [...new Set(links)];
  const parsed = uniqueLinks.map((link) => parsePublicLink(link, project.publicHostname, project.publicKeyPrefixes));
  if (parsed.some((item) => item === null)) {
    return errorResponse(400, 'PROJECT_LINK_MISMATCH', 'Every URL must be a canonical stored link for the selected project');
  }

  if (project.authContract === 'akhweb') {
    if (!await checkAkhEventManagerPermission(jwt, auth)) {
      return errorResponse(403, 'DELETE_NOT_AUTHORIZED', 'The delete batch is not authorized');
    }
  } else {
    const authorized = await authorizeImageDeletion(jwt, uniqueLinks, auth);
    if (authorized.length !== uniqueLinks.length || uniqueLinks.some((link) => !authorized.includes(link))) {
      return errorResponse(403, 'DELETE_NOT_AUTHORIZED', 'The complete delete batch is not authorized');
    }
  }

  const results: Array<{ link: string; deleted: boolean; code?: string; retryable?: boolean }> = [];
  const readyForRecordRemoval: string[] = [];
  for (let index = 0; index < uniqueLinks.length; index++) {
    const link = uniqueLinks[index];
    const key = parsed[index]!;
    try {
      await project.publicBucket.delete(key);
      await purgeSourceUrl(env, link);
      readyForRecordRemoval.push(link);
      results.push({ link, deleted: true });
    } catch (error) {
      const retryable = typeof error === 'object' && error !== null && 'retryable' in error
        ? Boolean((error as { retryable: boolean }).retryable) : true;
      results.push({ link, deleted: false, code: 'R2_OR_PURGE_FAILED', retryable });
    }
  }

  if (project.persistsImageRecords && readyForRecordRemoval.length > 0 &&
      !await removeImageRecords(jwt, readyForRecordRemoval, auth)) {
    for (const result of results) {
      if (readyForRecordRemoval.includes(result.link)) {
        result.deleted = false;
        result.code = 'RECORD_REMOVAL_FAILED';
        result.retryable = true;
      }
    }
  }

  const complete = results.every((result) => result.deleted);
  console.log('image_operation', { operation: 'delete', status: complete ? 'success' : 'partial', projectId: project.id });
  return jsonResponse({ complete, results }, complete ? 200 : 207);
}

function parsePublicLink(link: string, hostname: string, allowedPrefixes: readonly string[]): string | null {
  try {
    const url = new URL(link);
    if (url.protocol !== 'https:' || url.hostname !== hostname || url.port || url.username || url.password ||
        url.search || url.hash || url.pathname.includes('%') ||
        url.pathname.split('/').includes('..')) return null;
    const key = url.pathname.slice(1);
    return allowedPrefixes.some((prefix) => key.startsWith(prefix)) ? key : null;
  } catch { return null; }
}
