# Lokální implementace Wallet change queue

Zdroj: origin/main `a21a6f604781b98a7d20dd3a078b0bd20294a164`.
Worktree: `/Users/miakh/source/festapp-wallet-change-queue-20261113`.
Původní implementace proběhla bez publikace. Navazující zadání autorizovalo
commit a PR do main; produkční zásah zůstává neprovedený. PR #838 je oddělené.

## Kontrakt a odstranění

- `ticket_wallet_objects` drží pouze stabilní identity; šest starých scheduling
  sloupců a index `ticket_wallet_due` kontrakce odstraní po pause/drain guardu.
- `ticket_wallet_work` drží requested/captured/applied, lease, bounded retry,
  první dirty čas, budoucí časovou hranici, repair splatnost a scope cursor.
- Příkazy měnící sezení, produkty, scan/unused, platbu/refund, storno/delete,
  capability, akci/layout a značku zařazují práci v téže transakci. Přesná mapa
  a zámky jsou v autoritativním plánu. Scope změna nevytváří tisíce řádků
  v administrátorské transakci; rozpad používá durable verzovaný cursor.
- Class i object mají samostatného jediného lease ownera. Google object executor
  třídu nezapisuje. První vydání dokončí approved class před object claimem.
- Starý tříminutový full upsert je odstraněn. Jednou denně stejný owner porovná
  vzdálené spravované hodnoty a zapisuje skutečný drift. Opožděný cizí zápis
  nelze atomicky spojit s SQL, oprava je eventual.
- Starý finish overload se třemi argumenty je odstraněn; nový canonical finish
  přijímá volitelný bezpečný error code. Nezůstává alias. Kvótové čekání se
  odlišuje od provider chyby a nezvyšuje počet provider failures.
- Apple adaptér, APNs ani obecný broker nevznikly. Provider stav má oddělený klíč;
  dnes je povoleno pouze Google. QR, capability a admission vlastníci zůstávají.

## Ověření

Finální `seat-checkout` prošel všemi 11 canonical units, včetně notifikací,
browseru, SQL producer fixtures, 5/5 souběhů a 1/1 upgradu. Receipt
`20261113T012414-3ebcdf7db4eb` má `complete=true`, `inputsUnchanged=true`.
`ticket-preview-and-delivery` prošla všemi čtyřmi units v dřívějším receipt
`20261113T010515-531bd4f5192d`, včetně 19 Wallet Edge testů. Tento kombinovaný
receipt je celkově incomplete a má `inputsUnchanged=false`, protože během jeho
běhu vznikly opravy SQL/checkeru. Deklarované ticket lane inputs se potom
nezměnily, proto se její passing kontroly neopakovaly; opakovala se postižená
seat lane. Přesné cesty, hashe receipts a statuses obsahuje
[tento záznam](ticket-wallet-queue-validation-2026-11-13.json).

`git diff --check` prošel. Historické migrace z 20261110/20261112 jsou
nezměněné. Není žádný nevyřešený lokální testový bloker; výkonový limit pro
hromadný burst popsaný níže zůstává skutečným omezením.

Transportní testy pokrývají 409, throttling, 5xx, timeout po přijetí zápisu,
opakování stejné identity, opožděný starý zápis, oddělení class/object a
read-only repair zdravého stavu. SQL ověřuje captured vs requested, rollback,
stale ack, expiry, pause, restart fanoutu a převzetí starých registrací bez
vymyšleného applied version. Souběžné testy nepoužívají produkční fixtures.

## Kapacita

Viz sousední JSON receipts. Skutečný SQL fanout 10 000 registrací po dávkách
100 trval 11,212 s, p95 dávky 226 ms, maximum 340 ms. Enqueue burstu trval
325 ms. Pro 1 000 registrací: fanout 256 ms, burst 40 ms.

Řízený Google transport s 50 ms odpovědí a SQL kvótou 8 requestů/s dosahuje
asi 4 změn/s. P95 / max burstu 1 000 je 238,55 / 251,05 s; pro 10 000 je
2376,05 / 2501,05 s. Jeden trvale chybný pass je v simulaci zahrnutý.
To jsou optimistické provider bounds, nikoli produkční SLA; scheduler gaps,
SQL, cold OAuth a schvalování třídy mohou přidat další čas. Cíl p95 60 s pro
hromadný burst a max 5 min pro 10 000 se v této kvótě nesplní.

## Konkrétní rollout - neprovedený

1. Samostatně autorizovat scope vstupenky.online / org 3; ověřit canonical
   backend přes project skill a aktuální exact-main CI/release gates. Org 25
   ani jiný tenant se neaktivuje. PR #838 neintegrovat bez vlastní autorizace.
2. Atomicky aplikovat a zapsat ledger expanze
   `20261113090000_ticket_wallet_queue_expand.sql`. Starý claim dostane stejný
   pause fence; staré scheduling sloupce zatím zůstanou. Nový worker nezapínat.
3. `pause_ticket_wallet(3,true)`; vyčkat starých lease. Kontrakční SQL odmítne
   aktivní legacy lease i libovolnou nepozastavenou aktivovanou integraci.
   Pod pause aplikovat a zapsat ledger
   `20261113090100_ticket_wallet_queue_contract.sql` v jediné transakci.
4. Pod pause instalovat canonical Functions bundle a provést authenticated
   probes. Sdílený restart vyžaduje navíc pause/drain e-mailů a obnovení jejich
   přesné předchozí pause hodnoty. Žádné recreate Compose.
5. Opakovat `maintain_ticket_wallet(100)` pod pause, dokud všechny existující
   object i class identity mají práci. Nové applied zůstává 0. Ověřit identities,
   bodies, ACL, retired overload a nepřítomnost starých sloupců.
6. Scheduler běží v control-plane `postgres` (doloženo existujícím instalačním
   runbookem). Tam ověřit skutečný jobname, username, database a command.
   Připravený `automation/ticket-wallet/update-control-plane-scheduler.sql`
   vyžaduje explicitní runtime_database a scheduler_owner, odmítá více ownerů
   a mění pouze frekvenci jediného `festapp_google_ticket_wallet` na 10 s.
   Zachovává command a active stav. Kontrakce odstraní případný starý dormant runtime-DB job; nový se neinstaluje.
7. Obnovit org 3 a sledovat health: backlog, oldestDirty, versionGap, leased,
   retry, persistentErrors, quotaWait, quotaWaitUntil, lastSuccess, scope cursor.
   Reálný test přesazení vyžaduje zvlášť schválenou testovací objednávku.
   Žádné tisíce testovacích Google zápisů. Web release není pro tuto změnu nutný.

Před kontrakcí je rollback možný pod pause na starý kompatibilní bundle při
zachování nové práce. Po kontrakci jen dopředná oprava nového ownera pod pause;
starý full-poll writer se neobnovuje a identity/capabilities se nerotují.
Live scheduler readback, SQL migrace, Functions install/restart, canary,
main publication a produkční ověření zůstávají neprovedené.


## Publikace na žádost uživatele

Navazující zadání autorizovalo publikaci změny. Před publikací proběhl fetch
main, kontrola čtyř nových commitů a čistý rebase na
`ca626067fd56e1bdfd0354c08fe5c73483b98516`. Branch protection vyžaduje jednu
schválenou revizi, proto se změna publikuje přes PR bez admin bypassu.

Po rebase prošlo 6 skutečných SQL fixtures (Wallet producenty/protokol,
scanner izolace, provider efekty a canonical parity), 7 testů souběhů a upgradu
(včetně nového scanner ownership cutover), 11 source/ACL testů a 6 runtime unit
testů. Jeden source test vyžadující DB kontext a pět opt-in runtime integration
testů byly v samostatných unit bězích vynechány; skutečná DB validace běžela
samostatně. Assembler kontroly Wallet, scanneru, notifikací a generovaný canonical
contract také prošly. Dřívější kompletní mirror výsledky jsou uvedeny výše.
Žádná produkční migrace, restart, scheduler změna ani deploy nebyly provedeny.
