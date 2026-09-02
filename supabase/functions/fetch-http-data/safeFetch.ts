const MAX_BYTES = 10 * 1024 * 1024;
const MAX_REDIRECTS = 3;

export class UnsafeTargetError extends Error {}

interface FetchDependencies {
  fetch(input: URL, init: RequestInit): Promise<Response>;
  resolveDns(query: string, recordType: 'A' | 'AAAA'): Promise<string[]>;
}

const defaultDependencies: FetchDependencies = {
  fetch: (input, init) => globalThis.fetch(input, init),
  resolveDns: (query, recordType) => Deno.resolveDns(query, recordType),
};

function ipv4IsPrivate(value: string): boolean {
  const parts = value.split('.').map(Number);
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return false;
  const [a, b] = parts;
  return a === 0 || a === 10 || a === 127 ||
    (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) || a >= 224;
}

function ipIsPrivate(value: string): boolean {
  const normalized = value.toLowerCase().replace(/^\[|\]$/g, '');
  if (ipv4IsPrivate(normalized)) return true;
  if (!normalized.includes(':')) return false;
  if (normalized === '::' || normalized === '::1' || normalized.startsWith('fc') ||
      normalized.startsWith('fd') || /^fe[89ab]/.test(normalized)) return true;
  const mapped = normalized.match(/::ffff:(\d+\.\d+\.\d+\.\d+)$/)?.[1];
  return mapped ? ipv4IsPrivate(mapped) : false;
}

export function parseSafeTarget(value: unknown, base?: URL): URL {
  if (typeof value !== 'string' || value.length > 2048) throw new UnsafeTargetError('invalid_target');
  let url: URL;
  try {
    url = base ? new URL(value, base) : new URL(value);
  } catch {
    throw new UnsafeTargetError('invalid_target');
  }
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (url.protocol !== 'https:' || url.username || url.password ||
      (url.port && url.port !== '443') || !host || host === 'localhost' ||
      host.endsWith('.localhost') || host.endsWith('.local') ||
      host.endsWith('.internal') || ipIsPrivate(host)) {
    throw new UnsafeTargetError('unsafe_target');
  }
  return url;
}

async function assertPublicDns(
  hostname: string,
  resolveDns: (query: string, recordType: 'A' | 'AAAA') => Promise<string[]>,
) {
  const results = await Promise.allSettled([
    resolveDns(hostname, 'A'),
    resolveDns(hostname, 'AAAA'),
  ]);
  const addresses = results.flatMap((result) => result.status === 'fulfilled' ? result.value : []);
  if (addresses.length === 0 || addresses.some(ipIsPrivate)) throw new UnsafeTargetError('unsafe_target');
}

async function readLimited(response: Response): Promise<Uint8Array> {
  const declared = Number(response.headers.get('content-length') ?? 0);
  if (declared > MAX_BYTES) throw new UnsafeTargetError('response_too_large');
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > MAX_BYTES) {
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

export async function fetchPublicImage(
  target: unknown,
  dependencies: FetchDependencies = defaultDependencies,
) {
  let url = parseSafeTarget(target);
  for (let redirect = 0; redirect <= MAX_REDIRECTS; redirect += 1) {
    await assertPublicDns(url.hostname, dependencies.resolveDns);
    const response = await dependencies.fetch(url, {
      redirect: 'manual',
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('location');
      if (!location || redirect === MAX_REDIRECTS) throw new UnsafeTargetError('unsafe_redirect');
      url = parseSafeTarget(location, url);
      continue;
    }
    if (!response.ok) throw new UnsafeTargetError(`upstream_${response.status}`);
    const contentType = response.headers.get('content-type')?.split(';', 1)[0].trim().toLowerCase();
    if (!contentType?.startsWith('image/')) throw new UnsafeTargetError('invalid_content_type');
    return { bytes: await readLimited(response), contentType };
  }
  throw new UnsafeTargetError('unsafe_redirect');
}
