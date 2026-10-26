# Cloudflared certificate remediation - 2026-10-26

The authenticated Cloudflare email received on 2026-10-26 requested upgrading
all cloudflared instances because of compromised eMudhra intermediate
certificate keys. Gmail reported SPF, DKIM and DMARC pass. Cloudflare's advisory
states that its review had not identified active exploitation on its services;
this maintenance does not establish whether any individual account was attacked.

Source: https://blog.cloudflare.com/emudhra-certificate-compromise/

## Festapp changes and verification

- The Homebrew client on the Mac changed from 2026.7.3 to 2026.10.3.
- The existing control-channel LaunchAgents were restarted through the canonical
  festapp-control-channel skill. Public health returned 200, unauthenticated
  queue access returned 401, and the channel remained paired. Cloudflare's
  connector inventory reports 2026.10.3 for festapp-control-channel.
- The backend admin tunnel changed from 2026.9.0 to 2026.10.3, pinned to official
  image index digest
  sha256:faa8e0a1475f137c910be6025f43c8e4092fdd35461b31e19fd1390657a1ff39.
  Both runtime/pins.json and docker-compose.festapp.yml carry this pin.
- A temporary fixed-version replica was connected before replacing the main
  connector and removed after readiness verification. Main readiness returned
  200 with four connections; SSH reconnection succeeded. The previous installed
  Compose file is retained privately with mode 0600.
- Anonymous supabase.festapp.net requests returned a 302 Access redirect.
  api.festapp.net/pg/ and /project/default returned 404.
- Targeted infrastructure tests passed (6 tests); changed-file diff checks passed.

The separate public Auth health probe did not meet a 200 expectation: it returned
401 without credentials and 403 with the configured anon key, while the local
origin returned 200 with that key. No before-change baseline establishes this as
a regression. The admin tunnel update did not change API routing or credentials;
no unrelated Auth configuration was changed.

No DNS, Access policies, database, application release or tenant rollout was
changed. Account inventory also identified CatalogPilot's separate admin tunnel;
it was also upgraded to 2026.10.3 using the official Linux amd64 digest, with
HTTP/2 preserved, temporary replica removed, and its public Compose checks
passing. Final Cloudflare API readback confirms all three active tunnels
(catalogpilot-admin, festapp-control-channel, festapp-supabase-admin) are healthy
and every connected client reports 2026.10.3.
Inactive/down tunnels have no connected clients and their offline installations
were not verified. Update those installations before reactivating them.
