import { isIP } from 'node:net';
import { fetchPinnedHttps } from './pinnedHttps.ts';

const MAX_BYTES = 10 * 1024 * 1024;
const MAX_REDIRECTS = 3;

export class UnsafeTargetError extends Error {}

interface FetchDependencies {
  fetch(input: URL, init: RequestInit, address: string): Promise<Response>;
  resolveDns(query: string, recordType: 'A' | 'AAAA'): Promise<string[]>;
}

const defaultDependencies: FetchDependencies = {
  fetch: fetchPinnedHttps,
  resolveDns: (query, recordType) => Deno.resolveDns(query, recordType),
};

function ipv4IsPrivate(value: string): boolean {
  const parts = value.split('.').map(Number);
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return false;
  const [a, b] = parts;
  return a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127) ||
    (a === 192 && b === 0) || (a === 198 && (b === 18 || b === 19)) ||
    (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) || a >= 224;
}

function ipIsPrivate(value: string): boolean {
  const normalized = value.toLowerCase().replace(/^\[|\]$/g, '');
  if (ipv4IsPrivate(normalized)) return true;
  if (!normalized.includes(':')) return false;
  // Only global unicast, excluding transition mechanisms that can tunnel to a
  // private IPv4 address. This also rejects every mapped IPv4 representation.
  return !/^[23][0-9a-f]{3}:/.test(normalized) || normalized.startsWith('2002:') || /^2001:0*:/.test(normalized);
}

export function parseSafeTarget(value: unknown, base?: URL): URL {
  if (typeof value !== 'string' || value.length > 2048) throw new UnsafeTargetError('invalid_target');
  let url: URL;
  try {
    url = base ? new URL(value, base) : new URL(value);
  } catch {
    throw new UnsafeTargetError('invalid_target');
  }
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '').replace(/\.$/, '');
  if (url.protocol !== 'https:' || url.username || url.password ||
      (url.port && url.port !== '443') || !host || host === 'localhost' ||
      host.endsWith('.localhost') || host.endsWith('.local') ||
      host.endsWith('.internal') || host === 'image-api.festapp.net' || ipIsPrivate(host)) {
    throw new UnsafeTargetError('unsafe_target');
  }
  return url;
}

async function assertPublicDns(
  hostname: string,
  resolveDns: (query: string, recordType: 'A' | 'AAAA') => Promise<string[]>,
) {
  const literal = hostname.replace(/^\[|\]$/g, '');
  if (isIP(literal)) {
    if (ipIsPrivate(literal)) throw new UnsafeTargetError('unsafe_target');
    return literal;
  }
  const results = await Promise.allSettled([
    resolveDns(hostname, 'A'),
    resolveDns(hostname, 'AAAA'),
  ]);
  const addresses = results.flatMap((result) => result.status === 'fulfilled' ? result.value : []);
  if (addresses.length === 0 || addresses.some(value => !isIP(value) || ipIsPrivate(value))) throw new UnsafeTargetError('unsafe_target');
  return addresses[0];
}

async function readLimited(response: Response, maxBytes: number): Promise<Uint8Array> {
  const declared = Number(response.headers.get('content-length') ?? 0);
  if (declared > maxBytes) {
    await response.body?.cancel();
    throw new UnsafeTargetError('response_too_large');
  }
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maxBytes) {
      await reader.cancel();
      throw new UnsafeTargetError('response_too_large');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

export async function fetchPublicBinary(
  target: unknown,
  dependencies: FetchDependencies = defaultDependencies,
  maxBytes = MAX_BYTES,
  allowedTypes: readonly string[] = ['image/*','application/octet-stream'],
) {
  let url = parseSafeTarget(target);
  for (let redirect = 0; redirect <= MAX_REDIRECTS; redirect += 1) {
    const address = await assertPublicDns(url.hostname, dependencies.resolveDns);
    const response = await dependencies.fetch(url, {
      redirect: 'manual',
      signal: AbortSignal.timeout(15_000),
    }, address);
    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel();
      const location = response.headers.get('location');
      if (!location || redirect === MAX_REDIRECTS) throw new UnsafeTargetError('unsafe_redirect');
      url = parseSafeTarget(location, url);
      continue;
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new UnsafeTargetError(`upstream_${response.status}`);
    }
    const contentType = response.headers.get('content-type')?.split(';', 1)[0].trim().toLowerCase();
    if (!contentType || !allowedTypes.some(type => type === contentType || (type === 'image/*' && contentType.startsWith('image/')))) {
      await response.body?.cancel();
      throw new UnsafeTargetError('invalid_content_type');
    }
    const bytes=await readLimited(response, maxBytes);
    return { bytes, contentType };
  }
  throw new UnsafeTargetError('unsafe_redirect');
}

export async function fetchPublicImage(target: unknown, dependencies: FetchDependencies = defaultDependencies, maxBytes = MAX_BYTES) {
  const {bytes,contentType}=await fetchPublicBinary(target,dependencies,maxBytes);
  const png=bytes.length>=8 && [137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v);
  const jpeg=bytes.length>=3 && bytes[0]===255 && bytes[1]===216 && bytes[2]===255;
  if(contentType==='application/octet-stream' && !png && !jpeg)throw new UnsafeTargetError('invalid_content_type');
  return {bytes,contentType:contentType==='application/octet-stream'?(png?'image/png':'image/jpeg'):contentType};
}
