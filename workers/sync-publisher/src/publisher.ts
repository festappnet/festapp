export const REQUIRED_CATALOGS = [
  'occasion_config',
  'program_catalog',
  'map_catalog',
  'content_catalog',
  'unit_catalog',
] as const;
type CatalogName = (typeof REQUIRED_CATALOGS)[number];

const RAW_BUDGETS: Record<string, number> = {
  program_catalog: 1024 * 1024,
  occasion_config: 1024 * 1024,
  map_catalog: 1024 * 1024,
  content_catalog: 2 * 1024 * 1024,
  unit_catalog: 1024 * 1024,
  live_public: 512 * 1024,
};

export interface DirtyKey {
  component: string;
  scope_type: string;
  scope_id: number;
  entity_id: number;
  source_revision: number;
  claim_token: string;
}

export interface Descriptor {
  revision: number;
  mediaType: string;
  url: string;
  sha256: string;
  bytes: number;
}

export interface PublicationState {
  scope: string;
  catalog?: Descriptor;
  live?: Descriptor;
  components: Partial<Record<CatalogName, Descriptor>>;
  headEtag?: string;
}

export interface PublisherDatabase {
  claim(limit: number): Promise<DirtyKey[]>;
  releaseClaims(tokens: string[]): Promise<number>;
  refreshEvents(occasionId: number, eventIds: number[] | null): Promise<void>;
  refreshCleaning(occasionId: number): Promise<void>;
  nextReleaseRevision(): Promise<number>;
  component(name: string, scopeType: string, scopeId: number): Promise<unknown>;
  publicationState(scopeType: string, scopeId: number): Promise<PublicationState>;
  complete(input: CompletionInput): Promise<boolean>;
}

export interface CompletionInput {
  scopeType: string;
  scopeId: number;
  releaseRevision?: number;
  manifest?: unknown;
  manifestUrl?: string;
  manifestSha256?: string;
  manifestBytes?: number;
  live?: Descriptor;
  head: unknown;
  headEtag: string;
  catalogClaimTokens: string[];
  liveClaimTokens: string[];
}

export interface ObjectStore {
  putImmutable(key: string, bytes: Uint8Array, contentType: string): Promise<void>;
  putHead(key: string, bytes: Uint8Array, expectedPreviousEtag?: string): Promise<{ etag: string; head: unknown }>;
  exists(key: string): Promise<boolean>;
  deleteExact(key: string): Promise<void>;
}

function encoded(value: unknown): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(value));
}

export async function digest(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', Uint8Array.from(bytes));
  return [...new Uint8Array(hash)]
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

function assertBudget(component: string, bytes: Uint8Array): void {
  if (bytes.byteLength > (RAW_BUDGETS[component] ?? 1024 * 1024)) {
    throw new Error(`${component} exceeds its raw publication budget`);
  }
}

export class ClientSyncPublisher {
  constructor(
    private readonly db: PublisherDatabase,
    private readonly store: ObjectStore,
    private readonly assetOrigin = 'https://assets.festapp.net',
    private readonly now = () => new Date(),
  ) {}

  async runOnce(): Promise<number> {
    const dirty = await this.db.claim(1000);
    const scopes = new Map<string, DirtyKey[]>();
    for (const key of dirty) {
      const scope = `${key.scope_type}/${key.scope_id}`;
      scopes.set(scope, [...(scopes.get(scope) ?? []), key]);
    }
    const failures: unknown[] = [];
    for (const keys of scopes.values()) {
      try { await this.publishScope(keys); } catch (error) { failures.push(error); }
    }
    if (failures.length) throw new AggregateError(failures, 'one or more client-sync scopes failed');
    return scopes.size;
  }

  private async artifact(name: string, scopeType: string, scopeId: number, scope: string): Promise<Descriptor> {
    const value = await this.db.component(name, scopeType, scopeId) as { revision: number; scope: string };
    if (value.scope !== scope) throw new Error(`${name} returned a mismatched scope`);
    const bytes = encoded(value);
    assertBudget(name, bytes);
    const sha256 = await digest(bytes);
    const key = `client-sync/v1/${scope}/${name}/${value.revision}-${sha256}.json`;
    await this.store.putImmutable(key, bytes, 'application/json');
    return { revision: Number(value.revision), mediaType: 'application/json', url: `${this.assetOrigin}/${key}`, sha256, bytes: bytes.byteLength };
  }

  private async publishScope(keys: DirtyKey[]): Promise<void> {
    const [{ scope_type: scopeType, scope_id: scopeId }] = keys;
    const previous = await this.db.publicationState(scopeType, scopeId);
    const catalogKeys = keys.filter((key) => key.component !== 'live_public');
    const liveKeys = keys.filter((key) => key.component === 'live_public');
    let catalog = previous.catalog;
    let live = previous.live;
    let manifest: unknown | undefined;
    let manifestUrl: string | undefined;
    let manifestSha256: string | undefined;
    let manifestBytes: number | undefined;
    let releaseRevision: number | undefined;
    let catalogFailure: unknown;
    let liveFailure: unknown;

    if (catalogKeys.length) {
      try {
        const dirtyNames = new Set(catalogKeys.map((key) => key.component));
        const descriptors = { ...previous.components };
        for (const name of REQUIRED_CATALOGS) {
          if (dirtyNames.has(name) || !descriptors[name]) {
            descriptors[name] = await this.artifact(name, scopeType, scopeId, previous.scope);
          }
        }
        for (const name of REQUIRED_CATALOGS) {
          if (!descriptors[name]) throw new Error(`missing required ${name} descriptor`);
        }
        releaseRevision = await this.db.nextReleaseRevision();
        manifest = {
          protocol: 1,
          schema: 1,
          scope: previous.scope,
          releaseRevision,
          generatedAt: this.now().toISOString(),
          components: Object.fromEntries(REQUIRED_CATALOGS.map((name) => [name, descriptors[name]])),
        };
        const bytes = encoded(manifest);
        if (bytes.byteLength > 16 * 1024) throw new Error('release manifest exceeds 16 KiB');
        manifestBytes = bytes.byteLength;
        manifestSha256 = await digest(bytes);
        const key = `client-sync/v1/${previous.scope}/manifests/${releaseRevision}-${manifestSha256}.json`;
        await this.store.putImmutable(key, bytes, 'application/json');
        manifestUrl = `${this.assetOrigin}/${key}`;
        catalog = { revision: releaseRevision, mediaType: 'application/json', url: manifestUrl, sha256: manifestSha256, bytes: manifestBytes };
      } catch (error) { catalogFailure = error; }
    }

    if (liveKeys.length) {
      try {
        const eventIds = liveKeys.some((key) => key.entity_id === 0)
          ? null
          : [...new Set(liveKeys.filter((key) => key.entity_id > 0).map((key) => key.entity_id))];
        await this.db.refreshEvents(scopeId, eventIds);
        await this.db.refreshCleaning(scopeId);
        live = await this.artifact('live_public', scopeType, scopeId, previous.scope);
      } catch (error) { liveFailure = error; }
    }

    const catalogSucceeded = catalogKeys.length > 0 && !catalogFailure;
    const liveSucceeded = liveKeys.length > 0 && !liveFailure;
    if (!catalogSucceeded && !liveSucceeded) {
      await this.release(keys);
      throw (catalogFailure ?? liveFailure ?? new Error('nothing publishable'));
    }
    if (!catalog) {
      await this.release(keys);
      const detail = catalogFailure instanceof Error ? `: ${catalogFailure.message}` : '';
      throw new Error(`cannot publish a public head without an initial catalog${detail}`);
    }

    const head = { protocol: 1, serverTime: this.now().toISOString(), catalog, ...(live ? { live } : {}), publicationPending: Boolean(catalogFailure || liveFailure) };
    const headBytes = encoded(head);
    if (headBytes.byteLength > 16 * 1024) throw new Error('public head exceeds 16 KiB');
    const headKey = `client-sync/v1/${previous.scope}/public-head.json`;
    let headWrite: { etag: string; head: unknown };
    try {
      headWrite = await this.store.putHead(headKey, headBytes, previous.headEtag);
    } catch (error) {
      await this.release(keys);
      throw error;
    }
    const acceptedHead = headWrite.head as typeof head;
    const acceptedLive = acceptedHead.live;
    if (liveSucceeded && !acceptedLive) {
      await this.release(keys);
      throw new Error('accepted public head omitted the live descriptor');
    }
    let accepted: boolean;
    try {
      accepted = await this.db.complete({
        scopeType, scopeId,
        ...(catalogSucceeded ? { releaseRevision, manifest, manifestUrl, manifestSha256, manifestBytes } : {}),
        ...(liveSucceeded ? { live: acceptedLive! } : {}),
        head: acceptedHead, headEtag: headWrite.etag,
        catalogClaimTokens: catalogSucceeded ? [...new Set(catalogKeys.map((key) => key.claim_token))] : [],
        liveClaimTokens: liveSucceeded ? [...new Set(liveKeys.map((key) => key.claim_token))] : [],
      });
    } catch (error) {
      await this.release(keys);
      throw error;
    }
    if (!accepted) {
      await this.release(keys);
      throw new Error('database rejected a stale public head');
    }
    await this.release([
      ...(catalogFailure ? catalogKeys : []),
      ...(liveFailure ? liveKeys : []),
    ]);
    if (catalogFailure || liveFailure) throw (catalogFailure ?? liveFailure);
  }

  private async release(keys: DirtyKey[]): Promise<void> {
    const tokens = [...new Set(keys.map((key) => key.claim_token))];
    if (tokens.length) await this.db.releaseClaims(tokens);
  }
}
