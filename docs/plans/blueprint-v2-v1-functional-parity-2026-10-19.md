# Úplnost funkcí plánku V1 při napojení V2

Inventura zdrojového kódu k 2026-10-19. Tento seznam doplňuje
[implementační plán V2](blueprint-v2-plan-2026-10-18.md), zejména vlny 7-9 a 10B.
Nové zadání vyžaduje zachovat všechny níže uvedené funkce V1, nejen ceny,
výměnu a vytvoření objednávky. Neznamená oprávnění k nasazení nebo ke změnám
skutečných objednávek. Inventura neověřuje stav nasazené databáze.

Spustitelnou integraci řídí [nový plán B](blueprint-v2-integration-plan-2026-10-19.md)
a jeho [execution prompt](blueprint-v2-integration-EXECUTION-PROMPT-2026-10-19.md).
Tento dokument zůstává akceptačním seznamem všech funkcí.

## Stav a pravidlo dokončení

V2 má samostatný geometrický editor a oba viewery, ale Festapp stále používá
`BlueprintTab`/`VenueSeatController` pro V1. Samostatné demo používá `DemoPrices`,
nikoli skutečné produkty, místa a objednávky. Žádná níže uvedená obchodní funkce
proto není označená jako integračně dokončená pouze na základě fungujícího dema.

Každý řádek je akceptační požadavek. Stav `čeká` znamená, že pro V2 není v této
inventuře doložen celý tok UI → host → server → obnovený stav. Při implementaci
se ke splněnému řádku doplní konkrétní test nebo reprodukovatelný důkaz.
Položku nelze vyřadit bez výslovného rozhodnutí. Nové UI nemusí kopírovat ovládací
prvky V1, musí ale zachovat jejich účinek. Chyby a nedostatečné ochrany V1 se
nepřenášejí jako požadované chování.

## Zdroje

- [Editor a jeho režimy](../../lib/components/blueprint/views/blueprint_editor_tab.dart): `handleSeatTap`, `saveChanges`, `loadData`, skupiny, výměna a objednávka.
- [Produkty a skupinové/individuální přiřazení](../../lib/components/blueprint/views/blueprint_product_dialogs.dart): `SelectProductDialog`, `EditProductDialog`, `GroupProductManagerDialog`.
- [Objednávka z míst](../../lib/components/blueprint/views/blueprint_create_order_dialog.dart): analýza konfliktů, storna, nové položky, součet, kontakt a odeslání.
- [Skupiny](../../lib/components/blueprint/views/blueprint_groups_panel.dart), [legenda](../../lib/components/blueprint/views/blueprint_legend.dart), [rozměry a podklady](../../lib/components/blueprint/views/blueprint_controls_bar.dart), [mobilní ovládání](../../lib/components/blueprint/views/blueprint_mobile_scroll_view.dart).
- [Model místa a administrátorské tooltipy](../../lib/components/blueprint/blueprint_object_model.dart), [skupiny a pojmenování](../../lib/components/blueprint/blueprint_group.dart), [stavy](../../lib/components/blueprint/blueprint_seat_state.dart), [načtení a propojení dat](../../lib/components/blueprint/get_orders_helper.dart).
- [Flutter zákaznický výběr](../../lib/components/blueprint/seat_reservation/widgets/seat_reservation_widget.dart), [webový zákaznický výběr](../../web_client/src/components/blueprint/blueprint_selector.js), [webová příprava dat](../../web_client/src/components/blueprint/blueprint_data_preparer.js), [veřejné tooltipy](../../web_client/src/components/blueprint/tooltip_provider.js).
- [Form RPC adapter](../../lib/components/forms/db_forms.dart), [form commands](../../lib/components/forms/supabase_form_commands.dart), [ticket commands](../../lib/components/eshop/ticket_commands.dart), [objednávkové operace](../../lib/components/eshop/db_eshop.dart), [objednávkový transport](../../lib/components/eshop/db_orders.dart).
- SQL doména: [uložení V1](../../database/functions/eshop/update_blueprint.sql), [analýza míst objednávky](../../database/functions/eshop/analyze_new_order_spots.sql), [výměna a finanční přepočet](../../database/functions/eshop/swap_spot_tickets.sql). Tyto doménové implementace nejsou pokynem obejít jejich aktuální command/receipt fasády.

## A. Produkty a ceny

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| P01 | Nabídka místových produktů dané akce, názvy, formátovaná cena a označení aktuálního produktu. Přirozené řazení nabídky. | čeká |
| P02 | Vytvoření místového produktu včetně převzetí odpovídajícího typu/kontejneru akce z existujícího produktu; ošetřit chybějící výchozí produkt. | čeká |
| P03 | Úprava názvu a ceny existujícího katalogového produktu. Rozlišit okamžité uložení katalogu od rozpracovaného přiřazení v plánku. | čeká |
| P04 | Validace neprázdného názvu a nezáporné číselné ceny; zachovat měnu a formátování hosta. Server je autoritou částek. | čeká |
| P05 | Jedním krokem přiřadit produkt celé skupině a skutečně jej promítnout do všech jejích míst. | čeká |
| P06 | Přepsat produkt jednotlivého místa bez změny ostatních míst skupiny. | čeká |
| P07 | Rozpoznat jednotný i smíšený produkt skupiny; zobrazit odpovídající cenu, stav a seznam individuálních přiřazení. | čeká |
| P08 | Obsluha skupiny bez míst, skupiny bez produktu a místa bez přiřazení; nevytvářet tichou cenu 0 ani demo cenu 250. | čeká |
| P09 | Nové místo zdědí produkt vybrané skupiny / dosavadní fallback V1. Případnou změnu tohoto pravidla výslovně rozhodnout, nikoli ji skrýt migrací. | čeká |
| P10 | Ochrana objednaných, použitých a rezervovaných míst při hromadných i individuálních změnách; ověřit skutečná pravidla serverového ownera. | čeká |
| P11 | Změna katalogové ceny není lokální přepsání historické ceny prodané vstupenky. Finanční účinky změny místa řeší existující order/swap owner. | čeká |

## B. Skupiny, místa a stavy

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| S01 | Vytvořit skupinu s názvem, stabilní identitou a přirozeným řazením. | čeká |
| S02 | Výběr skupiny zvýrazní odpovídající místa; zobrazit počet míst a produkt/cenu či smíšený stav. | čeká |
| S03 | Smazání skupiny odstraní její volná místa, ale nesmí odstranit chráněná/obsazená místa. | čeká |
| S04 | Přidat prodejné místo do vybrané skupiny; převzít produkt a vytvořit výchozí označení podle skupiny a posloupnosti písmen. | čeká |
| S05 | Zablokovat místo/plochu, vytvořit volné místo a odstranit místo/plochu. V2 musí nabídnout obchodní ekvivalent i bez mřížky V1. | čeká |
| S06 | Chránit `ordered`, `used`, cizí `selected` i vlastní `selectedByMe` při strukturálních změnách. Server rozhoduje o aktuálním hold stavu. | čeká |
| S07 | Rozlišit všech sedm stavů V1: empty, available, selected, selectedByMe, ordered, used, blocked. Legendy, počty, klikatelnost a zvýraznění mají odpovídat datům. | čeká |
| S08 | Přepnutí/vypnutí režimu i obnovení dat vyčistí dočasný výběr pro swap/objednávku a vrátí skutečný stav míst. | čeká |
| S09 | Administrátorský detail místa: produkt, označení, cena; u prodaného místa také symbol vstupenky, zákazník, objednávka, další produkty a veřejné/interní poznámky podle oprávnění. | čeká |
| S10 | Obchodní skupina V1 se nesmí automaticky zaměnit za libovolný geometrický parent V2. Tabulka vazeb určí členství a jeho změny. | čeká |

## C. Výměna / přesun vstupenek

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| W01 | Dvoufázový výběr míst, vizuální označení obou, zrušení opakovaným klikem a potvrzení se souhrnem zákazníků/vstupenek. | čeká |
| W02 | Odmítnout prázdnou/blokovanou plochu, stejné místo, neexistující ID a místa z různých akcí. | čeká |
| W03 | Dvě obsazená místa: prohodit přiřazení vstupenek, zachovat identity vstupenek a příslušných objednávek. | čeká |
| W04 | Obsazené ↔ volné: přesunout vstupenku na volné místo. Dvě volná místa jsou serverový no-op. | čeká |
| W05 | Produkt patřící fyzickému místu zůstává na místě; vstupenka přijme cílový produkt přes serverovou operaci. Neprohazovat ceny pouhou výměnou UI barev. | čeká |
| W06 | Rozdílné ceny/produkty: zachovat přepočet položek, celku objednávky, platební částky/stavu a historie podle stávající SQL domény. Ověřit obě vstupenky ze stejné i různých objednávek. | čeká |
| W07 | Stejné produkty, různé stavy vstupenek, již použitá vstupenka a aktuální rezervace: doložit pravidla, identitu a metadata podle autoritativního ownera. | čeká |
| W08 | Úspěch obnoví data. Zamítnutí, síťová chyba a opakovaný submit nesmějí zanechat zdánlivě provedenou výměnu ani dvojitý finanční účinek. Použít stávající command receipts/sync. | čeká |

## D. Vlastní objednávka z výběru

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| O01 | Vícenásobný výběr skutečných míst, odebrání opakovaným klikem, počet vybraných a potvrzení dostupné až pro neprázdný výběr. | čeká |
| O02 | Výběr může obsahovat již objednaná místa; nejde jen o nákup dosud volných míst. Blokovaná plocha ani geometrická dekorace není objednatelná. | čeká |
| O03 | Před odesláním spustit `analyze_new_order_spots`, zobrazit nové položky/produkty/místa a celkovou cenu. Všechna místa musí patřit téže akci. | čeká |
| O04 | Zobrazit konflikty po původních objednávkách: dotčené vstupenky, zákazník, produkty, částky a úplné versus částečné storno. | čeká |
| O05 | Zachovat upozornění, že se neposílá storno e-mail, i existující vysvětlení finančních důsledků v dialogu. | čeká |
| O06 | Kontaktní e-mail, validace, zrušení dialogu a ochrana proti zavření/opakovanému odeslání během submitu. Chyba umožní opravu/opakování. | čeká |
| O07 | Potvrzení použije `DbEshop.createOrderFromSpots` → `DbOrders.replaceTicketOrder`, tedy existující Edge/command hranici; nevytvářet nezávislý klientský order engine. | čeká |
| O08 | Po úspěchu vyčistit výběr a obnovit objednávky/stavy. Při konfliktu mezi analýzou a potvrzením rozhoduje server, nikoli zastaralý součet náhledu. | čeká |

## E. Zákaznický výběr ve Flutteru i na webu

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| C01 | Stejné ID místa, produkt, cena a dostupnost v obou klientech. Zachovat napojení výběru na formulář, položky a součet objednávky. | čeká |
| C02 | Výběr i odvýběr přes `select_spot`/stávající session boundary se secretem, expirací a kontrolou vlastnictví hold. Geometrický výběr sám nic nerezervuje. | čeká |
| C03 | Optimistický vzhled s návratem po konfliktu/chybě; zabránit souběžným opakovaným klikům na jedno místo. | čeká |
| C04 | Obnovit vlastní výběr při znovuotevření, převzít serverem vrácený secret a zachovat soulad s payloadem formuláře. | čeká |
| C05 | Zachovat limit vstupenek a dostupnost produktů/prodejních vln podle pravidel hosta. Zobrazené místo není automaticky prodejné. | čeká |
| C06 | Pokračování/zavření vrací aktuální výběr; zpracovat i neúspěšné načtení a nedostupný plánek bez falešného potvrzení. | čeká |
| C07 | Veřejné tooltipy zobrazují jen veřejná data. Administrátorské interní poznámky, zákazníci a cizí objednávky nesmějí přejít do veřejné projekce. | čeká |
| C08 | Desktop/mobil, pan/zoom/fit, ovládání dotykem a myší, neztratit výběr při překreslení a korektně uvolnit handlery při zavření. Geometrie V2 již existuje, host tok je nutné doložit. | čeká |

## F. Uložení, načtení a provozní pravidla

| ID | Povinně zachovat / doložit | Stav V2 |
|---|---|---|
| U01 | Načíst plánek pro danou akci, objekty, produkty, skupiny a oprávněná order/ticket metadata. Výběr míst veřejně a administrátorsky používá správnou projekci. | čeká |
| U02 | Uložit a zahodit změny; dirty stav zahrnuje rozměry, podklad, členství a produktová přiřazení. Odlišit neuložený draft od okamžitých objednávkových operací. | čeká |
| U03 | Zachovat existující `spot.id` při pohybu, rotaci, změně tvaru a přečíslování. Nové místo dostane novou identitu, kopie nikdy nepřevezme objednávku/hold původního místa. | čeká |
| U04 | Uložit vazby a geometrii konzistentně; konfliktní revize, neplatný/cizí produkt a chráněné odstranění se musí vrátit bez částečných změn. | čeká |
| U05 | Použít stávající `update_blueprint_client_sync_v1` / `FormCommands.saveBlueprint`, receipt a sync publication; neobejít je přímým zápisem nové geometrie. | čeká |
| U06 | Zachovat možnost změny rozměrů a vložení/odstranění SVG či obrazového podkladu. V2 má bohatší nástroje, ale musí fungovat jejich uložení v hostu. | čeká |
| U07 | Read-only a editační oprávnění, odděleně objednávkové operace; serverová kontrola scope/akce je povinná i při skrytých UI tlačítkách. | čeká |
| U08 | Přeložitelné popisky/hlášky, formát ceny/měny, úspěch/chyba/načítání a mobilní dostupnost všech obchodních akcí. | čeká |
| U09 | Prototyp/demo nevolá živé swap/order/product operace a je viditelně označené. Funkční ukázka není dokladem persistence ani oprávnění. | čeká |

## Navíc zachovat už zadané chování V2

Tyto body nemají úplný ekvivalent V1, proto je nelze prohlásit za splněné paritou:

- Gauč / atomická jednotka: společné select/release, objednávka, storno, swap a náhrada bez napůl prodejné jednotky; jednotlivé vstupenky zůstávají identifikovatelné a skenovatelné.
- Stání po kusech: produktové inventory a množství používají stávající ledger; změna stepperu nesmí předstírat rezervaci konkrétního sedadla.
- Kulatý, obdélníkový i vlastní stůl, řady, dopravní sestavy a volná židle používají stejnou stabilní seat → spot vazbu.
- Historie změn geometrie/produktového draftu nesmí odvolat či znovu odeslat již potvrzenou serverovou objednávku. Geometrické a obchodní operace mají jasné hranice.
- Backendové změny, veřejné projekce a oba klienti se ověřují společně; samotný úspěch Flutter dema neuzavírá host integraci.

## Známé pasti, které inventura odhalila

1. `_performSwap` ve V1 upravuje místní stavy ještě před dokončením RPC. Po chybě je ve V2 nutné obnovit autoritativní data nebo vrátit změnu; tento nedostatek není požadovaná parita.
2. Skupinový `product` je ve V1 přechodové pole; produkt se materializuje do míst. V2 nesmí při načtení odvodit nesprávnou cenu pouze z geometrického rodiče.
3. Produktový katalog se může uložit už v dialogu, zatímco přiřazení míst čeká na uložení plánku. Zrušení geometrického draftu není automatické storno katalogové úpravy.
4. Zdrojové SQL soubory obsahují doménu i historické wrappery. Před implementací se ověří aktuální fasáda/transport a testy; nevybírá se RPC jen podle podobného názvu.
5. Order tooltips obsahují osobní a interní data. Veřejný renderer nesmí dostat administrátorský payload a teprve ho lokálně skrývat.

## Existující důkazy a následná validace

Výchozí regrese:
[editorové akce](../../test/components/blueprint/blueprint_editor_actions_cases.dart),
[draft produktů](../../test/components/blueprint/blueprint_draft_product_cases.dart),
[metadata objednávek](../../test/components/blueprint/blueprint_order_metadata_cases.dart),
[seat adapter](../../test/components/blueprint/blueprint_seat_adapter_cases.dart),
[kapacita formuláře](../../test/components/forms/form_blueprint_capacity_cases.dart),
[webové načtení](../../web_client/tests/components/blueprint_loading.test.js) a
[webový viewport](../../web_client/tests/components/blueprint_viewport.test.js).
Jsou to zdroje existujících scénářů, nikoli důkaz jejich průchodu na V2.

Pořadí implementace: stabilní bindingy a konzistentní save/read → produkty a
skupiny → režimy/ochrany stavů → objednávka a swap → oba zákaznické pickery →
integrační regression. Finanční/rezervační scénáře navíc potřebují skutečné
serverové testy atomity, oprávnění, dvojitého odeslání a souběhu; nejsou nahraditelné
mockem UI. U každého dokončeného řádku zaznamenat vlastníka, test a výsledek.
