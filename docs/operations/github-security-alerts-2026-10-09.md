# GitHub security alert reconciliation

Readback: 2026-10-09. Default-branch alerts remain open until the PR is merged and GitHub re-evaluates its dependency graph. The fixed versions below are from the security release worktree, not a claim that GitHub has closed the alerts.

Open Dependabot alerts: 53. Severity: high 19, low 18, medium 16.

| Alert | Severity | Package | Manifest | Fixed PR version |
| --- | --- | --- | --- | --- |
| #188 | high | rubyzip | `automation/release/fastlane/Gemfile.lock` | 3.7.0 (Fastlane 2.240.1) |
| #193 | medium | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #195 | medium | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #196 | low | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #197 | high | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #198 | low | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #199 | medium | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #200 | medium | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #201 | high | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #202 | low | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #203 | medium | undici | `automation/image-migration/package-lock.json` | 7.30.0 |
| #204 | high | brace-expansion | `web_client/package-lock.json` | 5.0.12 |
| #205 | high | brace-expansion | `web_client/package-lock.json` | 5.0.12 |
| #206 | medium | brace-expansion | `web_client/package-lock.json` | 5.0.12 |
| #208 | low | undici | `workers/image-worker/package-lock.json` | 7.29.1 |
| #209 | high | undici | `workers/image-worker/package-lock.json` | 7.29.1 |
| #210 | low | undici | `workers/image-worker/package-lock.json` | 7.29.1 |
| #211 | medium | undici | `workers/image-worker/package-lock.json` | 7.29.1 |
| #214 | low | undici | `workers/image-worker/package-lock.json` | 7.29.1 |
| #215 | medium | undici | `workers/image-worker/package-lock.json` | 7.29.1 |
| #217 | low | undici | `workers/self-hosted-monitor/package-lock.json` | 7.29.1 |
| #218 | high | undici | `workers/self-hosted-monitor/package-lock.json` | 7.29.1 |
| #219 | low | undici | `workers/self-hosted-monitor/package-lock.json` | 7.29.1 |
| #220 | medium | undici | `workers/self-hosted-monitor/package-lock.json` | 7.29.1 |
| #223 | low | undici | `workers/self-hosted-monitor/package-lock.json` | 7.29.1 |
| #224 | medium | undici | `workers/self-hosted-monitor/package-lock.json` | 7.29.1 |
| #226 | low | undici | `workers/supabase-legacy-keepalive/package-lock.json` | 7.29.1 |
| #227 | high | undici | `workers/supabase-legacy-keepalive/package-lock.json` | 7.29.1 |
| #228 | low | undici | `workers/supabase-legacy-keepalive/package-lock.json` | 7.29.1 |
| #229 | medium | undici | `workers/supabase-legacy-keepalive/package-lock.json` | 7.29.1 |
| #232 | low | undici | `workers/supabase-legacy-keepalive/package-lock.json` | 7.29.1 |
| #233 | medium | undici | `workers/supabase-legacy-keepalive/package-lock.json` | 7.29.1 |
| #235 | low | undici | `workers/sync-publisher/package-lock.json` | 7.29.1 |
| #236 | high | undici | `workers/sync-publisher/package-lock.json` | 7.29.1 |
| #237 | low | undici | `workers/sync-publisher/package-lock.json` | 7.29.1 |
| #238 | medium | undici | `workers/sync-publisher/package-lock.json` | 7.29.1 |
| #241 | low | undici | `workers/sync-publisher/package-lock.json` | 7.29.1 |
| #242 | medium | undici | `workers/sync-publisher/package-lock.json` | 7.29.1 |
| #244 | low | undici | `workers/sync-worker/package-lock.json` | 7.29.1 |
| #245 | high | undici | `workers/sync-worker/package-lock.json` | 7.29.1 |
| #246 | low | undici | `workers/sync-worker/package-lock.json` | 7.29.1 |
| #247 | medium | undici | `workers/sync-worker/package-lock.json` | 7.29.1 |
| #250 | low | undici | `workers/sync-worker/package-lock.json` | 7.29.1 |
| #251 | medium | undici | `workers/sync-worker/package-lock.json` | 7.29.1 |
| #252 | high | source-map-js | `web_client/package-lock.json` | 1.2.2 |
| #253 | high | source-map-js | `workers/image-worker/package-lock.json` | 1.2.2 |
| #254 | high | sharp | `workers/image-worker/package-lock.json` | 0.35.5 |
| #255 | high | sharp | `workers/self-hosted-monitor/package-lock.json` | 0.35.5 |
| #256 | high | sharp | `workers/supabase-legacy-keepalive/package-lock.json` | 0.35.5 |
| #257 | high | source-map-js | `workers/sync-publisher/package-lock.json` | 1.2.2 |
| #258 | high | sharp | `workers/sync-publisher/package-lock.json` | 0.35.5 |
| #259 | high | source-map-js | `workers/sync-worker/package-lock.json` | 1.2.2 |
| #260 | high | sharp | `workers/sync-worker/package-lock.json` | 0.35.5 |

## Exposure and compatibility

- The web brace-expansion alerts were already resolved by the first security package (5.0.12). Its callers are build/database scripts; it is not imported by the browser application.
- Worker sharp/undici/source-map-js packages are development/build dependencies. Supported Wrangler 4.149.0 includes patched dependencies through Miniflare 5.20261006.1-alpha. The previous Miniflare was already an alpha version; no override or new prerelease channel was introduced. Local emulation/build behavior still changes and is checked separately from deployed Worker behavior.
- Image migration undici is an operational tool dependency (cheerio), updated within its supported range to 7.30.0. No migration or live data operation is run for dependency validation.
- Fastlane is release tooling. Conservative resolution updates Fastlane to 2.240.1 and rubyzip to 3.7.0 under the upstream-supported >=3.4,<4 constraint; forcing rubyzip 3 into old Fastlane was avoided.
- No inspected package maps directly to deployed application runtime. Tooling exposure remains relevant, especially when processing external input.

## GitHub security coverage gaps

- Secret-scanning API explicitly returned 404/disabled. Repository security metadata reports secret scanning, non-provider patterns, push protection and validity checks disabled.
- Dependabot security updates are disabled, even though dependency alerts are available.
- Code-scanning API returned 404/no analysis found with an additional scope hint (`admin:repo_hook`). No clean CodeQL result or enabled analysis can be inferred.
- These are verified coverage gaps, not vulnerability-free results. GitHub settings were not changed during this audit.

## Local validation

- All seven affected npm projects report zero npm audit vulnerabilities, including development dependencies.
- npm audit found one additional high not yet represented among the 53 GitHub alerts: `nanoid <3.3.18` (GHSA-2v37-7h3g-55p8), a web build dependency. The supported patch to 3.3.18 is included.
- Worker image/sync/sync-publisher typechecks pass. Image unit tests, sync-worker/sync-publisher suites and monitor/legacy-keepalive Node tests pass. No remote integration tests ran.
- Wrangler deployment dry-runs pass for image-worker, sync-worker, self-hosted-monitor and legacy-keepalive; no deployment was performed. Sync-publisher uses a Node/tsx entrypoint, validated by its typecheck and tests.
- The final web client production build passes. Image migration cheerio/AWS SDK imports pass without invoking migration operations.
- Fastlane dependencies install in an isolated temporary bundle path, `bundle check` passes and `bundle exec fastlane --version` reports 2.240.1.
- All 53 recorded GitHub dependency alerts are addressed in the PR lockfiles; they remain open against the default branch until merge and GitHub reanalysis. Disabled/missing GitHub scanning coverage remains a separate gap.
