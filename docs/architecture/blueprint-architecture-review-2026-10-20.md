# Posouzení blueprintů, stylování a prodejního modelu

Následné hlubší ověření a autoritativní plán pro aktuálně zadaný rozsah do
1 000 lidí jsou v [plánu integrity](../plans/blueprint-1000-integrity-plan-2026-10-20.md).
Obsahuje skutečné SQL a browser důkazy, které nahrazují původní předběžný stav
ověření níže. Stadionová rozšíření nejsou součástí aktuálního zadání.

Datum: 2026-10-20. Rozsah: aktuální pracovní strom Festappu a lokální
`../venue_seat_picker`, včetně rozpracovaného V2. Read-only posouzení implementace;
nejde o potvrzení nasazeného stavu. Produkční DB, RLS/granty za běhu ani produkční
CSP nebyly ověřovány. Aplikační kód a databáze nebyly změněny.

## Závěr

Směr architektury je správný: přenositelný dokument geometrie, společné jádro
pro Flutter a JS a samostatná databázová autorita pro produkty, rezervace a
objednávky. JSONB je pro grafický dokument vhodný. Obchodní vztahy mají zůstat
relační. Kompletní přepis ani druhý rezervační systém nedoporučuji.

Současný stav ale nelze označit za hotovou, bezpečnostně ověřenou platformu
pro stadiony. Nový geometrický model ještě není napojený na současný prodejní
model Festappu. Existuje konkrétní nebezpečná SVG cesta a slabší kontroly
rezervace při dokončení objednávky. Stadion potřebuje také členění načítání,
trvalou adresu místa a provozní měření při náporu zákazníků.

## Co už je navrženo dobře

- V2 používá stabilní UUID uzlů, immutable dokument, verzi schématu, validaci
  referencí, cyklů, čísel a velikosti. Import neznámého schématu není tichý downgrade.
  Viz `../venue_seat_picker/packages/venue_layout_core/lib/src/model.dart:34,119,225,275,384`.
- Geometrie, styly a serverový stav jsou odlišné vstupy. Stav obsazení se nemusí
  přepisovat do uloženého grafického dokumentu. Sdílený scene compiler zmenšuje
  riziko odlišné geometrie ve Flutteru a na webu. Viz `scene.dart:245,332`.
- Globální vzhled podle druhu objektu a explicitní lokální výjimky dávají
  předvídatelné dědění. `effectiveNodeProperties` a `setLayoutAppearance` mají
  jednoznačnou autoritu; změna celého tématu nemusí přepsat každou židli.
  Viz `model.dart:1747`, `operations.dart:2934`.
- SQL save ověřuje příslušnost produktu a místa k akci, zamyká místa a chrání
  držená/prodaná místa proti odstranění či změně produktu. Receipts řeší opakování
  příkazu a subtransakce odmítnutou změnu vrací zpět. Nový save klient posílá
  očekávanou verzi. Viz `database/functions/eshop/update_blueprint.sql:8-57`
  a `update_blueprint_client_sync_v1.sql:20-67`.
- Veřejná projekce explicitně skládá pole spotů a nevrací rezervační secret ani
  objednávky. Admin data jsou v jiném RPC. To je správná hranice, kterou zachovat
  i pro V2. Viz `database/functions/eshop/get_blueprint.sql:60-80`.

## Nálezy podle priority

### 1. Vysoká: nevyčištěné SVG vstupuje do veřejného DOM

`update_blueprint.sql:77` ukládá `background_svg` bez sanitizace;
`get_blueprint.sql:45` ho poskytuje veřejnému pickeru.
`web_client/src/components/blueprint/svg_utils.js:22-55` pouze parsuje a serializuje,
`blueprint_renderer.js:115` výsledek vloží přes `innerHTML`.

Při lokální sondě s JSDOM zůstaly zachovány `onload` i `foreignObject`.
To dokládá chybějící sanitizaci, nikoli spuštění exploitu v produkčním prohlížeči.
Editor/importované SVG tak překračuje hranici do kódu veřejné stránky. Dopad
závisí také na nasazené CSP. Obecné chování injection sinku popisuje
[MDN innerHTML](https://developer.mozilla.org/en-US/docs/Web/API/Element/innerHTML).

Oprava: pro pozadí preferovat ověřený obrázek přes spravovaný asset reference.
Je-li inline SVG potřeba, použít udržovanou sanitizaci s explicitním SVG profilem,
omezením aktivních elementů, událostí a externích referencí. Parsování XML samo
není sanitizace. Přidat regresní kontrolu celého save/read/render toku.

### 2. Vysoká: dokončení objednávky nedokládá platný hold ve správném plánku

`database/functions/eshop/finalize_ticket_order.sql:190-206` načítá spot podle
ID a occasion, kontroluje obsazení a rovnost secretu. V této větvi chybí ověření
`spot.blueprint = form.blueprint`, nenulového secretu a budoucí expirace.
Při obou NULL hodnotách `IS DISTINCT FROM` neodmítne požadavek.
Veřejná fasáda `create_ticket_order_client_sync_v1.sql:11-19,66-69` tuto podmínku
nedoplňuje. Sousední `lock_ticket_order_products_internal` zamyká produkty a
inventory, neověřuje uvedený hold (`eshop_waitlist/tickets.sql:22-35`).

Staticky tedy chybí garance, že veřejná objednávka kupuje právě místo aktuálního
formuláře s dosud platnou rezervací. Nejde o tvrzení, že bylo prokázáno dvojí
prodání. Pozdější produktové a inventory kontroly mohou konkrétní vstup odmítnout.

Doporučení: veřejné dokončení má pod zámkem místa ověřit celý invariant
formulář/blueprint/spot/secret/expirace. Administrativní prodej má mít explicitní
oprávněnou výjimku. Ověřit SQL integračně NULL secret, expirovaný hold, jiný
plánek stejné akce a souběh dokončení s novým držením místa. `select_spot.sql`
samotné má row lock, který finální obchodní cesta musí respektovat také.

### 3. Vysoká před použitím V2: geometrie a prodej ještě nejsou integrovány

Festapp stále serializuje `objects/groups/configuration/background_svg`,
`BlueprintObjectModel` používá integer x/y a spot ID, databáze má původní
`eshop.blueprints` (`database/tables/tables.sql:575`, `blueprint_object_model.dart:58`).
Host používá `VenueSeatController`, nikoli nový `VenueLayoutController`
(`blueprint_editor_tab.dart:76,108,229`). V2 dokument má samostatná UUID,
world transforms, sekce a selection units.

Není správné převést nový dokument jen do staré mřížky nebo do libovolného
`data` a tak deklarovat integraci. Ztratil by se význam souřadnic a identit.
Existující integrační plán z 2026-10-19 správně navrhuje layout + revision
a relační node-to-spot bindings; tyto části zatím nejsou aktuálním kontraktem SQL.
Samostatný balíček geometrie proto dnes není důkaz dokončeného ticketingu V2.

### 4. Střední: server validuje obchodní vazby, nikoli celý grafický kontrakt

`update_blueprint.sql:17-38,71-78` nekontroluje úplné schéma souřadnic,
rozměrů, skupin a konfigurace. Mimo kontrolované obchodní reference ukládá
libovolná grafická pole. Veřejný reader vrací i `b.data` a raw grafická pole
(`get_blueprint.sql:40-45`). Ochrana standardních spot secretů je dobrá, ale
libovolná metadata se tím nestávají soukromými.

V2 validátor na klientovi nestačí. Serverový save musí odmítnout neplatný dokument
a vazby před zápisem, s omezením bytes/počtů/hloubky. Veřejná projekce má používat
povolený seznam polí; interní metadata nesmí bydlet ve veřejném dokumentu.
Nemá vzniknout druhý ručně odlišný geometrický engine v SQL, ale musí existovat
důvěryhodná validační hranice a databázové kontroly obchodních invariantů.

### 5. Střední: adresa prodaného místa a konflikt verzí nejsou důsledně chráněné

Save chrání produkt obsazeného místa, ale jeho title přepsat dovolí
(`update_blueprint.sql:47-64`). Historická objednávka ukládá `spot_title`
(`finalize_ticket_order.sql:330-346`), zatímco jiné projekce čtou aktuální spot.
Přejmenování tedy může způsobit rozdílné údaje na starší vstupence a při obsluze.
Pro stadion musí být odlišná trvalá identita, prodejní adresa a dekorativní popisek.
Přejmenování prodaného místa potřebuje řízenou změnu a dohledatelnou historii.

`update_blueprint_client_sync_v1.sql:47` při chybějící očekávané verzi použije
aktuální verzi. Je to doložená kompatibilita starších klientů, ale umožňuje
přepsání souběžné editace. V novém kanonickém V2 save vyžadovat baseline vždy.

### 6. Omezení rozsahu: velký stadion dnes není podporovaný jedním dokumentem

Starý SQL save má limit 10 000 objektů (`update_blueprint.sql:18`), V2 core
20 000 sedadel a 25 000 uzlů (`model.dart:34-37`). Obě hranice jsou dalšími
objekty zmenšovány a nejde o výkonnostní garanci. Stadion s 40 000-60 000 místy
nelze řešit pouhým zvýšením konstanty.

Veřejný `get_blueprint` načítá celý dokument i všechny spoty a produktovou projekci;
produktový join navíc vrací stejný produkt pro každé odpovídající místo
(`get_blueprint.sql:82-94`). To zbytečně zvětšuje payload.
Admin save zamyká všechny produkty akce a všechna místa plánku
(`update_blueprint_client_sync_v1.sql:38`, `update_blueprint.sql:44`).
Seed limity holdů jsou 1 000/min na unit, 5 000/min na organizaci a 20 aktivních
na buyer UUID (`abuse/seeds.sql:53-55`); skutečná efektivní politika nebyla čtena.
Náhodně měnitelný buyer UUID není samostatná ochrana proti botům.

Pro stadion doporučuji přehled areálu a samostatně načítané sektory,
cacheovatelnou statickou geometrii oddělenou od dostupnosti a malé aktualizace
stavů. Globální kapacita a prodej zůstávají v existující obchodní autoritě.
Zátěžové ověření má zahrnout nárazový prodej, čekání na zámky, expirace,
velikost payloadu i slabší mobil. Konkrétní SLA zatím nebylo prokázáno.

## Cílové hranice dat pro vstupenky.online

| Vrstva | Co má vlastnit |
| --- | --- |
| Přenositelný layout | UUID, geometrii, vizuální hierarchii, styly, popisky, resource references |
| Opakovaně použitelný areál | Šablonu a její verze, trvalé fyzické identity a adresy míst |
| Konkrétní akce | Zvolenou publikovanou revizi layoutu, node-to-spot vazby, zpřístupněné sektory |
| Obchod | Produkty/ceny, cenové zóny, konkrétní spoty, holds, kapacitu stání, objednávky |
| Odbavení | Platnost vstupu, oprávněné brány/zóny, pravidla opakovaného vstupu |

Pro opakované koncerty a zápasy má akce odkazovat na konkrétní snapshot/revizi.
Úprava šablony stadionu nesmí zpětně změnit již prodaný zápas. Stabilní fyzická
identita může procházet akcemi, ale spot a dostupnost jsou vždy konkrétní akce.
Plný model areálu lze odložit do chvíle skutečného opakovaného použití; stabilní
identity a verzování je potřeba zachovat už při integraci V2.

Sekce, cenová zóna, grafická skupina a nedělitelná prodejní jednotka jsou rozdílné
vztahy. VIP barva nemá určovat cenu ani oprávnění ke vstupu. Stání se má opírat
o množstevní inventory, ne o tisíce falešných židlí. Nedělitelná skupina míst
musí být atomická i na serveru při hold/finalize/swap/replace/storno.

Současné dědění stylů po druhu objektu je rozumné. Lokální výjimky jsou explicitní,
stav obsazení se přidává až při vykreslení. Pro budoucí tematizaci sektorů případně
doplnit jedinou deklarovanou vrstvu mezi stylem dokumentu a lokální výjimkou.
Nezavádět obecnou CSS kaskádu ani odvozování obchodních vlastností z barev.
Změnu velikosti/rozestupů židlí chápat jako změnu geometrie s kontrolou identity
a kolizí, ne jako pouhé přebarvení.

## Doporučené pořadí

1. Uzavřít SVG cestu a doložit platnost holdů při veřejném dokončení objednávky.
2. Dokončit existující integrační plán V2: jeden geometrický kontrakt, bindings,
   revize, serverová validace, oddělené veřejné/admin projekce a atomické units.
3. Upevnit adresu místa a publikované revize pro opakované akce.
4. Před prvním velkým stadionem doplnit načítání sektorů a zátěžová měření;
   podle skutečných výsledků upravit SQL, payloady a admission politiku.

## Provedené ověření a meze

- Statická kontrola modelu, stylového resolveru, rendererů, host adaptérů,
  SQL save/read/hold/finalize/swap a existujícího integračního plánu.
- `node --test tests/components/blueprint_loading.test.js tests/components/blueprint_viewport.test.js`
  v `web_client`: 8/8 prošlo. Testy nedokládají SQL bezpečnost ani V2 integraci.
- JSDOM sonda skutečného `SvgUtils.prepareBackgroundSvg`: zachovává event
  atribut a `foreignObject`; aktivní kód nebyl spouštěn.
- SQL scénáře z nálezu 2, produkční oprávnění, skutečné nasazení a stadionová
  zátěž nebyly testovány. Nálezy vycházejí z lokálního kódu, ne z incidentu.
