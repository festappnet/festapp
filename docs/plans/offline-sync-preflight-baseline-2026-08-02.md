# Offline sync — přípravný preflight baseline

Date: 2026-08-02

Scope: read-only produkční ověření a repo-only source refaktor. Nebyla provedena
DB migrace, Cloudflare změna, aplikace/deploy, capability aktivace ani commit.

Opakovatelná kontrola:

```bash
node automation/client_sync_preflight.mjs          # pouze repo
node automation/client_sync_preflight.mjs --remote # read-only produkční katalog
node automation/client_sync_preflight.mjs --feedback-audit-gate # úzký feedback/audit gate
```

Příkaz nikdy nezapisuje do Supabase ani Cloudflare a nevypisuje access token.
`--remote` vrací úspěch při bezchybném contract/drift ověření a výsledek vždy
obsahuje samostatné `feedbackAuditReady`/`feedbackAuditBlockers`. Přepínač
`--feedback-audit-gate` při blockeru tohoto úzkého dílčího kontraktu vrací
nenulový exit code. Nejde o release gate celé migrace: neověřuje DNS
`sync.festapp.net`, externí export a retenci auditních logů, úplnost writer
inventory ani load/privacy/atomicity gates.

## Uzavřené předpoklady

### Feedback contract

- Produkční tabulka `public.event_feedback` byla porovnána přes Supabase
  management read-only query: sloupce, identity, FK/check constraints, tři
  explicitní indexy, PK, RLS stav, nulové policies a table/sequence grants
  odpovídají canonical source.
- Produkce obsahuje všech šest očekávaných RPC se shodnými signaturami:
  `submit_event_feedback`, `get_event_feedback`,
  `get_event_feedback_for_edit`, `get_event_feedback_export_for_edit`,
  `delete_event_feedback` a `get_is_event_feedback_enabled_on_occasion`.
- Normalizované SQL bodies všech šesti canonical souborů jsou byte-for-byte
  shodné s `pg_get_functiondef` produkce po odstranění whitespace; preflight
  navíc ověřuje identity arguments, return type, volatility,
  `SECURITY DEFINER`, `search_path`, overloady a role grants.
- Canonical zdroj je nyní v `database/tables/event_feedback.sql` a
  `database/functions/events/*event_feedback*.sql`. Recovery soubor je výslovně
  označený jako historický snapshot, ne další implementační větev.

### Cloudflare public artifact boundary

- Wrangler účet je autentizovaný a `festapp-public` existuje.
- Read-only stav při ověření: EEUR, Standard, 139 objektů, přibližně 145 MB.
- `assets.festapp.net` je aktivní custom domain, ownership i SSL jsou active,
  minimální TLS 1.2.
- Veřejný `r2.dev` endpoint je vypnutý.
- Existující immutable mapový manifest vrací HTTP 200 a
  `Cache-Control: public, max-age=31536000, immutable`.
- `sync.festapp.net` zatím nelze DNS resolve-nout. Jeho Worker, route a DNS jsou
  implementační/release úkol, nikoli předpokládaná hotová infrastruktura.

### Produkční databázový audit

- Cílový projekt je healthy a má `pg_stat_statements`.
- `log_statement = ddl`, `log_min_duration_statement = -1`, `pgaudit` není
  nainstalovaný a `pgaudit.log = none`.
- Tento stav nestačí k tvrzení, že privileged přímý DML zásah bude externě
  auditovatelný. Před capability cutoverem je nutné zvolit/zapnout auditní
  zdroj, ověřit export mimo databázi a retention. `pg_stat_statements` není
  náhrada auditního logu.

### Produkční velikosti public dat

| Dataset | Raw | Přenos |
|---|---:|---:|
| Program s popisy, 939 eventů | 577 140 B | 156 533 B |
| Program bez popisů | 297 978 B | 42 254 B |
| Celý měřený public component set | 849 070 B | 228 490 B |

Současný objem potvrzuje full-component replacement. Obrázky a mapové dlaždice
zůstávají mimo JSON.

## Refaktor rozhodnutí

Před hlavní migrací se nemají přesouvat současné page-level loadery ani přidávat
prázdný `ClientSyncService`. Jejich odstranění bez funkčního canonical store by
změnilo chování; prázdná abstrakce by naopak vytvořila dočasnou druhou cestu.
Bezpečný cut proběhne ve Wave 3–4 současně s novým store/coordinátorem a consumer
cutoverem. Jediný vhodný předrefaktor byl návrat feedback backendu do canonical
repo source, protože nemění runtime kontrakt.

## Hranice pracovního stromu pro další session

Přípravná práce vlastní pouze:

- oba `offline-sync-revision-cache` dokumenty;
- tento baseline;
- `docs/architecture/database.md`;
- `automation/client_sync_preflight.mjs`;
- nové canonical feedback SQL soubory a recovery README;
- canonical feedback gate/contract SQL testy.

Při preflightu už v pracovním stromu existovaly nezávislé změny v
`get_occasion_users_for_edit`, `database/tables/tables.sql`, Users README, jeho
testu a migraci `20260802223000_optimize_occasion_users_for_edit.sql`. Další
session je musí zachovat a nesmí je automaticky přidat do sync změn.

## Zbývající release gates

1. Dokončit úplný repo + produkční `pg_catalog` inventory všech sync source a
   writer entry points; každý klasifikovat `migrate`, dočasný `boundary`, nebo
   `delete`.
2. Zapnout a end-to-end ověřit externí privileged DML audit a retention.
3. Implementovat `sync-worker`, R2 head a `sync.festapp.net` DNS bez Supabase
   public fallbacku.
4. Provést plánované load/size/privacy/atomicity gates před aktivací capability.
5. Zachovat staré RPC contracty pro vydané klienty a contraction provést až po
   doložené nulové legacy usage.
