# Local preview asset recovery - 2026-10-20

Reopening the preview exposed asset_load_failed in both consumers. The local Miniflare v4 bridge passed the obsolete r2Persist option, which its options converter discarded. SQL state survived, but image and native font objects did not survive bridge shutdown.

Changed the local-only bridge to resourcePersistencePath under the owned backend state directory. Restored the exact original PNG and cream JPEG through the real upload owner (matching original SHA256 and byteLength), and all four immutable Roboto faces through the authenticated font service. No document changes or production writes.

Stopped and restarted the bridge: both image GETs returned 200 with exact manifest hashes/lengths; all four font GETs retained their hashes. Actual public seat selector rendered two embedded bitmap images without asset_load_failed. Authenticated native application reopened the same fixture without error; screenshot /tmp/blueprint-asset-repair-native.png. Services remain running for user testing.

Follow-up: user still observed asset_load_failed on the public page. A fresh isolated browser loaded both images with status 200; the asset loader requests force-cache, so the earlier missing-object 404 can remain in an existing browser HTTP cache. The local Vite transport now explicitly overrides mapped image requests to cache:no-store. Regenerated configuration was served and browser reload + actual seat-selection click rendered two embedded images without asset error. Production asset cache policy is unchanged.
