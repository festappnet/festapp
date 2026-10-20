# Image processing ownership

Flutter image upload entry points send original supported bytes and a named
`ImageUploadProfile` through `DbImages` and `ImageControlClient`. The Image
Worker owns dimensions, encoding quality, byte budgets, validation and storage.
Ticket backgrounds use `ticket-background`: longest edge at most 1080 px,
output at most 800 KiB, JPEG quality 85. PNG stays PNG to preserve transparency;
print artwork is static. Processing failure never stores an unprocessed original
for a profile-based upload. Existing stored images are not rewritten.

The numeric-options request parser is a boundary adapter for already installed
Festapp clients and independent AKH consumers that do not yet send `profile`.
It is not used by current Flutter callers. Remove that adapter only after the
supported installed-client floor and the AKH producers have migrated, confirmed
by the producer inventory and request telemetry. It delegates processing to the
same `processUploadImage` implementation.

Client compression helpers are obsolete. Do not reintroduce
`ImageCompressionHelper`, `TicketBackgroundImage`, numeric processing overrides,
or a second ticket-background upload path.

## Verified Blueprint backgrounds

`blueprint-background` uses this same processing/upload owner with a 3000 px
longest edge, 800 KiB output budget and JPEG quality 90. PNG preserves alpha;
GIF, WebP and accepted SVG artwork become static PNG. SVG must be self-contained
and dimension-bounded; active XML, external references and CSS escapes are
rejected before Images decoding. Source SVG bytes are never published. The
processed output is inspected again for raster MIME and dimensions.

The request has exactly one existing owner, `occasionId` or `unitId`, plus the
user JWT. Geometry editor/manager permissions apply only to this profile; other
profiles retain their existing authorization. Unit uploads support the setup
wizard before an occasion exists. Existing admission owners charge measured
source/output bytes and gallery records.

The response adds `asset:{assetRef,hash,url,width,height,mimeType,byteLength,state}`.
Hash is SHA256 of final processed bytes, assetRef is `image:<hash>` and state is
`ready` only after the signed registry RPC acknowledges persistence. URLs remain
canonical HTTPS immutable R2 paths, with owner-specific prefixes. Conditional
puts preserve an existing same-hash object. An ambiguous registry failure retains
the bounded immutable blob because a concurrent request may have registered it;
it does not return readiness. General uploads retain their existing compensation.
No automatic orphan deletion is implemented: safe reconciliation must coordinate
with registration before deleting shared content-addressed bytes.

Worker `IMAGE_PROCESSING_SERVICE_SECRET` matches protected backend vault secret
`blueprint_image_processing_v1`. This is a dedicated HMAC key, not a Supabase
service-role credential. The register RPC requires both the caller JWT scope and
a SHA256 HMAC over these newline-separated UTF8 fields:

```text
blueprint-image-v1
occasion:<id> OR unit:<id>
project
assetRef
hash
url
width
height
mimeType
byteLength
issuedAt
```

`issuedAt` is Unix seconds, accepted for 600 seconds with 30 seconds future skew.
Exact repeated manifests are idempotent. Safe readers project only referenced,
ready, owner-scoped manifests. Existing authorized occasion/setup copy owners
associate verified immutable source bytes with the new occasion; clients cannot
create registry readiness directly. Background hash and raster dimensions must
match that scoped registry on every canonical layout save.

The guarded local bridge in `scripts/blueprint_local_bridge.mjs` runs actual
Miniflare Images (native Sharp/libvips), persistent local R2 and this Worker.
`--env-file` must be mode0600 and `--state-dir` task-specific. Only the owned API
127.0.0.1:59521 is permitted outbound; all other network destinations fail.
Control requests use bridge59525 `/upload` and `/delete`; public assets use
`/public/images/...`. Canonical response URLs and HMACs remain HTTPS unchanged.
`blueprint_local_images.mjs` exercises actual PNG/SVG/unit uploads, public bytes
and receipted background save/read/remove. The normal integration test directory
may target live infrastructure; use this explicitly guarded local command.
