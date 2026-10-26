# Execution prompt: Festapp canonical self-hosted Supabase cutover

Implementuj plán v
`docs/plans/festapp-self-hosted-supabase-hetzner-plan-2026-08-27.md` po vlnách a
zastav se na každé produkční nebo destruktivní rozhodovací bráně. Cílovým stavem
je jeden vyhrazený Hetzner VPS, jeden pinned self-hosted Supabase stack, jedna
databáze/Auth/Storage autorita a jediný veřejný endpoint
`https://api.festapp.net`.

Dnešní **Vstupenky.online backend** `kjdpmixlnhntmxjedpxh` (`default`) a
**Festapp A backend** `lwfpdjxsdmkfyrzqbrlk` (`a`) slouč ihned v rámci migrace.
Rozsah zahrnuje všechny organizace/tenanty a jejich navázaná data v obou
projektech, nikoli pouze dvě organization rows. Organization identifikuj vždy
dvojicí `(source_project, organization_id)`. `default` použij jako kanonický
základ. `a` neobnovuj surovým dumpem přes canonical tabulky: exportuj
jej do stagingu, předem alokuj per-table mapy číselných ID, reconciliuj Auth
identity a transformuj všechny FK i evidované JSON/text reference podle
verzovaného registry. Nevyřešená identity, unique-key, UUID nebo Storage kolize
je blocker, ne „last write wins“.

Hybridní režim je pouze dočasná kompatibilní hranice. Pro každý tenant a
entrypoint musí existovat jediný write owner. `default` po svém freeze/restore
zapisuje jen do self-hosted cíle; nepřepnuté tenanty `a` zapisují jen do cloudu
`a`. Před hybridem převeď všechny `a` zápisy na explicitní RPC, které ve stejné
transakci zapíší append-only journal, a odeber přímé DML grants. Host-local
forwarder přehrává journal jednosměrně a idempotentně přes dedikované cílové RPC.
Replay importuje durable state a nesmí znovu spouštět e-mail, platbu, push ani
jiný externí efekt. Nepoužívej klientský dual-write, bidirectional sync,
permanentní aplikační triggery ani neomezený compatibility fallback.

Nejdříve proveď autoritativní read-only inventuru obou projektů: schema a
PostgreSQL verze, extensions, roles/RLS/functions/cron, tabulky a FK/unique
constraints, embedded IDs, Auth/provider/MFA kolize, Storage, Edge Functions,
všechny mutující klienty a combined capacity. Objednej server až podle měření;
4 vCPU/8 GB/80 GB je jen oficiální výchozí minimum a disk musí mít po DB,
Storage, WAL, stagingu a restore workspace nejméně 50 % headroom.

Převzít lze provozní principy Mendelio — Terraform, Caddy, pinned Compose,
root-only env, off-host šifrované backupy, restore drill a monitoring — nikoli
jeho IDs, secrets ani automaticky jeho starší runtime pin. Neměň PostgreSQL major
současně s cutoverem. Nepoužívej `supabase/.temp/project-ref` jako autoritu a
nahraď cloud-only Management API/project-ref předpoklady explicitním self-hosted
deploy kontraktem.

Pro každou vlnu:

1. ulož reprodukovatelné artefakty do `automation/hetzner-supabase/` a provozní
   runbooky do `docs/operations/supabase-self-hosted/`;
2. nevepisuj secrets, PII, produkční identity mapping ani raw exporty do Gitu;
3. vytvoř manifest se source identity, schema fingerprintem, snapshot/journal
   pozicí, verzí transformace, counts/checksums a výsledkem validace;
4. proveď cílené standardní kontroly odpovídající security a migračnímu riziku;
5. aktualizuj deletion ledger a nedovol, aby dočasný most zůstal trvalou cestou;
6. zastav se při neznámém zapisovateli, schema driftu, unresolved konfliktu,
   journal bypassu, nenulovém final lagu nebo datové divergenci.

Minimálně dvakrát nacvič celý restore + merge + journal catch-up z různých
snapshotů. Produkční pořadí je: připravit infrastrukturu a backup/restore;
journalizovat všechny `a` zápisy; zmrazit a přesunout `default`; bulk importovat
snapshot `a` přes staging; jednosměrně dohánět journal; zmrazit `a`; aplikovat
final marker; ověřit nulu lagu a všechny datové/behaviorální invarianty; přepnout
tenant configs, organization mapping, Edge/cron/webhook/image registry; otevřít
cílové zápisy; cloudy ponechat read-only po retenční dobu.

Po stabilizaci odstraň journal, forwarder, dočasná ingest RPC/receipts,
`a.api.festapp.net`, inter-project sync rows/maps/cron, staré organization IDs,
cloud project refs, Management API logiku a staré keys. Generický external-sync
mechanismus ponech jen pokud reachability inventura prokáže skutečný ne-Festapp
externí zdroj. Cloud projekty nemaž bez samostatného výslovného schválení,
posledního šifrovaného exportu a důkazu nulového provozu.

Hotovo znamená: jeden dosažitelný produkční backend, jeden endpoint, všechny
tenanty a identity v canonical modelu, nula unresolved konfliktů/orphan FK,
ověřený backup/restore a odstraněné všechny hybridní a cloudové runtime cesty.
