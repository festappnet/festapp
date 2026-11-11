# Lokální sjednocení členství a pozvánek - 2026-11-10

Celý execution prompt je lokálně dokončený a ověřený pro unit, occasion i setup.
Všech 8 affected canonical CI lanes prošlo v navazujících dávkách.
Tento dokument neautorizuje publikaci ani rollout.

Výchozí branch `docs/festapp-tickets-readme-20261107`, HEAD
`742d614b722bbe619b3a095f66605bd4bb536006`. Výchozí status, diff a hashe cizích
rozpracovaných změn jsou v chráněném `/tmp/festapp-access-20261110/`. Změny
ostatních úkolů zůstaly zachované. Žádný commit, push, produkční SQL, deploy,
změna zákaznických rolí ani skutečné rozesílání nebyly provedené.

## Výsledek

- `people/` vlastní společný command, membership primitivum a scoped invitation
  lifecycle. Jedna tabulka `access_invitations` vzniká přejmenováním původní
  tabulky; zachovává ID, tokeny, expirace, audit, přijetí a message vazby.
  Draft má `ON DELETE SET NULL`. Existující identita je nabídce pevně přiřazená;
  odstranění účtu a vytvoření jiného se stejným e-mailem nepřenese nabídku.
- `manage-member-access` připraví lokalizovanou zprávu existujícím rendererem,
  resolverem a encrypted snapshot ownerem. Service-only krátkodobý deposit je
  vázaný na actor/command/intent/preview. Authenticated SQL command znovu ověří
  živou autorizaci a atomicky uloží požadovanou doménu, enqueue a receipt.
  Neimituje JWT ani nepřenáší autoritu na service_role. Heslo v depositu je
  šifrované; receipt neobsahuje heslo ani capability token.
- Plain save neposílá e-mail; notice/resend nemění profil ani role. Nabídka rolí
  před přijetím neuděluje přístup. Accept je aditivní, revoke/downgrade ruší
  pending nabídky i neodeslané zprávy. Souběhy zachovávají původní oprávnění,
  nedovolují vzkříšení odebraných práv ani duplicitní účet/receipt.
- Účastnický `SIGN_IN_CODE` dál nastavuje skutečné vygenerované heslo přes původní
  reset policy. Týmová nabídka/notice heslo existujícího účtu nemění. Unit scope
  credential reset nepovoluje. Přihlášky, automatická potvrzení, objednávky
  a platby používají své dosavadní vlastníky a transakční hranice.
- Obě správy členů používají společný dialog, transport a stavovou projekci.
  Setup předává uložený potvrzený výběr se stabilním commandem pro příjemce;
  partial batch nezruší ostatní výsledky. UI rozlišuje nabídku, membership,
  queued/provider/delivery a acceptance, nabízí refresh/revoke/resend, reaguje
  na změnu identity/contextu. Texty a scoped role jsou lokalizované v 6 jazycích.
- Scoped forward migrace a canonical manifests zahrnují runtime, worker admission,
  capabilities, Client Sync, šablony i ACL. Historické migrace nebyly přepsané;
  jejich assemblery ověřují neměnnost a účinné forward definice. Přizpůsobené
  globální i tenant/unit/occasion šablony zůstávají beze změny.

## Důkazy

SQL běžel výhradně na označené disposable DB
`festapp_access_20261110` na `127.0.0.1:55432`; queue paused, worker URL prázdná,
bez scheduleru/provideru. Skutečný lokální GoTrue v2.194.0 byl oddělený na portu
61699 a po testu odstraněný. Browser používal vlastní disposable Supabase projekt
`festapp-access-e2e-20261110`, API 61821, DB 61822, oddělený headless muted browser.

| Ověření | Výsledek / rozsah |
|---|---|
| `run_db_tests.js` nad access management/membership/invitations/atomicity, sign-in codes, invitation delivery, registration, free confirmation a application-only checkout | 9 passed; 4 z nich po repository sequential retry kvůli fixture DDL lock contention. |
| Setup invitation SQL | Passed; původní scope, potvrzený výběr, expiry, read-only role, historický retry i worker/ACL kontrakty zachované. |
| `access_migration.test.mjs` | Passed; pending/accepted/expired, stejné tokeny/audit/message, draft delete, nulové nové zprávy; vlastní šablony a resolver hierarchy zachované. |
| `access_lifecycle_concurrency.test.mjs` | 6 passed; oddělená fyzická spojení, pozorovaný blocker, accept/accept, revoke/accept, legacy teardown/accept, create/anonymous accept, credential retry. |
| `unit_membership_concurrency.test.mjs` | Passed; jeden commit při retry, delete versus replay neobnoví členství. |
| `participant_credentials.integration.test.mjs` | Passed; nový common preview/stage/command a skutečný GoTrue login, opakované heslo, expirace e-mailu, enqueue rollback, explicitní resend. Prepared mail fixture bez provideru. |
| Deno manage-member-access + setup handlers | 10 passed; inherited renderer a sealed snapshot skutečně obsahují stejné vygenerované heslo; replay, prepare failure, scope, partial batch. |
| Flutter unit/profile/invitation/setup/sign-in-code cases | 26 passed, `--no-pub --concurrency=1`. |
| Cílený Dart analyzer | 0 errors / 0 warnings; 11 informational style diagnostics. |
| Generátory access/people/source parity/email variables/authorization capabilities | Passed. |
| Security migration/header/ACL contracts | 8 passed; přesun starého lookup adaptéru explicitně registrovaný, bez rozšíření grandfather baseline. |
| Finální routing + invitation cases | 12 passed; bezpečný interní token destination, odmítnutí externího/duplicitního/secret redirectu. |
| Rights context + setup template editor regression | 28 passed; fixture ověřuje nový unit save RPC bez komunikace; všechny nové email variables mají lokalizované UI popisy. |
| Catalog contraction readback | Původní tabulka absent, starý enqueue RPC absent, 0 runtime function bodies odkazujících na starou tabulku. |

Browser prokázal skutečný unit header/dialog -> queued offer -> anonymous new
account accept; occasion header/dialog -> queued -> revoke/cancelled; správné
role a akce v UI; cross-tab logout zavře dialog a historii. Existující účet
přijal nabídku se stejným UUID a nezměněným password hashem. První průchod
odhalil ztrátu tokenu v login redirectu; oprava používá typed route a přesný
interní invitation destination před generic occasion resolution. Samostatný
whitelist dovoluje tento capability cíl i v Google návratu, nikoli obecné
secret-bearing redirecty. Finální browser roundtrip prošel: admin offer -> logout
-> login existujícím účtem -> automatický návrat se shodným tokenem (programově
porovnáno) -> explicitní Accept -> potvrzení UI. DB zachovala UUID/password hash
a udělila pouze nabídnuté occasion editor/read-only role, manager zůstal false.
Vlastní Flutter/browser byly zastavené a dočasný test target odstraněný.

Ověření je složené: Edge test vykonává reálný renderer/encryption; SQL/Auth
integrace používá bezpečný prepared fixture; browser používá skutečnou aplikaci
s lokálním Auth/backendem. Žádný test neposílal zprávu skutečnému provideru.

Původní organizační scénář create/role/delete/re-add/occasion add prošel.
Normalizace case/whitespace opravila reprodukované odmítnutí v explicitně načteném
repository SQL. Historická příčina zákaznického hlášení zůstává nepotvrzená.

## Uzavřený deletion ledger

| Původní cesta | Finální stav a vnější kontrakt |
|---|---|
| `occasion_team_invitations`, setup-specific write/accept logika | Jedna přejmenovaná tabulka a people owner. Žádná druhá zapisovatelná kopie. Historické migrace zůstávají neměnné. |
| `enqueue_occasion_setup_invitation` | Odstraněný interní sealed-content RPC. Jediný serverový producer převedený; nebyl klientským protokolem. |
| `preview_occasion_setup_invitations`, `send-occasion-team-invitations` | Podporovaný setup selection preview a tenký dávkový adaptér. Spotřebitelé: `occasion_setup_invitations.dart`, `occasion_setup_page.dart` a již instalované setup klienty. Minimální protokol: jejich stávající draftId/emails endpoint; odstranit až po vynuceném upgradu těchto klientů a přesunu stejného selection kontraktu. Neobsahují druhý grant/enqueue owner. |
| `get_occasion_team_invitation`, `accept_occasion_team_invitation`, `/team-invitation?token=...` | Mechanické event-only RPC adaptéry pro dříve odeslané odkazy/instalované klienty. Minimální protokol: původní token/password kontrakt. Unit nabídky starý RPC nepřijímá. RPC lze odstranit až po upgradu všech starých klientů; veřejnou URL zachovat po celou platnost historických odkazů. Nový klient používá common get/accept. |
| `add_user_to_unit` | Mechanický autorizovaný adaptér nad receipt-backed membership commandem. Spotřebitelé: instalované klienty s původní signaturou `(unit_id,usr)`; nový klient používá Client Sync v1. Smazat po vynuceném upgradu všech unversioned callerů. |
| `save_unit_user_client_sync_v1`, `save_profile_client_sync_v1`, `create_occasion_user_client_sync_v1`, legacy update RPC | Publikované v1/unversioned adaptéry nad stejnými specializovanými private writers, které volá common command. Spotřebitelé: instalované Client Sync editory a historické přímé RPC klienty; explicitní profile/role save se nesmí změnit na automatický e-mail. Odstranit až po vynucení klienta používajícího common command a odstranění posledního calleru. |
| `send-sign-in-code`, SIGN_IN_CODE, exchange login | Podporovaný účastnický kontrakt, není obsolete. HTTP zachovává sent/202 semantics. Týmová větev je tenký common producer; `teamAccessNotice.ts` a jeho druhá implementace odstraněné. |
| `data.is_invited` | Private save nové zápisy odstraňuje. Historická hodnota zůstává pouze read-only účastnickou delivery projekcí; není autoritou membership ani acceptance. |
| Setup-only worker/report/template/runtime/source registrace | Přepojené na scoped access autoritu a stávající delivery owner; registry, výběr testů a source parity aktualizované. |

Konkrétní číselná minimální vydaná app verze není doložená dostupným inventářem.
Proto nebyl žádný publikovaný vnější protokol odstraněn na základě odhadu verze;
výše jsou přesné minimální podporované signatury a podmínky contraction.

## Závěrečné kontroly

- Login routing regression: 12 passed. Automatický browser návrat a accept: PASS.
- Prošlé canonical lanes: image-contract 3,6 s, web-startup 51,1 s,
  wix-checkout-compatibility 9,6 s, navigation-interactions 49,8 s,
  client-contract 45,35 s. Server-policy na finálních překladech prošla 8,6 s;
  seat-checkout včetně notifications/browser prošla 92,24 s,
  ticket-preview-and-delivery prošla 65,93 s. Všech 8 lanes PASS.
- Preflight odhalil zastaralou exact-string aserci: startup kontrakt zachovává
  povinný první příkaz a dovoluje doplňující Wallet test, žádný test nebyl odebraný.
  Oficiální MCP generátor obnovil pouze sourceDigest po změně překladů.
- Checkout odhalil nezaktualizované refund assertions v souběžném pracovním
  stromu. Převzaté přesné aserce vlastníka ověřují received=1200, net=1100,
  overpaid=100 po returned=100; finance SQL se neměnilo. Notification owner
  odstranil pouze svůj starý necommitnutý draft/source patch, který už samostatně
  publikoval jinou prací. Historické migrace nebyly přepsané ani kontroly obejité.
- První ticket batch zachytil dvě vlastní regrese: zastaralý RPC fixture a chybějící
  UI descriptions nových template variables. Obojí opravené, cílený batch 28 passed;
  čtyři nové popisy jsou lokalizované ve všech 6 jazycích. Finální ticket lane PASS.
- Logy závěrečných běhů/receipts jsou v chráněném `/tmp/festapp-access-20261110/`,
  zejména `canonical-final-all8.log`, `canonical-final-client-ticket.log`,
  `canonical-final-remaining.log`, `canonical-final-seat-ticket.log` a
  `seat-ticket-receipt.json` (complete=true, exit 0 pro obě poslední lanes).
  Passing lanes byly zachované, po konkrétní opravě se opakoval dotčený gate.
  Starý první řez není finální důkaz.
- Vlastní browser, Flutter, Auth server i E2E backend jsou ukončené; vlastní SQL
  clone `festapp_access_20261110` odstraněný. Cizí backendy zůstaly nedotčené.
- Tento úkol neprovedl publikaci ani produkční rollout. Lokální migraci nelze
  zaměnit za nasazenou změnu; release vyžaduje samostatné zadání a jeho gates.

## Dodatečně autorizované začlenění a nasazení

Uživatel po dokončení lokální implementace výslovně zadal merge do main,
publikaci a nasazení, včetně hotové stránky `/pro-media` s balíčkem log.
Příprava probíhá v izolovaném worktree `festapp-access-release-20261110`,
nikoli přepsáním původního sdíleného pracovního stromu.

Nový main již obsahuje publikovaný forward17 kontrakt týmových e-mailů.
Společný producer proto používá jeho kanonické `occasionTitle`, `roleLabel`,
`invitationUrl` a `occasionAdminUrl`; draft-only aliasy eventTitle/eventUrl
se nezavádějí. Odpovídající popisy jsou už součástí main. Historické pending
zprávy si ponechávají svůj encrypted snapshot a vlastní šablony už zachovává
publikovaný conversion owner. Test společného rendereru navíc ověřuje jediné
escapování názvu scope.

Dosud nepublikovaný access draft160000 se při tomto začlenění nahrazuje
novou migrací `20261111010000_access_membership.sql`, po všech aplikovaných
migracích i Wallet hotfixu233000. Již aplikované migrace se nepřepisují.
Další release gates a skutečné nasazení jsou evidované v samostatném
release receiptu a závěrečném předání.

Integrovaný zdroj je založený na main `dab6cc77c89bae263aae05bc79e3d6496f69d2cc`.
Release validace: původní all8 běh má 6 passing jobs; jeho jediný skutečný
fail byl stale authorization projection po rozšíření authored template.
Po správném pořadí projection -> capability IDs -> forward -> parity prošly
všechny dotčené `web-startup`, `wix-checkout-compatibility`, `seat-checkout`,
s complete=true a inputsUnchanged=true. Původní passing jobs bez změny jejich
behaviorálních vstupů zůstávají doložené. Média mají 7 passing registry/render/ZIP
testů, common Edge 10 passing testů s aktuálním kanonickým variable kontraktem.
Lokální receipts: `/tmp/festapp-access-20261110/release-affected-final-receipt.json`
a `release-canonical-all8.log`. Autoritativní GitHub exact-main gate a skutečné
nasazení následují samostatně po publikaci, bez změny původních produkčních dat
jako testovacích fixtures.
