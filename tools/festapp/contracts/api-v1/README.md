# API v1 build artifacts

Eight build projections share canonical runtime schemas: global/regional facade,
operator/order-summary data profile, and bearer/DPoP proof profile.
DPoP projections append `proofs/dpop/` to the selected data-profile path;
their security requirement combines OAuth and the signed proof with AND. `openapi.json`, `manifest.json` and the
self-contained `docs/index.html` are delivered in the same MCP runtime image.
The API major is independent of package/release version. Schema compatibility is
directional: requests may widen, responses may narrow; strict response consumers
make added response fields a breaking change. Unrecognized constraint changes
are conservative breaks. Never overwrite a released baseline to accept a break.

`release-baseline.json` is explicitly **unreleased**. `api:compatibility` refuses
release approval until the first authorized publication seals immutable snapshots.
It does not quietly bootstrap a released baseline from the working tree.

Commands (pnpm 11.24.0, Node 24 LTS): `api:generate`, `api:check`, `api:docs`,
`api:compatibility`. Generation needs the repository source and Git metadata,
no credentials/backend session. Serving docs needs neither Git nor the generator.

The immutable snapshot route validates projectionDigest. Private operation data
and artifacts are no-store; public current docs/spec have ETag/revalidation.
The summary projection is available at `profiles/order-summary/openapi.json`
and `profiles/order-summary/docs/` beneath either public base. No credentials
are stored in the documentation, and its CSP denies all network requests.
