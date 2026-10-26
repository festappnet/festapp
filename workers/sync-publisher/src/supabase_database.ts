import type { CompletionInput, DirtyKey, PublicationState, PublisherDatabase } from './publisher.js';
import type { ArtifactCandidate, RetentionDatabase } from './retention.js';

export class SupabasePublisherDatabase implements PublisherDatabase, RetentionDatabase {
  constructor(
    private readonly origin: string,
    private readonly serviceKey: string,
    private readonly scopeIds: number[] = [],
  ) {}

  private async rpc<T>(name: string, params: unknown): Promise<T> {
    const response = await fetch(`${this.origin}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: this.serviceKey,
        Authorization: `Bearer ${this.serviceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(params),
    });
    if (!response.ok) throw new Error(`${name} returned ${response.status}: ${await response.text()}`);
    const body = await response.text();
    return (body ? JSON.parse(body) : undefined) as T;
  }

  claim(limit: number) {
    if (this.scopeIds.length) {
      return this.rpc<DirtyKey[]>('claim_client_projection_dirty_scopes_v1', {
        p_scope_ids: this.scopeIds,
        p_limit: limit,
      });
    }
    return this.rpc<DirtyKey[]>('claim_client_projection_dirty_v1', { p_limit: limit });
  }
  releaseClaims(tokens: string[]) {
    return this.rpc<number>('release_client_projection_claims_v1', {
      p_claim_tokens: tokens,
    });
  }
  refreshEvents(occasionId: number, eventIds: number[] | null) {
    return this.rpc<void>('refresh_event_public_state_v1', { p_occasion: occasionId, p_event_ids: eventIds });
  }
  refreshCleaning(occasionId: number) {
    return this.rpc<void>('refresh_cleaning_public_state_v1', { p_occasion: occasionId });
  }
  nextReleaseRevision() {
    return this.rpc<number>('next_client_sync_release_revision_v1', {});
  }
  component(name: string, scopeType: string, scopeId: number) {
    return this.rpc<unknown>('get_public_client_sync_component_v1', {
      p_component: name,
      p_scope_type: scopeType,
      p_scope_id: scopeId,
    });
  }
  publicationState(scopeType: string, scopeId: number) {
    return this.rpc<PublicationState>('get_client_sync_publication_state_v1', {
      p_scope_type: scopeType,
      p_scope_id: scopeId,
    });
  }
  complete(input: CompletionInput) {
    return this.rpc<boolean>('complete_client_sync_publication_classes_v1', {
      p_scope_type: input.scopeType,
      p_scope_id: input.scopeId,
      p_release_revision: input.releaseRevision ?? null,
      p_manifest: input.manifest ?? null,
      p_manifest_url: input.manifestUrl ?? null,
      p_manifest_sha256: input.manifestSha256 ?? null,
      p_manifest_bytes: input.manifestBytes ?? null,
      p_live: input.live ?? null,
      p_head_json: input.head,
      p_head_etag: input.headEtag,
      p_catalog_claim_tokens: input.catalogClaimTokens,
      p_live_claim_tokens: input.liveClaimTokens,
    });
  }
  artifactCandidates(cutoff: string, limit: number) {
    return this.rpc<ArtifactCandidate[]>('get_client_sync_artifact_retention_candidates_v1', {
      p_cutoff: cutoff,
      p_limit: limit,
    });
  }
  acknowledgeArtifact(url: string, cutoff: string) {
    return this.rpc<boolean>('delete_client_sync_artifact_metadata_v1', {
      p_artifact_url: url,
      p_cutoff: cutoff,
    });
  }
  compactReceipts(cutoff: string, limit: number) {
    return this.rpc<unknown>('compact_client_mutation_receipts_v1', {
      p_cutoff: cutoff,
      p_limit: limit,
    });
  }
}
