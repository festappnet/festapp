# Výsledek úklidu velikosti repozitáře 2026-10-21

Stav: dokončeno pro ověřenou hranici K `20260906140000`. Novější upgrade
vstupy zůstávají aktivní. Původní větev `feat/occasion-setup-wizard-20261007`
a HEAD `eb23047248d59bf86345b9e0b79db4a988275231` nebyly měněny. Bez commitu,
push, deploymentu, produkčních zápisů a Flutter úlohy.

## Odstraněné skupiny a retence

Úplný [mazací soupis](repository-size-cleanup-deletions-2026-10-21.tsv)
obsahuje všech 198 odstraněných cest, velikost, SHA-256 a důvod.

| Skupina | Výsledek |
|---|---|
| `.codex-artifacts` | 82 pracovních souborů včetně 22 již ignorovaných logů; uchováno v lokálním retenčním kitu |
| Scanner náhled a galerie | Odstraněna smyšlená demonstrace a duplicitně vložené PNG; originální screenshoty a skutečné PDF/QR fixture zachovány |
| Editor benchmark patch | Experimentální kopie odstraněna; měření zachováno, patch lokálně obnovitelný |
| Původní baseline a 111 migrací do K | Odstraněno po paritě, ledger no-op, obnově a upgrade testech; nový snapshot nahrazuje jejich čistou instalační cestu |
| Historický account-deletion generátor | Vyřazen, aby znovu nevyráběl odstraněnou migraci; původní soubor zahrnut do ověřené Git obnovy |

Prvních 85 artefaktů bylo při zahájení nesledovaných nebo ignorovaných.
Dalších 113 souborů bylo sledovaných a jejich původní bajty jsou ověřeně
obnovitelné z Git objektů. Git historie nebyla přepisována. Úspora níže
započítává i nový baseline, manifesty, nástroje a dokumentaci.

MapLibre overrides, fonty a aktivní JSON inventáře zůstávají. Google reference
mají aktivní generátory a vizuální test; SEO náhled a patch mají otevřené
publikační podmínky. Tyto vstupy a potřebné důkazy nebyly odstraněny.

## Jeden instalační kontrakt

Vlastníkem je [`supabase/baseline/manifest.json`](../../supabase/baseline/manifest.json):
schema-only snapshot do K, explicitní provider bootstrap, samostatný referenční
seed a hash historického manifestu. Referenční data obsahují pouze instalační
`public.client_sync_component_sources`, bez tenantových řádků a tajných klíčů.
Testovací identity nadále vlastní `supabase/seed.sql`.

Na tento manifest jsou přepojené lokální bootstrap, PG17 rehearsal builder,
occasion-setup launcher, canonical-source generator, operations inventory
a migration-layout kontrola. Migration-history inventory rozlišuje 111 baseline
verzí dostupných v historickém kitu a 105 aktivních forward migrací. Starý
jednorázový resume režim původní baseline byl odstraněn.

Nový ledger zapisuje přesných 111 pokrytých verzí a názvů. Supabase CLI vyžaduje
lokální soubory i pro zaznamenané verze; jednotný příkaz
`python3 automation/baseline.py upgrade-local --database-url ...` proto obnoví
historii do dočasného workspace a spustí běžný migration engine. Pokryté SQL
neprovádí znovu. Bootstrap tento příkaz používá i pro zbývající forward část.
Přímé `supabase migration up` nad samotným zkráceným adresářem není podporovaná
cesta. Existující ledger se neopravuje ani nenahrazuje snapshotem.

Postupy pro instalaci, upgrade a obnovu vlastní
[aktuální průvodce](../setup/local_development.md).

## Obnovitelnost a důvod hranice K

[`automation/historical-sql-manifest.json`](../../automation/historical-sql-manifest.json)
pinuje původní baseline, pokryté SQL a historický generátor na konkrétní Git
commit a SHA-256. Pokryté vstupy jsou bajtově shodné s předkem kanonického
`main` (`eb1d94ac41b085218b8ed618814b9e0727525e62`), obnova tedy nezávisí na
nepublikované feature větvi. Emailový kit navíc pinuje kompletní historické SQL a fixture
na jejich správné dobové revize. Obnova funguje bez sítě, ověřuje všechny
položky před zápisem a odmítá přepsat odlišný soubor. Git objekty musí být
přítomné; shallow clone je musí nejprve získat. Původní necommitované SQL bylo
samostatně zachováno v lokálním recovery kitu a nebylo smazáno.

Po samostatném souhlasu uživatele proběhla pouze read-only kontrola kanonického
backendu přes `festapp-backend-access`: ověřena živá activation tenant
`festapptickets`, organizace 3, generation 1, hostname a aktivní databáze.
SQL běželo v transakci `READ ONLY` s timeoutem 10 sekund, bez osobních dat.
Ledger měl 326 záznamů do `20261021040000`. Všech 111 zdejších verzí do K v něm
bylo zaznamenáno; první zdejší nezaznamenaná verze je `20260910070000`.
Ledger není zaměňován s úplným důkazem dnešních SQL efektů.

Proto nebyl jako hranice zvolen pouhý nejvyšší lokální filename. Zůstávají mj.
provozně nedoložené zdejší verze `20260910070000`, `20260910073000`,
`20261014130000`, `20261016120000`, `20261016133000` i všechny další verze
za K. Jejich případná pozdější kontrakce potřebuje samostatný důkaz; žádná
z těchto podmínek nebyla prohlášena za splněnou předpokladem.

Lokální [retenční kit](../../.codex-local/repository-size-cleanup-20261021/)
má oprávnění 0700, původní status/hashe, recovery archivy, retenční kopie,
schema diffy a logy. `SHA256SUMS` ověřuje archivy; rozbalují se výhradně do
nového adresáře, nikoli plošně přes pracovní strom. Kit se nepublikuje s repem
a při přesunu workstation je nutné jej přenést samostatně. Trvalá obnova
odstraněného SQL je navíc nezávislá na této jediné lokální kopii díky Git kitu.

## Opravené selhávající podmínky

- Source-contract check odhalil nesoulad helperu pro metadata sedadel. Původní
  `20261020120000` byl po ověření živého ledgeru zachován bajtově beze změny.
  Opravu a její chybějící helper definice obsahuje nová nepoužitá forward migrace
  [`20261021110000_order_seating_source_parity.sql`](../../supabase/migrations/20261021110000_order_seating_source_parity.sql).
  Existující assembler generuje pouze tento nový explicitní target; historické
  cíle odmítá. Žádná tato oprava nebyla aplikována v produkci. Budoucí vydání
  musí projít běžným sjednocením s aktuálním canonical main; tento checkout
  neobsahuje všechny novější migrace zaznamenané v provozu.
- Upgrade s reálným tvarem lokálních dat vyžaduje existující dávkový backfill
  `order_symbol` před jeho contract migrací. Upgrade příkaz tuto hranici
  respektuje a ověřuje postup dávkování, místo obcházení SQL precondition.
- Historická emailová fixture používala později přidané sloupce objednávky.
  Kit nyní používá původní fixture bez těchto budoucích sloupců a zachovává
  assertiony ID, auditů, receiptů a quarantine nejednoznačných odeslání.
- Opraveny zastaralé inventory/preflight kontroly: aktuální bound command modul,
  explicitní canonical-only adaptéry bez DML fallbacku, klasifikace
  `exchange-sign-in-code`, historická uzavřená sada RPC, podpora platných `$$`
  těl a citovaného `search_path TO`. Oprávnění aplikace nebyla rozšířena.
  Dva existující facade command owners jsou registrovány přesnými RPC/cesta
  dvojicemi; čtecí RPC nejsou zaměňovány za mutation commands.

## Provedené ověření

- Nový deterministický [`check_baseline_parity.py`](../../automation/check_baseline_parity.py):
  původní instalace do K versus nový baseline, zvlášť PG15 a PG17. Kompletní
  schema diff 0 řádků; shodné owner/ACL/default ACL, security/search_path,
  constraints/indexy, sekvence včetně hodnot a ownership, views, policies,
  triggery, extensions a referenční řádky. Vyloučeno jen samostatně ověřené
  migration bookkeeping. Provider objekty a provider default ACL se nekopírují
  do aplikačního dumpu, jejich shoda je součástí úplného porovnání.
- Finální čistá instalace na PG15 i PG17: baseline + reference seed + forward
  migrace + test seed. V obou případech 216 jedinečných ledger verzí.
  Následný skutečný migration up přes podporovaný workspace: `applied: []`.
- Upgrade od původní baseline na PG15 i PG17 s uloženými ID organizace,
  jednotky, akce a objednávky, platební referencí, pending emailem a auditem:
  assertiony prošly. PG17 prošel automatickou staging/backfill cestou.
- Historický emailový rehearsal přes ověřený kit: prošel včetně zachování ID,
  absence vymyšlených receiptů, pause a retry/adoption quarantine.
- Šest cílených SQL sad na každé major verzi: 6/6 + 6/6. Canonical mutation
  parity, bank/email oprávnění, spot assignment a seating metadata.
- 53 cílených Node testů a 9 Python testů: prošly. Baseline recovery testuje
  skutečné Git objekty po odstranění zdrojů i odmítnutí konfliktního cíle.
- Migration layout, rehearsal safety, canonical-source check, assembler check,
  operations-inventory check, client registry a lokální client preflight:
  prošly. Syntaxe dotčeného Bash/Python tooling ověřena.
- Dotčené odkazy, aktivní konzumenti odstraněných cest, hashe chráněných
  vstupů a scoped whitespace diff ověřeny. Dump zachovává existující mezery
  uvnitř funkčních těl kvůli přesné paritě; úzké Git whitespace pravidlo platí
  pouze pro generované baseline SQL.

Použité obrazy: Supabase PostgreSQL `15.8.1.085` a `17.6.1.156`; porovnávání
vždy uvnitř stejného majoru. Nejde o release validaci produkčního runtime.
Všechny vlastní dočasné DB byly na konci zastaveny; ostatní lokální projekty
nebyly zastaveny ani měněny.

## Skutečné metriky

Ve sdíleném workspace současně pokračovala nezávislá migrace npm na pnpm a
vznikly další plány. Jejich soubory nebyly přepisovány ani započítány do
izolované SQL skupiny níže. Celková tabulka je skutečný snímek workspace před/po,
nikoli tvrzení, že celý její rozdíl způsobila tato práce. U 18 původně
archivovaných vstupů byly samostatně zaznamenány paralelní změny; dalších
1570 chráněných původních vstupů zůstalo bajtově shodných mimo povolený soupis.

Stejná metoda před/po: množina `git ls-files -c -o --exclude-standard`, pouze
existující běžné soubory bez symlinků; text nemá NUL a řádky se počítají jako
počet LF. Druhý řádek zahrnuje existující soubory Git indexu; nové zatím
nesledované soubory obsahuje první řádek. Ignorované logy a lokální cache nejsou
započítány do zdrojů. Výsledek zahrnuje nový snapshot, manifesty a všechny
přidané nástroje a testy, nikoli pouze hrubý počet smazaných řádků.

<!-- METRICS -->

| Množina | Soubory před / po | Bajty před / po | Textové řádky před / po |
|---|---:|---:|---:|
| Workspace: neignorované zdroje | 4300 / 4151 | 73196272 / 70137560 | 892790 / 848422 |
| Workspace: existující soubory Git indexu | 2867 / 2747 | 51634183 / 47861241 | 654015 / 561831 |
| Izolovaná SQL/automation skupina této práce | 134 / 35 | 3446333 / 2386561 | 80423 / 60183 |

Čistý rozdíl izolované SQL/automation skupiny včetně nového baseline, manifestů,
nové forward opravy, souvisejícího tooling a testů: -99 souborů,
-1059772 bajtů, -20240 textových řádků.

Tato vymezená skupina nezahrnuje dokumentaci a generovaný operations/source-parity
inventář; její přesný seznam cest a hashe původních vstupů jsou v lokálním kitu.
Hrubé odstranění všech 198 souborů činí 5 388 872 bajtů; samotné hrubé číslo
není vykazováno jako čistá úspora.

Retence není uvolnění disku ani zmenšení `.git`. Lokální recovery/cache se
kvůli důkazům naopak zvětšila. MapLibre a fonty mají v tomto úklidu nulovou
úsporu; aktivní JSON nebyl minifikován.
