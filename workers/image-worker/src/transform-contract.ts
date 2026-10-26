import contract from '../config/image-transform-contract.json';

export const IMAGE_TRANSFORM_CONTRACT = contract;

export function renderImagesSourceAllowlist() {
  return contract.publicHosts.map((hostname) => ({ hostname, path: contract.sourcePathPrefix }));
}

export const PUBLIC_IMAGE_CORS_HEADER = {
  name: 'Access-Control-Allow-Origin',
  value: '*',
} as const;

export function renderCloudflareVariantCorsExpression(): string {
  const hosts = contract.publicHosts.map((host) => `"${host}"`).join(' ');
  return `(http.host in {${hosts}} and starts_with(raw.http.request.uri.path, "/cdn-cgi/image/"))`;
}

export function isCanonicalTransformRequest(value: string): boolean {
  try {
    const outer = new URL(value);
    if (outer.protocol !== 'https:' || !contract.publicHosts.includes(outer.hostname) || outer.search || outer.hash) return false;
    if (outer.pathname.includes('%') || outer.pathname.split('/').includes('..')) return false;
    const prefix = '/cdn-cgi/image/';
    if (!outer.pathname.startsWith(prefix)) return false;
    const rest = outer.pathname.slice(prefix.length);
    const separator = rest.indexOf('/https://');
    if (separator < 0 || !contract.options.includes(rest.slice(0, separator))) return false;
    const source = new URL(rest.slice(separator + 1));
    return source.protocol === 'https:' && source.hostname === outer.hostname &&
      source.pathname.startsWith(contract.sourcePathPrefix) && !source.search && !source.hash &&
      !source.pathname.includes('%') && !source.pathname.split('/').includes('..');
  } catch { return false; }
}

/** Checked-in fail-closed rule input. Applying it is an authorized P2 action. */
export function renderCloudflareWafBlockExpression(): string {
  const hosts = contract.publicHosts.map((host) => `\"${host}\"`).join(' ');
  const allowedPrefixes = contract.publicHosts.flatMap((host) => contract.options.map(
    (options) => `(http.host eq \"${host}\" and starts_with(raw.http.request.uri.path, \"/cdn-cgi/image/${options}/https://${host}/images/\"))`,
  )).join(' or ');
  return `(http.host in {${hosts}} and starts_with(raw.http.request.uri.path, \"/cdn-cgi/image/\") and not (` +
    `(${allowedPrefixes}) and http.request.uri.query eq \"\" and not raw.http.request.uri.path contains \"%\" and ` +
    `not raw.http.request.uri.path contains \"/../\" and not raw.http.request.uri.path contains \"/./\"))`;
}
