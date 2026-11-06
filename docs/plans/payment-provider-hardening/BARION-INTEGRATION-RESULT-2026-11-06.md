# Dokončení omezené Barion sandbox integrace - 2026-11-06

Barion má skutečný sandboxový `PaymentConnector`/`PaymentStore`, vlastní SQL
storage a explicitní registraci v SQL, Edge, Dart a JS. Reálný autentizovaný stav
Barionu prošel skutečným adaptérem, společným recovery enginem a SQL ownerem do
objednávky a vstupenky v disposable DB. Stripe regresní kontroly prošly.
Žádné produkční SQL, nasazení, aktivace, skutečné peníze, commit nebo push.

## Implementace a hranice

- `supabase/functions/_shared/barion/`: sandbox-only transport, ověřená vazba
  účtu/pokusu/platby, normalizace původní platby a externích refundů, adaptér,
  scoped persistence, callback a konfigurace. Žádný live host nebo automatický
  create/refund retry. Částky a měny jsou omezené na podporovaný plný checkout.
- `database/functions/eshop_barion/`: neveřejné connections/attempts/movements/
  capabilities/sources/observations, service-role RPC, immutable scope, fencing,
  jeden původní pohyb, konzistentní replay a provider projekce. Jeden callback
  jen trvale naplánuje autentizované čtení známého ID. Neznámý callback nesmí
  připojit cizí platbu ani vytvořit novou.
- Finanční důsledky vlastní výhradně
  `apply_provider_payment_effects_internal`. Adaptér nepřepisuje business
  rozhodování Stripe pro paid/storno/admission/email do nového adresáře.
  Schéma nevytváří bankovní transakce, platformní příjem nebo provizi.
- Ztracená odpověď Start zůstává unresolved. Uložený dispatch nikdy nespustí
  další Start; recovery bez známého ID nevyžaduje browser bearer ani nový
  source. Dřívější nevyřešený pokus není přeznačen na absenci. Inventář má
  samostatnou lhůtu a pozdní peníze neobnoví prodané místo.
- `CompletedAt` je čas dokončení původní platby. `TransactionTime` existuje již
  při přípravě. Pro admission se zlomky sekundy konzervativně zaokrouhlují
  nahoru. Refund a processing fee nejsou další zákaznické platby. Stav platby
  může zůstat Succeeded po částečném i plném refundu.
- Neznámé/review/reversal pohyby, pending refund a chybějící již potvrzený pohyb
  vytvářejí persistentní admission hold. Potvrzené peníze se nemažou a neověřený
  reversal/release automaticky neobnoví vstupenky. Chybějící attempt nesmí
  povolit ruční paid transition.
- Připojení je výhradně operátorská sandboxová konfigurace s explicitním
  allowlistem formulářů. Klíče nejsou v SQL ani klientovi. Runtime potřebuje
  explicitní sandbox konfiguraci; migrace nevytváří účet ani aktivaci. Veřejné
  prodeje a setup recipient discovery zůstávají unavailable. Aplikační zahájení
  refundu je unsupported; oddělený sandboxový operator probe má jednorázové
  durable refund intents a blokuje další příkazy při nejistém výsledku.

## Skutečné externí důkazy

Machine-readable [evidence](barion-integration-evidence.json) obsahuje redigované
provider observations, refund intents a výsledek skutečného common-engine/SQL
readbacku. Neobsahuje POSKey, payee email, bearer, checkout/callback URL ani
platební údaje zákazníka.

| Samostatný sandboxový případ | Výsledek |
|---|---|
| `23399c05-88e6-4e11-91a7-f128093614d0`, 1 CZK | Prepared -> Succeeded; callback a autentizované čtení; externí refund 0,50 CZK a následně celkem 1 CZK. Common engine/SQL: received=1, returned=1, objednávka i vstupenka storno. |
| `3ddad911-0dd4-45b8-8a1f-271a9a21c523`, 1 CZK | Zamítnutá veřejná testovací karta; API stále Prepared a žádné peníze. Úspěšná testovací karta poté ve stejném checkoutu; Succeeded a callback. Common engine/SQL: received=1, returned=0, objednávka i vstupenka paid. |
| `597fe855-892a-4199-8ae8-4122aace1542`, 1minutové okno | Skutečné Expired bez zadání karty. Payment Total=0, původní transaction Total=1 není přijatá platba. Common engine/SQL: received=0, objednávka expired, vstupenka storno. |
| Neplatný sandboxový POSKey, pouze čtení | Skutečné HTTP 401 / AuthenticationFailed; žádný finanční účinek. |

Původní samostatný Start `1f5b1e02-9a01-4eca-9bff-67377ddfe7bd` zůstává
unresolved bez uloženého statusu/body. Pozdější odpověď Draft jeho výsledek
nedokazuje. Schválený pokus `56026796-f5f9-4efd-83c9-bdae4db8f522` má vlastní
NotExistingCurrency receipt. Následné testy jsou výslovně nezávislé případy.

Pokus o druhý refund původní platby nejprve dostal
`400 TooLowBalanceToMakeRefund`, protože processing fee snížil sandboxový
zůstatek. Tentýž příkaz nebyl opakován. Samostatný decline/success test doplnil
testovací zůstatek a nový explicitní refund dokončil původní plný refund.
Historický odmítnutý intent zůstává konzervativně uložený; jeho klíč nebyl
recyklován. Neproběhlo dobití skutečnými penězi.

Po externím vytvoření checkoutů a práci v odděleném prohlížeči provedl
`barion_sandbox_apply.mjs` nové skutečné provider reads přes skutečný adaptér a
common engine nad syntetickými objednávkami. Lokální SQL transakce byly rollback;
žádné emaily nebyly odeslány. Tento důkaz není vydáván za produkční UI E2E nebo
provedený produkční ledger zápis. Timeout/late-observation a souběh jsou cílené
lokální scénáře; skutečná platba po Barion expiraci nebyla předstírána.

## Finální ověřování

Přesný HEAD, finální digesty a log hashes jsou v
[barion-integration-inputs.json](barion-integration-inputs.json).

- **97 Deno testů prošlo**, 0 failed, 0 skipped: Stripe a společný tok,
  protokol, common checkout/commit, refund, chybné identity/částky, konzervativní
  čas platby, neznámé/reversal stavy, callback hint a durable recovery.
  Zahrnutý SQL případ používá skutečnou disposable DB a normalizované skutečné
  Barion responses, včetně platby, partial/full refundu, stale lease, replay,
  ztracené create odpovědi, uvolnění inventáře a pozdního pozorování.
- **16 společných/Stripe SQL souborů prošlo**, fresh baseline + forward migrace
  prošly. Nová migrace je pouze navazující
  `20261106180000_barion_sandbox_connector.sql`; obě předchozí connector/hardening
  assemblery prošly beze změny historické migrace.
- **Populated upgrade prošel**: existující bankovní záloha, Stripe ekonomická
  fakta, historie, leases, events, capabilities, tickets a accepted email receipts
  zachovány. Hash porovnává všechny původní sloupce; nový nullable
  `barion_connection_id` je při porovnání vynechaný a na starých řádcích je null.
- **Skutečný dvouspojení concurrency test prošel**. Čekání druhého workeru bylo
  ověřeno v `pg_locks`, poté dostal busy; stale ingest byl odmítnut, callback
  replay nevytvořil další pohyb nebo paid účinek.
- **17 web/guard/coverage testů a 7 Dart core testů prošlo**; sandbox redirecty
  odmítají live Barion, duplicitní ID i cizí path. Stripe redirect policy zůstává.
  Deno check prošel. CI mirror contract: **6 testů prošlo** v izolovaném uv
  prostředí s PyYAML 6.0.3 (systémový Python PyYAML neměl).
- CI explicitně spouští Barion upgrade, concurrency, Deno SQL/adapter a web/guard
  testy; SQL se v této bráně nepřeskakuje kvůli chybějící proměnné.
  Coverage inventory: **50 production functions, 1 excluded, 119 discovered
  tests, 0 uncovered**. Širší předexistující Flutter architecture gate a jeho
  neklasifikované test roots nejsou tímto označené za zelené.

## Zbývající aktivační podmínky

Implementovaný a ověřený je omezený sandboxový rozsah. Produkční Barion,
marketplace/MoR oprávnění, úplný chargeback/refund-reversal release kontrakt a
E1/E2 pro provize zůstávají uzavřené. Úspěšný merchant sandbox toto neopravňuje
povolit. Tyto neověřené podmínky nejsou nahrazené test doublem ani novým defaultem.

POSKey a payee jsou zachované v šifrované lokální macOS Klíčence; iCloud sync není
potvrzený, login heslo nebylo zachyceno. Dočasné tunely/server i izolovaný browser
byly ukončené. Nesouvisející karty hlavního Chromu zůstaly beze změny. Disposable DB byla po ověření zastavena
bez backupu; ostatní projekty nebyly zastavovány.
