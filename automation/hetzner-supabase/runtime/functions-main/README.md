This is the Supabase self-hosted/v0.8.4 router from commit
189adda99d1b56da55fc5a6ee3f849354aaea92a, with the existing Festapp proof-route,
worker environment, ticket asset, document CPU, monitoring and resource-metric
patches applied. `memory-pressure.ts` is unchanged upstream source. The empty
import map establishes the bundle's requested file without changing the
installed Functions' explicit imports. Installed business handlers are retained.

Provenance: https://github.com/supabase/supabase/tree/189adda99d1b56da55fc5a6ee3f849354aaea92a/docker/volumes/functions/main

The finite container ceiling is 2 GiB on the existing 4 GiB host. Production
preflight measured 1.144 GiB Functions usage and about 1.1 GiB available host
memory; the ceiling allows approximately 0.86 GiB above that observed usage.
The router adds native idle-worker cleanup and retains the document CPU policy.
Live memory/queue monitoring remains a deployment gate, rather than a promise
that the ceiling can accommodate arbitrary concurrent workloads.
