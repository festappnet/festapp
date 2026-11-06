# E-shopové konektory - autoritativní realizační plán

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

Datum 29. 10. 2026. Stav: vlastník schválil společné jádro, ověření před větší implementací, držení nejasné rezervace a základní rozsah. Provider garance zatím nejsou prokázané. Žádná implementace/migrace/provozní aktivace. Ověřování standard. Pracovní větev `docs/shoptet-research-20261029`, izolovaný worktree `/Users/miakh/source/festapp-shoptet-research-20261029`, referenční main `00f05276de8c07c186c9d884e59291666d7707d6`.

**Jeden Commerce Connector nad existujícím Festappem; Shoptet je první provider adaptér.** Další nativní e-shopové extensiony použijí stejný kontrakt a doménové operace. Podrobná autorita: [společná architektura](../architecture/commerce-connectors.md). Shoptet překlad: [adaptér](../architecture/shoptet.md). [Execution prompt](commerce-connectors-EXECUTION-PROMPT-2026-10-29.md) odkazuje na tento plán.

[Záznam schválených rozhodnutí](commerce-connectors-review-2026-10-29.md).

## Výsledek a rozsah

Jeden kanonický proces od rezervace přes externí košík až po domácí objednávku, finance a doručení. Dvě okna, přímý formulář, embed i nativní e-shop spotřebovávají stejné inventory units. Provider adapter překládá svůj protokol a nepřepočítává kapacitu nebo účetní fakta.

V rozsahu návrhu jsou shared-reservation-v1, obecná schema/interface, Shoptet adaptér, bezpečnostní/pořadové kontrakty, potřebné změny stávajících doménových vlastníků a důkazní matice. První profil CZ/CZK a jedna akce. Smíšený fyzický košík, více akcí/měn, split payment a refundace použitého ticketu vyžadují explicitně podpořený kontrakt; nejsou automaticky aktivované.

Odesílání zpráv/podání je zakázané. Tento plán nic neimplementuje a neopravňuje k produkční migraci, deploy, zapnutí pilotu, placenému testu, commitu nebo pushi. Implementace dalších providerů se nezahajuje pouze proto, že jim architektura vytváří seam. Existující WordPress/Wix/Make se nepřepisují.

## Současné opory a důsledky

| Zjištění v repozitáři | Důsledek pro návrh |
| --- | --- |
| integrations/README.md vyžaduje platformní balíčky a sdílený checkout ve web_client/backendu. | Extension v integrations/<platform>; obchodní logika v existujících doménových SQL a společném serverovém modulu. |
| Make používá Operations.invoke nad kanonickým backendem a vlastní read-only profil. | Zachovat stejný princip adaptéru. Provider import nesmí získat lidské orders.mark_paid oprávnění a obcházet svoji validaci. |
| Stripe provider.ts drží HTTP oddělené od SQL částek/stavů, payments.ts používá claim/reconcile. | Následovat existující rozdělení odpovědností. Nepoužít Stripe identitu/účetní logiku jako generickou commerce sémantiku. |
| select_spot/finalize/apply_allocations zamykají autoritativní kapacitu; řada readers počítá order nebo active secret. | Přidat generic capacity claim do všech těchto cest před aktivací provider produceru. |
| Domácí finalizer přijímá bank/stripe, katalogovou cenu a připravuje e-mail. | Externí import nemůže volat nepozměněný veřejný create s paid flagem. Vyjmout společné materialization části; oddělit source-specific price/payment preparation. |
| payment_financial_totals_internal a update_order_and_tickets_to_paid/queue vlastní finance a vydání. | Connector facts přispějí do stejné projekce a stejné fronty, nevzniknou kopie. |

Přehled kandidátů obsazenosti: [capacity-candidates.json](commerce-connectors-evidence-2026-10-29/capacity-candidates.json). Výpis je kandidátní navigace, ne potvrzení správného zpracování všech symbolů. Implementátor před aktivací doplní semantickou klasifikaci: admission, read, maintenance, copying nebo odůvodněný non-capacity caller. Navíc ověří product maximum a form participant capacity bez závislosti na výskytu textu secret.

## Rozhodnutí, předpoklady a blokátory

- D1: Core nezná shippingRequestCode/verificationCode ani jméno provideru v obchodní větvi; Shoptet je mapuje v adaptéru.
- D2: Capacity reservation alokuje skutečné eshop.spots, chrání všechny závislé kontexty i form/product limity a převede claim do existujících tickets bez dvojího odečtu.
- D3: Provider nejistota se zachová trvale, nevyřeší se timeoutem. Mutace se slepě neopakují a lease TTL není fencing běžícího procesu.
- D4: paid, provider acceptance a delivery jsou různé stavy; žádné fake bank transakce, druhá QR evidence ani poštovní fronta.
- D5: Přidání druhého provideru splňujícího stejný profil znamená adapter, manifest a conformance fixtures. Jiný obchodní model vyžaduje výslovnou změnu společného kontraktu. Nové SQL tabulky/provider-specific price paths nejsou běžný registrační krok.
- A1: Shoptet zvláštní shipping kontrakt bude dostupný našemu doplňku. Řeší G1; zatím nejsou přístupy ani schválení.
- A2: G2-G4 prokážou serverové vázání nabídky a bezpečný konečný výsledek. Pokud ne, společný native checkout nelze označit za funkční; není povolen automatický fallback na kvótu.
- B1: Dosud neprovedený vlastní sandbox s aktivním provider kontraktem. V této fázi je skutečná práce veřejné čtení a design, ne fiktivní pass výsledky.
- B2: Zákaz nového externího odesílání/podání. Otázky G1-G5 se přednostně řeší dokumentací a vlastními scénáři, ne automatickým e-mailem podpory.

## Etapa 0 - lokální kontrakt a důkazní plán

Invariant: design má jediného vlastníka a nevyžaduje další survey.

Změny: architektura, konkrétní Shoptet mapping, machine evidence veřejného API/zdrojů, permission matrix a inventory caller ledger. Manifest budoucího integrace balíčku ještě není distribuovaná aplikace. Staré návrhy mají pointer na nové autority, ne alternativní pokyny pro vlastní runtime.

Ověření nyní: lokální odkazy, konzistence názvů a evidence, statický náhled. Žádný Flutter/Deno/SQL test jen kvůli psaní dokumentu. Hotovo: tyto artefakty jsou přehledné, nezaměňují facts/design/gates a mají explicitně nepovolené provozní kroky.

## Etapa 1 - společný interface a Shoptet adaptér v izolaci

Až bude implementace autorizovaná: vytvořit `_shared/commerce/contract.ts`, `connector.ts`, `providers/shoptet.ts` a statický registry v composition root. Source-independent normalized types, exact-money konverze a allowlist display projekce mají jediného vlastníka v core. Doménové částky stále určuje SQL; adaptér jen validuje provider reprezentaci.

Veřejné route zatím nepublikovat. `integrations/shoptet/` dostane manifest/profile/setup a platformní browser adaptér podle stávající integrační konvence; nevytvářet rozkopírovanou core logiku v balíčku extensionu. Source generování, je-li nutné, má jeden kontrolovaný owner a ověřitelný digest. Generic DTO vlastní core contract, provider instalace má jen metadata/bridge.

Ověření: navržené Deno contract tests na fake-provider outcomes přes stejné interface, pro confirmed/rejected/unknown, nesprávnou scope/měnu a špatně normalizované stavy. Druhá syntetická conformance fixture pro jiný raw API tvar musí dojít ke stejným doménovým výsledkům bez úprav connector.ts. Fixture není tvrzení, že existuje hotový Upgates adaptér.

Hotovo: registry/test adaptér se liší jen překladem protokolu; core neimportuje konkrétního providera a neobsahuje jeho business switch. Žádný test nevolá reálné e-shop API.

## Etapa 1a - levný provider go/no-go před rozsáhlými SQL změnami

Po získání vlastního oprávněného sandboxu provést minimální probe G1-G4 přes adaptér a disposable lokální evidenci. Zkoušet změněný košík se starým kódem, dvě okna a opačné pořadí odpovědí, vynucení dopravní metody a přijetí těsně před expirací. Před tímto výsledkem se nepouštět do plošné úpravy inventory callerů jen na základě veřejné dokumentace.

Experiment nepoužívá produkční kapacitu, email delivery ani reálné peníze. Ověří pouze provider kontrakt; není náhradou pozdějších SQL concurrency testů. Když není G4 definitivně prokázaná, výstup musí říct, zda navržená konservativní blokace poskytne provozně přijatelný model, nebo automatické zotavení zůstává blokátorem.

Hotovo: evidence klíčových provider garancí, explicitní výsledek pro každou G1-G4 a rozhodnutí pokračovat v tomto profilu. Neprovedený probe není pass. Při chybějících přístupech nebo trvajícím zákazu mutací zůstává připravený harness a blokovaná etapa, nikoli automatická žádost podpoře.

## Etapa 2 - generic capacity reservation v kanonickém inventory

Změny: `database/tables/commerce_connectors.sql` a `capacity_reservations.sql`; explicitní aditivní migrace bez produkčního použití. Přidat capacity_reservation_id FK+exclusivity CHECK k eshop.spots. `database/functions/inventory/capacity_reservations.sql` vlastní reserve/adopt/transfer/release, jeden occupancy helper a souběhové zámky.

Upravit současně select_spot/hold admission, materialize_ticket_products, apply_allocations, blueprint projections/availability/get_blueprint, authoring snapshots a všechny maintenance/delete/swap/batch/waitlist kandidáty. Podrobné lokality obsahuje ledger; každou sémanticky ověřit a označit výsledek. Kopie akce nepřenese žádný claim. Zmenšení poolu/resource, ruční uvolnění nebo změna vazby aktivní claim bezpečně odmítne.

Product maximum a form participant capacity zahrnou reservation items jako intended tickets; PIC claims nesmějí násobit počty. Převzetí vlastní rezervace do order ticketu udržuje invariant sumy a zámků. Výsledek je vždy všechno, nebo nic, i pro atomickou skupinu sedadel a více inventory kontextů.

Ověření: nové SQL scénáře `database/tests/commerce_connectors/capacity_test.sql` a deterministic dvě-connection `capacity_concurrency.test.mjs`; propojit se stávajícím blueprint concurrency harness namísto kopie. Regrese capacity_resources, blueprint_reservation_integrity, standing inventory, form_capacity, admin release, swap, waitlist a batch podle dotčených ownerů.

Hotovo: nejistý external claim nemůže přidělit, smazat ani uvolnit žádná podporovaná domácí cesta; veřejné read modely neodhalí jeho tajemství. Žádná aktivní instalace ani externí POST.

## Etapa 3 - commerce agregáty, lifecycle a bezpečný import

Změny: `database/functions/commerce_connectors/` pro installations/mappings, checkout prepare/claim/finish, durable inbox/tasks, order links a financial facts. Každá service-only operace prověří uloženou install generation a resource scope. Actor commands mají typed predicates v `user_permissions/commerce_operations.sql`; replay znovu ověřuje práva.

V existing finalizeru vyjmout sdílenou materializaci do jednoho interního owneru použitelnou domácím create i trusted external importem. Zachovat běžnou veřejnou signaturu a zákaz klientského price/paid override. Generic inventory header má jen opaque owner reference; commerce_offer vlastní vazbu na reservationId. Provider currency/mapping/price snapshot nepatří do capacity_reservation_items. Externí snapshot se připravuje neveřejně, převzetí claimu nevytváří další kapacitu a nevytváří ticket dvakrát po reinstalaci.

`payment_financial_totals_internal`/refresh, recalculate_order_payment_status, bank/Stripe matching, order deadline/release, reminders a paid delivery respektují payment_method=external_commerce. Domácí expired reactivation a refund-induced debt se na externí source neaplikují generickou větví. Provider labels se promítnou do existujících reportů/allowedActions, nikoli nové reportovací paralely.

Ověření: SQL unique replay, changed-payload same command, reinstalace a credential generation, cizí tenant, price/currency mismatch, ambiguous financial snapshot, late paid/cancel/refund, exactly-one accepted email intent. Přímý browser/public RPC nesmí přinést trusted external facts. Regrese bank/Stripe payment_totals a Client Sync vlastníků. Nepodporovanou externí refundaci/změnu prokazatelně detekovat a ověřit kanonické zneplatnění a scan projections; nesmí se ignorovat nebo automaticky uvolnit místo.

Hotovo: konektor obslouží fake-provider lifecycle skrze stejné canonical orders/tickets/projections. Neexistuje shoptet_orders/shoptet_tickets ani provider-specific capacity calculation.

## Etapa 4 - jeden routovaný ingress a worker

Změny: `supabase/functions/commerce-connector/index.ts`, route adapter do core, config.toml, `_shared/edgeEntrypoints_test.ts`, test-coverage.json a bezpečnostní inventář. Explicitní auth tabulka pro install callback, raw signed events, buyer session/checkout a admin JWT; žádná veřejná cesta přímo k service-only ingest.

Provider callback nevybírá unit z query; propojení vyžaduje ověřené merchant vlastnictví a oprávněnou akci. Session bearer capability nevyžaduje third-party cookie, neloguje se a předává se mimo URL. Provider API origin a allowed callbacks jsou pinované ověřenou instalací. Secret reference a generation jsou chráněné v runtime, browser je nikdy neobdrží.

Worker používá generic commerce_tasks/attempt fence a stejný core. Nejasná mutace blokuje nový sender; skutečně ukončený původní proces je podmínka dalšího ne-idempotentního pokusu. Čtení mají bounded retry a limity; nejistota končí repair, ne release. Pause/uninstall ponechá claims chráněné a doručené QR funkční; reconnect porovnává staré identity.

Společná klientská session v web_client/src/components/eshop/commerce_checkout_session.js obslouží status/revision/conflict pro všechny nativní extensiony. U blueprint_layout_adapter.js/blueprint_selector.js vyjmout jen selection callback seam pro existující renderer; nekopírovat plánek a nevolat nezměněný bankovní veřejný checkout pod jiným tlačítkem. Admin nastavení patří do dosavadního form/occasion authoringu s generic installation DTO a typed commands; provider names nejsou nové Features s kopií logiky.

Ověření: ingress auth matrix, signature/raw-body cases, SQL finish lost response, process crash před/po external write, concurrent workers a stale generation. Lokální UI checks mohou používat pouze fake backend/disposable tenant podle repo pravidel. Ovládání cizího konkurenčního e-shopu není testovací fixture.

Hotovo: bezpečný local end-to-end fake průchod a jasná registrace/coverage; žádný prod Functions reload.

## Etapa 5 - vlastní provider sandbox a conformance

Po dřívějším provider probe z etapy 1a a hotové místní integraci provést celé S1-S10 proti reálným společným alokacím. Jen ve vlastním oprávněném sandboxu. Žádné reálné peníze. Trvat na G1-G5 včetně podvržené jiné dopravy, změny obsahu, jiné metody platby, dvou oken, ztraceného PUT výsledku a objednávky přijaté těsně před expirací.

Výsledek váže provider/app/spec version, contractProfile a anonymizované requests/responses na skutečný capacity readback. Obnovovatelný open stav po expiraci není finalita; bez ní core zachová awaiting_provider. Při nedostatečném kontraktu úprava návrhu a explicitní rozhodnutí; žádná tichá větev kvóty.

Hotovo: důkazy pro povolený profil, dokumentované unsupported cases a průkazný poslední kus přes oba kanály. Zpráva podpory není náhradou skutečného testu a samotný test není záruka všech budoucích změn platformy.

## Etapa 6 - připravenost pilotu a samostatný rollout

Založit profile state disabled/sandbox/enabled a aktivovat až po gates+role check. Pilot je jedna výslovně vybraná akce, nikoli rollout na všechny tenanty. Přesný main/tenant source, deploy a operace musí mít samostatnou autoritu a existující release gates. Rutinní autorizovaný deploy se deleguje podle osobních pravidel, nikoli provádí během návrhu.

Pořadí: aditivní SQL; všechny readers/writers kapacity; canonical import/finance; kompatibilní Edge+worker; frontend; teprve pak installation enabled. Old clients nesmějí umět uvolnit nové claimy skrze původní SQL. Feature config není náhrada serverového enforcementu.

Rollback: zastavit nové nabídky a nadále bezpečně zpracovávat admitted orders/unknown claims. Nevracet automaticky schema, které nezná capacity_reservation_id, a nemažat orders/facts/attempt journal. Destruktivní odstranění až po nulových claims a řízeném odstavení. Nevracet se k webhook-only prodeji.

Hotovo: cílené lokální checks, případné normální CI a explicitní release gates vybraného tenantu, provider conformance evidence a operátorův repair postup. Podání do marketplace a obchodní podmínky jsou samostatný stav.

## Ověřovací příkazy a testovací seams

Příkazy pro budoucí source/test soubory jsou záměrně označené jako plánované; netvrdí, že teď existují nebo prošly.

| Etapa | Nejlevnější důkaz |
| --- | --- |
| Dokumentace nyní | Lokální link/JSON kontrola a file:// náhled; bez aplikačních testů. |
| Interface/adaptéry, plánované | `deno test supabase/functions/_shared/commerce/contract_test.ts` s fake providerem a bez network permissions. |
| SQL lokálně | V web_client `pnpm exec node scripts/run_db_tests.js ../database/tests/commerce_connectors/capacity_test.sql` s explicitním disposable local DATABASE_URL; ochrana identity podle normální repo workflow. |
| Souběh SQL, plánovaný harness | `pnpm exec node scripts/commerce_capacity_concurrency.mjs` v izolovaném projektu a se dvěma skutečnými DB spojeními. |
| Dotčený web klient | `pnpm exec node --test tests/forms/commerce_checkout.test.js` (plánovaný nový test) a relevantní stávající reservation testy. |
| Deterministická browser smlouva | Stávající repository E2E/mirror gate pro dotčenou cestu; agent-browser jen explorace v izolovaném headless profilu. |
| Provider sandbox | S1-S10 s přesným source/e-shop/profil digestem, žádné fake assertions místo skutečného čtení. |

Před instalací JS balíčků pnpm 11.24.0 a frozen lockfile. Žádné paralelní Flutter úlohy, testy případně concurrency=1; samotný konektor není důvod pro Flutter build, dokud se jeho klientský kód nemění.

## Kontrakce a odstranění duplicit

| Artefakt / riziko | Výsledné pravidlo |
| --- | --- |
| Starší Shoptet návrhy | Zůstávají historická evidence a odkazy; nový execution prompt vede sem. Nejsou druhou implementační autoritou. |
| Shoptet-prefixed kopie checkout/finance/tickets | Nezaložit. Pokud vznikly v lokálním prototypu, nahradit generic core před mergem a odstranit všechny callers. |
| Samostatné provider podmínky v inventory/finalizeru | Přeložit na canonical claim a external_commerce source; provider name patří pouze do registry/metadata/adapteru. |
| Přímé HTTP odesílání ticketů v extensionu | Nezaložit; jediný accepted intent je v existující queue. |
| Rozkopírovaná schema a konverze mezi extensiony | Jeden core contract owner; provider distribuce má jen odvozené allowlist DTO/manifest. |
| Aktuální WP/Wix/Make/Stripe | Zachovat v jejich existující roli. Nepřejmenovávat ani nemigrovat jen pro formální unifikaci. |

## Definice úplného návrhu a hotové implementace

Úplný návrh dnes znamená malé společné interface, provider translation, explicitní storage/state/claim ownership, přesné změny současných ownerů, failure/authorization model, activation gates a proveditelnou testovací mapu. Tyto dokumenty jsou takový návrh; nejsou implementací.

Hotová implementace znamená navíc ověřené G1-G5 a S1-S10, všechny relevantní capacity readers/writers upravené, kanonickou finanční projekci a delivery, žádnou obcházející veřejnou cestu, doložené zachování claims po výpadku a žádnou provider kopii doménových pravidel. Zbytkový risk: změna neveřejného provider kontraktu nebo jeho neprokazatelná finalita může zablokovat aktivaci či automatický release; nelze to vyřešit přejmenováním modulů.
