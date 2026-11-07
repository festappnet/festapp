# Local browser OAuth evidence - 2026-11-07

The local issuer, OAuth provider, SQLite storage and MCP endpoint ran from the working tree. The first pass used simulated backend Auth and REST; the follow-up below used a task-owned disposable Supabase with real GoTrue, PostgREST and canonical SQL. No production account or tenant was used.

Run `node tools/festapp/test/browser-oauth-fixture.mjs` and note its loopback URL. Use an isolated `agent-browser` session with a task-owned config containing `{"args":"--mute-audio"}` and `--headed false`. Open `<url>/start`. Authenticate with fixture credentials from `remote.test.mjs`, select the fixture occasion, name the connection, and approve. The callback harness exchanges the code at the real issuer `/token`, runs an MCP `tools/list`, and refreshes the real token. Its result page reports success only after those operations pass.

On the tested working tree, a second browser flow selected a new device and 365 days and also completed token exchange, MCP and refresh. A third flow selected replacement, approved consent and reached the callback without exchanging the code. `<url>/fixture-check` then showed 2 issued, 2 active, 0 revoked. In `/connections`, browser authentication and the disconnect button removed the second device; the first remained visible and the fixture check showed 1 active, 1 revoked and MCP HTTP statuses 400 and 401 respectively for malformed requests (the 400 passed authentication, the 401 did not). The browser session and server were closed after the check.

The initial browser run failed at login because `Referrer-Policy: no-referrer` caused Chromium to send `Origin: null` on the form POST. The run above passed after the issuer changed this policy to `same-origin`. That initial simulated pass did not establish backend session expiry, MFA, or real GoTrue behavior; the real backend pass is recorded below.

Representative commands used (replace the port with the printed port and re-snapshot after every navigation):

```sh
printf '{"args":"--mute-audio"}' > /tmp/festapp-pr749-browser-config.json
node tools/festapp/test/browser-oauth-fixture.mjs
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth --headed false open http://127.0.0.1:57784/start
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth snapshot -i
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth fill @e7 fixture@example.test
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth fill @e8 fixture-password
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth click @e9
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth snapshot -i
# Choose the occasion, connection name, duration and action using current refs.
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth open 'http://127.0.0.1:57784/start?abandon=1'
# Approve replacement, then inspect the callback and fixture state.
curl -s http://127.0.0.1:57784/fixture-check
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth open http://127.0.0.1:57784/connections
# Authenticate and disconnect the second device using the current refs.
curl -s http://127.0.0.1:57784/fixture-check
agent-browser --config /tmp/festapp-pr749-browser-config.json --session festapp-pr749-oauth close
```

Existing local GoTrue containers belonged to other worktrees; they were not reused or modified. The real backend pass below used a separate task-owned project.

## Real disposable backend pass

A fresh Supabase CLI project `festapp-pr749-oauth-local` used API port 62421 and database port 62422, with cron disabled, the canonical baseline, reference tenants, forward migrations and seed. The harness created a synthetic organization, organizer, occasion and real confirmed GoTrue user. The only simulated backend response was the activation manifest.

`FESTAPP_BROWSER_BACKEND_DIR=<private-task-directory> FESTAPP_BROWSER_REAL_BACKEND=1 node tools/festapp/test/browser-oauth-fixture.mjs` started the real issuer at its printed loopback URL. The same isolated muted headless browser flow above used the disposable credentials in the private task directory. Both the first 7-day connection and an explicitly new 365-day connection reached the real `/token` endpoint, successfully called MCP `tools/list`, and refreshed. The browser approved a replacement but deliberately did not exchange its callback code: the harness returned `issued:2, active:2, revoked:0` and both malformed authenticated MCP requests returned 400. In browser management, disconnecting Device Two left Device One visible; the harness returned `issued:2, active:1, revoked:1` and MCP statuses 400 and 401. The task-owned browser, issuer and Supabase project were stopped.

The two-connection and abandoned-replacement pass loaded issuer modules before the final internal-only storage visibility refactor. A fresh issuer on the final runtime repeated consent, callback, token exchange, MCP tools/list, refresh and browser revoke against a freshly bootstrapped backend; after revocation its fixture check returned `issued:1, active:0, revoked:1, statuses:[401]`. These runs exercise standalone consent and real password Auth, not the separate tenant bridge, external login providers or production session policy.

The existing real SQL regression `FESTAPP_AUTHORIZATION_DATABASE_URL=<task-owned-loopback-db> FESTAPP_LOCAL_DB_PORT=62422 FESTAPP_LOCAL_DB_PROJECT_ID=festapp-pr749-oauth-local node --test tools/festapp/test/mcp-tree-postgres.test.mjs` passed 1/1 with 0 skipped, including live rights removal. The test verified the project marker, disabled cron and paused email queue before its transaction.

After the final run, the reusable harness gained an explicit backend-directory input and assertions for the same disposable-project and email-fence markers. This only hardens fixture setup; issuer/runtime code is unchanged. Its syntax was checked, and the real-backend scenarios above were executed before this fixture-only adjustment.
