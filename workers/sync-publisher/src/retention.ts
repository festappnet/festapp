import type { ObjectStore } from './publisher.js';

export interface ArtifactCandidate {
  artifact_url: string;
  published_at: string;
  byte_size: number;
}

export interface RetentionDatabase {
  artifactCandidates(cutoff: string, limit: number): Promise<ArtifactCandidate[]>;
  acknowledgeArtifact(url: string, cutoff: string): Promise<boolean>;
  compactReceipts(cutoff: string, limit: number): Promise<unknown>;
}

export interface RetentionResult {
  apply: boolean;
  candidates: number;
  candidateBytes: number;
  deleted: number;
  receipts: unknown;
}

export class ClientSyncRetention {
  constructor(
    private readonly db: RetentionDatabase,
    private readonly store: ObjectStore,
    private readonly artifactRetentionDays: number,
    private readonly receiptRetentionDays: number,
    private readonly now = () => new Date(),
  ) {}

  async runOnce({ apply = false }: { apply?: boolean } = {}): Promise<RetentionResult> {
    if (!Number.isInteger(this.artifactRetentionDays) || this.artifactRetentionDays < 7) {
      throw new Error('artifact retention must preserve at least seven days');
    }
    if (!Number.isInteger(this.receiptRetentionDays) || this.receiptRetentionDays < 30) {
      throw new Error('receipt retention must preserve at least thirty days');
    }
    const artifactCutoff = new Date(
      this.now().getTime() - this.artifactRetentionDays * 24 * 60 * 60 * 1000,
    ).toISOString();
    const candidates = await this.db.artifactCandidates(artifactCutoff, 200);
    const keys = candidates.map((candidate) => this.exactKey(candidate.artifact_url));
    let deleted = 0;
    if (apply) {
      for (let index = 0; index < candidates.length; index++) {
        await this.store.deleteExact(keys[index]);
        if (await this.db.acknowledgeArtifact(candidates[index].artifact_url, artifactCutoff)) deleted++;
      }
    }
    const cutoff = new Date(
      this.now().getTime() - this.receiptRetentionDays * 24 * 60 * 60 * 1000,
    ).toISOString();
    const receipts = apply ? await this.db.compactReceipts(cutoff, 500) : { status: 'dry_run' };
    return {
      apply,
      candidates: candidates.length,
      candidateBytes: candidates.reduce((sum, candidate) => sum + Number(candidate.byte_size), 0),
      deleted,
      receipts,
    };
  }

  private exactKey(value: string): string {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.hostname !== 'assets.festapp.net'
      || url.port || url.username || url.password || url.search || url.hash
      || !url.pathname.startsWith('/client-sync/v1/')) {
      throw new Error('retention candidate is outside the exact client-sync asset boundary');
    }
    const key = url.pathname.slice(1);
    if (key.includes('//') || key.includes('..')) throw new Error('invalid retention candidate key');
    return key;
  }
}
