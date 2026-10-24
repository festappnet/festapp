# Plán aktualizace README a navazující dokumentace

> Historical plan or dated evidence. Statuses, versions, authorization and pending steps below apply to the recorded phase, not automatically to today. Use [current documentation](../../README.md) for operating procedures; archiving does not close unverified gates.


Datum: 2026-10-07
Stav: dokumentační aktualizace provedena lokálně, bez publikování
Podklad auditu: pracovní větev `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`.
Realizace: čistý main worktree `docs/documentation-refresh-20261007`, základ `eb1d94ac4`.
Ověření: statické porovnání dokumentace s místním kódem a provozními doklady.
Popisy auth/produkčních hranic mají targeted standard kontrolu; žádné živé operace.

## Rozsah a omezení auditu

Audit pokrývá hlavní README, dokumentační rozcestník, CONTRIBUTING, CLAUDE,
aktivní architektonické/backendové/setup návody a relevantní automation a
komponentové README. Historické a provozní záznamy slouží jako doklady změn;
neproběhla úplná kontrola každého souboru v archivu ani všech feature popisů.

Produkce, obchody, veřejné weby ani externí účty nebyly nově dotazovány.
Datované provozní doklady proto potvrzují zaznamenaný stav, nikoli stav dnes.
Existující změny překladů a webového blueprintu nejsou součástí tohoto plánu.
Plán nevyžaduje úpravy aplikace, databáze, tenant konfigurací ani deployment.

## Potvrzené nálezy

| Priorita | Dokument a místo | Rozpor a požadovaná oprava | Podklad |
|---|---|---|---|
| P0 | `README.md:119`, `docs/setup/howto.md:54`, `CONTRIBUTING.md:56` | Popis probíhajícího backend cutoveru a povinnost aplikovat změny také na cloudové zdroje jsou zastaralé. Popsat jediný kanonický produkční backend; staré zdroje jsou retenční/reconciliation cíle. | `docs/architecture/ai_context.md`, dokončený `canonical-self-hosted-cutover-2026-09-02.md`: přepnutí 2026-09-10. |
| P0 | `docs/setup/howto.md:56`, `CONTRIBUTING.md:60` | Výběr živé databáze podle samotného `SUPABASE_URL` může určit legacy fallback. Popsat ověření tenant aktivace, generace, canonical organization a případné forced occasion. | Aktuální pravidla v `ai_context.md`; activation pole v `automation/project.conf`. |
| P0 | `docs/setup/bank_import.md`, `docs/setup/aws_ses.md` | Návody k původnímu Festapp SNS parseru obsahují neexistující `automation/setup_aws_ses.sh`, `supabase/functions/bank-mail-parser` a `workers/image-worker/tests/integration/bank-import.test.ts`. Nahradit aktivní návod hranicí BankSync/Festapp a současnými kontrolními vstupy. | `docs/operations/banksync/FULL-CUTOVER-2026-10-04.md`, `bank-sync-{manage,reconcile,webhook}`, kanonické SQL `eshop_bank_sync/`. |
| P1 | `docs/backend/edge_functions.md:5,32,110` | QR výměna už není jedinou anonymní autentizační výjimkou: dokument sám níže popisuje Google broker. Inventář vynechává Google a BankSync funkce. Cloudový CLI deploy příkaz není postup pro canonical self-hosted runtime. | `runtime-writer-policy.json`, `supabase/functions/test-coverage.json`, současné function entrypointy a runtime bundle skripty. |
| P1 | `CONTRIBUTING.md:233`, `docs/setup/howto.md:77`, `lib/components/email_templates/README.md:21`, `docs/architecture/SERVICES.md:130` | Zmínka o SMTP/nodemailer odkazuje na odstraněný `emailClient.ts`; AWS receiving návod je chybně označen jako SMTP setup. Komponentový návod směruje diagnostiku jen na producenta a diagram zaměňuje potvrzení objednávky za odeslaný e-mail. Popsat enqueue, šifrovaný snapshot, jediného sendera a delivery receipt. | `_shared/README.md`, `emailSender.ts`, `send-custom-email` používá `enqueueAndAwaitEmail`; `send-ticket-order` vrací `delivery: queued`. |
| P1 | `automation/hetzner-supabase/README.md:10` | „Current implemented boundary“ prezentuje Wave 0 jako současný stav celé infrastruktury. Oddělit provoz canonical backendu od historických migračních nástrojů a jejich původních gate podmínek. | Dokončený cutover a záznam o záměrném zachování legacy zdrojů z 2026-09-23. |
| P1 | `docs/backend/image_worker.md`, `docs/architecture/SERVICES.md:133` | Tabulka image hostů míchá cílový stav „after P3“ s aktuálním provozem; offline diagram ukazuje pouze legacy cache, přestože text popisuje také Client Sync v1. Diagramy a tabulky musí jasně rozlišit současný stav a podmíněný cíl. | Image worker `wrangler.toml` stále obsahuje veřejné hosty; image cutover work item je blocked. `synchro_service.dart` vybírá v1 podle capability. |
| P2 | `README.md:179`, `docs/architecture/database.md:79` | README používá název `ANON_KEY` místo `SUPABASE_ANON_KEY`. SQL inventář opomíjí `eshop_bank_sync/` a popis e-mailů neodráží kanonickou queue. | `project.conf`, současné doménové SQL a `ai_context.md`. |
| P2 | `docs/README.md` | Rozcestník nezpřístupňuje přímo aktuální auth, BankSync a Client Sync provozní návody. Tvrzení, že všechny dokončené materiály jsou v archivu, nezohledňuje `operations/work-items/completed/`; `docs/plans/` obsahuje také datované release/evidence záznamy. | Současný strom dokumentace a registry work items. |

Kontrola 36 hlavních dokumentů našla 59 relativních Markdown odkazů na soubory,
všechny existují. Kontrola nezahrnovala URL na internetu, kotvy, HTML obrázky
ani cesty uvnitř code bloků; odstraněné příkazy výše proto přesto představují
potvrzenou chybu.

## Body k vyjasnění při aktualizaci

- README slibuje „fully offline“. Popsat dostupné cache/projekce a jejich
  předpoklady; zápisy, platby, autentizaci a první načtení nelze zahrnout do
  obecného příslibu bez důkazu. Nejde o potvrzenou regresi aplikace.
- Root `project.conf` má legacy URL a prázdnou activation phase. Nezaměňovat
  výchozí konfiguraci sdíleného checkoutu za důkaz produkčního cíle a automaticky
  ji nepřepisovat podle jednoho tenantu.
- Image projektové identifikátory `default` a `a` jsou stále v kódu registry.
  Backend cutover sám neznamená, že se smějí odstranit nebo přejmenovat.
- BankSync doklady obsahují různé fáze nasazení, včetně dříve blokované platby
  a neuzavřené identity bankovních e-mailů. Zachovat datované doklady; z pouhé
  existence nového kódu netvrdit, že všechny účty a email ingress jsou ověřeny.
- Screenshoty, veřejné odkazy a přísliby podpory platforem nebyly vizuálně ani
  provozně ověřeny. Případný refresh vyžaduje samostatný omezený průchod.

## Pořadí aktualizace

1. **Sjednotit autoritu backendu.** Upravit README, howto a CONTRIBUTING podle
   `ai_context.md`; doplnit activation postup a odkaz na dokončený cutover.
   Odstranit aktivní doporučení cloudové parity. Zdůraznit rozlišení veřejných
   konfiguračních hodnot a privátních credential vstupů.
2. **Nahradit vysloužilé integrační návody.** Přesunout původní AWS/SNS bankovní
   postup do archivu se statusem historical. Na původních vstupních cestách
   ponechat krátký aktuální rozcestník, aby fungovaly stávající odkazy.
   Doplnit BankSync API/control/email hranice a skutečné evidence gates;
   oddělit odchozí SES queue od příjmu bankovních e-mailů.
3. **Aktualizovat technickou referenci.** Srovnat Edge inventář a auth výjimky
   s runtime policy a coverage matrix. Deployment popsat přes existující
   canonical bundle/release tooling a projektový backend-access skill.
   Opravit e-mailovou pipeline, SQL inventář a oba diagramy v SERVICES.
4. **Zpřehlednit provozní a historický stav.** Přepsat úvod infra README,
   rozlišit současné image routování od P3/P4 cíle a doplnit docs rozcestník.
   U každého zvažovaného přesunu plánu nejdříve ověřit uzavření a závislosti;
   nepřesouvat automaticky všechny starší nebo datované soubory.
5. **Dotáhnout produktový úvod.** Upřesnit offline příslib a konfiguraci
   README. Přidat krátké odkazy na Google login, ticket layout editor, reporty
   a další doložené aktuální funkce bez kopírování podrobných runbooků.

Změny připravit jako dokumentační celek na kanonickém main základě v čistém
worktree. Publikování ani propagace na `prod/*` nejsou součástí tohoto plánu.

## Kritéria hotovo a ověření

- Aktivní vstupní návody určují stejný backend a nevybírají jej podle fallback
  URL; nepožadují běžné zápisy do bývalých cloudových zdrojů.
- Žádný aktivní integrační postup nevyžaduje odstraněný parser, skript nebo test.
- Edge inventář odpovídá runtime policy; výjimky a deployment mají jasný scope.
- Dokumentace rozlišuje queued/accepted/sent e-mail, aktuální image Worker
  routing a ještě neprovedený P3/P4 cíl, v1 a legacy offline větev.
- Datované provozní důkazy zůstávají dohledatelné; otevřené gates nejsou
  bez nového důkazu označeny za dokončené.
- Jedna závěrečná levná kontrola: lokální odkazy, existence dokumentovaných
  cest, porovnání Edge inventáře s policy a scoped vyhledání starých aktivních
  instrukcí. Historické záznamy z této kontroly vyjmout.

Buildy ani aplikační testy nejsou pro tento čistě dokumentační celek nutné.
Ukázkové SQL/deploy/AWS příkazy při kontrole nespouštět. Pokud vznikne potřeba
nového produkčního readbacku, vést jej odděleně s verification: standard a
zaznamenat čas i přesný scope pozorování.

## Realizace 2026-10-07

Aktualizace provedla všech pět kroků výše jako dokumentační celek. Změny
vznikly na čistém main základě a byly přeneseny do původního checkoutu bez
zásahu do existujících změn aplikace. Publikování a tenant rollout nejsou součástí.

- README, CONTRIBUTING a howto určují kanonický backend podle aktivace,
  odlišují public config od privátních vstupů a nepředepisují cloudovou paritu.
- Bank import a AWS/SES vstupy nyní popisují BankSync a jedinou odchozí queue.
  Původní postupy jsou v `docs/archive/setup/` s výslovným historical statusem;
  původní vstupní cesty a odkazy zůstaly funkční.
- Edge inventář odpovídá writer policy včetně Google, BankSync a email proof
  funkcí. Deployment popisuje reviewed bundle a odděluje staging od restartu.
  SERVICES, SQL inventář a email templates popisují queued/accepted/feedback,
  oba sync store typy a jediného sendera.
- Infra README odděluje současný provoz od historického Wave 0. Image tabulka
  rozlišuje checked-in Worker routing, datovaný readback a otevřený P3/P4 cíl.
  Rozcestník zpřístupňuje aktuální provozní vstupy i různé typy historických dokladů.
- Produktový úvod upřesňuje offline předpoklady, správný název anon key a
  odkazuje na doložené Google, ticket layout, report a bank account funkce.

### Další nálezy ze širšího průchodu

1. Eshop README popisoval starý vícefázový klientský postup přes
   `confirm_blueprint_order_change` a nedoložený diagram Stripe/Comgate.
   Nyní popisuje skutečný `send-ticket-order` transport s receipted create/replace
   RPC a transakčními email intents. Legacy SQL zdroj nebyl odstraněn.
2. Client Sync runbook doporučoval cloud-only health/preflight a release skripty.
   `loadCanonicalSupabaseTarget` má přes název cloudový `.supabase.co` resolver
   a management API transport; health, cutover a scheduler skripty proto
   nejsou postup pro self-hosted produkci. Runbook nyní výslovně omezuje jejich
   scope a ponechává lokální registry check. **Adaptace nástrojů zůstává
   samostatnou implementační prací**, nikoli součástí refresh dokumentace.
3. Google operation guide označoval přednasazovací snapshot za aktuální stav,
   přestože rollout doklady již zaznamenávají instalované server inputs.
   Úvod nyní odkazuje na pozdější doklady a zachovává původní snapshot s datovaným
   významem; z rollout dokladů neodvozuje dnešní native/tenant readiness.
4. Automation README označoval konfigurační vstupy obecně za credentials.
   Popis nyní výslovně odděluje veřejné klientské nastavení od privátních secrets.

### Zbytkové limity

Žádný nový produkční, bankovní, provider, store nebo vizuální readback neproběhl.
Provozní tvrzení vycházejí z označených datovaných dokladů. Otevřené image,
bank email identity a EUR pilot gates zůstávají otevřené. Starší plány ani
operační doklady nebyly hromadně přesunuty nebo označeny za dokončené.

Závěrečná kontrola: relativní odkazy v upravených dokumentech, nové dokumentované
source/tool cesty, Edge inventář a coverage proti policy, scoped vyhledání
vysloužilých aktivních instrukcí a `git diff --check`. Build ani aplikační testy
nejsou pro tento dokumentační celek potřeba. Výsledek: PASS - 20 dokumentů, 106 lokálních odkazů, 30 Edge položek
(včetně jednoho production exclusion), coverage test cesty a 16 source/tool
cest souhlasí; kontrola starých aktivních instrukcí a whitespace prošla.
Externí URL a všechny existující Markdown kotvy nebyly ověřovány.
