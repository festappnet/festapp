import type { SupabaseAuth } from './auth';
import type { Env } from './types';
import { ImageProcessingError } from './upload-policy';

export interface BlueprintImageAsset {
  assetRef: string; hash: string; url: string; width: number; height: number;
  mimeType: string; byteLength: number; state: 'ready';
}
export async function blueprintImageAccess(jwt: string, auth: SupabaseAuth, occasion: number | null, project: string, unit: number | null = null): Promise<boolean> {
  const response = await fetch(`${auth.supabaseUrl}/rest/v1/rpc/get_blueprint_image_upload_access`, {
    method: 'POST', headers: { apikey: auth.anonKey, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_occasion: occasion, p_project: project, p_unit: unit }), signal: AbortSignal.timeout(8000),
  });
  return response.ok && await response.json() === true;
}
export function imageAttestationMessage(occasion: number | null, project: string, asset: BlueprintImageAsset, issuedAt: number, unit: number | null = null): string {
  return ['blueprint-image-v1', unit === null ? `occasion:${occasion}` : `unit:${unit}`, project, asset.assetRef, asset.hash, asset.url,
    String(asset.width), String(asset.height), asset.mimeType, String(asset.byteLength), String(issuedAt)].join('\n');
}
export async function signImageManifest(secret: string, message: string): Promise<string> {
  const encode = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encode.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', key, encode.encode(message)));
}
export function hex(value: ArrayBuffer): string { return [...new Uint8Array(value)].map(byte => byte.toString(16).padStart(2, '0')).join(''); }
export async function registerBlueprintAsset(jwt: string, auth: SupabaseAuth, env: Env, occasion: number | null, project: string, asset: BlueprintImageAsset, unit: number | null = null): Promise<void> {
  if (!env.IMAGE_PROCESSING_SERVICE_SECRET || env.IMAGE_PROCESSING_SERVICE_SECRET.length < 32) {
    throw new ImageProcessingError(503, 'IMAGE_MANIFEST_UNAVAILABLE', 'Image verification unavailable', true);
  }
  const issuedAt = Math.floor(Date.now() / 1000);
  const proof = await signImageManifest(env.IMAGE_PROCESSING_SERVICE_SECRET, imageAttestationMessage(occasion, project, asset, issuedAt, unit));
  const response = await fetch(`${auth.supabaseUrl}/rest/v1/rpc/register_blueprint_image_asset`, {
    method: 'POST', headers: { apikey: auth.anonKey, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_occasion: occasion, p_project: project, p_asset: asset, p_issued_at: issuedAt, p_proof: proof, p_unit: unit }),
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new ImageProcessingError(response.status === 403 ? 403 : 502, 'IMAGE_MANIFEST_REJECTED', 'Image verification rejected', true);
  const receipt = await response.json() as BlueprintImageAsset;
  if (receipt.assetRef !== asset.assetRef || receipt.hash !== asset.hash || receipt.state !== 'ready') {
    throw new ImageProcessingError(502, 'IMAGE_MANIFEST_INVALID', 'Invalid image verification response', true);
  }
}
