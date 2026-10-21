# Canonical authorization evidence - 2026-10-20

The removed 65-file capture is recoverable from immutable Git source
`a4296c57687294b34826e59c7b232eef582c9748` under `docs/plans/evidence/canonical-authorization-20261020/`.
This is historical local evidence, not a current runtime catalog or production receipt.

The [implementation result](../plans/canonical-authorization-RESULT-2026-10-20.md)
records 1,162 function identities, 408 RLS policies, 71 retained public adapters,
58 transport and 41 dynamic-SQL candidates, with 42 resolved dynamic dispatch sites.
Source reachability is conservative and does not imply executed permission coverage.
Historical final checks: 66 SQL/MCP passed without skips, web 531 passed/25 skipped
post-rebase, Flutter 120 passed, source checks 8 Node/9 Python passed. Mocked
providers and local SQL are not production verification. Earlier failed attempts
and superseding receipts remain recoverable as `validation.json`.

Paired synthetic A/B measurements used 8/1000 occasions and 4/50 bank memberships,
six workloads and four clients. The maximum final p95 increase was 3.5% for small
concurrent writes; throughput improved 3.3%. Final warm context p95 improved
36.9/58.9% serially and 52.5/33.2% concurrently. First-request tests used new
connections with warm shared/OS caches, not flushed cold storage. These are not
production latency claims. Recover `performance-summary.json` and paired raw files
for exact workload contracts and limits.

Production migration/deployment, real email delivery, installed-client telemetry
and live latency verification were **not performed**. Backend migration must
precede capability-consuming client rollout. Original read-ACL activation and
other outstanding deployment gates remain separate. This cleanup changes none
of those gates, authorization SQL, grants or database safeguards.

## Independent inputs and deliberate replay

Normal generation and regressions use the compact immutable
[policy/ACL fixtures](../../database/fixtures/authorization/README.md).
Retained capture/replay scripts use `FESTAPP_AUTHORIZATION_EVIDENCE_DIR`, default
`.codex-artifacts/authorization/run/` (ignored). Choose a separate folder for each
capture or historical replay. Missing paired inputs fail with recovery instructions;
no script restores them from production or creates historical expectations from
current SQL. SQL tools still require loopback port 61022, marker
`festapp-authz-20261020`, cron disabled and paused/fenced email.

From a full-history checkout, deliberately restore the original capture set:

```sh
export FESTAPP_AUTHORIZATION_EVIDENCE_DIR="$PWD/.codex-artifacts/authorization/replay-20261020"
mkdir -p "$FESTAPP_AUTHORIZATION_EVIDENCE_DIR"
git ls-tree --name-only a4296c57687294b34826e59c7b232eef582c9748 docs/plans/evidence/canonical-authorization-20261020/ | while IFS= read -r path; do
  git show "a4296c57687294b34826e59c7b232eef582c9748:$path" > "$FESTAPP_AUTHORIZATION_EVIDENCE_DIR/${path##*/}" || exit 1
done
```

For a single file, use `git show a4296c57687294b34826e59c7b232eef582c9748:docs/plans/evidence/canonical-authorization-20261020/catalog-before.json`
and redirect into the explicit replay directory. Compare SHA-256 with the table
below before replay. Replaying `baseline.py` requires `catalog-before.json`;
`compare.mjs`, `concurrent.mjs` and `cold.mjs` require its paired `baseline.sql`.
The subsequent [artifact cleanup](repository-artifact-followup-2026-10-21.md)
retired the one-time inventory/reconciliation/receipt builders. Their original
source remains recoverable at the same full revision; it is not a current runner
or proof that historical commands ran again.

## Removed capture hashes

All 65 files, 67,454,209 bytes and
1,491,544 LF separators at removal:

| File | Bytes | SHA-256 |
|---|---:|---|
| `baseline.sql` | 979209 | `4528e510ea26689a0209774d706bfd736ea9266bea7bb9d8bee6e93c8351dcca` |
| `before-blueprint-fixture-failures.json` | 4772 | `2fb0942b402772664eb605ef0826631fd51d626471981331de2cd67ccc08376d` |
| `before-definition-failures.json` | 758 | `4e52744af137d00c885b804c955542fa77fdb88a5fbef209f8e96718edf6e0fe` |
| `boundary-ledger.json` | 41062 | `e4782b36f47fee5918fb642496ed02e1259c855ca29458726ec67525a488ad81` |
| `catalog-after.json` | 6774378 | `eaa403f561848989e21342d5ce8f08a9cb84c72a00c172276d373d352569f300` |
| `catalog-before-pristine.json` | 6645528 | `24778d17289fb1e11a23df4aa67c397dc4f2bce2a56b8caf967a13c0ec6a671a` |
| `catalog-before.json` | 4516502 | `21b222e1ba622b53adc62e380802e8c1eb50dbdafcb161e8fb759a2666bae8d2` |
| `context-nested-profile.json` | 76680 | `0a592793e4999b13d58cd39d6003abe0197058bea02f5db95a9d3f6a9fb01807` |
| `current-execution-contract.json` | 423973 | `74f99bcfc9351772b9b0a2bf0eb2fce212f4a085c293af3fb6154512d98d0fa8` |
| `domain-ledger.json` | 7850716 | `08ec2bdc2b82f1756185e1c6fe5b040950fdcf0fc2516ae0fad34c7924289b36` |
| `entrypoint-inventory.json` | 6856054 | `4f0f8b7aa5f59a56700e8ddd9c317ad2cfedc7127540c064b738771ac9924f33` |
| `obsolete-form-writer.json` | 286 | `54b716f447d3058141601fb5edc55ac71ec666789e57cd5ea0503a21ce358a63` |
| `performance-ab.json` | 232653 | `c3486fd877a44e8100b71ed0390dfa1cb96a3c6c5956327a9ac367a1737a825f` |
| `performance-after.json` | 26023 | `c61735c6b5efd29e00f38a8ab44b2c143d4996ca1e22739e37b5201b8786c961` |
| `performance-bank-roles-optimized.json` | 288275 | `d460ff0708c098669a94a47ed6d7a10281b835a96327c945163f15f216699b2c` |
| `performance-bank-roles.json` | 288255 | `9af49958bc13c4001dd9b93e75f705ee66656a18d10831ec1ba63da441993fa5` |
| `performance-before-jsonb-serialization.json` | 287514 | `887cd86bdb2e605c43d63a098f2e1d5a1b94276d5b089d3de043f66bb4cb42f0` |
| `performance-before-plpgsql-projection.json` | 287737 | `c2d7f5aa887bdfec84b5c0ef33d125ef0d9972aaacef419158b541f4c4b2bc60` |
| `performance-before-reception-projection.json` | 287594 | `4ffb4b86afbdf6295c31143c431f5c0bcb70de80053f1f8912f17957e1b4d7ff` |
| `performance-before.json` | 25992 | `c396e63c983266603cb668f6a9ce89210e64635cdf30078334014d95e28b6b54` |
| `performance-concurrent-before-context-row-reuse.json` | 199219 | `d86c107a83897eb08e768ee71dd0619b87c072d8cd8cf5d1a622c862c4caa933` |
| `performance-concurrent-before-jsonb-serialization.json` | 199263 | `5b752108b47c27867ea499764d0461b06465bd6db3bebd3c0ebc6264411a9fdf` |
| `performance-concurrent-before-reception-projection.json` | 199092 | `c8288de4e67a3a74cac8e808a5c5564637f3b8e30df92e01dd9d30177b97a600` |
| `performance-concurrent-canonical-final.json` | 1279241 | `e43a497d8e24b2716a09ec07c9ecb8ac1fb652933aaf3bc22a02fe5604921a4f` |
| `performance-concurrent-context-final.json` | 931433 | `6c635a8636589f7789df3076466adf574ad94c2162709d3ab0d36dc64ac7af66` |
| `performance-concurrent-context-row.json` | 313205 | `a2e32dae1e0ddcb5250d5abaacb27d759ad3c1e8a01b92da66bad29142121835` |
| `performance-concurrent-facts-final.json` | 928595 | `ef40b2789bda34278223b81bb6435ffe1ad1c66b6e624aebe734a286e48b33ed` |
| `performance-concurrent-facts.json` | 625342 | `c1de4b4cfc7cd17a91ab070b4ec11e0e1e5a3298bb49c869cc9af0d990a0fd96` |
| `performance-concurrent-final.json` | 594696 | `47c51f1172ad9a272df6c6abea5f820d1e227101c2954a3d664d38cfd4fc42d8` |
| `performance-concurrent-focused.json` | 934384 | `fe01253e1793596f224a563adfe61fe51cd56b5c1cd829ee47e76cf34bbee7e7` |
| `performance-concurrent-navigation-final.json` | 1014135 | `6708845c882b09e21d6d26a808f875ab8cab89b2e9621de196f4f822f4318bd0` |
| `performance-concurrent-rls-sealed.json` | 996224 | `74b2bcc9712be771d20d072eb5192300cb29b96d0aada473671cb7f6b1b159fe` |
| `performance-concurrent-sealed.json` | 1885479 | `b6544e2249a7f75abcacc1be3aca1e2d254b2646a6799f80843ad9b6b5ac9e15` |
| `performance-concurrent-unit-index.json` | 1426655 | `5779a529425ebd3cf557a1373250aba831b4c88dfac6622ff742b4c26780a8b2` |
| `performance-concurrent.json` | 199457 | `866117e67f43262c3db3ae97cd2f8e6f2abbd2daacead75aba98fc14370985b7` |
| `performance-context-fact-plan.json` | 1042722 | `62567923454ead063bce8cd4d30186e1e37eaa6c9814238b338014bd6574f0f0` |
| `performance-context-generic-plan.json` | 1042747 | `79d0e6cf113226928197762818979883997fce6ebce4d8e47ae4e16cc8112787` |
| `performance-context-navigation-final.json` | 1005627 | `6edcc7090091a9503f36fd9631b540d95355c087cf0f14c12567d40cdd6e1c85` |
| `performance-context-operation-facts.json` | 1042207 | `855fa53d58c85b57614163d4f5ada4a69d7a0041f29aa5774bbc14fb1a1f10b0` |
| `performance-context-single-plan.json` | 1042695 | `b1bc2bb2ed8abf53c829845a9b2b77aee7130c715332d094543185c60dfa79fb` |
| `performance-context-unit-index.json` | 1121431 | `8279165a0f9df572651f861af0fbb8731c28ba69b2988fae738b7c3158324501` |
| `performance-current.json` | 288084 | `e2f0172a173f163be87453ebe59ad8e9ef99f9b74544f3ec0c1fe45b4ad8c8fe` |
| `performance-final-before-context-row-reuse.json` | 287571 | `5408fca44a4f3bc287c4bb98c26e0a60194aab4607d76bd31fe9dfab9c2827ea` |
| `performance-final.json` | 288061 | `ff0770aa88e543f82b2c98c188debd77b086ef9c8e53364ba67b1cbf84f21fc5` |
| `performance-first-request-controlled.json` | 983069 | `8595a350c3d7b7eb54bd8bd8ebbc353f4f1f8937db4a3286b9937a037387f108` |
| `performance-first-request-inline-projection.json` | 983175 | `50a438d72ee2e30e7dbaf863690fa9bdb1f9e8c4abd1699a7cb7e6e888573a99` |
| `performance-first-request-navigation-final.json` | 984605 | `51ea541587c483bcaf005a56ea0a7de091a68e3d4d8588c0bb4e0230acdcb429` |
| `performance-first-request-operation-facts.json` | 983171 | `0b4b59207b5b6da8cab561f689f5a47525553d498181fb0e721b0ff7147da4b7` |
| `performance-first-request-org-facts.json` | 983069 | `8595a350c3d7b7eb54bd8bd8ebbc353f4f1f8937db4a3286b9937a037387f108` |
| `performance-first-request.json` | 970079 | `55cdb0fae64a69479ffe69fb5e12fc4d6c8e59a984304edf5de03d69bb28cd7c` |
| `performance-interrupted-baseline-refresh.json` | 198173 | `f87eb1646d1d7581e51637a8b0f52f94249170edb127a72e598f87df79cabac3` |
| `performance-serial-canonical-final.json` | 1245478 | `0e71c5c5b2fe6b0b1dcebe29b5fb91d2753cd897ecb68f3111001ba75da7b3aa` |
| `performance-serial-context-final.json` | 266834 | `ba61fb7614be11165393022d48450396ad9d9a90ea32b67b7d0e7509afb318bc` |
| `performance-serial-facts-final.json` | 267208 | `1fbc76615d8a3f0087d8c15e9cb5f322710d28298476fe86537f1cd484b8b8e7` |
| `performance-serial-other-final.json` | 1141482 | `b6665d39ff268d807ec4185be5b2f4dd7ea508729cfe54475e3c4e5d8a58bcb3` |
| `performance-serial-remaining-sealed.json` | 1021619 | `c5ba82b32d3a46886a12be48ca42e48adf6e69c89f3d535604ff3e932940a868` |
| `performance-serial-sealed.json` | 1230647 | `870a8cce52a8470317f88abe5049cbb7893162864e4b2cb4fe2156a422a8192c` |
| `performance-summary.json` | 37462 | `36f9c12a84b684e182c22e9a33669fef25b905b69a7a6de91f75ae6f35831a08` |
| `pristine-baseline-receipt.json` | 849 | `5bd161b7fa6f58b6427f5a46ecb9831b4aa5c6def7bbf003cf217386f78116a1` |
| `semantic-contract-evidence.json` | 46004 | `817f46b4147ec8b4268a789518c1c0f3be142530c26b17ae0033cd89cb3cf3a1` |
| `source-hashes.json` | 64358 | `af1be29ecc2ff0d350898ff143ce99a3e83eee14a6f6e334c56e37093465a0c3` |
| `source-inventory.json` | 1144511 | `7fa1fb2f822d6d9c558da245b14de5ef2c979aa67a95efeca71b3d01518053a6` |
| `transport-resolution.json` | 45528 | `dccb5e9ce7ef344ab9bd2badcfe18f34e24e06c02e516987c6c26b42670e19d7` |
| `unit-access-service-lane.json` | 363 | `746696720d5a1f6a9cd15ab3029074cc37dd3418bc194c13a47e984856baea17` |
| `validation.json` | 74999 | `dd58cdd62eb259fb3d25e8f08605ea69a700b3adfe1064e6adf539f375703559` |
