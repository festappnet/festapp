import { MAX_IMAGE_INPUT_BYTES, readUploadForm, resolveUploadPolicy, processUploadImage, ImageProcessingError } from './upload-policy';
import type { Env } from './types';
import {
  checkAkhEventManagerPermission,
  checkImageProjectAccess,
  extractBearerToken,
  type SupabaseAuth,
} from './auth';
import { assertControlHost, resolveControlProject, ProjectResolutionError } from './project-registry';
import { errorResponse, jsonResponse } from './responses';
import { isPrivateKey } from './private-key';
import { assetKey } from './asset-key';

/**
 * Sanitize a filename: remove special chars, keep alphanumeric, hyphens, underscores, dots.
 */
function sanitizeFilename(name: string): string {
  const ext = name.lastIndexOf('.') >= 0 ? name.slice(name.lastIndexOf('.')) : '';
  const base = name.slice(0, name.length - ext.length);
  const sanitized = base.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 100);
  return sanitized + ext.toLowerCase();
}

/**
 * Handle authenticated image upload with optional compression via Images Binding.
 *
 * Accepts multipart form data with:
 *   file         — The image file to upload (required)
 *   occasionId   — Occasion context for permission check
 *   unitId       — Unit context for permission check (alternative to occasionId)
 *   maxEdge      — Override longer-edge limit in px  (optional, default 1200)
 *   maxBytes     — Override byte threshold — skip transform if file is smaller (optional, default 800 KB)
 *   quality      — Override JPEG quality 1-100 (optional, default 70)
 */
export async function handleUpload(
  request: Request,
  env: Env
): Promise<Response> {
  if (request.method !== 'POST') {
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

  // Parse multipart form data
  let formData: FormData;
  try {
    formData = await readUploadForm(request);
  } catch (error) {
    if (error instanceof ImageProcessingError) return errorResponse(error.status, error.code, error.message, error.retryable);
    return errorResponse(400, 'INVALID_FORM_DATA', 'Invalid form data');
  }

  const file = formData.get('file') as File | null;
  const occasionIdRaw = formData.get('occasionId');
  const unitIdRaw = formData.get('unitId');

  if (!file) {
    return errorResponse(400, 'MISSING_FILE', 'Missing file field');
  }

  const occasionId = occasionIdRaw ? Number(occasionIdRaw) : null;
  const unitId = unitIdRaw ? Number(unitIdRaw) : null;

  if (occasionIdRaw && (occasionId === null || !Number.isSafeInteger(occasionId) || occasionId <= 0)) {
    return errorResponse(400, 'INVALID_OCCASION', 'Invalid occasionId');
  }

  if (unitIdRaw && (unitId === null || !Number.isSafeInteger(unitId) || unitId <= 0)) {
    return errorResponse(400, 'INVALID_UNIT', 'Invalid unitId');
  }

  let project;
  try {
    project = resolveControlProject(env, {
      projectId: formData.get('projectId') as string | null,
      // Temporary canonical URL alias for the measured installed-client window.
      legacySupabaseUrl: formData.get('supabaseUrl') as string | null,
    });
    assertControlHost(project, request.url);
  } catch (error) {
    if (error instanceof ProjectResolutionError) {
      return errorResponse(400, error.code, error.message);
    }
    throw error;
  }
  const auth: SupabaseAuth = { supabaseUrl: project.supabaseUrl, anonKey: project.anonKey };

  if (project.authContract === 'festapp' && ((!occasionIdRaw && !unitIdRaw) || (occasionIdRaw && unitIdRaw))) {
    return errorResponse(400, 'INVALID_OWNER', 'Exactly one of occasionId or unitId is required');
  }
  if (project.authContract === 'akhweb' && (occasionIdRaw || unitIdRaw)) {
    return errorResponse(400, 'INVALID_OWNER', 'AKH uploads do not accept Festapp owner identifiers');
  }

  // Check the selected project's permission contract using the user's JWT.
  let isEditor = false;
  if (project.authContract === 'akhweb') {
    isEditor = await checkAkhEventManagerPermission(userJwt, auth);
  } else {
    isEditor = await checkImageProjectAccess(userJwt, auth, project.id, occasionId, unitId);
  }
  if (!isEditor) {
    return errorResponse(403, 'FORBIDDEN', 'Forbidden');
  }

  if (file.size > MAX_IMAGE_INPUT_BYTES) return errorResponse(413, 'FILE_TOO_LARGE', 'Image exceeds 20 MB');
  let policy;
  try { policy = resolveUploadPolicy(formData); }
  catch (error) {
    if (error instanceof ImageProcessingError) return errorResponse(error.status, error.code, error.message);
    throw error;
  }

  // Use explicit key for private uploads, otherwise generate one
  const explicitKey = formData.get('key') as string | null;
  let key: string;
  if (explicitKey && !project.supportsPrivate) {
    return errorResponse(400, 'PRIVATE_NOT_SUPPORTED', 'Private images are not supported for this project');
  }
  if (explicitKey && isPrivateKey(explicitKey)) {
    key = explicitKey;
  } else if (explicitKey) {
    return errorResponse(400, 'INVALID_PRIVATE_KEY', 'Explicit keys must be canonical private keys');
  } else if (project.authContract === 'akhweb') {
    let prefix: string;
    let folder: string;
    try {
      prefix = normalizeAkhPath(formData.get('prefix'), 'images');
      folder = normalizeAkhPath(formData.get('folder'), 'uploads');
    } catch {
      return errorResponse(400, 'INVALID_AKH_PATH', 'AKH storage path is invalid');
    }
    if (!project.publicKeyPrefixes.some((allowed) => `${prefix}/`.startsWith(allowed))) {
      return errorResponse(400, 'INVALID_AKH_PATH', 'AKH upload prefix is not allowed');
    }
    const safeName = sanitizeFilename(file.name);
    const uid = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    key = `${prefix}/${folder}/${uid}-${safeName}`;
  } else {
    // Generate storage key — timestamp + random suffix guarantees uniqueness
    const safeName = sanitizeFilename(file.name);
    const prefix = occasionId !== null
      ? `images/${occasionId}`
      : `images/unit-${unitId}`;
    const uid = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    key = `${prefix}/${uid}-${safeName}`;
  }

  if (project.authContract === 'festapp') {
    try {
      const admission = await fetch(`${auth.supabaseUrl}/rest/v1/rpc/admit_image_upload_v1`, {
        method: 'POST',
        headers: { apikey: auth.anonKey, Authorization: `Bearer ${userJwt}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_bytes: file.size, p_occasion_id: occasionId, p_unit_id: unitId }),
        signal: AbortSignal.timeout(8000),
      });
      if (!admission.ok) {
        const error = await admission.json() as { code?: string };
        return errorResponse(error.code === 'PT429' ? 429 : 503, 'UPLOAD_ADMISSION', 'Upload temporarily limited', true);
      }
      if (await admission.json() !== true) return errorResponse(503, 'UPLOAD_ADMISSION', 'Upload temporarily limited', true);
    } catch { return errorResponse(503, 'UPLOAD_ADMISSION', 'Upload temporarily unavailable', true); }
  }

  let processed;
  try {
    processed = key.startsWith('private/')
      ? { body: file.stream(), contentType: file.type || 'application/octet-stream', extension: undefined }
      : await processUploadImage(file, policy, env);
  } catch (error) {
    if (error instanceof ImageProcessingError) return errorResponse(error.status, error.code, error.message, error.retryable);
    throw error;
  }
  if (processed.extension) key = key.replace(/\.[^./]+$/, `.${processed.extension}`);

  // Charge actual transformed bytes before the R2 write. Streaming original
  // bodies have the measured File size; processed raster bodies are ArrayBuffers.
  if (project.authContract === 'festapp') {
    const storedBytes=processed.body instanceof ArrayBuffer ? processed.body.byteLength : file.size;
    try {
      const admission=await fetch(`${auth.supabaseUrl}/rest/v1/rpc/admit_image_storage_v1`, {
        method:'POST', headers:{apikey:auth.anonKey,Authorization:`Bearer ${userJwt}`,'Content-Type':'application/json'},
        body:JSON.stringify({p_bytes:storedBytes,p_occasion_id:occasionId,p_unit_id:unitId}), signal:AbortSignal.timeout(8000),
      });
      if(!admission.ok) {
        const error=await admission.json() as {code?:string};
        return errorResponse(error.code==='PT429'?429:503,'STORAGE_ADMISSION','Storage allocation limited',true);
      }
      if(await admission.json()!==true)return errorResponse(503,'STORAGE_ADMISSION','Storage allocation unavailable',true);
    } catch {return errorResponse(503,'STORAGE_ADMISSION','Storage allocation unavailable',true);}
  }

  const isPrivate = key.startsWith('private/');
  const bucket = isPrivate ? project.privateBucket : project.publicBucket;
  await bucket.put(assetKey(project, key), processed.body, {
    httpMetadata: {
      contentType: processed.contentType,
      ...(isPrivate ? {} : { cacheControl: 'public, max-age=31536000, immutable' }),
    },
  });

  const objectUrl = isPrivate
    ? `https://image-api.festapp.net/${key}?projectId=${project.id}`
    : `https://${project.publicHostname}/${key}`;

  if (!isPrivate && project.persistsImageRecords) {
    try {
      await addImageRecord(userJwt, auth, objectUrl, occasionId, unitId);
    } catch (error) {
      await bucket.delete(assetKey(project, key));
      console.error('image_upload_failed', { operation: 'upload', status: 'db_failed_compensated' });
      if (error instanceof ImageProcessingError) return errorResponse(error.status, error.code, error.message, error.retryable);
      return errorResponse(502, 'IMAGE_RECORD_FAILED', 'Image record could not be persisted', true);
    }
  }

  console.log('image_operation', { operation: 'upload', status: 'success', projectId: project.id });
  return jsonResponse({ url: objectUrl, key, projectId: project.id });
}

function normalizeAkhPath(value: unknown, fallback: string): string {
  if (typeof value !== 'string' || !value.trim()) return fallback;
  const normalized = value.trim().replace(/^\/+|\/+$/g, '');
  if (!normalized || normalized.length > 512 || !/^[A-Za-z0-9._/-]+$/.test(normalized) ||
      normalized.split('/').some((part) => !part || part === '.' || part === '..')) {
    throw new ProjectResolutionError('Invalid AKH storage path');
  }
  return normalized;
}

/**
 * Call add_image_record RPC on the caller's Supabase to insert the DB record.
 * Uses the user's JWT so the RPC's SECURITY DEFINER permission check applies.
 */
async function addImageRecord(
  userJwt: string,
  auth: SupabaseAuth,
  link: string,
  occasionId: number | null,
  unitId: number | null
): Promise<void> {
  const response = await fetch(
    `${auth.supabaseUrl}/rest/v1/rpc/add_image_record`,
    {
      method: 'POST',
      headers: {
        'apikey': auth.anonKey,
        'Authorization': `Bearer ${userJwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_link: link,
        p_occasion_id: occasionId,
        p_unit_id: unitId,
      }),
    }
  );
  if (!response.ok) {
    if (response.status === 429) throw new ImageProcessingError(429, 'IMAGE_RECORD_LIMIT', 'Image metadata capacity is limited');
    console.warn('add_image_record failed:', response.status);
    throw new Error('add_image_record failed');
  }
}
