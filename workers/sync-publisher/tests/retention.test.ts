import { describe, expect, it, vi } from 'vitest';
import type { ObjectStore } from '../src/publisher.js';
import { ClientSyncRetention, type RetentionDatabase } from '../src/retention.js';

function fixture(urls: string[]) {
  const db: RetentionDatabase = {
    artifactCandidates: vi.fn(async () => urls.map((artifact_url) => ({
      artifact_url,
      published_at: '2026-07-01T00:00:00Z',
      byte_size: 10,
    }))),
    acknowledgeArtifact: vi.fn(async () => true),
    compactReceipts: vi.fn(async () => ({ compacted: 2 })),
  };
  const store: ObjectStore = {
    putImmutable: vi.fn(),
    putHead: vi.fn(),
    exists: vi.fn(async () => true),
    deleteExact: vi.fn(async () => undefined),
  };
  return { db, store };
}

describe('ClientSyncRetention', () => {
  it('is dry-run by default and reports without deleting', async () => {
    const { db, store } = fixture([
      'https://assets.festapp.net/client-sync/v1/9/643/live_public/1-a.json',
    ]);
    const result = await new ClientSyncRetention(db, store, 7, 30).runOnce();
    expect(result).toEqual(expect.objectContaining({ apply: false, candidates: 1, deleted: 0 }));
    expect(store.deleteExact).not.toHaveBeenCalled();
    expect(db.acknowledgeArtifact).not.toHaveBeenCalled();
    expect(db.compactReceipts).not.toHaveBeenCalled();
  });

  it('deletes only an exact approved key before acknowledging metadata', async () => {
    const { db, store } = fixture([
      'https://assets.festapp.net/client-sync/v1/9/643/live_public/1-a.json',
    ]);
    await new ClientSyncRetention(db, store, 7, 30, () => new Date('2026-08-05T00:00:00Z')).runOnce({ apply: true });
    expect(store.deleteExact).toHaveBeenCalledWith('client-sync/v1/9/643/live_public/1-a.json');
    expect((store.deleteExact as ReturnType<typeof vi.fn>).mock.invocationCallOrder[0]).toBeLessThan(
      (db.acknowledgeArtifact as ReturnType<typeof vi.fn>).mock.invocationCallOrder[0],
    );
    expect(db.compactReceipts).toHaveBeenCalledWith('2026-07-06T00:00:00.000Z', 500);
    expect(db.artifactCandidates).toHaveBeenCalledWith('2026-07-29T00:00:00.000Z', 200);
    expect(db.acknowledgeArtifact).toHaveBeenCalledWith(
      'https://assets.festapp.net/client-sync/v1/9/643/live_public/1-a.json',
      '2026-07-29T00:00:00.000Z',
    );
  });

  it.each([
    'https://assets.festapp.net/csmostrava2026/v4/map.json',
    'https://other.example/client-sync/v1/9/643/a.json',
    'https://assets.festapp.net/client-sync/v1/../map.json',
    'https://assets.festapp.net/client-sync/v1/9/643/a.json?all=true',
  ])('fails closed for an unsafe candidate %s', async (url) => {
    const { db, store } = fixture([url]);
    await expect(new ClientSyncRetention(db, store, 7, 30).runOnce({ apply: true })).rejects.toThrow('retention candidate');
    expect(store.deleteExact).not.toHaveBeenCalled();
  });
});
