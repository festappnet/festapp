# Stripe integration readiness - 2026-10-22

Vlny 1-4 byly připravené v samostatném worktree. Navazující zadání autorizovalo publikaci a produkční release jednoho tenanta a skrytou aktivaci unity 8. Aktuální kontrakt a dodatečné ověření popisuje [release záznam](../../operations/stripe-hidden-unit-release-2026-10-22.md). Níže zachované důkazy původní přípravy nejsou potvrzením produkčního nasazení.

## Zdroj a samostatný patch

- Upstream byl před přípravou načten pomocí `git fetch origin main`. Base: `eab22c17db361362fc7fd1c5aa84a09dd4c427eb`, včetně nového průvodce, sdíleného vzhledu formulářů/vstupenek a opravy bankovních členství.
- Zdroj: původní dirty checkout `/Users/miakh/source/festapp`, větev `feat/occasion-setup-wizard-20261007`, HEAD `eb23047248d59bf86345b9e0b79db4a988275231`. Při zahájení měl 2387 změněných cest. Tento checkout nebyl resetován, stashed ani přepsán.
- Výsledek: `/Users/miakh/source/festapp-stripe-readiness-20261022`, větev `integrate/stripe-readiness-20261022`, původní příprava commitnutá jako `cc7896c20`, aktuální `main` `e069a11b7` následně integrován.
- [Manifest](INTEGRATION-MANIFEST.json) obsahuje konkrétní cesty, důvody, finální SHA-256 a dostupné hashe dirty zdrojů. [Přesný pathspec](INTEGRATION-PATHS.txt) zahrnuje i nové soubory. [Původní kandidáti](integration-evidence/source-candidates.txt) jsou širší inventář, nikoli seznam k publikaci.

Sdílené soubory byly integrovány po Stripe úpravách. Zůstaly současné SQL `can_*` kontroly, Blueprint zámky a vazby, rychlý agregát objednávek, BankSync varování, `/order`, routing, dialogy, bankovní editor i nové UI průvodce. Nebyla převzata celá feature větev, její dirty diff, starý fontový katalog, jiné migrace ani lokální sandbox tooling/secrets. Historické sanitizované důkazy jsou zachované se svými limity.

## Skrytí a deaktivace

`StripeFeature.visible` čte serverový příznak aktuální unity `stripe_preview_enabled`, výchozí hodnota je `false`. Skrytou aktivaci ovládá pouze administrátor portálu přes SQL `set_stripe_unit_feature`; build-wide preview přepínač byl odstraněn. Běžné menu pořadatele, vstup z nastavení, přímá stránka správy karet i volba v editoru formuláře jsou skryté. Widgetové preview fixture mají explicitní `showCardPayments: true`; není to serverové oprávnění ani zapnutí prodeje. Běžné nastavení neprovádí Stripe read a neodstraňuje případnou uloženou konfiguraci.

SQL runtime policy má `new_payments_enabled=false` a nepovolené povrchy ve výchozím stavu. Rehearsal neobsahuje jedinou zapnutou policy. Samotné propojení účtu nezapíná kartu a chybějící provider secrets neblokují bankovní checkout. Čtení historie, oddělené capability, webhook/recovery a admission/email fences zůstávají implementované i při zastavení nových plateb. Původní příprava neměnila živou konfiguraci; následné zadání autorizovalo zviditelnění pouze unity 8 při vypnutém prodeji.

## Konečné migrace a opravy při integraci

Tři nepublikované migrace byly přesunuty za aktuální main head migrací `20261022050000`:

1. `20261022160000_stripe_foundation.sql`
2. `20261022170000_stripe_connections.sql`
3. `20261022180000_stripe_checkout_ingest.sql`

Nahrazují pouze dosud nepublikované soubory `20261021160000`, `20261021170000`, `20261021180000`. Publikované migrace z main se neměnily. Generátor, source contract a runbook používají konečné názvy. Skutečný runner je `automation/baseline.py upgrade-local`, který materializuje historické migrace a používá `supabase migration up --include-all`; jeho pořadí je v replay receipts.

Přenos odhalil rozdílné vlastníky v main. Nové privátní Stripe SQL a společný nový součet vznikají explicitně jako `postgres`, aby je mohly volat současné příkazy vlastněné `postgres`. Existující sdílené funkce si ponechávají své vlastníky, včetně scanner funkcí vlastněných `supabase_admin`. Migrace se ověřovaly extension-owning superuserem, bez rozšiřování klientských grantů.

Provider/expiry ochrana přechodu na zaplaceno je v současném `mark_order_and_tickets_paid_internal_v1`, takže ji neobchází nové volající main. Opravené jsou také admin/history DTO, přesnost emailů a obou klientů, obnovení cen a příjemce bez nové objednávky. Flutter i JS obnovují ceny sedadel přes aktuální kanonický Blueprint adapter; neobnovují starou cenu ani uvolněné sedadlo. `payment_method` a `payment_type` zůstávají samostatné osy.

Dvě starší bank/scanner regrese potřebovaly opravu fixture: zálohový test již nezakládá osiřelá legacy sedadla a snapshot test nepřebírá náhodnou existující událost. Doménové assertions zůstaly zachované; produkční ochrany nebyly zeslabeny.

## Skutečně provedené ověření

Podrobnosti a reprodukce: [integration-evidence](integration-evidence/REPRODUCE.md). Počty mezi překrývajícími se běhy se nesčítají do jedné fiktivní sady.

| Hranice | Výsledek |
|---|---|
| Finální fresh replay | Kanonický baseline, všechny forward migrace a konečné tři Stripe migrace prošly skutečným runnerem v task-owned instanci na 61232 |
| Upgrade dnešního main | Samostatná instance na 61242 byla nejprve na přesném base bez Stripe; následně prošly jen tři konečné Stripe migrace |
| Zachování staré bankovní objednávky | Před Stripe vznikla paid bankovní objednávka s pohybem 123.45 CZK; původní JSON objednávky a pohledávky zůstal přesně stejný, přibyly jen nové payment sloupce |
| Readback katalogu | Obě cesty mají shodné definice/ACL 53 vybraných funkcí a 12 Stripe tabulek: RLS zapnuté, žádné klientské policies/přímé granty ani persistentní aplikační triggery. `/stripe` i `/order` rezervované; sales a cron dispatch vypnuté |
| SQL regrese na fresh | 31 vybraných souborů pokrývá Stripe, scanning, BankSync, bank/free/deposit/manual/report a source parity. 30 prošlo v dávce; po opravě snapshot fixture prošel její jediný cílený rerun. Žádné skips |
| SQL regrese po upgradu | 12/12 souborů: celý Stripe adresář a canonical source parity |
| Skutečný souběh PostgreSQL | 1 Node test, všech 6 held-lock races prošlo, bez skipu. Použil vlastní klon task-owned databáze; sdílený 55432 harness nebyl měněn ani restartován |
| Deno | 55 provider/connection/source testů a 27 existujících payment/email/deposit regresí prošlo. Typecheck order senderu, confirmation rendereru a šesti Stripe endpointů prošel s frozen lockfile |
| JS | 246/246 formulářových, platebních, bootstrap a publikačních lokalizačních testů prošlo. Produkční Vite build prošel přes pnpm 11.24.0 |
| Flutter | 55/55 widget/link/connection/refund/amount/hidden-feature případů prošlo ve výchozím buildu; další 2 regrese kanonického obnovení ceny prošly. Cílený startup/post-login běh má 6 prošlých případů a překrývá hidden testy. Vždy jediný Flutter task, `--concurrency=1` |
| Core a tooling | 9/9 core payment/report testů, 5/5 routing/PWA automation testů, oba generátory a diff whitespace check prošly. Nové Flutter roots jsou klasifikované |
| Dart analýza | Cílená analýza výsledných hranic nemá chyby. Zůstávají existující varování/stylové informace, mj. mutable `FormPage`/`MyApp`; nové Stripe soubory nemají varování |

## Zbývající gates a omezení

- **Existující problém main:** `automation/test_client.py` spouští `tool/check_architecture.dart`, který v připnutém upstream main není. Tato kontrola neprošla a není vydávána za úspěch. 12 Python kontraktních testů runneru prošlo, ale simulují runner a chybějící architecture guard nenahrazují. Před požadavkem na úplný client/release gate je třeba vyřešit tento nezávislý problém; v rámci Stripe nebyl doplněn neznámý starý checker.
- Neproběhl nový provider sandbox/browser E2E na tomto integrovaném patche. Starší skutečné sandboxové transakce jsou simulace z původní dirty revize, nikoli důkaz merge, aktuálního buildu či nasazení.
- Native device návrat/restart, ruční VoiceOver/TalkBack a přijetí konkrétního produkčního CMS/hostu zůstávají otevřené. Native/embed se neaktivují na základě widgetových důkazů.
- Publikace, jediný tenant release, instalace recovery a ostrý pilot potřebují následnou odpovídající autoritu. Pro pilot nadále platí přijetí 31minutové rezervace, dispute hold, online admission a refund/late-payment pravidel z runbooku.

## Konkrétní publikační kroky po dalším zadání

Návrh commit message: `feat(payments): integrate hidden Stripe checkout with canonical payment authority`.

1. Zkontrolovat manifest a soubory v novém worktree, poté stage pouze přes `git add --pathspec-from-file=docs/plans/stripe-client-owned/INTEGRATION-PATHS.txt`. V této přípravě se nestagovalo ani necommitovalo.
2. Bezprostředně před publikací znovu `git fetch origin main`, porovnat s base `eab22c17...`, integrovat intervenující změny a zopakovat jen jejich dotčené kontroly. Ověřit požadované repository gates a CI triggery, včetně výše uvedeného chybějícího architecture checkeru. Nepoužít obecný push s implicitním targetem.
3. Při výslovném schválení commit/push preferovat ověřené přímé začlenění do autoritativního main, dovolují-li to pravidla větve. Není připraven PR jako mezikrok. Zaznamenat skutečný výsledný commit.
4. Deploy je samostatné zadání: vybrat jednoho tenanta a overlay, dodržet lokální build a `automation/deploy_direct.sh`, projít backend/client/email/router pořadí a všechny release gates. Viditelnost nastavovat po unitách přes admin RPC a nové Stripe prodeje ponechat vypnuté. Rutinní release delegovat podle AGENTS.md.
5. Zviditelnění/aktivace pilotu jsou další samostatná rozhodnutí. Samotná publikace kódu ani deploy je neautorizují.
