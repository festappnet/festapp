import type { Env } from './types';
import {
  checkAkhEventManagerPermission,
  checkEditorPermission,
  checkUnitEditorPermission,
  extractBearerToken,
  type SupabaseAuth,
} from './auth';
import { assertControlHost, resolveControlProject, ProjectResolutionError } from './project-registry';
import { errorResponse, jsonResponse } from './responses';

/** Absolute maximum upload size (before any transform). */
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

/** Default transform thresholds — used when the caller doesn't specify overrides. */
const DEFAULT_MAX_EDGE = 1200;          // longer-edge limit (px)
const DEFAULT_MAX_BYTES = 800 * 1024;   // 800 KB — skip transform if already under
const DEFAULT_JPEG_QUALITY = 70;        // ~200-400 KB at 1200 px

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

  // Check file size before reading body
  const contentLength = request.headers.get('Content-Length');
  if (contentLength && parseInt(contentLength, 10) > MAX_FILE_SIZE) {
    return errorResponse(413, 'FILE_TOO_LARGE', 'File too large');
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
    formData = await request.formData();
  } catch {
    return errorResponse(400, 'INVALID_FORM_DATA', 'Invalid form data');
  }

  const file = formData.get('file') as File | null;
  const occasionIdRaw = formData.get('occasionId');
  const unitIdRaw = formData.get('unitId');

  if (!file) {
    return errorResponse(400, 'MISSING_FILE', 'Missing file field');
  }

  const occasionId = occasionIdRaw ? parseInt(String(occasionIdRaw), 10) : null;
  const unitId = unitIdRaw ? parseInt(String(unitIdRaw), 10) : null;

  if (occasionIdRaw && (occasionId === null || isNaN(occasionId))) {
    return errorResponse(400, 'INVALID_OCCASION', 'Invalid occasionId');
  }

  if (unitIdRaw && (unitId === null || isNaN(unitId))) {
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
  } else if (occasionId !== null) {
    isEditor = await checkEditorPermission(userJwt, occasionId, auth);
  } else if (unitId !== null) {
    isEditor = await checkUnitEditorPermission(userJwt, unitId, auth);
  }
  if (!isEditor) {
    return errorResponse(403, 'FORBIDDEN', 'Forbidden');
  }

  // Validate file size from actual body
  const buffer = await file.arrayBuffer();
  if (buffer.byteLength > MAX_FILE_SIZE) {
    return errorResponse(413, 'FILE_TOO_LARGE', 'File too large');
  }

  // Read optional per-request transform overrides from form fields
  const maxEdgeRaw = formData.get('maxEdge');
  const maxBytesRaw = formData.get('maxBytes');
  const qualityRaw = formData.get('quality');

  const maxEdge = maxEdgeRaw ? parseInt(String(maxEdgeRaw), 10) : DEFAULT_MAX_EDGE;
  const maxBytes = maxBytesRaw ? parseInt(String(maxBytesRaw), 10) : DEFAULT_MAX_BYTES;
  const jpegQuality = qualityRaw ? parseInt(String(qualityRaw), 10) : DEFAULT_JPEG_QUALITY;
  if (!Number.isInteger(maxEdge) || maxEdge < 1 || maxEdge > 4000 ||
      !Number.isInteger(maxBytes) || maxBytes < 0 || maxBytes > MAX_FILE_SIZE ||
      !Number.isInteger(jpegQuality) || jpegQuality < 1 || jpegQuality > 100) {
    return errorResponse(400, 'INVALID_TRANSFORM_INPUT', 'Upload transform values are out of bounds');
  }

  // Use explicit key for private uploads, otherwise generate one
  const explicitKey = formData.get('key') as string | null;
  let key: string;
  if (explicitKey && /^private\/[A-Za-z0-9._/-]+$/.test(explicitKey) &&
      !explicitKey.includes('..') && explicitKey.length <= 1024) {
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

  // Detect if PNG (has alpha channel — preserve format)
  const bytes = new Uint8Array(buffer);
  const isPng =
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47;

  // Only transform if the file exceeds the byte threshold.
  // Images already under the limit are stored as-is (no quality loss).
  let body: ArrayBuffer | ReadableStream | null;
  let contentType: string;

  const needsTransform = buffer.byteLength > maxBytes;

  if (needsTransform && env.IMAGES) {
    const outputFormat = isPng ? 'image/png' : 'image/jpeg';
    const outputOptions: Record<string, unknown> = { format: outputFormat };
    if (!isPng) {
      outputOptions.quality = jpegQuality;
    }
    try {
      const transformed = await env.IMAGES
        .input(buffer)
        .transform({ width: maxEdge, height: maxEdge, fit: 'scale-down' })
        .output(outputOptions);
      const resp = transformed.response();
      body = resp.body!;
      contentType = outputFormat;
    } catch (err) {
      body = buffer;
      contentType = file.type || 'application/octet-stream';
      console.error('Images transform failed, storing original:', err);
    }
  } else {
    // Already small enough or Images binding not available — store as-is
    body = buffer;
    contentType = file.type || 'application/octet-stream';
  }

  const isPrivate = key.startsWith('private/');
  const bucket = isPrivate ? project.privateBucket : project.publicBucket;
  await bucket.put(key, body, {
    httpMetadata: {
      contentType,
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
      await bucket.delete(key);
      console.error('image_upload_failed', { operation: 'upload', status: 'db_failed_compensated' });
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
    const text = await response.text();
    console.warn('add_image_record failed:', response.status, text);
    throw new Error('add_image_record failed');
  }
}
