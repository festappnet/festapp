import { describe, expect, it } from 'vitest';
import {
  IMAGE_TRANSFORM_CONTRACT,
  PUBLIC_IMAGE_CORS_HEADER,
  isCanonicalTransformRequest,
  renderCloudflareVariantCorsExpression,
  renderCloudflareWafBlockExpression,
  renderImagesSourceAllowlist,
} from '../../src/transform-contract';

const valid = 'https://img.festapp.net/cdn-cgi/image/width=300,fit=scale-down,format=auto,quality=75,onerror=redirect/https://img.festapp.net/images/42/a.jpg';

describe('bounded transform contract', () => {
  it('contains exactly three ordered presets', () => {
    expect(IMAGE_TRANSFORM_CONTRACT.widths).toEqual([300, 600, 1200]);
    expect(IMAGE_TRANSFORM_CONTRACT.options).toHaveLength(3);
  });
  it('accepts only canonical URLs', () => {
    expect(isCanonicalTransformRequest(valid)).toBe(true);
    expect(isCanonicalTransformRequest(valid.replace('width=300', 'width=301'))).toBe(false);
    expect(isCanonicalTransformRequest(valid.replace('width=300,fit=scale-down', 'fit=scale-down,width=300'))).toBe(false);
    expect(isCanonicalTransformRequest(valid.replace('img.festapp.net/images', 'evil.example/images'))).toBe(false);
    expect(isCanonicalTransformRequest(valid.replace('/https://img.festapp.net/images/', '/https://a.img.festapp.net/images/'))).toBe(false);
    expect(isCanonicalTransformRequest(`${valid}?x=1`)).toBe(false);
    expect(isCanonicalTransformRequest(valid.replace('/images/', '/images%2f'))).toBe(false);
    expect(isCanonicalTransformRequest(valid.replace('/images/42/', '/images/../'))).toBe(false);
  });
  it('renders a fail-closed block expression from the same contract', () => {
    const expression = renderCloudflareWafBlockExpression();
    for (const option of IMAGE_TRANSFORM_CONTRACT.options) expect(expression).toContain(option);
    for (const host of IMAGE_TRANSFORM_CONTRACT.publicHosts) expect(expression).toContain(host);
  });
  it('renders an exact per-host source allowlist', () => {
    expect(renderImagesSourceAllowlist()).toEqual([
      { hostname: 'img.festapp.net', path: '/images/' },
      { hostname: 'a.img.festapp.net', path: '/images/' },
    ]);
  });
  it('renders public variant CORS from the same host contract', () => {
    expect(PUBLIC_IMAGE_CORS_HEADER).toEqual({
      name: 'Access-Control-Allow-Origin',
      value: '*',
    });
    expect(renderCloudflareVariantCorsExpression()).toBe(
      '(http.host in {"img.festapp.net" "a.img.festapp.net"} and starts_with(raw.http.request.uri.path, "/cdn-cgi/image/"))',
    );
  });
});
