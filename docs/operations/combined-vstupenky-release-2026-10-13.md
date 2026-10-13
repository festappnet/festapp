# Combined vstupenky.online release

The user approved publication/deployment, the complete workspace snapshot, all
shared ticket consumers, and inclusion of the existing cancelled-order deletion
change. Only the festapptickets web client is selected for deployment.

The release snapshot was reconciled with main
`ed18e864696a0e1db9e41e9d4fa9bc53f4193ca4`. Published fixes remain, including
prepared ticket backgrounds, canonical membership teardown and client-sync
receipts. The cancelled-order delete change retains these boundaries while
allowing its existing unit manager/editor role contract. Bank facts survive.
Operational backup artifacts are excluded from publication. Subsequent unfinished
waitlist work is outside this fixed snapshot.

Validation: 1233 Flutter tests passed, with one skip and three outdated fixture
expectations. All three failures were corrected and their ten targeted tests
passed. Four deletion UI tests passed. Web: 277 passing and nine skipped;
the four CSS-import setup failures were corrected and all four passed. Deno:
46 passing. Image worker: typecheck and 91 unit tests passed. All eight release
migrations and cancelled/paid deletion SQL tests passed in an isolated database
using the current production schema. No customer data was copied for that schema
check. Existing shared local databases were preserved.

All 133 shared ticket configurations have a dry-run manifest with zero unresolved
rows. Three original backgrounds were recovered from canonical storage and
restored to their existing R2 URLs; public bytes match their source hashes.
No production database migration, processing pause, Edge restart or web deployment
has happened yet. Main requires a GitHub review; the normal merge path must accept
the exact PR before proceeding.

After merge: prepare one clean festapptickets overlay, increment from
`0.20.160+644`, set `OCCASION_SETUP_ENABLED=true` in that tenant profile, generate
once and pass canonical tenant drift/build/legal gates. Prepare the canonical
Edge bundle. Keep other tenant clients untouched. Back up and fence writers,
copy/render and email processing using the existing operational gates. Refresh
all scoped inventories under the fence, regenerate every manifest and apply the
exact eight release migrations plus all ticket conversions and their existing
ledger/audit/client-sync receipts in one reviewed transaction. Do not run a
blanket migration-up command. Publish the shared Edge consumers, selected web
client and affected image worker under their existing deployment contracts;
verify deployed digests, live version, rendering and queue preparation before
restoring the saved processing state. No customer email is sent for verification.
