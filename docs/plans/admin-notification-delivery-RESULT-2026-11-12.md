# Administrátorské souhrny - lokální výsledek

Implementováno v pracovním stromu `/Users/miakh/source/festapp`, výchozí HEAD
`742d614b7`. Stávající větev a cizí rozpracované změny jsou zachovány.
Bez commitu, pushe, změny produkční větve, produkční migrace či aktivace.

## Sdílená příprava a odstraněné výpočty

- `notification_center_event_facts_internal` je společný owner pro DTO,
  prepared apply a email context. Captured count včetně nuly má přednost;
  jediná legacy count/form větev zůstává jen pro chybějící historická fakta.
  Běžná událost bez formuláře zachytí kanonický prázdný kontext.
- Platební fakta a platební problémy nemají příspěvek osob/vstupenek.
  Jejich count/formContext jsou NULL jako nepoužitelné údaje: source owner
  nepočítá tickety a facts helper nespouští legacy hydration. Souhrn ani send
  permit nepřepočítávají ticketové nebo finanční domény.
- `notification_center_event_relevant_internal` sjednocuje relevanci s oběma
  původními privacy adaptéry. Platební problém kontroluje aktuální doménovou
  epizodu; bankovní problém odkazuje na původní BankSync owner/readiness.
- `notification_center_event_display_internal` a explicitně recipientový bank
  display helper sdílejí bezpečný kontext s UI. Email skládá materializované
  distinct events, metadata a existující scope vektory. Žádná DTO kopie,
  prepared cache, nové UI scope, read receipt nebo N+1 RPC.

## Funkční doručení

Collector čte existující deliveries přes per-scope sequence cursor a vlastní
commit. Enqueue používá druhé RPC/commit, pevný deadline 300 sekund, společnou
recipient obálku napříč tenanty, normalizované source vazby a databázové unique,
CHECK a composite FK pojistky. Jeden aktivní queue intent blokuje další enqueue;
collecting catch-up může dál přijímat nové příspěvky. Enqueue kvóta vrací obálku k původnímu abuse release time bez sekundového retry loopu. Unknown se nenahrazuje.

Jediný `admin_notification_digest` smí mít recipient scope s organization=NULL.
Používá původní queue/sender a samostatnou notification admission třídu ve
stávajícím abuse backendu. Výchozí recipient limit je 288/24 h a 2/min,
globální intent/send budget 1000/24 h, další preparation/backlog/payload meze
zůstávají ve stejném policy backendu. Aktivace vyžaduje čerstvě ověřenou provider
kapacitu a notification budget nejvýše 10 % její denní alokace.

Příprava a finální permit sdílejí context/fingerprint owner. Finální SQL statement
současně rozhodne o aktuálním obsahu a přepne attempt/message. Stará příprava se
vrací do stejného intentu bez spotřebovaného sendu; změna adresy jej zruší bez
náhradní zprávy. Tenantové reporty digest nevracejí. Self stav je ve stávajícím
panelu s globálním stopem, scope odběry a dostupnými kategoriemi.

Renderer odděluje organizace, akce, měny a přiřazení již přijatých peněz od nového
příjmu. Má limit 100 detailních příspěvků a 48 kB pro sekce HTML, přebytek ukazuje
jako změny s autorizovaným odkazem. Nepřikládá vstupenky, nepoužívá tenant sender,
engagement tracking ani tenant SES tag u recipient zprávy.

## Reuse/deletion ledger

| Artefakt | Výsledek |
|---|---|
| Nepodmíněný DTO ticket COUNT, prepared legacy count/context větev | Nahrazeny společným facts ownerem. |
| Duplicitní relevance CASE | Jeden owner, původní live/cached privacy adaptéry zachovány. |
| Emailový role/count/finance resolver, prepared cache a feed hook | Nevytvořeny. |
| `enqueue_bank_sync_health_alerts`, monitor caller | Odstraněny; `enqueue_email` navíc odmítá nový `BANK_SYNC_WARNING`. |
| `_shared/notificationCenterHealth.ts`, claim/complete RPC, center bank health table | Odstraněny; runtime installer a source/ACL inventory aktualizovány. |
| `bankSyncWarningEmail.ts`, legacy renderer/validátor, `notified_at` | Odstraněny za transakčním legacy drain gate; audit/prepared accepted obsah zachován. |
| Druhé bankovní počítání epizod | Nahrazeno skutečným doménovým incident UUID; nejednoznačné staré projekce uzavřeny jako baseline a invalidovány. |
| Povinné provozní e-maily | Bankovní správci konkrétního účtu podle canonical write policy; správci připojení brány podle společné unit-manager policy. Bez volitelných subscriptions a bez aktivace tenantů. Historické bankovní identity zůstávají baseline. |
| Platby | Bank/cash pairing a stávající provider effects/registry publikují uložené movement identities; reprice/refund/manual paid nevymýšlí příjem. |
| Queue, attempts, provider a původní mute preference | Zachováni vlastníci transportu a auditu. Mute řídí volitelná upozornění, povinné provozní e-maily nevypíná. |

## Následné zadání: povinné provozní problémy

- `bank_problem` dostává pouze aktuální administrátor dotčeného účtu podle stávající bankovní write policy (bank admin a správce propojeného spolku). Samotný čtenář objednávek ani správce organizace nestačí. Feed může zachovat bezpečný kontext pro čtenáře objednávek; to jim nedává právo na bankovní e-mail.
- `provider_problem` dostává pouze správce spolku příslušného připojení. `payment_provider_unit_manager_internal` je společná identitní policy i pro stávající příkazy Stripe. Demo omezení zůstává platné.
- Oba druhy jsou povinné. Server vrací `requiredKinds`, UI ukazuje „Vždy zapnuto“ a API odmítá jejich zapnutí i vypnutí. Globální stop volitelných souhrnů, scope subscriptions a mute je nevypnou. Automatický profil má volitelné e-maily stále vypnuté; první insert sdílí advisory fence se self-save. Smíšené volitelné kategorie mají třístavový checkbox.
- Stripe a Barion poskytují `notification_connection_health` přes existující registry. Čerpají ze svého autoritativního stavu a počítadel workeru; žádný další poller, přihlašovací údaje ani sender nevznikl. Potvrzené omezení/revokace Stripe a tři po sobě jdoucí transportní neúspěchy založí epizodu. Práh tří neúspěchů má jednoho vlastníka. Úspěšné ověření epizodu uzavře, nové selhání po recovery dostane nový UUID; změna důvodu nepřeposílá stejnou epizodu. Záměrné odpojení Stripe nebo vypnuté Barion připojení není porucha. Barion zůstává v dosavadním sandbox režimu.
- `provider_connection_notification_incidents` uchovává pouze identitu a lifecycle provozní epizody. Relevance, stávající prepared centrum a e-mail používají tuto autoritu; nepřepočítávají stav konektoru, finance ani vstupenky. Aktivní incident neexpiruje jako běžná aktivita. Příjemce se zachytí stávajícím capture ownerem a aktuální oprávnění se znovu ověří před send permitem.
- Vše jde do stejného recipient souhrnu, `email_messages` a jediného SES send gate. Okno 300 sekund, tenant aktivace, backpressure, suppression a provider pause zůstávají společné.

## Ověření

85 různých SQL testů prošlo v cílených batchech, včetně stávajícího centra,
queue/admission, finančních hranic a account deletion. Passing kontroly se
opakovaly jen po změně jejich vstupů nebo rozšíření konkrétního scénáře.

- Pět notifikačních concurrency případů se skutečnými PostgreSQL spojeními ověřují rollback
  collect, dva workery, enqueue crash/response loss, queue backpressure a jediný
  send permit. Globální diagnostická řádka používá SKIP LOCKED, aby se nestala
  skrytým blokujícím místem. Přidány jsou souběh prvního založení profilu a souběh založení provider incidentu včetně rollbacku; samostatně prošla stávající Barion runtime concurrency.
- Pět migration/upgrade případů ověřuje ochranu historických bytes, prerequisites,
  odmítnutí legacy produceru a unknown drain gate. Původní queue reconciliation
  s testovacím důkazem zachovává accepted audit.
- Source parity odpovídá aktuálním kanonickým definicím; assembler `--check`,
  source-owner inventory, deklarace definer ACL a dotčené Deno entrypointy prošly.
  Disposable upgrade ze současné baseline proběhl na samostatném portu 55492;
  následné úpravy definic byly aplikovány kanonickými soubory a ověřeny parity.
- Deno: 23 různých testů dispatcheru, health observeru, rendereru, queue klienta a
  jediného senderu. Transport je simulovaný; žádná skutečná SES zpráva neodešla.
- Flutter: 49 různých controller/widget případů v cílených batchech, poslední
  případ ověřuje také označení přiřazené platby a skupiny platebních změn.
  Testy běžely s `--concurrency=1` v koordinovaném jediném Flutter slotu.
  Dotčený Dart analyze je bez nálezů. Skutečný light-mode capture je uložen níže.

Přejímací důkazy: 30 objednávek ze tří akcí/dvou organizací a dva UUID se stejným
mailboxem; žádný enqueue před deadlinem; immutable deadline; cursor gaps/replay;
revokace zdroje A při zachování B; opt-out a změna adresy po přípravě; chybějící
adresa; 21 skutečných send permitů stejného recipienta při zachovaném ordinary
limitu; přímá porušení DB pojistek; stará aktivita po 24 h; aktivní bankovní
incident po 25 h a po odstranění všech source vazeb i journal retention; bankovní
projekce druhého tenantu až po prvním accepted intentu; finanční reassign/replay
/rollback; queue audit zachovaný po skutečném smazání disposable účtu.

Reuse důkaz používá přejmenování ticketové tabulky a zahození session plánů:
DTO, captured facts i email context fungují bez jejího lookupu. EXPLAIN nad
skutečným context statementem ověřuje materializované scopes/metadata/facts.
Renderer získává obsah jediným RPC a nepotřebuje otevřené centrum.

[Strojový receipt a SHA-256 zdrojů](evidence/admin-notification-delivery-2026-11-12/receipt.json),
[SQL centrum](evidence/admin-notification-delivery-2026-11-12/sql-center.txt),
[concurrency](evidence/admin-notification-delivery-2026-11-12/concurrency.txt),
[light capture nastavení](evidence/admin-notification-delivery-2026-11-12/email-settings-light.png).

## Neprovedené provozní kroky

Neproběhl commit/push, plné publikační CI mirror lanes, tenant overlay, produkční
schema/data migrace, skutečný legacy bank drain, ověření produkční identity vazby
napříč tenanty, změna produkčních limitů/odběrů, aktivace tenantů, Functions
restart, produkční Flutter build ani deploy. Tyto kroky potřebují samostatnou
autorizaci vybrané tenantové scope a původní exact-main release gates.

Před aktivací musí skutečný provider rozpočet projít existující policy a capacity
gate. Před kontrakcí musí být všechny legacy in-flight/unknown zprávy vypořádány
původním protokolem s důkazem. Provider exactly-once se neslibuje; ochrana se týká
idempotentního vytvoření intentu a zachovaného unknown protokolu. Pro diagnostiku
platí [cursor -> dispatch -> message -> attempt runbook](../operations/monitoring/admin-notification-delivery.md).


## Doplnění po otázce na jednu konstantu

Interval souhrnu má jediného autora v
`database/functions/notification_center/email_policy.sql`.
Collector, DB CHECK a settings údaj `windowSeconds` používají stejný owner;
popis v panelu jej lokalizuje bez vlastního hardcoded intervalu. Nový transakční
test změnil pouze owner na 600 sekund a ověřil změnu skutečné obálky, DB pojistky
i settings projekce. Po rollbacku zůstává interval 300 sekund. Pět cílených SQL
případů, tři concurrency případy, widget a analyze prošly. Jeden globální
`email_messages`/`process-email-queue` gate pro celou platformu je zachován.
