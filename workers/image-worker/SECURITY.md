# Private file security contract

The registry's project is the existing sharing boundary. Festapp editors on any
occasion in that project can read, presign and delete its private exports. The
current contract is documented in `docs/backend/image_worker.md`; a key such as
`private/236/export.pdf` is not authoritative evidence of occasion ownership.
No active private upload/presign caller was found in `lib/` during the
2026-10-09 review. Legacy consumers and stored objects still need compatibility.

The public-only AKH project rejects private operations, including explicit-key
uploads. Public and private buckets coincide in that registry entry, so allowing
an explicit private upload would accidentally store the file in a public bucket.
Canonical private keys are validated consistently before reads, writes, deletion
and signing. Private content and signed-URL responses use `private, no-store`.
Presigned links remain bearer capabilities until their requested expiry (at most
seven days); changing the editor role does not revoke an already issued URL.

## Requirements for a narrower ownership boundary

A future product decision to isolate exports per occasion needs these steps;
none can safely be replaced by parsing old file names:

1. Inventory private keys in each registered bucket and identify their producer,
   consumers, expected sharing and retention. Do not infer ownership from numeric
   path segments or accept a caller-supplied owner as proof.
2. Add an authoritative object catalog keyed by project and exact storage key,
   with explicit project-shared, occasion-owned or unit-owned classification.
   Resolve legacy rows from export records/provenance; quarantine ambiguous rows
   only after their consumers have a recovery path.
3. Have upload atomically establish the authorization metadata for new objects;
   prevent overwrite of an existing object through a newly claimed owner. Add a
   scoped database authorization boundary used by read, presign and delete.
4. Migrate released clients and verify expected shared exports. Keep deliberately
   shared objects under the documented project contract. Verify catalog coverage
   before enforcing scoped access for all other objects.
5. Let existing signed links expire, or explicitly revoke them through object/key
   rotation where operationally safe. Test positive sharing and cross-owner
   rejection together before release.

## Browser policy

Both web header inputs enforce `base-uri 'self'; object-src 'none'` and
`X-Content-Type-Options: nosniff`. This prevents foreign document-base injection
and plugin/object embedding. It preserves inline Flutter/bootstrap scripts,
editor styles, Google login and iframe-based PDF preview. It is deliberately a
baseline policy, not a strict script CSP or a replacement for DOMPurify.

A strict script CSP requires removing or hashing inline entry/bootstrap scripts,
inventorying Flutter/WebAssembly and worker requirements, and testing Google
auth and all embedded form hosts with the final production bundle. The current
policy does not restrict `frame-ancestors`, because external form embedding is a
supported use case; it also leaves iframe PDF preview available.

Local validation: `npm run typecheck` and `npm run test:unit` in this directory.
The remote integration suite creates a real backend user and must not be used
as a local validation shortcut. Deployment remains the control-plane checkpoint
workflow in `deploy.sh`, without changing public routing or unrelated tenants.
