# Service identities for integrations - ADR draft

Status: proposed, not approved, not implemented. Owning follow-up: wave S.
`client_credentials` remains explicitly disabled in the provider. Successful
`private_key_jwt` client authentication does not create a service principal.

## Existing constraints and evidence

The hosted owner uses a separate ordinary GoTrue session and live `auth.uid()`.
`database/functions/eshop/product_catalog.sql` delegates to the existing typed
order/product authorization boundary. `begin_unit_client_mutation_v1.sql`
requires its actor to equal `auth.uid()` and rejects receipts with a different
actor/client claim. User profiles, audit and mutation receipts also represent
humans. Merely switching on an OAuth grant cannot satisfy those contracts.

## Proposed identity and authority

A service principal belongs to one organization, with a responsible human
administrator and explicit disable/review deadline. Its memberships select
concrete units/occasions, permission ceiling and data profile. Removing its
creator does not disable an organization-owned integration; disabling the
principal or its current membership rejects the next admission and receipt read.
There is no corresponding fabricated `auth.users`/`user_info` employee row.

Introduce one canonical principal resolver at the SQL authorization boundary,
distinguishing human and service facts. Existing typed operation predicates
consume those facts; clients, HTTP and MCP never reconstruct role combinations.
Human calls preserve their existing semantics. Unconverted `auth.uid()` paths
remain closed to machines. The first service operation is one bounded read,
not arbitrary table/RPC access. Organization/unit/occasion scope comes from
stored membership and the stored target row, not caller-supplied organization.

A PostgreSQL principal/membership representation is a domain identity owner,
not a second OAuth store. Provider clients, assertions and tokens remain in the
existing canonical AS/store. Audit records identify the machine, requesting
client and responsible administrator separately. Mutation/audit columns that
currently require a human actor need explicit forward migrations before any
machine write; human UUID fields cannot be repurposed silently.

## Trust boundary that must be selected and approved

Opaque API credentials are never forwarded to Supabase. Before implementation,
choose and prove a backend credential/verification mechanism that authenticates
only the service-principal claim and cannot impersonate a human subject.
Registering another unrestricted signing key in a shared PostgREST JWKS is not
such proof: a compromised key could otherwise forge ordinary human JWT claims.
No service-role executor, arbitrary JWT claims from an HTTP body, per-operation
super-token proxy or invented personal refresh session is acceptable.

The approving ADR must name the issuer/audience/key restrictions, SQL/Edge
entrypoint, claim-to-principal verification, revocation fence and ACL, backed by
negative tests for a forged human subject, wrong issuer/audience/key and absent
membership. This draft intentionally does not pretend that the present GoTrue
session bridge already supports those credentials.

## OAuth and rollout after approval

Use registered asymmetric client keys and short `private_key_jwt` assertions
with aud/exp/jti validation and replay detection. Require fresh current
principal/client policy at every exchange. Prefer DPoP-bound short access tokens;
no refresh token and no personal consent masquerading as machine ownership.
Keep resource/profile/scopes immutable and keep canonical domain command IDs.
Financial/destructive actions require their separate domain approval and proof
policy; an `approved: true` body field is never human approval evidence.

Inventory and migrate the exact typed predicates, RLS, Edge identity checks and
receipt/audit owners for that first read. Add ACL/membership/key-replay tests on
a marked disposable database, then a separately authorized isolated rollout.
The exit criteria include creator departure, principal disable, key rotation,
assertion/DPoP replay, wrong organization, receipt access and audit actor identity.
No activation, migration or machine capability is claimed by this draft.
