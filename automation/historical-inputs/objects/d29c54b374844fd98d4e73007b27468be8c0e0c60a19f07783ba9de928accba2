export type AccountAsset = { assetId: string; bucket: string; key: string; sha256: string };
export type AccountAssetDependencies = {
  getBatch(requestId: string, limit: number): Promise<unknown>;
  acknowledge(requestId: string, asset: AccountAsset): Promise<void>;
  secret(): string | undefined;
  fetch?: typeof fetch;
};

function parseAsset(item: unknown): AccountAsset {
  if (!item || typeof item !== 'object') throw new Error('asset_inventory');
  const asset = item as AccountAsset;
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(asset.assetId) || !['festapp-images', 'festapp-images-private'].includes(asset.bucket)
    || !/^[a-f0-9]{64}$/.test(asset.sha256)
    || !/^(assets|images)\/storage\/[A-Za-z0-9_-]+\/[a-f0-9]{20}\/[a-f0-9]{64}\/[a-f0-9]{64}$/.test(asset.key)
    || !asset.key.endsWith('/' + asset.sha256)) throw new Error('asset_inventory');
  return asset;
}

/** SQL owns durable identities. Never acknowledge an object before R2+purge.
 * A crash between remote success and acknowledgement repeats the same delete.
 */
export async function deleteAccountAssets(requestId: string, deps: AccountAssetDependencies) {
  for (let attempt = 0; attempt < 10000; attempt++) {
    const value = await deps.getBatch(requestId, 100);
    if (!Array.isArray(value)) throw new Error('asset_inventory');
    if (!value.length) return;
    const assets = value.map(parseAsset);
    if (assets.length > 100 || new Set(assets.map(asset => asset.assetId)).size !== assets.length) throw new Error('asset_inventory');
    const secret = deps.secret();
    if (!secret || secret.length < 32) throw new Error('asset_cleanup_config');
    for (const asset of assets) {
      const response = await (deps.fetch ?? fetch)('https://image-api.festapp.net/service/account-assets', {
        method: 'DELETE', redirect: 'error', signal: AbortSignal.timeout(15000),
        headers: { Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ bucket: asset.bucket, key: asset.key, sha256: asset.sha256 }),
      });
      await response.body?.cancel();
      if (response.status !== 204) throw new Error('asset_cleanup_retryable');
      await deps.acknowledge(requestId, asset);
    }
  }
  throw new Error('asset_inventory_limit');
}
