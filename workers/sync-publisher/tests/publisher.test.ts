import { afterEach, describe, expect, it, vi } from 'vitest';
import { ClientSyncPublisher, REQUIRED_CATALOGS, type Descriptor, type ObjectStore, type PublisherDatabase } from '../src/publisher.js';
import { R2NativeObjectStore } from '../src/r2_object_store.js';
import { R2S3ObjectStore } from '../src/s3_object_store.js';
import { SupabasePublisherDatabase } from '../src/supabase_database.js';

afterEach(() => vi.unstubAllGlobals());

const descriptor = (revision: number, name = 'old'): Descriptor => ({
  revision, mediaType: 'application/json', url: `https://assets.test/${name}.json`,
  sha256: `${revision}`.padStart(64, '0'), bytes: 10,
});

function fixture(dirty: string[], failingComponent?: string) {
  const calls: string[] = [];
  const components = Object.fromEntries(REQUIRED_CATALOGS.map((name) => [name, descriptor(1, name)]));
  const db: PublisherDatabase = {
    claim: vi.fn(async () => dirty.map((component) => ({ component, scope_type: 'occasion', scope_id: 42, entity_id: component === 'live_public' ? 7 : 0, source_revision: 3, claim_token: `${component}-token` }))),
    releaseClaims: vi.fn(async (tokens) => tokens.length),
    refreshEvents: vi.fn(async () => undefined), refreshCleaning: vi.fn(async () => undefined),
    nextReleaseRevision: vi.fn(async () => 11),
    publicationState: vi.fn(async () => ({ scope: '7/42', catalog: descriptor(10, 'manifest'), live: descriptor(2, 'live'), components, headEtag: '"old"' })),
    component: vi.fn(async (name) => {
      calls.push(`snapshot:${name}`);
      if (name === failingComponent) throw new Error(`${name} unavailable`);
      return { protocol: 1, schema: 1, component: name, scope: '7/42', revision: 3, generatedAt: '2026-08-02T00:00:00Z', payload: {} };
    }),
    complete: vi.fn(async () => { calls.push('complete'); return true; }),
  };
  const store: ObjectStore = {
    putImmutable: vi.fn(async (key) => { calls.push(`immutable:${key}`); }),
    putHead: vi.fn(async (key, bytes) => {
      calls.push(`head:${key}`);
      return { etag: '"etag"', head: JSON.parse(new TextDecoder().decode(bytes)) };
    }),
    exists: vi.fn(async () => true),
    deleteExact: vi.fn(async () => undefined),
  };
  return { db, store, calls };
}

describe('ClientSyncPublisher', () => {
  it('rebuilds only dirty structural components and reuses clean descriptors', async () => {
    const { db, store, calls } = fixture(['program_catalog']);
    await new ClientSyncPublisher(db, store, 'https://assets.test', () => new Date('2026-08-02T12:00:00Z')).runOnce();
    expect(calls.filter((x) => x.startsWith('snapshot:'))).toEqual(['snapshot:program_catalog']);
    expect(calls.filter((x) => x.startsWith('immutable:'))).toHaveLength(2);
    expect(calls.at(-1)).toBe('complete');
  });

  it('publishes live independently when a structural artifact fails', async () => {
    const { db, store } = fixture(['map_catalog', 'live_public'], 'map_catalog');
    await expect(new ClientSyncPublisher(db, store).runOnce()).rejects.toThrow('one or more');
    expect(store.putHead).toHaveBeenCalledOnce();
    expect(db.complete).toHaveBeenCalledWith(expect.objectContaining({
      catalogClaimTokens: [], liveClaimTokens: ['live_public-token'], live: expect.objectContaining({ revision: 3 }),
    }));
    expect(db.releaseClaims).toHaveBeenCalledWith(['map_catalog-token']);
  });

  it('publishes catalog independently when live projection fails', async () => {
    const { db, store } = fixture(['content_catalog', 'live_public'], 'live_public');
    await expect(new ClientSyncPublisher(db, store).runOnce()).rejects.toThrow('one or more');
    expect(store.putHead).toHaveBeenCalledOnce();
    expect(db.complete).toHaveBeenCalledWith(expect.objectContaining({
      catalogClaimTokens: ['content_catalog-token'], liveClaimTokens: [], releaseRevision: 11,
    }));
    expect(db.releaseClaims).toHaveBeenCalledWith(['live_public-token']);
  });

  it('does not advance a head when the only dirty class cannot upload', async () => {
    const { db, store } = fixture(['map_catalog'], 'map_catalog');
    await expect(new ClientSyncPublisher(db, store).runOnce()).rejects.toThrow('one or more');
    expect(store.putHead).not.toHaveBeenCalled();
    expect(db.complete).not.toHaveBeenCalled();
    expect(db.releaseClaims).toHaveBeenCalledWith(['map_catalog-token']);
  });

  it('uses null only for an explicit full live projection refresh', async () => {
    const fixtureValue = fixture(['live_public']);
    (fixtureValue.db.claim as ReturnType<typeof vi.fn>).mockResolvedValueOnce([
      { component: 'live_public', scope_type: 'occasion', scope_id: 42, entity_id: 0, source_revision: 3, claim_token: 'full-token' },
    ]);
    await new ClientSyncPublisher(fixtureValue.db, fixtureValue.store).runOnce();
    expect(fixtureValue.db.refreshEvents).toHaveBeenCalledWith(42, null);
  });
});

describe('R2S3ObjectStore head recovery', () => {
  it('reuses the exact existing head on a same-revision retry', async () => {
    const existingBytes = new TextEncoder().encode(JSON.stringify({
      catalog: { revision: 11 },
      live: { revision: 3 },
      serverTime: '2026-08-03T10:00:00Z',
    }));
    const retryBytes = new TextEncoder().encode(JSON.stringify({
      catalog: { revision: 11 },
      live: { revision: 3 },
      serverTime: '2026-08-03T10:00:01Z',
    }));
    const send = vi.fn(async () => ({
      ETag: '"already-written"',
      Body: { transformToByteArray: async () => existingBytes },
    }));
    const store = new R2S3ObjectStore({ send } as never, 'bucket');

    await expect(store.putHead('head.json', retryBytes, '"old"'))
      .resolves.toEqual({
        etag: '"already-written"',
        head: {
          catalog: { revision: 11 },
          live: { revision: 3 },
          serverTime: '2026-08-03T10:00:00Z',
        },
      });
    expect(send).toHaveBeenCalledOnce();
  });
});

describe('R2NativeObjectStore head recovery', () => {
  it('returns the concurrent monotonic winner after a conditional write loses', async () => {
    const winner = {
      catalog: { revision: 12 },
      live: { revision: 4 },
      serverTime: '2026-08-03T10:00:02Z',
    };
    const get = vi.fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({
        etag: 'winner',
        httpEtag: '"winner"',
        arrayBuffer: async () => new TextEncoder().encode(JSON.stringify(winner)).buffer,
      });
    const put = vi.fn(async () => null);
    const store = new R2NativeObjectStore({ get, put } as unknown as R2Bucket);
    const pending = new TextEncoder().encode(JSON.stringify({
      catalog: { revision: 11 },
      live: { revision: 3 },
    }));

    await expect(store.putHead('head.json', pending)).resolves.toEqual({
      etag: '"winner"',
      head: winner,
    });
    expect(put).toHaveBeenCalledWith('head.json', pending, expect.objectContaining({
      onlyIf: { etagDoesNotMatch: '*' },
    }));
  });
});

describe('SupabasePublisherDatabase', () => {
  it('accepts an empty successful response from void RPCs', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(null, { status: 204 })));
    const database = new SupabasePublisherDatabase('https://database.test', 'service-key');
    await expect(database.refreshCleaning(42)).resolves.toBeUndefined();
  });

  it('claims only explicitly configured production scopes', async () => {
    const fetchMock = vi.fn(async () => new Response('[]', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    const database = new SupabasePublisherDatabase(
      'https://database.test',
      'service-key',
      [643],
    );
    await database.claim(1000);
    expect(fetchMock).toHaveBeenCalledWith(
      'https://database.test/rest/v1/rpc/claim_client_projection_dirty_scopes_v1',
      expect.objectContaining({ body: JSON.stringify({ p_scope_ids: [643], p_limit: 1000 }) }),
    );
  });
});
