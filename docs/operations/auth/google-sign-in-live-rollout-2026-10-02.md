# FestApp Google sign-in rollout - 2026-10-02

Approved target: https://live.festapp.net, organization 1, prod/festapp only.

## Production installation

- Google project festapp-d23ef, dedicated broker OAuth client, External audience In production; openid/email/profile only. Callback https://api.festapp.net/functions/v1/google-auth-callback. Homepage, privacy and terms point to live.festapp.net. Supabase's separate Google provider remains unused.
- Five private server inputs installed in root-only runtime configuration; values are not recorded here. Two independent 32-byte keys are used for encryption and mailbox HMAC.
- Canonical database festapp_rehearsal_20260909220601 verified. Migration 20261001150000_google_auth_broker.sql applied after successful rolled-back production rehearsal. Migration SHA256: 67159a031b381d98faefa46dd4e68c642b6947918428d2e6a12b2d5a214cb8ed.
- Hourly cleanup job 13 runs in the postgres control-plane scheduler against the canonical database. Unrelated jobs were preserved.
- Only exact web and flutter-web rows for https://live.festapp.net enabled. Native and other tenant rows were not enabled.
- Installed Function bundle main SHA 0e2c4b2f52bb8a2269d9257fe27157a2b3a91bfa, archive SHA256 5e2ed868b0e7f8f279d1b584362d6d5ee6e053821b37e3693c3db256262a0fad. The exact three anonymous Google proof routes are patched into the pinned host router. Existing JWT protection and the concurrent ticket release/static font fixes are preserved.
- Only the functions container was recreated. All previously healthy services remain healthy.
- Root-owned runtime rollback evidence: /root/festapp-google-rollout-20261002 and /var/lib/festapp-rehearsal-evidence/production-function-bundle-20261002T001845Z/result.json.

## Publication and checks

- PRs 187, 189, 190, 192, 194 and 195 merged to main under the user's rollout/admin-merge authorization.
- Initial Google frontend 0.20.37+521 deployed successfully in workflow 36941425635. Concurrent ticket release 0.20.38+522 was preserved.
- Follow-up 0.20.39+523 at prod/festapp SHA 730fb44be852ffa825e3cee2d94aed95566edbfa contains the web callback routing fix. Tenant drift passed against current main 0e2c4b2f52bb8a2269d9257fe27157a2b3a91bfa.
- Version 0.20.39+523 deployed successfully in workflow 36945363994; three consecutive deployment probes passed. A further real Google test exposed the optional Cloudflare analytics module triggering callback reload. PRs 194/195 restrict startup recovery to same-origin application modules and account for Vite HTML rewriting.
- Final release 0.20.41+525 at prod/festapp SHA a2edae64b94529ca771aea467b1d41c7617163b8, based on main 9702ec9fe50960f6684dd7b80c9beecd8bcad1d0. Final deployment https://github.com/festappnet/festapp/actions/runs/36946566649 succeeded. Three consecutive independent deployment probes verified version 0.20.41+525, immutable Flutter bundle, service-worker generation, canonical runtime and real legal documents. Superseded 0.20.40+524 workflow 36946333078 was cancelled before deployment.
- 43 targeted bootstrap/Google client/router tests, successful Vite production build, and runtime-router/static-font/hosting contract tests passed for the follow-up. The full earlier pinned GoTrue, SQL, endpoint, Flutter and visual proofs remain in the reference directory.
- Live web and flutter-web capability return enabled; android/ios return provider_unavailable. Invalid callback proofs fail closed. Callback responses are no-store/no-referrer. Anonymous identity reads and registration-initializer execution are denied.
- Real Google account selection, consent, signed OIDC token exchange and callback to live succeeded. This revealed premature web-to-Flutter routing, fixed in PR 192. The follow-up reached awaiting_account_proof on the canonical backend without linking an identity. Final real Google flow on 0.20.41+525 reached the visible Propojit existující účet dialog with email/password fields. Callback query was cleared, startup was ready, and the modal remained open. The test was then cancelled before linking. Screenshot: docs/plans/google-sign-in-reference-2026-10-01/production-web-account-proof.png. Flutter web Google CTA was separately verified visually.
- Production identity count remains zero; no real FestApp account was created, linked, deleted or signed into merely for testing. Full live account-mutation E2E and native device verification are not claimed. Session mint/MFA/refresh/concurrency/deletion were verified against the pinned isolated runtime.

## Access cleanup

A temporary TCP22 rule was restricted to one workstation IPv4 /32 to complete installation. Removed after installation; UI readback shows the original three rules and SSH TCP22 now times out. Existing ICMP and Cloudflare-only HTTP/HTTPS rules were preserved.

The original root workspace and other unfinished changes were preserved. The narrowly scoped callback/router/bootstrap fixes are also applied in the local workspace. Final SQL reread after SSH cleanup was unavailable because the cached Cloudflare Access token was absent; the last successful read showed zero identities, and the final browser test submitted only the claim operation and cancellation. No registration or account-proof submission was performed.
