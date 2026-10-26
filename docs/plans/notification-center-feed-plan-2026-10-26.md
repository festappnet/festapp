# Centrum upozornění: seznam podle akce a životní cyklus formuláře

Datum: 2026-10-26
Stav: lokálně dokončeno, sjednoceno s aktuálním main a ověřeno. Žádná produkční změna.
Ověřování při implementaci: `standard` (SQL kontrakty, oprávnění, souběh a migrace)

## Autoritativní korekce základu po průzkumu 26. 10.

Před pokračováním platí
[plán sjednocení pracovního stromu](workspace-canonical-reconciliation-plan-2026-10-26.md).
Původní pracovní větev je předek main a její necommitovaná vrstva z velké části
opakuje už sloučený snapshot. Nesmí přepsat novější canonical implementace.

Publikovaná migrace `20261024235000` odstranila `notification_center_activation`
a `set_notification_center_activation`. Cílový owner je
`notification_center_organizations` / `initialize_notification_center_internal`.
Odkazy níže na zachování aktivace, pause/resume nebo preview rollout jako server
kontraktu vycházejí ze staršího stavu a jsou tímto výslovně nahrazeny: žádný
odstraněný mechanismus se neobnovuje. Funkční požadavky na flat feed, kontakt,
počty, oprávnění, ack a ruční/naplánovanou dostupnost se nemění.

Vlny 1-3 musí začít z aktuálních canonical ownerů a skutečné historie main.
Form creation/wizard hook patří také do `form_creation_domain.sql`. Původní celé
lokální SQL funkce se nesmějí použít jako náhrada novějších main těl. Stávající
nové delta a dílčí receipts nejsou povolením aplikace ani finální release gate.

## Výsledek a autorita

Pod jedním názvem akce bude přímo seznam jednotlivých upozornění od nejnovějšího. Nová objednávka, náhradník, storno i otevření nebo uzavření formuláře jsou jednotlivé řádky. Neexistuje další úroveň rozbalování podle typu či dne. Číslo/symbol objednávky se nezobrazuje, ale interní identita a navigace zůstávají. Jméno/příjmení má fallback na e-mail; zbytečné „1 místo“ u samostatné přihlášky se vynechá.

Tento dokument je autoritativní pro navazující změnu. Nahrazuje skupinové UI a jeho read kontrakt z UI částí [původního plánu](organization-notification-center-plan-2026-10-23.md), nikoli pravidla osobního doručení, oprávnění, aktivace, e-mailů nebo BankSync. Existující bezpečnostní a provozní invariance zůstávají závazné.

Vizuální reference: [samostatné HTML](notification-center-feed-evidence-2026-10-26/preview.html), [snímek](notification-center-feed-evidence-2026-10-26/preview.png). Jde o ilustrační data a schválený směr rozložení, ne o důkaz implementovaného Flutteru nebo backendu. Formulace „přihláška/prodej“ ve vzoru nejsou důkazem existujícího doménového příznaku. Funkční close/settings ovládání v aplikaci zachovat; chování těchto tlačítek v maketě není specifikace.

## Rozsah a omezení

- Zahrnout SQL producenty, soukromé projekce, jednotlivé položky a stránkování, Flutter controller/panel, lokalizace, cílené regresní testy a forward migraci.
- Dostupnost formuláře má jeden SQL výpočet používaný existujícím registračním režimem i upozorněními. Kapacita má nadále svého současného vlastníka.
- Žádné aplikační triggery, druhá fronta, veřejný sync katalog, lokální inbox, Realtime fallback, nová banka ani přímé odesílání e-mailů.
- Neměnit checkout, cenu, přidělování míst, waitlist pravidla, timezone politiku ani povolené přechody objednávek. Extrakce společného časového výpočtu musí být behaviorálně ekvivalentní.
- Žádná produkční migrace, aktivace, commit, push ani release v rámci tohoto plánovacího zadání. Budoucí vydání má samostatné oprávnění a nejvýše jeden vybraný tenant; nepřidávat ostatní `prod/*`.
- Pracovní strom obsahuje rozsáhlé cizí rozpracované změny. Implementátor musí zachovat jejich obsah, vymezit vlastní diff a nepřepínat naslepo větev.

## Doložený výchozí stav

| Fakt | Vlastník / důkaz | Dopad |
|---|---|---|
| Panel již lokálně sdružuje skupiny pod nadpis akce, ale vnitřní řádky jsou stále typ/den s rozbalováním. | `lib/components/notification_center/notification_center_panel.dart`: `_section`, `_group` | Změna nadpisů je jen částečný mezikrok. |
| Page RPC vrací skupiny a jen prvních pět položek každé skupiny. | `database/functions/notification_center/core.sql`: `get_notification_center_page`, `get_notification_center_group` | Pouhé zploštění klientem by mělo díry a chybné pořadí; neřešit hromadou group requestů. |
| Pouze `open_notification_center` potvrzuje snapshot; delivery a open serializuje osobní row lock. | `core.sql`, `notification_center_controller.dart`, `read_cursor_concurrency.test.mjs` | Zachovat i při změně read modelu. |
| Časové otevření vyhodnocuje SQL; před startem, po konci a při `is_open=false` vrací `closed`. | `database/functions/eshop_waitlist/form_capacity.sql`: `get_form_registration_mode_internal` | Extrahovat jeho část pro časovou bránu, nevytvořit alternativní kalkulaci. |
| Formulářová data mají `schedule.start_time/end_time` i dosavadní top-level fallback. | Stejná funkce; `packages/festapp_core/lib/src/forms/form_definition.dart`: `startTimeUtc`, `endTimeUtc` | Zachovat dosavadní precedenci a přesné hranice `< start`, `> end`. |
| `update_form_internal_v1` mění `is_open`/data, ale volá pouze kapacitní observer; zachytává také návratové chyby uvnitř subtransakce. | `database/functions/eshop_forms/update_form.sql`, wrapper `update_form_client_sync_v1.sql` | Publikovat jen za úspěšnou skutečnou změnu uvnitř úspěšné transakční větve. |
| `capacity_reopened` znamená `remainingPublic` 0 -> kladná hodnota a pouze obnoví starou epizodu. | `notification_center/capacity.sql`: `notification_center_capacity_transition_internal` | Není to samostatná historická událost otevření prodeje; nesmí se tak zobrazovat. |
| `remainingPublic` odečítá také nabídky a prioritu waitlistu. | `eshop_waitlist/form_capacity.sql`: `get_form_capacity_snapshot_internal` | Nula neprokazuje „vše prodáno“. |
| Form otevřen/uzavřen ani evaluator termínů nyní v centru neexistuje. | `notification_center/{orders,capacity,maintenance}.sql` | Nutný nový producent v existující doméně a rozšíření existující údržby. |
| Osobní projekce má aktivační gate, recipient snapshot, mute, bounded fanout a recheck práv. | `notification_center/{schema,core,maintenance}.sql` | Použít stejnou infrastrukturu; neobejít ji novým jobem. |
| DTO objednávky doplňuje pouze `customerName`, ne fallback e-mail. | `core.sql`: `notification_center_dto` | Samotná úprava labelu ve Flutteru nestačí. |
| Fallback jméno/příjmení -> e-mail -> prázdný text již existuje. | `lib/components/eshop/models/order_model.dart`: `toCustomerData()` | Sdílet tuto sémantiku; nepoužívat debug `toString()` celého modelu. |
| Konfigurovaný `max_tickets` defaultuje na 1 a má globální strop; zbývající kapacita ho v UI dále omezuje. | `TicketEditorWidgets._getMaxTickets`, `TicketHolder`, `FormHolder` | Prezentaci odvozovat z konfigurace, ne aktuálně volného posledního místa. |
| V prohlédnutých modelech není spolehlivý sale/registration discriminator. | `FormDefinition`, `FormFeature`, form metadata | Neodvozovat prodej z ceny ani přihlášku pouze z limitu 1. |
| Aktuální assembler přepisuje pevný původní migration soubor z živých zdrojů. | `automation/assemble-notification-center-migration.py` | Pro tuto změnu potřebuje dopředný režim; nepřepisovat aplikovanou historii. |

Stav live migrací/klientů v tomto zadání nebyl ověřován. Starší plán popisuje lokální ověření a neprovedené provozní kroky; není důkazem dnešního stavu produkce. Poslední pokus o Flutter test této konverzace skončil před testy na `image`/`archive` (`decodeLazy`), cílená analýza tehdy prošla. Tento blocker ověřit z aktuálního lockfile při implementaci, neřešit úpravou globální cache.

## Cílová architektura a smlouvy

### 1. Jeden význam dostupnosti formuláře

Zavést interní SQL `get_form_availability_snapshot_internal(p_form, p_at)` v doméně `eshop_forms`. Čistý read bez publikování. Vrací normalizovanou časovou bránu (`manual_closed`, `before_start`, `open`, `ended`), `isWindowOpen`, efektivní start/konec a nejbližší budoucí časové rozhraní. Vychází z `forms.is_open` a `get_effective_form_data`, se stejnou precedencí a inkluzivitou jako dnes. `get_form_registration_mode_internal` mu deleguje svou časovou část a zachová dnešní blueprint/regular/waitlist/full rozhodování z kapacity.

Rozlišovat dvě osy: časová/manuální brána formuláře a možnost běžné registrace/waitlistu podle kapacity. `form_opened` neznamená, že je volná vstupenka. Při současném `full`/`waitlist` doplnit bezpečnou kvalifikaci „Kapacita naplněna“ / „Příjem náhradníků“. Změna samotné kapacity neprodukuje `form_opened` ani `form_closed`. Neměnit `occasions.is_open` na synonymum `forms.is_open`; jde o jinou existující hranici.

Názvy v základním kontraktu jsou neutrální „Formulář otevřen“, „Formulář uzavřen“. „Znovu“ jen s doloženou předchozí otevřenou epizodou. Název konkrétního formuláře je v druhém řádku; při chybějícím názvu generické „Formulář“, bez interního ID. „Prodej/přihlašování“ použít pouze tam, kde existuje doložená sémantika formuláře; jinak zůstává neutrální text. Nezavádět kvůli tomu nový konfigurační přepínač.

### 2. Jeden producent změn a jeden scheduler

Nové interní helpery v `notification_center/form_availability.sql` spravují `source_key='form-availability:<formId>'` v existujícím `notification_center_source_state`. Nekolidují s kapacitním `form:<id>`. Stav nese poslední vyhodnocenou časovou hranici, předchozí normalizovanou konfiguraci, stav brány a monotónní číslo přechodu. Přidat nullable typovaný `next_evaluation_at timestamptz` s indexem pro due stavy. Všechny poziční `INSERT ... VALUES` do rozšířené tabulky převést na explicitní sloupce, zejména současný kapacitní seed.

Publikovat přes `notification_center_publish_internal`, bez přímých delivery insertů. Událost nese `formId`, historický bezpečný název formuláře, `from/to`, omezený důvod (`manual`, `schedule_start`, `schedule_end`, `schedule_changed`), čas účinku a režim v okamžiku přechodu. Žádné kontakty, celé form JSON nebo tajemství v event logu. Dedup klíč obsahuje form ID a uložené číslo přechodu; číslo a insert se potvrdí atomicky. Pozdější otevření nepřepisuje původní historické uzavření.

Před úspěšnou změnou konfigurace dopracovat staré splatné hranice podle původní uložené konfigurace do jednoho zachyceného `p_at`; potom aplikovat novou konfiguraci a vyhodnotit její skutečný dopad ke stejnému okamžiku. Pouhá změna textu, opakování stejného nastavení, neúspěšná mutace a command replay neprodukují další událost. Přepnutí `is_open=true` před budoucím startem nebo po platném konci samo neznamená otevření. Zavření již skončeného formuláře nevytvoří druhé uzavření jen kvůli jiné příčině.

Rozšířit `maintain_notification_center`, spouštěné současným minutovým cronem, o bounded vyhodnocování splatných stavů. Indexovaný výběr due položek, limit, spravedlivý postup a retry po rollbacku; údržba nesmí držet source row lock a teprve čekat na form lock v opačném pořadí proti writeru. Neměnit výhradní projector lease ani osobní ack lock. Zachovat email/bank údržbu a zabránit jejich hladovění. Žádný další cron, proces ani klientské publikování při návštěvě stránky.

Pořadí zámků pro dotčené cesty výslovně dodržet: existující organizační activation gate, současné doménové form/product/inventory pořadí, source state, event/recipient snapshot. Začlenit se do existujícího command/replay ownera; nepřidávat doménový lock v protisměru. Scheduler může přeskočit obsazenou formu a vrátit se k ní. Současný save a scheduler musí vytvořit každý skutečný přechod právě jednou.

Pokud údržba nebyla spuštěna přes start i konec, nesmí skončit jen porovnáním dvou hodnot `closed`. Dopracuje obě skutečné hranice podle uložené konfigurace s původním časem události. Neodvozovat minulost z dnes přepsaného nastavení. Zachovat přesné `< start` / `> end`: konec je splatný až po hranici konce, bez změny checkout semantiky; `occurredAt` události uvádí konfigurací daný konec. Chybné či prázdné rozsahy vyhodnotit shodně s dosavadním SQL; nesyntetizovat otevření pro neexistující interval.

První aktivace, upgrade již aktivního tenantu a resume založí tichý baseline ke konzistentnímu okamžiku. Žádné historické „právě otevřeno“ při instalaci ani replay hranic z pauzy. Nový/duplikovaný formulář také začíná baseline bez falešného otevření; skutečné následné otevření se již publikuje. Při odstranění formuláře zrušit jeho due stav bez umělého `form_closed`. Mutované formy přes create, duplicate, wizard a occasion authoring musí být klasifikované, ne pouze `update_form`.

### 3. Jednotlivé události v osobním snapshotu

Kanonický nový reader `get_notification_center_feed(p_organization, p_current_occasion, p_snapshot, p_cursor, p_limit)` vrací `items`, `nextCursor`. Sdílený interní autorizovaný výběr dodá pro každou událost pouze poslední delivery revizi v daném snapshotu. Použít stávající `notification_center_allowed`, kontext, recipient snapshot a osobní sekvence; zdrojové tabulky ani kontakty se nezveřejňují.

Každá položka nese `id`, `sequence`, `section`, occasion ID/title/link, `kind`, historické `occurredAt`, aktuální `status` a omezená typed data. Řazení: `section ASC, occurredAt DESC, id DESC`; čas události je stabilní. Snapshot se stále omezuje `delivery.sequence <= snapshot`, nikoli wall-clock časem. Sekvence je ack watermark, ne náhrada skutečného času události. Cursor je neprůhledná validovaná tuple ze stejných sort klíčů; vázat na organizaci/snapshot/occasion kontext, odmítnout neplatné kombinace, nevěřit cursoru jako oprávnění.

Stránkování má limit jednotlivých položek, nikoli počet skupin. Při revokaci práv lze položku odstranit, nevytvořit duplicitu a nezastavit cursor na znepřístupněném řádku. Žádné `expand()` requesty pro dokončení jedné stránky. SQL a případné indexy ověřit i na mnoha událostech stejné akce ve stejný den; nepřijmout N+1 skupinové RPC nebo neomezené klientské načtení.

`open_notification_center` zachová jeden ack owner a stejný osobní row lock. Nad stejným zachyceným snapshotem přidá `feedItems`, `feedNextCursor`, `feedSupported=true`. Nový klient otevře panel až s tímto potvrzeným feed kontraktem a další strany čte výhradně přes feed RPC. Chybějící capability je jeden nepodporovaný stav, bez přepnutí do starého skupinového UI. Read-only capability zjistit již z badge odpovědi; neprovádět detekční open, který by potvrdil položky před zobrazením.

**Záměrná kompatibilní hranice:** dokud není doloženo vyřazení starších vydaných klientů, dosavadní `groups/nextCursor` v open a RPC `get_notification_center_page/group` zůstanou pouze legacy serializační adaptéry nad týmž autorizovaným výběrem. Nový Flutter je nevolá. `group_key` je v této době jen potřeba starých externích čtenářů, nikoli nová kanonická feed identita. Původní historický snapshot a ack kontrakt se nesmí změnit kvůli novému UI. Adaptér má jediný důvod existence: starší skutečně vydané klienty. Při doložené absenci všech takových klientů odstranit v kontrakční vlně současně RPC, pole, sloupec/index a skupinovou část projektoru. Bez důkazu neprohlašovat externí kontrakci za hotovou a nevyžadovat ji pro lokální feed implementaci.

### 4. Prezentace kontaktu, počtu a typů

- SQL DTO doplní autorizovaný `contact: {name, surname, email}` z aktuální objednávky stejné akce/tenantu; ne ze zveřejněných snapshotů nebo jiné osoby. Chybějící/smazaný kontakt se vrátí prázdný. Oprávnění recheck předchází hydrataci. E-mailový incident nadále ukazuje svého `recipient`, což je jiný význam než objednavatel.
- Extrahovat čisté `formatCustomerLabel({String? name, String? surname, String? email})` do `packages/festapp_core/lib/src/eshop/customer_label.dart`, exportovat přes `festapp_core/eshop.dart` a delegovat na něj `OrderModel.toCustomerData()` i notification presenter. Pravidlo: trimované neprázdné části jména -> trimovaný e-mail -> prázdno. Žádný symbol/id jako fallback a žádný prázdný oddělovač.
- SQL přidá omezený `formContext` s konfigurovanou možností více vstupenek a form identitou. Použít existující normalizaci ticket field metadata a globálního stropu; ne aktuální `remainingPublic`, cenu, název akce ani absenci blueprintu. Pokud je třeba společný SQL metadata helper, spotřebitelé na něj delegují, nevznikne druhý set defaultů.
- Přesný počet je fakt konkrétní události: creation/waitlist skutečně vytvořené ticket identity, storno počet skutečně zrušených míst (již nyní), nabídka její zasažený počet. Nevyměnit historický počet za dnešní počet po částečném stornu. Bezpečný neosobní form kontext/počet zachytit v producentu; pro starou historii použít přesný dostupný fakt, jinak počet vynechat, nevymýšlet backfill.
- Při počtu >1 vždy zobrazit počet; při 1 zobrazit jen pro doložený více-vstupenkový kontext; při chybějícím/nejistém počtu jej vynechat. Tím i historické 2 vstupenky zůstanou čitelné po změně limitu formuláře na 1.
- Singular labels pro jednotlivé události. Terminologie „přihláška“ není automaticky důsledkem `max_tickets=1`; pokud stávající doména nedává jiný explicitní význam, používat neutrální stávající objednávkový pojem. Pro formulářové změny neutrální formulář. Žádné nové nastavení jen pro text upozornění.
- Kapacitní problém „Kapacita naplněna“, ne nepodložené „Vyprodáno“. Recovery popisuje uvolnění míst, ne otevření prodeje. Zachovat jednu existující kapacitní epizodu s recovery bez další unread události; nepřidávat paralelní druh kapacitní události kvůli mockupu.

### 5. Flutter seznam a stavové chování

Controller vlastní jediný seznam `NotificationItem`/typed DTO a jeden feed cursor. Panel jej promítne do dosavadních sekcí 0/1/2 a v nich do bloků podle occasion ID, v pořadí prvního výskytu v serverovém feedu. Stejně pojmenované akce nesloučit. V bloku zachovat časové pořadí; příští stránka doplní existující blok. Organizace-only položky nestrkat pod libovolnou akci; společné incidenty si ponechají pozornost a povolené affected occasion odkazy.

Název akce jednou, mute menu jednou, žádné součty neúplné historie. Řádek obsahuje druh, volitelný kontakt/počet nebo název formuláře/důvod a čas; celý řádek je ovladatelný jen s existujícím autorizovaným detailem. Informativní form/capacity řádek nemá falešnou šipku/Detail. Nenavrhovat nové form editor deep linky mimo tento rozsah. Zachovat e-mailové a bankovní detaily, bezpečné affected links, draft guard, Escape, fokus a AppDialog shell.

Otevřený panel drží snapshot a pořadí. Hydratace již načtených ID aktualizuje fakta nebo odstraní revokovanou položku, ale nepřesouvá řádky ani nevkládá nové. Nové položky se objeví po explicitním obnovení. Preserve generation/revision/badge fences, identity reset, 15s/60s polling a pauzu na neaktivní route/background. Open, scroll, další strana, mute a refresh známých ID si nesmějí plést ack pravidla: potvrzuje pouze explicitní open/obnovení snapshotu.

## Implementační vlny

### 1. Zafixovat kontrakty a bezpečný migrační vstup

**Změny:** zkontrolovat aktuální lokální diff, přítomnost původní migrace a její známé aplikování. Vymezit feed DTO/cursor, capability a legacy adaptér výše. Upravit `automation/assemble-notification-center-migration.py` pro nový pojmenovaný forward manifest a `--output`/`--check`; explicitní manifest uvádí pouze potřebný schema delta a změněné funkce v závislostním pořadí. Výchozí kontrola ověřuje aktuální kanonické tabulky a aktuální forward výstup; nepřegeneruje fixní historický baseline z dnešních zdrojů. Minulé soubory jsou neměnná historie. Přidat pojmenovaný test této vlastnosti a odmítnutí přepsání existujícího jiného výstupu.

**Migrace/kompatibilita:** nová forward migrace po skutečných prerequisite revisions, žádné úpravy `20261023210000...` ani nechtěné publikování ticket-batches. Aktuální canonical schema a `database/tables/tables.sql` zůstanou shodné. Rehearsal musí projít z čistého canonical schema i z předchozího stavu přes pouze nový delta soubor.

**Ověření a výstup:** statické source/manifest contract testy pro assembler, jasný seznam grantů a minimálních prerequisite; žádné produkční připojení. V této vlně neaplikovat nedokončený schema delta. Hotovo, když je konkrétní cesta vygenerování a ověření nové migrace bez přepsání historie.

### 2. Kanonická dostupnost a transakční producenti

**Změny:** společný snapshot helper; `form_capacity.sql` deleguje časovou bránu. Rozšířit schema/source state, opravit poziční inserty. Nový availability reducer a tichý baseline. Zapojit úspěšnou větev `update_form_internal_v1` uvnitř command replay hranice; registry vytvoření/kopie v `create_form_internal_v1.sql`, `duplicate_form_to_occasion.sql`, `others/duplicate_occasion.sql` a implicitní create v update. U změn occasion, které jen připojují blueprint, ověřit mode kontext; nepublikovat smyšlené časové přechody. Smazání retirement zapojit do stávajícího delete ownera nalezeného scoped vyhledáním `DELETE FROM public.forms`.

**Selhání:** neúspěšný domain command a rollback nesmí ponechat event, posunutý baseline ani číslo přechodu. Ověřit vlastní author suppression se stejným auth actor pravidlem, automatické přechody mají NULL actor.

**Ověření/výstup:** nové `database/tests/notification_center/form_availability_test.sql` + dotčené existující form/waitlist testy. Tabulkově časové hranice, no-op, replay, save failure, rollback, create/copy/delete, full vs closed a ruční reopen za neplatného časového okna. Stejný input před/po extrakci dává stejný registrační režim.

### 3. Naplánované přechody, souběh a baseline

**Změny:** `maintenance.sql` vyhodnocuje due rows přes tentýž reducer, `set_notification_center_activation` se rozšíří o konzistentní availability baseline. Nová migrace baseline již aktivních tenantů serializuje existujícím org gate; feature se nesmí ztišit nebo reaktivovat jako vedlejší účinek migrace. Stávající cron registrace zůstává jediná. Dotčené provozní metriky/return counts doplnit aditivně a bezpečně.

**Selhání:** outage přes obě hranice, save během due evaluace, dva workery, změna termínu po nedoběhlé hranici, pauza/resume, odstraněná forma, obsazený zámek, malé batch limity. Zaručit běh bez otevřeného admin UI a bez starvation email/projector části.

**Ověření/výstup:** skutečný dvouspojový Postgres test `form_availability_concurrency.test.mjs`, ne mock zámků; SQL scénáře pro backlogged start+end a baseline upgrade. Hotovo při právě jedné historické události za skutečný přechod, správném původním času a tichém baseline.

### 4. Jednotlivé feed položky a bezpečná prezentace dat

**Změny:** v `core.sql` společný autorizovaný výběr, feed RPC, read-only capability, aditivní feed výstup v open a staré serializační adaptéry. Nové objednávkové DTO/form kontext a historické počty v `orders.sql`/skutečných producentech. Klientské formatter helpery v `festapp_core`; `OrderModel.toCustomerData` deleguje na ně. Metadata pole neveřejně joinovat setově, ne jedním veřejným RPC za každou položku. Rozšířit indexy podle skutečného query plánu na reprezentativní lokální historii.

**Migrace:** nový schema/func delta a grants ve forward manifestu; interní helpery bez client grants. Existující `get_notification_center_updates` nadále recheckuje položky proti snapshotu a vrací stejný obohacený DTO.

**Ověření/výstup:** `feed_test.sql`, rozšířené `contract_test.sql`, `projection_lifecycle_test.sql`, read-cursor concurrency. Více než 5 položek stejného typu/dne, více než jedna stránka, shodné časy, pozdě doručený starší event, více revizí jedné události, tenant/role/recipient/mute změny, neplatný cursor, dvě akce stejného názvu a legacy reader nad stejným snapshotem. Core testy pro whitespace, částečné jméno, email a prázdno. Žádné díry kvůli starému group preview limitu.

### 5. Flutter cutover a lokalizace

**Změny:** controller přepnout výhradně na feed, rozšířit typed `NotificationItem`, smazat `NotificationGroup` a `expand`, vykreslit ploché řádky pod akcí. Výpočet čistého row presentation soustředit do jednoho malého presenteru, ne duplikovat podmínky panel/bell. Upravovat jen potřebné komponenty a všech šest stávajících překladů. Error/recovery email/bank/capacity nesmějí ztratit původní význam ani detail. Read-only uživatel vidí historii pouze v dosavadních právech; info form row nezpřístupní editaci.

**Odstranění:** nový Flutter neobsahuje group cursor, načítání skupiny, kind/day accordion, symbol jako label fallback ani duplicitní mute menu. Staré group testy přepsat na skutečný feed kontrakt; security/ack/retention testy zachovat.

**Ověření/výstup:** rozšířit existující `notification_center_cases.dart`, registrované přes `default_locale_5_cases.dart` v `shared_default_3_test.dart`. Pokrýt stránkování bez díry, nové arrivals, revoked item, scoped reset, detail navigation, kontakt/count/missing form kontext, otevření/uzavření, unknown kind, dlouhý e-mail a 2x text při 320/719/720/1100 px. Počet testů musí být nenulový. Provést i existující navázané navigation suites v běžném a reverse pořadí. Skutečně prohlédnout render, neprohlašovat HTML mock za Flutter důkaz.

### 6. Integrační důkaz a uzavření ledgeru

**Změny:** lokální disposable tenant podle `festapp-local-e2e`, existující `test/browser/notification_center_e2e.dart` a fixture. Skutečný save -> SQL event -> osobní projekce -> feed -> panel. Dále scheduled start/end bez návštěvy administrace, otevření náhradníků, storno, jméno chybí, více stránek jedné akce a revokace. Vnější e-mail/banka zablokované, žádné produkční testovací objednávky. Aktualizovat oba notification README, architekturní odkazy a execution evidence; původní plán odkázat na tento jako náhradu UI/read části.

**Ověření/výstup:** omezený headless `agent-browser` v izolované session, přes repository E2E workflow. Zaznamenat mobil/desktop screenshot a přesný source revision/check receipt. Vyhodnotit ledger níže. Kompatibilní externí adapter zůstane výslovně evidovaný, dokud není doloženo vyřazení vydaných klientů. Neotvírat nový audit/subagent review bez zadání.

## Ledger odstranění a zachování

| Artefakt | Akce | Důkaz |
|---|---|---|
| `NotificationGroup`, `groups`, `expand`, per-group cursor/busy/loaded v novém Flutter toku | Smazat a nahradit item feed stavem. | Scoped rg + analyzer + widget test stránkování. |
| Accordion typ/den a opakované názvy/mute | Smazat. | Widget strom a skutečný render. |
| Order symbol/id jako viditelný fallback | Odstranit z prezentace; orderId zachovat pro autorizovaný detail. | Widget test bez symbolu a test detail navigace. |
| Nezávislé časové rozhodování v notification producentu | Nevytvářet; všichni volají společný availability snapshot. | SQL callers a parity mode testy. |
| „Prodej znovu otevřen“ jako capacity recovery, „Vyprodáno“ odvozené jen z `remainingPublic=0` | Nahradit pravdivým kapacitním textem; nepřidávat unread při recovery. | Localization/presenter scénáře a SQL episode test. |
| Group RPC/pole/group_key pro starší vydané klienty | Jediná omezená externí hranice; nový klient ji nevolá. Při doloženém vyřazení odstranit společně v samostatné forward kontrakci. | Consumer inventory, nulové nové client callsites, compatibility tests; případně drop/absence proof. |
| Stávající projector, recipient snapshot, activation/mute, update hydration, badge a cron | Zachovat jako jedinou infrastrukturu. | Dosavadní contract/concurrency testy + kontrola registrace jednoho cron ownera. |
| `NotificationCenterRollout.visibleToEveryone` | Zachovat existující preview politiku; toto zadání nepovoluje zapnutí všem. | Žádná změna rollout scope. |
| Historická migrace, bank/email fronta, obchodní data | Zachovat; nová forward migrace, žádné další business úložiště. | Migrační diff a clean/upgrade rehearsal. |
| Dočasné HTML/CSS z `/tmp` | Archivní vizuální reference je již v evidence složce; nikdy se nestává druhým produkčním UI. | Produkční code path vede výhradně přes Flutter komponentu. |

## Ověřovací sada při implementaci

Nespouštět testy kvůli samotnému napsání tohoto plánu. Následující příkazy jsou budoucí cílené brány, nikoli dnešní receipts. DB runner smí mířit jen na výslovně vybranou disposable lokální DB; `.env.local` s neurčeným cílem není povolená volba. Každý runner musí skutečně objevit a provést nenulový počet testů.

| Oblast | Příkaz / důkaz |
|---|---|
| SQL notification kontrakty | `pnpm --dir web_client exec node scripts/run_db_tests.js database/tests/notification_center/` s explicitním lokálním `DATABASE_URL`. |
| Souběh | `pnpm --dir web_client exec node --test ../database/tests/notification_center/read_cursor_concurrency.test.mjs ../database/tests/notification_center/form_availability_concurrency.test.mjs`. |
| Registrační režim/waitlist | Stejný SQL runner s konkrétními dotčenými soubory v `database/tests/eshop/` nalezenými přes `rg --files`; požadovat před/po časovou ekvivalenci a skutečný replay/rollback. |
| Core formatter | `cd packages/festapp_core && fvm dart test test/eshop/customer_label_test.dart`. |
| Flutter | `fvm flutter test --no-pub --concurrency=1 test/sessions/shared_default_3_test.dart --plain-name notification_center`, potom affected shared session v normálním a `FESTAPP_FIXTURE_ORDER=reverse` pořadí dle registračních pravidel. Společné dávky neduplikovat bez změny pokrytého kódu. |
| Analýza | `fvm dart analyze` s explicitními změněnými Dart soubory. |
| Migrace | Forward assembler `--check` dle vlny 1, atomická lokální upgrade rehearsal a čisté canonical bootstrap; nezávislá kontrola grantů, indexů a source parity. |
| Skutečné UI | Repository local E2E + izolovaný headless browser, obě šířky, žádný vlastní alternativní Playwright runner. |

Na workstation nejvýše jeden Flutter task včetně analyze/test/build/server, testy `--concurrency=1`; cizí task nezastavovat. Použít pnpm 11.24.0, při potřebě install jen `pnpm install --frozen-lockfile`. Dependency blocker řešit cíleně se zachováním authoritative lockfiles; neskrýt jej mockem ani tvrzením o prošlém UI.

## Rollout a návrat

Po samostatném oprávnění: ověřit skutečný tenant/backend activation a migration history, aplikovat jen nový prerequisite-kompletní forward delta, založit tichý baseline pro aktivní tenanty a ověřit due údržbu, pak vydat klienta. Existující activation/preview flag se automaticky nezapíná. Nový klient bez feed capability centrum bezpečně skryje; nemá skupinový fallback. Legacy klient může po dobu svého doloženého života použít jen explicitní serializační adaptér.

Při problémovém vydání použít existující hide/pause hranice a zachovat data. Nevracet nezávislý kalkulátor dostupnosti ani staré skupinové UI jako běžný feature fallback. Případné omezení jen nového availability evaluátoru má explicitně definovanou pauzu a tichý baseline při resume; nerozbít kvůli němu email/bank/projector cron. Destruktivní drop legacy RPC/sloupců až po doloženém ukončení jejich klientů, samostatnou forward migrací. Lokální implementace není potvrzení live nasazení.

## Rozhodnutí, předpoklady a zbývající rizika

- **Rozhodnuto:** ploché položky po akcích, žádné order symboly, sdílený kontakt fallback, počet podle form konfigurace a skutečného eventu, neutrální form lifecycle text, zachované kapacitní epizody, jeden SQL availability owner a jeden scheduler.
- **Předpoklad:** není k dispozici doložený konfigurační význam prodej vs přihláška. Bez něj je autoritativní neutrální text, nikoli odhad z ceny nebo max limitu. Implementátor může doložit existující explicitní metadata a využít je; nesmí přidat nový editor/feature mimo rozsah.
- **Předpoklad:** live starší klienti mohou existovat. Proto úzký externí adapter, žádný nový client fallback. Stav řeší release inventory, ne odhad podle lokálního kódu.
- **Riziko:** změna schedule mezi neprovedenými hranicemi vyžaduje uloženou starou konfiguraci a before-save drain; pouhý dnešní snapshot nestačí.
- **Riziko:** původní pending migrace má závislosti na jiné rozpracované funkci. Wave 1 musí určit přesný prerequisite, nikoli vydat celý pracovní strom.
- **Riziko:** historický event nemusí mít form/počet a objednávka může být smazaná. Bezpečná generická prezentace je přípustná; vymýšlená osobní nebo kapacitní data nikoli.
- **Provozní blokace:** produkční kroky vyžadují nové vydávací zadání a konkrétní tenant. Psaní a lokální implementace plánu tím blokované nejsou.

## Definice hotovo

- [ ] Plochý seznam nevynechá šestou a další událost stejného typu/dne, stránkuje po položkách a drží snapshot.
- [ ] Každá akce má jeden nadpis/mute, form změny jsou ve stejném chronologickém bloku, společné incidenty si zachovají vlastní scope.
- [ ] Kontakt fallback, absence symbolů, chybějící form data a smysluplné počty fungují na skutečných DTO, ne jen v maketě.
- [ ] Ruční i naplánované otevření/uzavření používají jeden SQL význam a producent; rollback/retry/concurrency neduplikují události a outage neztratí obě časové hranice.
- [ ] Upgrade/activate/resume/create/copy baseline je tichý, disabled/muted/revoked historie se nereplayuje a osobní oprávnění/ack invariance zůstávají.
- [ ] Kapacitní recovery nevydává falešné otevření prodeje; email/bank/waitlist navigace a provozní vlastníci zůstávají funkční.
- [ ] Nový Flutter nevolá grouped RPC ani neobsahuje accordion stav; případný externí legacy adapter má doloženého konzumenta/retirement gate.
- [ ] Forward migrace i canonical schema jsou reprodukovatelné, stará historie se nemění, clean/upgrade rehearsal a skutečné cílené testy prošly.
- [ ] Skutečný render a local E2E jsou doložené; stav produkční migrace, aktivace a nasazení je samostatně a pravdivě uveden.
