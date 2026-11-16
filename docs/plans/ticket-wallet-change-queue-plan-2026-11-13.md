# Spolehlivá propagace změn vstupenek do peněženek

Datum: 2026-11-13. Stav: lokálně dokončeno a ověřeno; bez publikace či produkční aplikace.
Ověřování: standard (souběhy, autorizace, migrace a sdílené chování).
Tento dokument nahrazuje pracovní návrh `ticket-wallet-change-queue-2026-11-13.md`.
Neuděluje souhlas k publikaci, obcházení revize ani produkčním změnám.

## Výsledek a rozsah

Přesazení zákazníka nebo jiná relevantní změna vstupenky spolehlivě založí
aktualizaci již vydané Google Wallet karty. Po restartu, výpadku poskytovatele
nebo souběžných změnách nezůstane novější změna označená za vyřízenou starší
prací. Oprávnění ke vstupu zůstává ve stávající databázové a skenovací doméně.

Rozsah: databázová fronta změn, kanonické producenty, worker, opravná kontrola,
metriky, testy a připravený postup převzetí existujících Google registrací.
Principy mají umožnit pozdější Apple implementaci s odděleným zpracováním.
Nyní nepřidávat Apple kód, tlačítka, certifikáty, APNs, registrace ani další tenanty.
Neměnit e-mailovou frontu, QR identitu, admission, platby ani obchodní pravidla
sezení. Nevytvářet univerzální broker pro libovolné úlohy.

Samostatně zbývá publikovat a nasadit automatické pokračování do Googlu z PR
[#838](https://github.com/festappnet/festapp/pull/838). Frontu lze implementovat
nezávisle; PR neamendovat a neznehodnotit jeho schválené CI bez skutečné potřeby.

## Ověřený výchozí stav

Zdrojový bod průzkumu je canonical main
`a21a6f604781b98a7d20dd3a078b0bd20294a164`. Dne 2026-11-13 při přípravě:

| Fakt | Důkaz | Důsledek |
|---|---|---|
| Fronta už je trvalá, nikoli v paměti | `database/functions/ticket_wallet/schema.sql`, tabulka `eshop.ticket_wallet_objects`; `sync.sql`, `claim_ticket_wallet`, `finish_ticket_wallet` | Zachovat identity, retry, lease a rozpracovanou práci. |
| Zdravé objekty se kontrolují každé 3 minuty; worker má výchozí limit 25 a deadline 45 s | `sync.sql`, `supabase/functions/_shared/ticketWallet.ts::reconcileTicketWallet` | Není to změnová fronta ani důkaz kapacity. |
| Aktualizace čte skutečný ticket, objednávku, sezení a platební projekci | `projection.sql::ticket_wallet_projection_internal`, `eshop/get_tickets_with_details.sql` | Nepřidávat paralelní obchodní stav nebo kopii oprávnění. |
| Vydání i periodická synchronizace používají stejný synchronizační owner | `ticketWallet.ts::issueTicketWallet/synchronizeWallet`, `googleWallet.ts::synchronize` | Zachovat jednu cestu pro zápis Google objektu. |
| Každá Google synchronizace dnes zapisuje i sdílenou třídu akce | `googleWallet.ts::walletDocuments/synchronize` | Serializace jen podle ticketu nestačí pro sdílenou třídu. |
| E-mailová fronta řeší jinou jednotku práce | `database/functions/emails/email_queue.sql::claim_email/recover_email_leases` | Převzít principy spolehlivosti, nikoli její tabulky či stavy doručení. |
| PR #838 je OPEN, head `e21523c84f2b69da129fa337c2868b5046aa8b79`, všech 8 CI zelených | GitHub readback při přípravě; lokální receipt `20261113T002122-13178634e7d9` | Chybí povinná revize nebo nová explicitní výjimka. Souhlas pro #836 neplatí pro #838. |

Zjištěný regionální prod tip byl `0855cfdd24008a6255cc70faa5325738266a7a90`,
verze `0.20.596+1112`, base main `279281560848ba0a0dad35349f2f52a7e785c07c`.
Souběžně připravované vydání notifikací může tyto údaje změnit. Před exekucí
obnovit stav; nepoužívat zde uvedenou verzi pro budoucí hardcoded overlay.
Google je aktivovaný pouze pro vstupenky.online / organizaci 3. Globální
Festapp Tickets / organizace 25 má branding, ale není tím aktivovaný Wallet.

## Cílový kontrakt a invarianty

1. **Změna a požadavek jsou jedna transakce.** Kanonický příkaz změní obchodní
   stav a označí dotčenou Wallet práci. Rollback vrátí oboje. HTTP volání mimo DB
   nastává po commitu; ztracené probuzení opraví scheduler. Bez aplikačních triggerů.
2. **Jedna aktuální práce na prostředek a poskytovatele.** Nová trvalá tabulka
   `eshop.ticket_wallet_work` vlastní plánování a verze, existující
   `ticket_wallet_objects` zůstane registrem stabilních externích identit.
   Klíč práce rozlišuje poskytovatele a prostředek (ticket nebo sdílená akce).
   V první implementaci je povolen pouze skutečně podporovaný Google.
3. **Verze a souběh.** Práce má požadovanou, převzatou a potvrzenou verzi,
   lease, splatnost, první nevyřízenou změnu, počet pokusů a bezpečnou chybu.
   Enqueue zvýší požadovanou verzi; nesmaže platný lease. Dokončení potvrdí
   nejvýše převzatou verzi a správný lease. Novější požadavek zůstane připravený.
   Změny lze sloučit na poslední stav, nemusí se přehrávat každé přesazení.
4. **Google objekt i třída mají jediného zapisovatele.** Vydání a background sync
   procházejí stejným claim/lease ownerem. Sdílená třída má vlastní serializaci
   podle existujícího class ID; nevytvářet alternativní zápis třídy z každého
   ticket workeru. První vydání připraví schválenou třídu před uložením objektu.
5. **Žádná nová vstupenka.** Zachovat issuer, environment, class/object ID, QR,
   capability generaci, audit a vazbu na skutečný tenant. Nesynchronizovat
   neuložené vstupenky do nových Google objektů jen proto, že se změnila akce.
   Po smazání ticketu zachovat identitu nutnou ke vzdálenému zneplatnění.
6. **Bez změny autorizace.** Producent zůstává za existujícím oprávněním
   doménového příkazu. Klient nedostane přímý enqueue/claim přístup ani možnost
   zadat cizí organization, externí ID či hotovou projekci. Interní SQL pomocníci
   nemají klientské granty; používat existující autorizovaný definer owner,
   nikoli rozšířit oprávnění invoker RPC kvůli pohodlnému volání helperu.
   Nastavení `wallet_enabled` nadále ovládá budoucí nabídku; jeho vypnutí samo
   nerevokuje již vydané karty. Revokace/reissue zůstávají explicitní operace.
7. **Oddělené chyby a férovost.** Retry/backoff a kvóty zůstávají omezené pro
   issuera/poskytovatele. Chybná karta nesmí blokovat ostatní. Priorita invalidace
   nesmí vyhladovět běžné změny ani jiného tenanta. Všechny fronty mají pozorovatelné stáří.
8. **Opravná kontrola zůstává.** Pravidelná pomalejší kontrola úplnosti/projekce
   a vzdáleného driftu používá stejnou frontu a zapisovatele. Nejde o druhý worker,
   který by souběžně bez fronty znovu zapisoval všechny Google objekty.
9. **Časové změny jsou také práce.** Začátek/konec akce, expirace a termíny
   ovlivňující admission potřebují naplánovaný budoucí požadavek i bez editace.
   Při změně termínu přesunout odpovídající splatnost, nečekat jen na ruční enqueue.

Vzdálený zápis a SQL nelze potvrdit atomicky. Opakování používá stejnou identitu;
po timeoutu a opožděném zápisu musí opravná kontrola obnovit nejnovější stav.
Neslibovat exactly-once Google I/O ani okamžitou změnu na offline telefonu.

## Změny, které musí mít producenta

| Oblast | Ověřený vstup pro trasování |
|---|---|
| Přesazení obou zákazníků a produkt | `eshop/swap_spot_tickets.sql::apply_blueprint_seat_pair_locked_internal`, `_swap_spots_update_ticket`; `blueprint/apply_seat_swap_internal.sql`; `eshop_orders/update_ticket_products_ws.sql::update_ticket_products_wsv2` |
| Přejmenování stolu/místa, změna plánku | `blueprint/save.sql::save_blueprint_layout_impl_internal`, vazby v `eshop.blueprint_seat_bindings`, `order_spot_metadata_internal` |
| Použití a návrat do nepoužitého stavu | `scanning/admission.sql::scanner_admit_ticket_internal` včetně offline sync; `eshop_orders/update_ticket_to_unused_ws.sql` |
| Platba, refundace, storno a smazání | `mark_order_and_tickets_paid_internal_v1`, `reconcile_order_payment_internal_v1`, `internal_storno_tickets_221`, `delete_order_internal_v1`; trasovat i současné payment provider vlastníky admission |
| Podpůrná revokace/reissue | `ticket_wallet/capabilities.sql::manage_ticket_wallet`, příprava nové capability |
| Akce, čas, místo, vzhled, produkty, značka | `others/update_occasion.sql::update_occasion_internal_v1`, `occasion_setup/appearance.sql`, současné save vlastníky produktů/organizací a ticket layoutu |

Tabulka je začátek konkrétního writer inventáře, nikoli tvrzení, že každý uvedený
soubor je samostatný producer. Ve vlně 0 přes scoped `rg`, canonical operation
registry a callery najít nejnižší společný oprávněný writer pro každou změnu.
Zahrnout mazání vazeb, rezervované/online platby a sdílená metadata; obyčejný
`UPDATE eshop.tickets` neodhalí změnu názvu stolu uloženého v blueprint JSON.
Výsledek zapsat do tohoto dokumentu jako konkrétní producer -> enqueue -> test.

Hromadná změna akce/třídy/organizace uloží v transakci jeden požadavek scope.
Rozpad na existující registrace musí být trvalý, dávkovaný, restartovatelný
a verzovaný. Novější scope změnu během rozpracovaného rozpadu nesmí dokončení
starého cursoru smazat. Nová registrace vždy sama zařadí počáteční synchronizaci.

## Rozhodnutí, předpoklady a skutečné blokery

- Rozhodnutí: vlastní Wallet fronta s principy e-mailové queue; žádné Wallet řádky
  v `email_messages`, žádná závislost na úspěchu e-mailu při pozdějším přesazení.
- Rozhodnutí: sdílet doménovou projekci a požadovanou verzi; externí stav, chyby
  a potvrzení držet odděleně pro poskytovatele. Nyní implementovat jen Google.
- Apple do budoucna potřebuje aktualizační webovou službu, registrace zařízení,
  verzi podepsaného passu a APNs upozornění. APNs přijetí nepotvrzuje stažení
  nebo zobrazení na telefonu. Zdroj: [oficiální Apple protokol](https://developer.apple.com/documentation/walletpasses/adding-a-web-service-to-update-passes).
- Předpoklad: existující Google identity jsou jedinečné a dostatečně zachované.
  Ověřit katalogem a disposable migračními fixtures; produkční readback jen při
  oprávněném preflightu. Při neshodě nejprve zdokumentovat opravu, neměnit ID suffixy.
- Předpoklad: registry má úplný writer inventář. Ověřit závislosti všech polí
  výsledné projekce, nejen ticket tabulku. Chybějící owner znamená práci vlny 0.
- Bloker pro nasazení: schválené zdroje, exact-main 8/8 CI, oprávněný rollout,
  koordinace souběžného releasu a kapacitní důkaz. Exekuční prompt autorizoval lokální implementaci a ověření.
- Bloker pro PR #838: revize main nebo explicitní výjimka právě pro #838.
  Připravený kód a CI nejsou produkční nasazení. Nepokládat souhlas s plánem za výjimku.

## Implementační vlny

### 0. Uzavřít inventář a pořadí zámků

Cíl: před změnou kontraktu mít úplné producenty a žádnou inverzi zámků.
Obnovit main/prod/PR stav v čistém worktree; root workspace obsahuje cizí změny.
Doplnit writer mapu, scope fanout a závislosti třídy/objektu. Zvlášť prověřit
ticket -> capability -> work proti současnému work -> refresh capability v claimu.
Claim drží pouze krátké frontové zámky; síťové I/O nikdy DB transakci.
Pokud jeden požadavek potřebuje třídu i objekt nebo více ticketů, všechny cesty
musí používat stejný deterministický pořádek prostředků; nečekat na třídní lease
uvnitř transakce držící ticket/domain zámek.
Projekci číst po claimu bez nových doménových write zámků. Případné mutující
obnovení expirace přesunout do explicitního owneru se stejným pořadím zámků.
Neměnit veřejný capability model kvůli této úpravě.

Validace: focused zdrojová mapa a plán souběhových testů; během plánování testy
nespouštět. Výstup: konkrétní vlastníci všech polí projekce, lock order a staging
SQL/Functions změn jsou zaznamenané, bez nevyřešeného rozhodnutí ohrožujícího data.

### 1. Aditivní fronta, verze a provozní pozastavení

Cíl: restartovatelná práce bez přerušení stávajících identit.
Přidat canonical SQL v `database/functions/ticket_wallet/`: schéma práce,
scope fanout, enqueue, claim/ack/retry a service-only pause/resume pro zvolený
tenant. Pause musí bránit novému claimu jak z endpointu vydání, tak z workeru;
rozpracované lease lze bezpečně dokončit a nové změny se dál evidují.
Výchozí stav expanze zachová dosavadní provoz; nový worker se ještě nepouští.

Vytvořit novou forward migraci a assembler/manifest; staré migrace z 20261110
a 20261112 neměnit. Doplnit `automation/migration-forward-owners.json`, parity,
ACL/RLS a source contracts podle skutečně dotčených vlastníků. Případný hash
ticket-layout write contractu obnovit existujícím generátorem, pokud se jeho
evidované zdroje změnily. Neobcházet registry úpravou samotného očekávaného hashe.

Validace: disposable SQL testy pro enqueue rollback, deduplikaci, captured vs
requested verzi, lease expiry, stale ack, neoprávněný přístup a scope. Výstup:
restart ani dvojí claim neztratí novější práci, klient nemůže tvořit cizí práci.

### 2. Připojit všechny skutečné producenty

Cíl: změna zařadí práci atomicky a bez Google volání.
Připojit helper na zjištěné společné writery. Přesazení označí obě dotčené karty;
storno, smazání a platební invalidace zachovají vzdálenou identitu pro invalidaci.
Scope změny používají trvalý fanout, nikoli neomezenou smyčku přes všechny karty
v transakci administrátora. Neznačit běžný read jako obchodní změnu.

Validace: SQL integrační testy přes reálné příkazové funkce z writer mapy.
Pro každou kategorii změny doložit požadovanou verzi, tenant scope a rollback.
Výstup: mapování producer -> enqueue -> test je úplné; nezůstává ruční cesta,
která funguje pouze díky periodickému porovnání.

### 3. Převést jediného Google zapisovatele

Cíl: vydání i aktualizace používají stejnou frontu a nevytvářejí souběžné třídy.
Upravit `ticketWallet.ts`, `googleWallet.ts`, `sync-ticket-wallet/index.ts`
a SQL owner kontrakty. Rozdělit synchronizaci sdílené třídy a ticket objektu
za odpovídající lease, při vydání vyřešit závislost na schválené třídě.
Neměnit tvar veřejné email capability ani důvěřovat klientské projekci.
Vrátit srozumitelný retry při provozní pause; nehlásit úspěšné přidání.

Pozdější změna po claimu může vyvolat další běh i když worker už načetl novější
projekci; bezpečné opakování je přijatelné, předčasné potvrzení novější verze ne.
Retry přijetí Google není potvrzení zobrazení na telefonu.

Validace: Deno testy přes skutečný executor s řízenými transportními odpověďmi:
timeout po úspěšném zápisu, opožděný zápis, 409, throttling, souběžný save/sync,
dvě karty jedné třídy a změna stolu během sync. Výstup: všechny externí zápisy
mají právě jednoho claim ownera; starší práce nemůže potvrdit novější požadavek.

### 4. Převzetí registrací, opravná kontrola a odstranění staré cesty

Cíl: pouze jedna fronta a měřitelné zotavení.
Idempotentně převést každou existující registraci do nové práce, včetně failed,
inactive, deleted a objektů s nejasným výsledkem posledního pokusu. Nevymyslet
si potvrzenou verzi pro neověřený stav. Přidat scheduler pro časové hranice a
pomalejší opravnou kontrolu; obojí jen zařazuje práci stejného ownera.
Naplánovat backfill tak, aby nedržel dlouhé zámky ani nezpůsobil jednorázový
neomezený nápor do Google. Stávající scheduler skutečně může běžet v control-plane
DB, nikoli runtime DB; identifikovat a změnit jeho skutečnou registraci.

Metriky zahrnou dirty backlog, nejstarší čekající změnu, rozdíl requested/applied,
lease, retry, quota wait, chyby, poslední úspěch a scope fanout cursor.
Rozlišit pending od permanentní chyby; žádné tiché zahození práce či nekonečný
hot loop. Opravná kontrola nesmí každých pár minut bezdůvodně přepisovat všechny karty.

Validace: disposable upgrade nad starým schématem s identity/lease fixtures,
opakovaný backfill, změna během fanout, restart, časová expirace bez editace,
absence starého přímého zapisovatele. Výstup: všechny registrace dohledatelné
v nové práci, staré plánování odstraněné podle ledgeru níže.

### 5. Kapacita, integrace a předání k samostatnému rolloutu

Cíl: doložené chování a provozní limit místo slibu neurčité rychlosti.
Změřit alespoň 1 000 a 10 000 existujících registrací, velkou scope změnu,
burst invalidací i jeden trvale chybný pass. Externí Google nahradit řízeným
transportem, který respektuje skutečné počty požadavků, kvótu a latence.
Nevolat placené/external API tisíckrát a nevytvářet produkční testovací karty.
Zaznamenat throughput, p95 a maximum čekání; oddělit simulaci od reálného důkazu.
Navržený cíl je p95 přijetí individuální změny poskytovatelem do 60 s a nejstarší
zdravá práce do 5 min v doloženém objemu. Pokud se nevejde do kvóty, upravit dávky/
frekvenci nebo otevřeně uvést dosažitelný limit; nevytvářet falešnou garanci.

Spustit postižené canonical CI mirror lanes podle současného selection/DAG:
`bash automation/test_ci.sh seat-checkout ticket-preview-and-delivery`,
případně `web-startup` pouze pokud se mění web nebo se integruje PR #838.
Názvy před použitím potvrdit v `automation/ci/checks.json`; runner může rozšířit
závislosti. Pro vývoj používat užší SQL a Deno seam; celé passing lanes neopakovat
bez změny jejich vstupů. Flutter pouze jeden task, testy `--concurrency=1`.

Výstup: cílový kontrakt, migrační postup, odstranění a měření jsou doložené;
lokální implementace hotová, produkční kroky výslovně označené za neprovedené.

## Ledger odstranění a záměrného zachování

| Artefakt | Konečný stav a důkaz |
|---|---|
| `ticket_wallet_objects` | Zachovat existující identitní registry; scheduling/lease/retry sloupce odstranit kontrakční migrací po převzetí. Nezahodit object/class IDs. |
| Staré `claim_ticket_wallet` / `finish_ticket_wallet` chování | Převést všechny callery na nový canonical kontrakt; staré overloady/helpery bez callerů odstranit. Žádné permanentní V1/V2 aliasy. |
| Bezpodmínečné tříminutové full Google upserty | Odstranit. Pomalejší opravná kontrola úmyslně zůstává, ale používá stejný enqueue/claim a umí prokázat drift. |
| Zápis sdílené třídy z každé ticket sync | Odstranit; test souběhu různých ticketů téže akce prokazuje jediného class ownera. |
| Původní scheduler registrace | Upravit skutečný job na cílový worker; žádný druhý job zapisující starým kontraktem. Zdokumentovat control-plane/runtime umístění. |
| Staré testy/dokumentace | Nahradit očekávání full polling a pouze periodické propagace; původní plán 2026-11-10 ponechat jako historický se zřetelným odkazem na tento nástupnický plán. |
| Migrace z 20261110/20261112 | Historicky neměnné; nová expanze a kontrakce samostatnými forward migracemi. |
| `email_messages`, QR/admission a capability | Záměrně zachovat vlastníky a veřejné kontrakty; žádné jejich náhrady v rámci této práce. |
| Apple adaptér a obecný job broker | Nyní nevytvářet. Budoucí poskytovatel má samostatná potvrzení/transport nad stejnými doménovými požadavky. |

## Rollout a rollback - až po samostatném oprávnění

1. Koordinovat jediného runtime/prod ownera. Obnovit branch a backend assertions
   podle project skillu `festapp-backend-access`; nevolit DB z legacy `.env.local`.
   Publikace vyžaduje souhlas a branch pravidla. PR #838 je samostatná hotová větev;
   při jeho dřívějším merge převzít aktuální canonical main, neduplikovat opravu.
2. Aplikovat kompatibilní expanzi včetně service-only pause guardu do starého
   claim ownera. Starý worker zatím používá staré scheduling sloupce, nové enqueue
   ukládá práci; nový externí writer ještě neběží. To je ohraničené migrační okno.
3. Pozastavit nové Wallet claimy pro vybraný tenant a nechat doběhnout existující
   lease. Pod pause provést finální backfill a atomický přechod kontraktů. Pokud
   API/SQL verze nelze v tomto pořadí bezpečně provozovat, zastavit rollout a opravit
   staging, nikoli ponechat dva zapisovatele nebo přeskočit drain.
4. Pro změnu Functions použít canonical bundle/install/restart existujícího
   containeru. Sdílený restart navíc vyžaduje pause/drain e-mailů, authenticated
   worker probe a až pak obnovu předchozí email pause hodnoty. Nerecreate Compose.
   SQL a migration ledger zapsat atomicky; nezávisle ověřit hash/bodies/ACL.
5. S novým bundlem ověřit autentizované queue/Wallet probes pod pause, odstranit
   staré scheduling sloupce/callery až po potvrzení jejich nepoužívání. Potom
   povolit cílový worker, zkontrolovat backlog, nejstarší změnu a nové verze.
   Řízený test přesazení pouze na výslovně schválené testovací objednávce;
   existující canary bez sezení sám nedokazuje aktualizaci stolu.
6. Web vydávat jen pokud obsahuje PR #838 nebo jinou skutečnou web změnu. Pouze
   `prod/festapptickets`, current prod ancestry, exact `baseMainSha` 8/8 gate,
   main-owned drift a lokální `automation/deploy_direct.sh`; použít existující
   chráněný release manifest. Žádný global build či aktivace org 25.

Před kontrakcí lze pod pause vrátit kompatibilní bundle bez odstranění nové
nevyřízené práce. Po kontrakci neobnovovat starý full-poll writer jako fallback;
pod pause opravit nový owner dopředně. Nikdy nerotovat identity ani capability
kvůli rollbacku fronty. Nezavřít incident s trvale pozastavenými e-maily.

## Definice dokončení a zbytkové limity

- Všechny kategorie změn mají kanonického producenta a integrační test přes něj.
- Novější změna během synchronizace, scope fanout nebo retry se neztratí.
- Existující registrace a invalidace přežijí migraci, restart a timeout.
- Vydání i background sync mají stejného jediného zapisovatele pro class/object.
- Staré scheduling kontrakty, sloupce, přímé zápisy a druhé joby jsou odstraněné;
  záměrně zachované registry a opravná kontrola mají popsaný účel.
- Měření uvádí dosažitelný objem a zpoždění; healthy idle neprohlašuje výkonový test.
- Implementace neaktivovala Apple ani další tenanty a nezměnila vstupní oprávnění.
- Handoff jasně rozliší lokálně hotové, publikované a skutečně produkčně ověřené.

Zbytkové limity: offline telefon může držet staré údaje, poskytovatel může mít
výpadek a cizí API nelze atomicky spojit s SQL. Zde navržená fronta tyto hranice
nezruší; zajistí dohledatelnou, obnovitelnou a měřitelnou propagaci.


## Exekuční inventář (2026-11-13)

Čistý worktree: `festapp-wallet-change-queue-20261113`, zdroj origin/main
`a21a6f604781b98a7d20dd3a078b0bd20294a164`. PR #838 je podle
`gh pr view 838` stále OPEN, head `e21523c84f2b69da129fa337c2868b5046aa8b79`.
Lokální větev main je jiná než authoritative origin/main; implementace vychází
z origin/main. Žádná část #838 se nekopíruje.

| Skutečný producer | Enqueue | Integrační důkaz |
|---|---|---|
| `apply_blueprint_seat_pair_locked_internal` (obě strany aggregate swapu) | ticket přes uložené OPT | swap + product command fixture |
| `update_ticket_products_wsv2` | ticket po přepočtu | product edit fixture |
| `save_blueprint_layout_impl_internal` | occasion scope | rename blueprint fixture |
| `scanner_admit_ticket_internal`, `update_ticket_to_unused_ws` | ticket | scan/unused fixture |
| `mark_order_and_tickets_paid_internal_v1`, `reconcile_order_payment_internal_v1` | order registrations | paid/refund fixture |
| `apply_provider_payment_effects_internal` | order registrations | provider dispute fixture |
| `internal_storno_tickets_221`, `delete_order_internal_v1` | ticket IDs před ztrátou vazeb | storno/delete fixture |
| `manage_ticket_wallet`, `prepare_ticket_wallet` při změně capability | ticket | revoke/reissue fixture |
| `update_occasion_internal_v1`, layout-only větev `save_occasion_domain_command_internal_v1` | occasion scope | occasion/layout fixture |
| `update_product_internal_v1` | occasion scope | product title fixture |
| `update_organization_admin` | organization scope | branding fixture |

`occasion_setup/appearance.sql` je čistý normalizátor, nikoli writer.
Finalizace vytváří novou akci bez existujících registrací; první registrace
vždy založí class i object práci. Planned product price/visibility neovlivňují
žádné pole Wallet projekce. QR symbol ani admission se zde nepřepisují.

Pořadí: existující doménové zámky -> ticket/capability -> Wallet work.
Enqueue více ticketů používá vzestupné ticket ID. Scope enqueue nezamyká
jednotlivé karty. Fanout drží jen scope work a zařazuje ticket work ve vzestupném
ID; producent jednotlivé karty nikdy nezamyká scope. Claim zamyká pouze work;
projekce se čte až po převzetí, bez mutujícího refresh capability. Refresh termu
patří před ticket work ve fanoutu a při explicitním resolve/prepare. Class
lease se nikdy nečeká pod ticket/domain zámkem; endpoint nejprve dokončí class
claim a až v další transakci přebírá object. Síťové I/O je mimo SQL transakce.


Doplnění inventáře: `set_ticket_seat_assignments` je další skutečný writer
umístění již prodaných admission items. Zařazuje dotčené ticket IDs po finální
alokaci; `blueprint/seating_assignment_test.sql` ověřuje enqueue při přiřazení
i odebrání a absenci druhého enqueue při receipt replay. `delete_occasion_internal_v1`
vytvoří durable occasion scope ještě před smazáním akce. Přechod paid -> sent
nemění žádné pole Wallet projekce (oba stavy mají stejnou admission projekci).

Pořadí claimu je work -> sdílený tenant advisory fence. Pause používá
výhradní stejný fence -> integration. Claim po získání fence znovu ověří pause.
Síť se nespouští pod žádným zámkem. Kvótová rezervace drží work -> issuer advisory
-> integration; claim integrační řádek nezapisuje. Férovost bere poslední
`claimed_at` z work řádků tenanta, nikoli ze sdíleného integračního writeru.


Aktuální canonical DAG potvrzuje obě požadované lanes. Finální
`seat-checkout` prošel 11/11 units na nezměněných vstupech; ticket lane prošla
4/4 units v předchozím kombinovaném běhu a její pokryté vstupy se po něm
nezměnily. Podrobnosti a omezení reuse jsou v
`ticket-wallet-queue-validation-2026-11-13.json`. Čekání na Flutter a globální
CI mirror skončilo bez zásahu do cizí session. PR #838 je podle finálního
readbacku stále OPEN se stejným head a nebylo změněno.


Kapacitní důkaz upravuje původní předpoklad výkonu: 8 requestů/s a GET+PUT pro
každou změněnou kartu dávají optimisticky asi 4 karty/s. Naměřené p95 burstu
1 000 karet je 238,55 s a 10 000 karet 2376,05 s. Pětiminutový limit pro
10 000 současně změněných karet není v této kvótě dosažitelný. Výstupy jsou v
`ticket-wallet-queue-capacity-2026-11-13.json` (řízený skutečný Google executor,
virtuální čas, bez sítě) a `ticket-wallet-queue-sql-capacity-2026-11-13.json`
(skutečný disposable PostgreSQL: scope 1 000 / 10 000 za 256 / 11212 ms,
burst enqueue 40 / 325 ms). Jde o dvě samostatná měření, nikoli end-to-end SLA.


Obnovený vzdálený stav přes `git ls-remote`: main nadále
`a21a6f604781b98a7d20dd3a078b0bd20294a164`, regionální prod
`9a3db0fd22c8ee4d3ac23397338fcf90e6366ec8`. Jde o Git tip, nikoli
ověření nasazeného backendu či veřejné verze. Kontrakce také odstraňuje přesný
historický dormant runtime cron řádek; skutečný control-plane job se mění
připraveným odděleným skriptem až po samostatné autorizaci.


Důkaz z finálního mirroru: původní
`assemble-admin-notification-delivery-migration.py --check` skládal instalovanou
migraci 20261112234500 z aktuálního `payment_providers/effects.sql` a odmítl
legitimní registrovaný Wallet forward. Checker nyní pro deklarované pozdější
vlastníky používá checksum-pinned historické tělo a současně ověřuje shodu
aktuálního těla s effective migration head. Ostatní zdroje a prerequisites dál
kontroluje původním způsobem. Žádné historické migrační bytes se nezměnily;
regresní test stále odmítá přepsání publikované migrace při neplánovaném driftu.


Finální test souběhu odhalil původní integrační UPDATE v claimu: dvě různé
karty stejné akce čekaly na tentýž tenant row lock navzdory SKIP LOCKED.
Implementace nyní používá sdílený claim fence a výhradní pause fence, takže
krátká otevřená transakce prvního claimu neblokuje jinou kartu. Nový test také
ověřuje čekání pause na claim transakci, blokování nových claimů a dovolené ack
již převzaté práce. Pause RPC je definováno již v expanzi, ne až v kontrakci.
