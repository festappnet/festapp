# Managed-source Auth fixture

`managed-auth-uid.sql` is the exact always-NULL Auth foundation used by the isolated
PG17 asset-cutover test. Extracted without changes from
`f4aa0b6edfa688b03937197d74b0506d2ae81db7:automation/hetzner-supabase/rehearsal/prepare-source-staging-databases.sh`.
Original script SHA-256: `c316a0bda23be18f53f9afe3b2e581509888b6c2a3604f2f7a6ffcd695460e68`.
This represents a managed source staging database, not application JWT handling.
The existing test assertions and isolation safeguards remain unchanged.

`client-sync-expansion.sql` retains exactly the six tables and four functions
already selected by the same test from historical migration `supabase/migrations/20260802234000_client_sync_v1_expansion.sql`.
That migration was removed from current main in `1852775db96de8061612ea7d64ee0abe385b01c4`.
Extracted from its last source at `6f6c5aa5108f0f67e150fb915d4c8bad9612c66c`;
original blob SHA-256 `a41d67ab183f783a609a7cb690080e162d2073f7d1d07bd2bf57c2262864d14b`.
Each complete declaration was compared to that immutable original. Tests no
longer depend on deleted migrations or Git history in a fresh checkout; they
still exercise precisely the same historical transaction owner and table schema.
