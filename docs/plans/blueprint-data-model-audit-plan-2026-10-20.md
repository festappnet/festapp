# Plánek: audit datového modelu a plán stabilizace před rozšířením používání

> Pro další realizaci nahrazeno plánem
> [kanonického renderu a kvalitních fontů](blueprint-canonical-rendering-fonts-plan-2026-10-20.md).
> Ten je jedinou aktuální autoritou a zachovává níže uvedenou původní acceptance
> jako přílohu. Původní odklad skutečných font faces/shaping již neplatí.

Datum: 2026-10-20. Stav: rozpracovaná realizace; vlna 1 částečně implementována, její exit brána znovu otevřena po kontrole; vlny 2-7 dosud neprovedeny.
Ověřování: `standard` - veřejný formát, dědění produktů a budoucí migrace.

## Stav realizace 2026-10-20

Vlna 1 má opravu scoped-font SQL dependency closure, strukturální validaci appearance,
fontový sběr v hostu a save/read/setup/copy corpus ověřený ve Flutteru i
skutečném distribuovaném JS kernelu. Podrobnosti, příkazy a omezení:
[evidence realizace](evidence/blueprint-data-model-implementation-20261020.md).

Změněný předpoklad: přibalený npm artefakt 0.2.2 odmítal appearance fontId,
přestože package baseline jej už podporuje. Pro výstupní bránu první vlny byl
z přesné package baseline sestaven lokální 0.2.3 a aktualizován host vendor/lock.
Není to dokončení vlny 7 ani vydání kontraktu 2. Původní archiv zůstal nezměněn.

Vlny 2-7, cílový jediný interní model 2, TX2, převodní corpus i UI/PF brány
zůstávají otevřené. Žádný produkční převod, deployment, commit ani push neproběhl.
Následující cílový kontrakt a zbývající acceptance se tím nemění.

Opakovaná architektonická kontrola potvrdila dvě dosud neuzavřené mezery první
vlny: SQL validátor přijme duplicitní appearanceOverrides odmítané core/kernelem,
a dependency collector neobsahuje odvozený text capacity badge. Na platném
atomic furniture dokumentu prošla SQL validace, ale distribuovaný kernel vydal
`glyph_unavailable` pro `×`. Vlna 1 proto nemá úplný exit důkaz. Viz opakovaná
kontrola v odkazované implementační evidenci. Dosavadní corpus dokazuje úzký
scoped-font průchod, nikoliv úplnou rovnost scén/paths mezi runtimy.


## Závěr

Zachovat hranici přenositelné geometrie / obchodního hostu / transakční SQL.
Před zmrazením uloženého formátu sjednotit styly a jejich dědění, autorský
záměr umístění židlí, reprezentaci vlastního obrysu a verzování validace.
Nejbližší konkrétní chyba je neúplný serverový sběr fontů: nově přidaný font
v `appearance.table.fontId` editor připraví, ale reader jej nevrátí.
Druhá nevratná ztráta informace je nerozlišení zděděného a ručně zvoleného
produktu, jestliže mají právě stejnou hodnotu.

Jde o audit zdrojů a izolované modelové reprodukce. Žádný plánek ani databáze
nebyly změněny. Dosavadní úspěšná UI kontrola sama neprokazuje round-trip přes SQL.

## Rozsah a pevný bod

- Festapp: `a3a0637d8eeec1b0d5d3a5292e6db62fdcb4f5d1`, pracovní kopie
  `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`.
- Package: `0b881853bd9071784fd66102a03a1606a81afa79`, pracovní kopie
  `/Users/miakh/source/venue-seat-picker-blueprint-b-20261019`.
- Editor, core, JS kernel, SQL save/read/resources, setup/copy, historie a
  převod existujících dokumentů. Ne nový rezervační, finanční nebo sync systém.
- Tento dokument navrhuje změny. Neopravňuje produkční migraci, deployment,
  hromadné převody skutečných plánků, commit ani push.
- Historický inventář 49 plánků v `docs/plans/evidence/blueprint-b-20261019/`
  je důkaz z předchozího průzkumu, ne dnešní ověření produkčního schématu.

## Inspirace a vlastní rozhodnutí

- [SVG 2 styling](https://www.w3.org/TR/SVG/styling.html): definovaná priorita
  stylových deklarací a dědění. Převzít princip rozlišení deklarované a výsledné
  hodnoty. Níže navržené pořadí vrstev je naše doménové rozhodnutí, nikoli
  implementace celé CSS kaskády.
- [tldraw persistence](https://tldraw.dev/docs/persistence) a
  [migrations](https://tldraw.dev/sdk-features/persistence): oddělení dokumentu
  a uživatelské session, schema metadata a explicitní převody vlastností.
- [tldraw bindings](https://tldraw.dev/sdk-features/bindings): samostatné vztahy
  mezi stabilními identitami a jednotný životní cyklus při copy/delete.
- Existující Ticket Editor: katalog a ověřené fontové zdroje. Jeho použití
  neřeší automaticky správný výběr zdrojů v blueprint SQL readeru.

Z těchto zdrojů neplyne potřeba převzít jejich SDK, React, CSS engine nebo CRDT.

## Co je správně a zůstává

| Oblast | Potvrzené vlastnictví | Zachovaný invariant |
| --- | --- | --- |
| Geometrie | Core `VenueLayoutDocument`, immutable uzly, parent transformace | Stabilní UUID, plánek bez produktů, cen, holds a zákazníků |
| Obchod | Host `BlueprintLayoutSnapshot`, seat/area bindings | `nodeId` a `spotId` mají odlišné role; přesun nemění spot/ticket identitu |
| Ukládání | `BlueprintLayoutSaveRequest`, `BlueprintLayoutSaver`, SQL `save_blueprint_layout_impl_internal` | Jedna revize geometrie i bindingů, zmrazený retry payload a command ID |
| Peníze a rezervace | Existující SQL příkazy, spots, inventory a receipts | Žádná druhá autorita v rendereru; žádný přepočet peněz v core |
| Zobrazení | Core `compileScene`, Flutter painter a JS SVG adaptér | Společná geometrie a vektorové glyphy; editovatelný text zůstává textem v modelu |
| Session | Kamera, výběr, pending a prezentace mimo dokument | Hover a obsazenost nemění dirty/revision/undo |
| Autorské sestavy | Parametry a vazby + materializovaná geometrie | Renderer nepřerovnává sedadla při obyčejném načtení |

## Potvrzené nálezy

### F1 - Blokuje vydání: fontové závislosti se mezi vrstvami liší

`lib/components/blueprint/views/blueprint_layout_host.dart:_prepareFonts` sbírá
fonty také z `document.appearance`. Naproti tomu
`database/functions/blueprint/resources.sql:blueprint_layout_resources_internal`
vybírá jen `defaultTextStyle.fontId` a `nodes[].fontId`.
`validation.sql:validate_blueprint_layout_internal` kolem řádku 170 ověřuje
stejnou neúplnou dvojici, navíc bez respektování priority `appearanceOverrides`.

Konkrétní scénář: nastavit pro stoly font B, který není současně výchozím nebo
lokálním fontem žádného uzlu. Před uložením jej host má. SQL reader jej po
znovunačtení nevrátí; core pro takový label vrací `font_unavailable`.
Toto je zdrojově prokázaná chyba v uzavření závislostí, ne domněnka o konkrétním
produkčním záznamu. Server také povoluje top-level `appearance`, ale nevaliduje
jeho vnitřní strukturu stejně jako core.

**Nutné nyní:** společná sémantika výsledného fontu a úplný dependency collector;
serverové testy save -> read -> scene pro scoped font a lokální výjimku.

### F2 - Blokuje zmrazení záměru: produktové dědění se odhaduje rovností

`blueprint_layout_controller.dart:applyGroupsProduct` považuje místo za zděděné,
když `seat.productId == oldGroupDefault`. `BlueprintSeatBinding` ani
`eshop.blueprint_seat_bindings` neukládají režim přiřazení.

Ručně zvolený produkt A je proto nerozlišitelný od zděděného A. Při změně
skupiny na B se může změnit i ruční volba. Obráceně při cyklu A -> B -> A
může původní výjimka splynout se zděděnými místy. Pozdější migrace tuto
informaci ze samotných hodnot nezrekonstruuje.

**Nutné nyní:** explicitní host/SQL assignment mode `inherit` nebo `override`.
Aktuální `spots.product` zůstává provozní a finanční autoritou. Mode řídí
budoucí explicitní aplikaci defaultu, ne dynamické přecenění při renderu.
Protected/free-only pravidla nadále mohou ponechat skutečný produkt odlišný
od aktuálního defaultu; nesmějí proto samovolně změnit uložený režim.

### F3 - Vysoká priorita: style má dvě reprezentace a chybí dědění v sestavě

`model.dart:effectiveNodeProperties` přepisuje lokální properties typovým stylem
a lokální hodnotu vrací teprve maska `appearanceOverrides`. Lokální properties
současně obsahují factory defaults, importovaný vzhled a skutečné ruční změny.
`defaultTextStyle` se přimíchává až v dalších callerech, například ve scéně.

Izolovaná reprodukce: výchozí velikost 24, na uzlu uložené 40, společná 36.
Po odstranění společného nastavení se vrátí 40. Chybějící lokální deklarace
nemá jednotný význam „dědit“; může odkrýt starou skrytou hodnotu.

`widgets/layout_style.dart:applyLayoutAppearance` kopíruje styl do nynějších
židlí, ale stůl neukládá default jejich vzhledu. `operations.dart:reflowTable`
vytváří novou židli bez takového stylu. Reprodukce: dvě vlastní zelené židle,
přidání třetí - třetí nemá jejich lokální fill. Fyzický `parentId` dnes znamená
transformační vztah, nikoliv obecnou kaskádu stylů.

Dále existují zároveň `italic` a `fontStyle`; `_glyphs` je spojuje pomocí OR.
`italic:false` tedy neumí přebít přítomné `fontStyle:italic`.

**Nutné nyní:** jedna sparse deklarace vlastních stylů, jeden resolver,
explicitní default vzhledu židlí konkrétního stolu, jedno pojmenování kurzívy.

### F4 - Vysoká priorita: židle nemá jednoznačně vyjádřený režim umístění

Poloha je v node transformaci, attachment současně drží target, edge/perimeter,
`t`, gap, další souřadnice a `manual`. Uzel má další `manual` a
`manualRotation`. `TableSeating.fromDocument` někdy dopočítá profil z dominantní
velikosti židlí a mediánu attachment gap. Globální fyzické nastavení je uloženo
v `appearance.table`, ale `effectiveNodeProperties` pro něj má zvláštní výjimku.

Dvě různá významově správná umístění používají různou kombinaci booleanů:
volná pozice a připevnění ke zvolené straně. Nedávná oprava resize musela tyto
kombinace zvlášť rozeznávat. To je příznak chybějícího doménového typu.

**Nutné nyní:** explicitní placement union a samostatný fyzický seating profil.
Geometrie zůstane materializovaná. Reflow smí proběhnout jen v příkazu, který
mění rozmístění, ne jako vedlejší efekt obecného `apply` nebo pouhého načtení.

### F5 - Vysoká priorita: vlastní obrys není uložen jako gridový obrys

`grid_surface.dart` výslovně ukládá jen polygon. Modul 100 pro stůl a 60 pro
bar je konstantou v kódu. `validateDocument` přijme obecný polygon, který
`GridSurfaceBrush.fromNode` odmítne jako negridový. Tento rozdíl reprodukuje probe.

Pozdější změna modulu nebo nový import může z validního uloženého stolu udělat
objekt, který nejde stejným způsobem upravovat. Z polygonu nelze vždy bezpečně
odvodit původní modul a autorský záměr.

**Nutné nyní:** rozlišit běžnou polygonovou dekoraci a gridovou plochu stolu/baru;
persistovat velikost modulu a gridový zdroj, validovat jeho konzistenci.
Cílový grid ukládá kompaktní celočíselné ortogonální hranice a modul. Buňky
jsou odvozená pracovní reprezentace malování, nikoliv druhý uložený zdroj.
Souvislost, díry, limity a odkazy na cell faces se ověří proti hranici.

### F6 - Vysoká priorita: veřejný kontrakt nemá řízený evoluční mechanismus

`VenueLayoutDocument.fromJson` rozumí jen `schemaVersion:1`. Přesto se stejným
číslem rozšířily přípustné appearance/override klíče. Core validator,
`tool/export_contract.dart` a SQL whitelist jsou samostatně udržované definice.
SQL aktuálně nehlídá například obsah `appearance` ve stejné míře jako core.

**Nutné nyní:** verzovaný formát s čistým převodem na jeden interní model a
kontraktové fixtures společné pro core, distribuovaný kernel a SQL. Změna
uloženého významu se nesmí skrýt pod stávající verzí schématu.

### F7 - Střední priorita: zamčení dnes mění význam dědění podle vlastnosti

`setLayoutAppearance` zmrazí typography zamčeného uzlu do lokálních overrides,
ale globální fill nechá změnit. Controller má pro typography metadata zvláštní
výjimku `onlyTypographyFreeze`. Probe na stejném locked objektu potvrdil změnu
fill a zachování size.

**Před implementací sjednotit politiku:** doporučeně zamčení blokuje přímé úpravy
objektu/sestavy, ale nemění jeho vztah ke společným stylům. Globální deklarace
působí stejně na všechny dědící objekty. Chce-li uživatel zmrazit vzhled, má
zvolit vlastní styl; tím vznikne běžná explicitní deklarace. Je to navržená změna
chování, ne již existující invariant. Při převodu zachovat současný výsledný
vzhled již uložených výjimek; nezahodit dříve vytvořené overrides.

### F8 - Střední priorita: resource a veřejná projekce rostou s editací

`register_blueprint_layout_font` slučuje glyphy do globálního registrovaného
fontu; `blueprint_layout_resources_internal` následně vrací celý jeho outline.
Výstup není omezen na znaky daného dokumentu. Public `get_blueprint` také vrací
celé `b.layout`, včetně nepotřebných dokumentových presets/generators.

**Před vydáním upravit projekci:** vybrat potřebné glyphy podle výsledných fontů
a skutečně zobrazovaných řetězců. Registry může zůstat cache. Public runtime
projekce neobsahuje autorskou knihovnu; musí dát stejnou scénu a selection units.
Jde o velikost a oddělení projekcí; audit netvrdí únik konkrétních soukromých dat.

### F9 - Vysoká priorita: redo obnovuje host metadata bez aktuální ochrany

`lib/src/layout_editor/venue_layout_controller.dart:undo/redo` kontroluje přes
`_protectedSeatsRemain` existenci sedadel a atomic units. Potom `_restore`
obnoví checkpoint všech `LayoutHistoryParticipant`. Host
`blueprint_layout_controller.dart:restore` obnoví bindingy bez nové obchodní
validace proti aktuální live projekci.

Izolovaný host probe: přiřadit volnému místu produkt 2, undo na produkt 1,
obnovit live stav s novou rezervací a skutečným produktem 1, redo. Místo je
chráněné, přesto má draft produkt 2. SQL save má vlastní guardy; probe netvrdí,
že došlo k přepsání rezervace v databázi. Prokazuje chybný draft a neúplnou
kontrolu historie. Výstup je přiložen v evidenci.

**Nutné nyní:** společný validate/prepare/commit pro příkaz i undo/redo a
host metadata. Kandidáta posuzovat vůči současné obchodní autoritě. Návrat k
aktuálnímu serverovému produktu může být bezpečný, i když současný draft není.
Zamítnutá obnova nesmí odebrat položku z history stacku.

### F10 - Střední priorita: textový editor neskládá stejné defaulty jako scéna

`layout_scene_surface.dart:inlineEditor` dostává `effectiveNodeProperties`,
tedy typový appearance respektuje. Neaplikuje ale `defaultTextStyle` stejně
jako scéna; používá vlastní fallback velikosti a hledá font v node properties.
Dokumentový font a velikost se tak mohou při vstupu do editace lišit.

**Nutné nyní:** výsledný textový styl i font pro měření, inline edit a glyphy
musí vracet stejný resolver. Samostatná typografická pravidla v callerech odstranit.

## Ověřovací evidence a její meze

Dne 2026-10-20 spuštěn izolovaný pure-Dart probe nad přesným package ref
a samostatný Flutter host probe historie. Oba pouze proti paměťovým fixtures.
Zdroj a JSON výstup jsou v soukromém adresáři:
`/tmp/festapp-blueprint-release-private-20261019/architecture-audit-20261020/`.
Sanitizovaný reprodukční zdroj a výstup: [evidence](evidence/blueprint-data-model-audit-20261020.md).
Výsledky:

| Případ | Výsledek |
| --- | --- |
| Typový font size 36 -> odstranit typový style | Vrací se lokální 40, default dokumentu je 24 |
| Locked table + společný fill/size | Fill se změní, size zůstane 40 a přibude override |
| Dvě stylované židle -> přidat třetí | Staré mají vlastní fill, nová jej nemá |
| Obecný validní polygon stolu | Dokument validní, grid editor odmítne seed |
| Redo po nové live rezervaci | Protected=true, server produkt 1, obnovený draft produkt 2 |

F1/F2/F6/F8 jsou doloženy konkrétními producenty a consumery ve zdrojích.
Nebyly nově spuštěny SQL transakce, produkční inventura ani kompletní E2E.
Před realizací ověřit aktuální live stav schématu a existujících dat read-only
podle repository backend pravidel. Historická inventory nemůže tuto bránu nahradit.

## Cílový kontrakt a závazná rozhodnutí

Následující pravidla jsou **návrhová rozhodnutí pro implementaci**, ne popis již
hotového systému. Cílem je úplný cutover interního modelu; starý formát zůstane
jen v pojmenovaném importéru. Nezavádět nový editorový framework ani druhý renderer.

### Jedno vlastnictví významů a malá společná rozhraní

| Význam | Kanonické uložení | Odvozené / transientní |
| --- | --- | --- |
| Identita a transformace | UUID, parentId, lokální transformace uzlu | World matrix, index bounds, handles |
| Styl dokumentu | `styles.label`, `styles.kinds[kind]` | Výsledný vzhled a provenance |
| Vlastní styl | `node.style`, sparse deklarace | Žádná maska nad skrytými factory hodnotami |
| Styl židlí stolu | `table.childStyles.seat` | Společný vzhled nynějších i nových dědících židlí |
| Fyzický profil židlí | `seatingDefaults`, table/assembly-root `seating` patch | Rozlišený profil pro explicitní seating příkaz |
| Záměr připojení | Attachment `placement` | Node transform je jediná renderovaná poloha |
| Plocha stolu/baru | `surface` union | Path/bounds a transientní buňky malování |
| Autorská sestava | Typed `assembly` spec na root uzlu | Materializovaní potomci, ne runtime regenerace |
| Produktový záměr | Host binding `productAssignmentMode` | Skutečný provozní produkt ve `spots.product` |
| Rezervace, finance | Stávající SQL, inventory, receipts | Live status/tooltip mimo dokument a historii |
| Session | Controller session | Kamera, hover, editorový výběr, pending |

Tři soustředěná rozhraní, nikoliv nové vrstvy jen pro přeposílání:

1. Core `resolveNodeAppearance(document, nodeId)` vrací immutable výsledný
   vzhled a zdroj jednotlivých hodnot. Použije ho scéna, inspector, náhled,
   inline editor, měření textu i sběr fontových závislostí.
2. Core editovací operace připraví `LayoutEditResult` obsahující nový dokument
   a přesně označené strukturální efekty/záměr operace. Controller provede
   jedinou validaci a commit. Existující příkazy lze takto prohloubit bez
   obecného command busu nebo registru libovolných pluginů.
3. Host participant připraví další opaque checkpoint a případné issues před
   commitem. Core nezná Festapp produkty/ceny. Pouhé capture/restore nestačí:
   host musí předem ověřit i kandidáta undo/redo vůči aktuálnímu live stavu.

### Verze a tvar dokumentu

Writer emituje jen `schemaVersion:2`. To není generace UI ani verze sync RPC.
`symbolSetVersion`, resource protocol, kernel protocol a client-sync `_v1`
zůstávají samostatnými verzovacími doménami; bump jen při změně jejich kontraktu.

Nové closed záznamy: document `styles`, `seatingDefaults`; node `style`,
`childStyles`, `seating`, `surface`, `assembly`. Styly a fyziku neschovat zpět
do libovolného properties bag. Zachovat UUID, transformace, canvas, sections,
selection units, attachments, background a preset knihovnu. Ostatní potřebné
geometrické properties ponechat validované podle kind; jejich hromadné
přejmenování není cílem refaktoru.

Core vlastní deklarativní metadata klíčů, typů, defaultů, rozsahů a kind/scope
přípustnosti. `tool/export_contract.dart` z nich generuje JSON Schema a SQL
whitelist/range artefakt s digestem. SQL si ponechá transakční a referenční
validaci; nesmí ručně duplikovat seznamy stylových klíčů. Strukturální schéma
samo neprokazuje doménovou validitu. Stejný valid/invalid corpus musí projít
core, sestaveným kernel artefaktem i SQL.

Capabilities uložit do host/kernel envelope, nikoliv do každého uzlu: podporované
read/write document schemas, schema digest a resource protocol. Starý klient
nesmí přepsat uloženou verzi 2 dokumentem 1 ani s platnou revizí. Změna významu
nemůže zůstat pod stejnou verzí s jiným digestem. Nepodporovanou budoucí verzi
odmítnout s čitelným důvodem a zachováním původního payloadu, bez fallback writeru.

### Stylová kaskáda, reset a presety

Pořadí pro vzhled židle:

```text
core seat default -> styles.kinds.seat
  -> childStyles.seat přímo připojeného stolu -> node.style
```

Pořadí textu: core label default -> `styles.label` -> kind `label` -> případný
připojený table child seat `label` -> vlastní `node.style.label`.
Dědění probíhá **po listech vnořeného záznamu**. Pole se nahrazují jako celek.
Chybějící klíč dědí; `false`, `0`, prázdné pole a transparentní barva jsou
explicitní hodnoty tam, kde je daný typ dovoluje. Uložené `null` není reset.
Explicitní volba shodná s rodičem zůstává explicitní. Nededuplikovat ji podle
aktuální výsledné hodnoty.

Editace používá Set(path,value) / Unset(path) a určený scope. Reset jednotlivé
vlastnosti odstraní její deklaraci, nepřepíše celý label objekt. Reset vzhledu
sestavy odstraní table `style` a `childStyles.seat`, ale ponechá skutečné lokální
výjimky židlí. Jejich odstranění je samostatná výslovná akce. Inspector ukazuje
„Dědit vzhled“ a zdroj „Ze stolu S10 / Z plánku / Vlastní“, ne nepravdivé
„Použít styl plánku“, když nejbližším zdrojem je stůl.

`material` je kanonické jméno nynějšího `objectStyle`; zachovat stávající rodiny.
Materiálová rodina se rozvine na defaulty **v té vrstvě, kde byla deklarována**;
explicitní listy stejné vrstvy mají přednost. Nedumpovat odvozené defaulty do
každého potomka. `seatStyle` je vizuální varianta židle, nikoliv její fyzický
profil. Barevný preset je předem definovaný patch pokrytých polí, ne nový
průběžný odkaz na knihovnu. Table preset atomicky nastaví stůl a child seat
style; ponechá individuální výjimky. Materiálový preset musí výslovně určit,
které své staré překrývající deklarace odstraňuje. Nezasáhne text ani geometrii.

Obyčejný group je transformační vztah. Žádné implicitní dědění vzhledu přes
obchodní skupinu/sekci. Budoucí pojmenované styly a styly sekcí mohou využít
stejný resolver, ale nyní nezavádět nevyžádanou referenční knihovnu ani CSS engine.

Lock blokuje přímé úpravy zamčeného objektu/sestavy. Nemění dědění: změna
společného stylu působí i na locked objekt, který jej dědí. Již uložené explicitní
výjimky zůstanou. Tato sjednocená politika nahrazuje typography-only freeze.

### Matice vlastností a text

Toto je rozdělení současných skupin klíčů; kontraktová metadata ve vlně 2 musí
strojově doložit pokrytí každého současného renderovaného/editovaného klíče.
Žádný aktivní klíč nesmí při převodu tiše zmizet.

| Dnes | Dokument 2 / pravidlo |
| --- | --- |
| `fontId,size,color,align,lineHeight,labelOrientation` | `style.label` odpovídající listy; globálně stejné v `styles.label`/kind label |
| `bold`, `italic`, `fontStyle` | Label `weight:400|700` a `italic:boolean`; importer převede dosavadní skutečný výsledek, pak aliasy odstraní |
| `fill,stroke,strokeWidth,opacity,cornerRadius` | Vizuální listy `style`; jen u kind, kde renderer vlastnost používá |
| `objectStyle,seatStyle` | `material`, `seatStyle` ve stylové vrstvě |
| `dash,strokeStyle` | Jediný `strokePattern` union solid/dashed/dotted/custom; custom nese neprázdné pole kladných délek, solid nahrazuje prázdné dash; staré dash má při importu dosavadní prioritu |
| `appearanceOverrides` | Pouze vstup importéru 1; v cíli existence deklarace určuje vlastní hodnotu |
| `seatWidth,seatHeight,seatGap,seatSpacing,seatEdgePadding` | Fyzický `seatingDefaults` / table `seating`, nikdy style |
| Table `shape,points,holes` | `surface` rect/circle/grid, module a integer rings u grid |
| Obecné `shape,points,holes,arrowHeadLength,pathPattern,zigzagTeeth,zigzagAmplitude` | Stávající validovaná geometrie dekorací; neomezovat je pravidly stolů |
| `text`, node `label` | Dosavadní typ obsahu s jediným per-kind zdrojem; rename nesmí vytvářet další kopii |
| `manual,manualRotation`, attachment souřadnice | Placement + rotation mode; jediná materializovaná node transformace |
| `assembly,slot,rows,seatsPerRow,blocks,aisle,spacing,rowSpacing,arc,left,right,rear,decks,upperRows,upperRear,deck,compartments,seats` a generátory | Jeden typed root assembly spec pro příslušný druh; role/slot potomka zůstává explicitní reference; konflikty kopií hlásit |
| `furniture,guestSide,symbol,role,obstacle` | Typované geometrické/doménové properties podle kind; nepřejmenovávat bez potřeby, nesmí se stát styly |
| `capacity` | Autorský capacity hint oddělený od host inventory; skutečnou kapacitu mění existující area-binding příkaz, ne renderer |

Velikost labelu se volí sliderem s celočíselným krokem a čitelnou hodnotou.
B/I jsou dvě kombinovatelné přepínací akce, ne checkboxy v seznamu. `weight`
ponechává prostor pro budoucí váhy, ale verze 2 teď validuje 400/700. Skutečné
font faces a shaping nejsou automaticky vyřešeny touto změnou. Vlastní font
rodina z Google katalogu musí jít zvolit a náhled se skutečně načíst stejně
jako v Ticket Editoru; při chybě nesmí proběhnout tichý fallback.

Celá čísla používat pro počty a běžně zadávanou velikost písma, ne slepě pro
geometrii, opacity, lineHeight či transformace. Staré platné desetinné velikosti
při importu zachovat kvůli vizuální shodě, první uživatelská změna sliderem je
celočíselná. Úprava vzhledu/fontu **nesmí měnit fyzický rozměr stolu**.
Název stolu/objektu má definovaný shrink-to-fit v jeho label boxu; text node
wrap+clip v jeho boxu. Model ponechá celý text a tooltip jej zpřístupní. Font
změna nesmí rozbít celý plánek bannerem `text_overflow`.

### Povrch, umístění židlí a sestavy

`surface` je rect / circle / grid. Circle má stejné width/height a symetrický
resize. Každý běžný stůl může změnit tvar všemi třemi směry, se zachováním ID a
explicitním přepočtem rozmístění v jednom příkazu. Bar respektuje stejná pravidla
gridového růstu/mazání; současné omezení baru bez kruhového tvaru zůstává.

Grid ukládá `moduleSize` a normalizované integer rings `outer` + `holes`, ne
pole všech buněk ani druhý world polygon. Modul je kladný a per-object uložený;
100 pro nový stůl / 60 pro nový bar jsou jen výchozí hodnoty. Hrany jsou
ortogonální, plocha souvislá, díry validní a nedotýkají se obvodu ani sebe.
Maximálně 512 vrcholů celkem a bounding footprint do 16384 buněk omezují cenu
rekonstrukce brush gridu. Width/height odpovídají bbox * module a jsou validovaná
odvozená geometrie. Path vzniká převodem integer bodů do lokálních souřadnic.
Buňky existují pouze během malování, přidávání a mazání. Stejné operace
používá úchyt hrany. Volné tažení bodů nesmí vyrábět obecný mnohoúhelník stolu.

Attachment placement je union:

- `automatic`: explicitní seating příkaz jej smí znovu rozmístit.
- `sidePinned`: drží zvolenou stranu a podélný parametr; na gridu integer cell
  coordinate + face, nikoliv nestabilní index polygonové hrany.
- `free`: zachová materializovanou lokální polohu. Rotace má samostatný
  auto/manual režim; ne dva překrývající se placement booleany.

Node transform je výsledek pro renderer; attachment nesmí duplikovat x/y/rotation.
Při normalizaci gridového počátku přemapovat cell-face reference a posunout center
tak, aby zůstaly world pozice nedotčených modulů. UI umožní přesun židle na
zvolenou stranu, přerozdělí ostatní automatické židle na té straně a zachová
připnuté/volné výjimky. Nevznikají nové seat IDs pro pouhé přemístění.

Fyzické document defaults slouží explicitnímu configure/create příkazu. Jejich
změna sama nepřerozmístí nynější sestavy. Renderer ani save/load negenerují nodes.
Rows/bus/compartments mají jeden root assembly spec; skutečné children a jejich
manual exceptions jsou materializované. Neodvozovat profil za běhu z majority
rozměrů, pořadí dětí či mediánu gap. Rozpor spec vs nodes je validační issue,
ne povel tiše regenerovat dokument.

### Transakce, historie a produktový záměr

Jedna operace mění dokument a host checkpoint atomicky. Selhání validate/prepare
ponechá dokument, bindings, selection a oba history stacky beze změny. Jeden
ukončený drag/slider/rename/brush gesture je jeden undo krok; pointer move a IME
intermediate events nejsou samostatné commity. Undo/redo nepřepisuje dnešní
live holds a nevrací staré pending požadavky.

| Operace | Povolený účinek a zakázaný vedlejší účinek |
| --- | --- |
| Move/rotate | Jen rigidní transformace; žádné reflow, změna count/profilu/surface/product |
| Resize / seating / brush | Výslovný návrh nové fyziky + placement; protected a atomic guardy platí před commitem |
| Rename/style | Obsah/deklarace; žádná geometrie, finance nebo automatická nová ID |
| Explicit attach | Fyzické připojení a host návrh cílové obchodní skupiny/defaultu podle cíle |
| Detach / strukturální normalizace / reparent při importu | Zachovat obchodní členství a produkt; není to automaticky explicit attach |
| Undo/redo | Stejné guardy jako nový příkaz, včetně host produktu, mode, členství a live ochrany |
| Refresh live / pan / scroll / hover | Žádný dirty/history/scene-geometry commit |
| Copy/create/delete | Deklarované reference a lifecycle IDs; existing protected/atomic pravidla se nesmí obejít |

`_geometryChanged` nesmí být skrytý vlastník obchodní změny po commitnutí core.
Explicitní attach efekt řeší target, ne starou source skupinu preferovanou jen
proto, že zůstala ancestor. Není-li cílový default jednoznačný, vrať strukturovaný
požadavek na volbu. Nikdy nevybírat první dostupný produkt. Obecný public raw
`apply` nesmí obcházet tyto guardy ani skrytě volat reflow; import/load mají vlastní
pojmenované rozhraní. Nepřepisovat širší navigaci nebo sync engine.

`productAssignmentMode:inherit|override` je mimo portable dokument. `inherit`
znamená účast na příští explicitní aplikaci defaultu skupiny, ne přecenění za
běhu. Explicitní produkt A musí zůstat override i při defaultu A. Protected
místa může freeOnly vynechat bez změny jejich mode. Zrušení objednávky samo
neaplikuje ceník. Při explicit attach se inherit účastní cílového defaultu,
override zachová svou volbu, dokud uživatel výslovně nezvolí převzetí defaultu.
`groupNodeId` je obchodní vazba; detach ji nemaže. Finanční
pravda zůstává v SQL/spots. Změnu mode i členství chrání stejné obchodní guardy.

History budget musí zahrnovat host checkpointy, ne jen JSON dokumentu. Zachovat
omezení počtu a paměti; místo serializace celého aggregate na každém pointer
použít immutable checkpointy/cachovaný fingerprint. Změna stylu invaliduje
skutečné závislosti, panely/scroll nesmějí znovu kompilovat celou scénu.

### Save, asynchronní fonty a distribuované resources

Normalizace proběhne před ustavením draft baseline, ne tajně při Save. Save
zachytí immutable semantic proposal, z jeho výsledných stylů a textů připraví
resources a odešle tento konkrétní snapshot. Další editace mezitím zůstanou dirty;
po odpovědi se nezamění za potvrzenou uloženou verzi. Výsledek přípravy je
ready/superseded/failure, ne `void`, které caller pokládá za úspěch.

Sběr závislostí rozlišuje existenci deklarovaného font ID a glyph coverage
skutečně renderovaných textů. Zahrne odvozené labely, čísla a count symboly;
admin náhledy presets jen v admin režimu. Nevyžaduje glyphy pro nezobrazovaný
label židle. Výběr fontu a async příprava mají generation token; starý výsledek
nepřepíše novější volbu. Selhání nevrací nesouvisející pozdější editace. Při
chybějících glyph resources může editace ukázat lokální přípravu/chybu, ale
Save není ready. Vektorové paths ve view nezávisí na stažení celého fontu.

Resources a jejich cache nepatří do dokumentové historie. Cache klíč obsahuje
font identity/hash, sadu glyphů a outline protocol; merge hlídá stejné metriky.
Reader neposílá celé postupně rostoucí globální outlines. Public runtime projekce
vynechá autorské presets/assembly parametry pouze při důkazu shodné scény a
selection units; není to druhý renderer. SQL collector má stejné fixture
výsledky jako core, bez libovolného hledání stringů ve všem JSON.

Zachovat jediný unresolved save intent: po nejednoznačné síťové odpovědi tentýž
command ID + přesné payload bytes. Příprava/migrace nesmí přepsat již zmrazený
požadavek. Definitivní rejection jej ukončí; revision conflict nabídne reload
nebo vědomé řešení draftu, nikoliv automatický business merge. Replay historického
receipt vyhodnotit před novou schema-version admission, poté reload současné
head revize se zachováním novějšího draftu. Nevyrábět druhý intent pro tutéž akci.

Limity měřit na skutečném UTF-8 aggregate: stávající request 8 MiB a result
4 MiB neznamenají, že 8 MiB dokument plus bindingy lze bezpečně odeslat. Zavést
předběžnou srozumitelnou chybu s komponentou velikosti. Neřešit plný font katalog
slepým zvýšením limitů. Rozsahy geometrie a existující resource limity zachovat,
pokud měření neprokáže konkrétní nutnou změnu.

## Převod a nevratné informace

Pure importer 1 -> 2 je deterministický a idempotentní. Původní payload zachovat;
read nemigruje databázi a sám nezpůsobí dirty dokument. Writer emituje pouze 2.
Existující node/spot/group/selection-unit UUID, wrappery a parent transformace se
neflattenují ani nenahrazují náhodnými ID. Copy vytvoří nové geometrické ID jen
při skutečné kopii; nemění existující spot/ticket identity.

| Třída starých dat | Převod / nutná evidence |
| --- | --- |
| Explicitní maskovaný style | Zachovat vlastní deklaraci i při shodě s defaultem |
| Skrytá nepoužitá nemaskovaná style hodnota | Nepovýšit na override; po resetu se nesmí znovu objevit |
| Viditelná nemaskovaná style hodnota | Pokud odpovídá cílovému role/default vzhledu, dědit; jinak zachovat jako explicitní importovanou výjimku a vypsat |
| Stejný styl na všech židlích | Není důkaz společného záměru; ponechat explicitní overrides, případné sloučení do child style vyžaduje přezkoumání |
| Produkt stejné hodnoty jako default | Bez původního záměru konzervativní override + seznam k rozhodnutí; žádný odhad rovností |
| Dvojí italic/manual/generator parametry | Zachovat současný výsledek, uvést rozpor a vybraný zdroj v receipt |
| Grid-aligned polygon | Odvodit modul jen při jednoznačné shodě s pravidly původního zdroje, ověřit přesný path a uložit integer rings |
| Negridový nebo neurčitý table/bar polygon | `surface_review_required`, žádný autosnap ani trvalý druhý frozen runtime typ |
| Preset fragmenty | Každý vlastní namespace a převod vlastního dokumentu; nepřepisovat UUID-like text v labelu |

Negridové případy před cutoverem ukázat v náhledu a výslovně převést na podporovanou
plochu s evidencí geometrické změny. Do té doby záznam zůstane na backendu beze
změny a blokuje jeho přepnutí na nový writer. Starý renderer lze použít v offline
porovnávacím nástroji, ne jako trvalou druhou produkční cestu. Pokud inventura
odhalí potřebu trvale zachovat libovolné polygony stolů, je to nové produktové
rozhodnutí vyžadující aktualizaci plánu, ne důvod zavést skrytý fallback.

Migrace nemůže obnovit ztracený záměr. Zachování současné scény neznamená záruku
shodného budoucího chování chybných masek. Nová politika reset/lock a konzervativní
product mode jsou výslovně uvedené změny. Žádné přecenění, zrušení holds nebo
přegenerování inventory není součástí převodu.

Receipt po blueprintu: source schema/hash/revision, target schema/digest/hash,
změněná geometrická ID, counts, stylové výjimky, nerozlišené produkty a povrchy,
scene comparison a případné schválení záměrné odchylky. Porovnat scény po současné
kvantizaci 1/1024, ne pixel screenshot bez kontroly identity. Převod zapisovat s
expected revision **i source hash**, dokument a nové binding modes v jedné SQL
transakci. Concurrent edit znamená skip/replan, nikoliv overwrite. Report
neobsahuje zákaznická osobní data ani credentials.

## Implementační vlny a výstupní brány

Každá vlna končí konkrétním důkazem a aktualizací seznamu odstraněných cest.
Převod produkce není automatickou součástí žádné kódové vlny.

### 1. Uzavřít nynější scoped-font round-trip

- **Změna:** `database/functions/blueprint/{resources,validation}.sql` a host
  `_prepareFonts`; doplnit současné appearance, správnou override prioritu,
  strukturální validaci a závislosti admin/public/setup. Připravit forward
  migraci z kanonických SQL zdrojů, neupravovat jen historický migration file.
- **Selhání:** missing font/glyph a malformed appearance odmítnout bez změny
  revize/bindingů. Neinterpretovat každou libovolnou string hodnotu jako font.
- **Ověření:** DB fixture scoped B + local C, save -> admin/public/setup read ->
  core/JS scene. Missing resource test musí selhat atomicky.
- **Exit:** uložení a reload nepřijdou o žádný výsledný font. Tuto opravu převést
  do verze 2, nedržet zvláštní trvalý collector pro každý frontend.

### 2. Zavést kontrakt 2, resolver a čistý importer

- **Změna:** core `model.dart`, contract metadata, `tool/export_contract.dart`,
  typed style/label/surface/seating/placement/assembly. Generovaný schema + SQL
  metadata digest, capability envelope a valid/invalid fixtures. Property
  matice výše se uzavře mechanickým pokrytím současných klíčů.
- **Převod:** jeden importer 1; neznámé/neurčité hodnoty dostanou issues/report,
  nikoliv tichý úspěch. Legacy masku smějí číst jen importer/test fixtures.
- **Ověření:** ST, CT a MG případy níže; stejné resolver výsledky pro inline edit,
  scénu a resource collector. Golden není jediný důkaz dědění.
- **Exit:** document 2 má deterministický round-trip a odmítá neplatný vztah,
  transformaci, neortogonální grid i neznámou verzi bez poškození source.

### 3. Převést fyzické operace a editorové styly

- **Změna:** core `operations.dart`, `grid_surface.dart`, seating/assembly,
  package `layout_style.dart`, `layout_inspector.dart`, `layout_global_style.dart`,
  scéna a inline editor. Všechen vzhled přes resolver; attach/reflow/brush přes
  jednu operaci; rigidní move bez implicitního reflow. Child style místo kopírování.
- **Odstranění:** majority/median runtime inference, dvojí manual, style freeze
  výjimka a shape aliasy mimo importer. Stabilní IDs a fyzická ochrana zachovány.
- **Ověření:** PH/ST případy, gesto -> jeden undo krok, nová židle a tvarový cyklus.
  Změna fontu a přesun nesmějí pohnout jinou židlí ani měnit rozměr stolu.
- **Exit:** stejnými pravidly lze malovat i zvětšovat/mazat grid stolu a baru,
  všechny nynější styly mají doložený viditelný účinek a provenance/reset.

### 4. Sjednotit transakce, historii a business bindings

- **Změna:** package `venue_layout_controller.dart` + host
  `blueprint_layout_controller.dart`, DTO/save/setup/copy/history, SQL binding
  schema/projection/save. Přidat mode inherit/override, prepare host checkpointu
  a live guard celé změny. Nahradit post-commit `_geometryChanged` reconciliation
  explicitním záměrem změny; source ancestor nesmí maskovat target attach.
- **Převod:** doplnit DB sloupec a konzervativní backfill bez změny skutečného
  produktu; neumožnit starému writeru obcházet nový mode. Výchozí hodnota sloupce
  není důkaz historického dědění.
- **Ověření:** TX/PR případy, concurrent live update a rejected undo/redo, existing
  finance/holds/atomic-unit suites v dotčeném rozsahu. Checkpoint bez mutací při reject.
- **Exit:** žádná vstupní cesta neobchází ochranu, A -> B -> A zachová ruční A,
  undo vrací celý povolený aggregate a nikdy nevrací starou live rezervaci.

### 5. Uzavřít async save, resources a public projekci

- **Změna:** `_save/_prepareFonts`, saver, resources SQL, core collector a oba
  adaptéry. Připravit captured snapshot, explicitní async výsledky/generation,
  glyph subsets a admin/runtime projekce. Doplnit preflight velikosti aggregate.
- **Odstranění:** skryté normalizace při Save, stale void-success a celé globální
  outlines v read response. Public nevrací nepotřebnou autorskou knihovnu.
- **Ověření:** IO případy; edit během přípravy/response a font A/B v opačném pořadí,
  ambiguous retry s totožnými bytes, resource budget a scene/selection parity.
- **Exit:** reload používá stejné paths, neztrácí novější draft, nepotřebuje celé
  font binárky a nezaměňuje odmítnutý/stale save za uložený dokument.

### 6. Ověřit migrační corpus a UI/performance kontrakt

- **Změna:** read-only inventář na autorizovaném zdroji; převod kopií s receipt,
  identity/path comparison, přezkum neurčitých stylů/produktů/polygonů. Nevyřešené
  záznamy blokují jejich cutover. Setup/copy zahrne preset namespaces a obchodní vazby.
- **Ověření:** MG/UI/PF případy, skutečný save -> close -> reopen -> copy,
  admin i public reader a distribuovaný JS kernel/archive consumer.
- **Exit:** každý zkoušený záznam má výsledek a důvod, vizuální shoda a identity
  nejsou tvrzeny jen podle neuloženého screenshotu. Žádný runtime legacy fallback.

### 7. Připravit vydání a dokončit odstranění starých cest

- **Změna:** čistý package commit, kernel manifest/schema digest, host piny/vendor
  integrity a dokumentace. Vstupní importer zůstává pojmenovaný a otestovaný.
  Žádná paralelní interní verze 1 ani runtime shape/font/manual aliasy.
- **Brána:** readers/server support před writerem; koordinovaně zastavit staré
  writery při cutoveru (krátké maintenance/read-only okno je přijatelné). Expand
  schéma samo neopravňuje neomezeně míchat staré a nové editory.
- **Exit:** nový kontrakt funguje z reálných distribučních artefaktů a downgrade
  writer je odmítnut. Produkční rollout a převod čekají na zvlášť určený tenant
  a autorizaci; rollback po prvním v2 zápisu ponechává v2 reader/guard.

## Mazání a omezené retenční hranice

| Dnešní reprezentace / cesta | Cílová akce a důkaz |
| --- | --- |
| `appearanceOverrides` + skryté style properties | Odstranit z verze 2 writerů a resolverů; pouze importer 1 je smí číst |
| `fontStyle` vedle `italic`, staré `bold` | Jediný italic a weight; žádné renderovací OR nebo druhá autorita |
| Seating rozměry v `appearance.table` | Přesunout do fyzického profilu, žádná výjimka v visual resolveru |
| `node.manual` + `attachment.manual` pro placement | Nahradit union; staré kombinace čte jen importer |
| Attachment `x/y/rotation` kopie | Odstranit jako další zdroj; node transform je renderovaná poloha |
| Grid modul pouze v konstantě | Uložit ve grid surface spec, polygon shape dále vlastní obecné dekorace |
| Majority/median odhad fyzického profilu | Ponechat jen explicitnímu legacy importeru s evidencí, ne editovacím příkazům |
| Produktové dědění podle shody ID | Nahradit režimem; test stejné explicitní hodnoty musí projít |
| Dvojí root/assemblyId a kopií parametrů | Jeden typed assembly owner; vstupní alias jen v importeru |
| Typography-only locked freeze | Odstranit po jednotné politice, zachovat již uložený explicitní vzhled |
| Ruční rozdílné whitelists/ranges | Generovaný kontrakt + společné fixtures; business SQL validace zůstává |
| Public celé presets a všechny glyphy fontu | Projekce jen potřebných runtime dat a prokázaná shoda scény |
| Post-commit host `_geometryChanged` business reconciliation | Explicitní prepare efekt před commitem, odlišit attach a normalizaci |
| Host history restore bez live guardu | Validace kandidáta celého aggregate před undo/redo |
| Obecné apply se skrytým reflow | Typed operace; raw replace pouze pojmenovaná load/import hranice |
| Dvojí dash/strokeStyle | Jeden strokePattern; legacy priorita pouze importer |
| DefaultTextStyle přimíchávaný ručně callery | Jeden úplný resolver včetně inline editace a resources |
| Starý writer nebo schema-downgrade fallback | Server admission guard a doložený cutover writerů |

## Ověřování při realizaci

Tato matice je acceptance kontrakt, nikoliv seznam již úspěšných testů. Přidávat
případy do existujících vlastnících suites; nevytvářet paralelní test framework.

| ID | Minimální důkaz |
| --- | --- |
| ST1 | Doc -> kind -> table child -> own: každý scope, Set shodné hodnoty, Unset, explicit false/0/transparent/[] podle typu; žádná skrytá hodnota po resetu |
| ST2 | Table preset + nová/připojená židle, explicitní jiná židle, reset sestavy vs jednotlivé židle, materiálový preset zachová text/fyziku |
| ST3 | Globální font/size/B/I + lokální override; locked objekt dědí shodně; inline edit, preview, scene a collector stejný výsledek |
| CT1 | Každý klíč má owner/type/scope/range, neznámé klíče a null odmítnuty; NaN/Infinity, reference cycles, neplatná IDs; žádný fallback budoucí verze |
| CT2 | Stejný valid/invalid corpus core, sestavený JS kernel, JSON Schema a SQL; referenční/domain omezení navíc výslovně pojmenována |
| PH1 | Stůl rect/circle/grid a zpět: stabilní IDs, symetrický circle, minimum velikosti, žádný text overflow nebo samovolný skok židlí |
| PH2 | Malování add/erase a edit hrany stejný výsledek; odmítnout diagonály, self-intersection, odpojení, dotýkající díry a překročení limitů; stejné pro bar |
| PH3 | Move/rotate stolu zachová lokální pozice všech židlí, profil/count/shape; resize respektuje sidePinned/free a protected/atomic pravidla |
| PH4 | Židle z čela na stranu a zpět, lokální redistribuce, grid rebase vlevo/nahoře zachová world polohu ostatních modulů a reference |
| TX1 | Rename/slider/drag/brush = jeden undo krok; při reject beze změn doc/host/selection/history; undo po změně live hold obnoví pouze povolený stav |
| TX2 | Přidat host reprodukci F9 s opačným očekáváním: redo nesmí obnovit produkt 2 chráněnému místu s authoritative produktem 1; bezpečný návrat k serverovému stavu povolit |
| PR1 | Ruční A při defaultu A přežije A -> B -> A; inherit se změní, freeOnly přeskočí protected bez změny mode; uvolnění samo nepřecení |
| PR2 | Attach cílovému stolu uvnitř staré source skupiny, detach zachová business členství, normalize/reparent neaplikuje target produkt; missing default žádá volbu |
| IO1 | Scoped font B + own C save/read/admin/public/setup/copy, derived digits/counts, glyph subset; chybějící font/glyph atomicky odmítne save |
| IO2 | Font A/B resolve v obráceném pořadí, rename během přípravy, edit během save response; žádný stale commit ani ztráta novějšího draftu |
| IO3 | Ambiguous retry totožné bytes/command, receipt replay po upgradu, revision conflict, starý writer se správnou revizí odmítnut nad dokumentem 2 |
| IO4 | Skutečné UTF-8 limity doc+bindings+resources, velký globální font registry nemění read velikost jiného dokumentu; malformed style nic neuloží |
| MG1 | Import dvakrát identický, scene paths/labels/selection units parity, stabilní node/spot/group IDs a wrappery; conflicting aliasy dostanou report |
| MG2 | Neurčitý product intent a offgrid polygon nejsou automatický success; preset namespaces/copy, changed revision/source hash zastaví zápis |
| UI | Níže uvedená pozorovatelná pravidla na uloženém a znovu otevřeném plánku |
| PF | Reprezentativní 317-node fixture, 5000 seats a největší platný aggregate pod limity; stejné zařízení/toolchain, p50/p95 před/po, žádná plná kompilace scény při scrollu panelu |

Minimální fyzické rozměry stanovit v jediném seating/surface helperu podle
profilu, paddingu, druhu plochy a skutečné obsazenosti stran. Resize je clampuje
nebo výslovně odmítne; nesmí místo toho tajně změnit počet či strany židlí.
Současné minimum chránící štítek nesmí vnutit fyzickou změnu při pouhém výběru
většího fontu. Přesné numerické limity helperu patří do contract metadata a
PH1 fixtures, ne do několika nezávislých inspector widgetů.

### Zachovaný uživatelský kontrakt

Tato pravidla chrání požadavky z celé QA konverzace při refaktoru. Některá již
mohou být opravena; nejprve ověřit na pevné baseline a neměnit fungující chování
jen kvůli nové struktuře. V1 je referencí kvality ovládání a tooltipů.

| Režim / prvek | Viditelné chování |
| --- | --- |
| Editor výběr | Modré zvýraznění; stůl má handles na vlastní desce a drobné spojnice k židlím, židle nemá zákaznický checkmark |
| Rezervace | Klik na stůl otevře jeho modal, na židli její detail; vybraný stůl je výrazný, řádek seznamu se označí a doscrolluje; žádná navigace stejné stránky ani slide transition |
| Objednávka | Click toggluje více/méně sedadel bez nutnosti Shiftu; Shift může přidávat, nesmí být jediná cesta. Výběr objednávky je oddělený od editorového výběru |
| Nástroje | Konzistentní Výběr/Posun a jejich umístění v obou režimech; dostupné nástroje vysvětlit tooltipem, ne zavést další duplicitní ikony |
| Detaily | Tooltip pro stůl/sedadlo s názvem, produktem/cenou a relevantním stavem podle dostupné projekce; žádná druhá duplicitní akce správy skupiny |
| Styly | Čtvercové/obdélníkové cards s horizontálním scroll pro styly, žádné elipsy; změna preset mění i dědící židle; název, family, size a B/I dostupné lokálně i ve společném label stylu |
| Šablony | Kompaktní obdélníkové cards: název + počet míst; další popis až tooltip; ne elipsy ani dlouhé odstavce |
| Pozadí/fonty | Nejprve upload modal s drop/klik pickerem, zavření X bez Stornovat; načtené fontové náhledy, lokální loading bez page progress/navigation efektu |
| Povrchy | Obnovit/doložit Malovat stůl, gridové rozšiřování i mazání, žádná libovolná polygonová deformace. Table/bar pravidla sdílejí implementaci |
| Mikrokopie/advanced | Storno v objednávce, odstranit Náhled počtu; nepotřebné obstacle/otáčení kolem rohu nepřidávat do hlavního UI, ale nesmazat kvůli tomu význam importovaných dat |
| Validace | Legitimní kontakt/vrstvení s hranicí sálu nebo dekorací není samo o sobě chyba. Collision/povolené překrytí vychází z role/operace; žádný falešný globální červený banner |
| Odezva | Drag a scroll panelu plynulé; pan/scroll nevytváří history a nereflowuje židle. Ctrl+Z funguje po střídání canvas/inspector/modal, respektuje textové editace a live ochranu |

### Konkrétní test seams a příkazy

Nejprve ověřit aktuální CONTRIBUTING a stav běžících Flutter procesů. Jediný
Flutter task na workstation; všechny Flutter testy s `--concurrency=1`.
Nespouštět každý příkaz po každém souboru. Po souvislé vlně jeden cílený batch,
širší integrační brána před vydáním podle dotčeného kontraktu.

- **Core/package:** `packages/venue_layout_core/test/appearance_test.dart`,
  `grid_surface{,_edit}_test.dart`, `table_attachment_test.dart` a stávající
  shape/move/resize/selection/history widget suites. Pure core z jeho kořene:
  `fvm dart test`; package widget batch:
  `fvm flutter test --concurrency=1 test/layout_history_focus_test.dart test/layout_table_move_stability_test.dart test/layout_table_resize_policy_test.dart test/layout_table_shape_controls_test.dart test/layout_table_selection_links_test.dart test/layout_scene_cache_test.dart`.
  Rozšířit batch jen podle změněných seams; další testy resolveru přidat do jeho owner suite.
- **Host:** `test/components/blueprint/blueprint_layout_{host,ui,assets}_cases.dart`
  jsou cases importované ze session suite, nikoliv samostatné `_test.dart` roots.
  Použít `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart`
  s filtrem podle skutečných jmen skupin, nebo repository cílený session runner.
  Nevydávat úspěšný běh nula testů za důkaz.
- **SQL:** `layout_integration_test.sql`, `copy_setup_test.sql`,
  `setup_draft_integration_test.sql`, `canonical_layout_cutover_test.sql` a
  dotčené finance/hold suites v `database/tests/blueprint/`. Na disposable DB
  `node web_client/scripts/run_db_tests.js database/tests/blueprint/layout_integration_test.sql`;
  předem ověřit lokální URL/markery podle backend/local-E2E pravidel. Produkce
  není testovací prostředí. Přidat scoped-font/mode/schema/downgrade cases.
- **Distribuce:** package `tool/archive_check.sh`, manifest/piny a současné
  web_client testy pro kernel/Blueprint. Nejprve přes scoped `rg` zjistit owning
  test/runner v aktuálním checkoutu, potom spustit existující lane, ne nový
  obcházející skript. Stejný corpus projde skutečným distribuovaným artefaktem.
- **Výkon:** stávající `tool/benchmark_layout_scene_cache.dart` a
  `tool/drag_overlap_benchmark.dart` pro CPU porovnání; to není důkaz browser FPS.
  Dodat izolovaný headless browser trace drag/scroll na stejných fixtures,
  p50/p95 a počty full compile/reflow. Cíl je nulové full compile při panel scrollu
  a nulové reflow při rigid move. Zhoršení p95 proti baseline nad 10 % vyšetřit
  před handoffem; absolutní UI latenci naměřit, ne slibovat z VM benchmarku.

## Provozní hranice a rollback

Aktuální stav cílového backendu je před produkční etapou nutné zjistit z jeho
aktivace a read-only inventury. Pokud již má nové layouty, převod potřebuje
vlastní receipt a optimistic revision + source-hash check; pokud ne, legacy převod může
rovnou emitovat cílový formát. Nepřepisovat historické obchodní identity.

Po prvním uloženém dokumentu 2 není bezpečné vrátit writer rozumějící pouze 1.
Rollback aplikace musí ponechat čtečku/guard nové verze nebo editor dočasně
přepnout do read-only. Obnova starých dat není automatický release rollback.
Konkrétní tenant, produkční inventura/převod a rollout vyžadují samostatný rozsah.

## Co může počkat

Rozdělení velkých souborů model/operations, další optimalizace nad nutné
invalidation/history opravy, přesnější shaping/kerning a skutečné řezy fontů mohou mít
vlastní navazující změny, pokud jsou identita fontu a resource protokol verzované.
Současný rune-by-rune glyph renderer a syntetické B/I nejsou důkaz podpory
kontextového tvarování všech písem jen proto, že je rodina v Google katalogu.
Nezaměňovat dostupnost rodiny s ověřeným pokrytím znaků a shapingem.

Nové metadata typovat na hranicích; neprovádět plošný přepis každého JSON mapu
jen pro vzhled kódu. Není třeba měnit databázi na jeden řádek pro každý bod/glyph
ani nahrazovat současnou revizi CRDT systémem.

## Předpoklady, otevřené provozní brány a přijaté kompromisy

- **Potvrzeno:** chyby F1-F10 mají konkrétní producent/consumer nebo izolovanou
  reprodukci. Neznamená to, že každý záznam v živé databázi je těmito chybami dotčen.
- **Předpoklad pro realizaci:** stávající dvě pracovní kopie představují požadovanou
  Blueprint větev. Před implementací porovnat head/diff s uvedenými SHA; zachovat
  cizí rozpracované změny, neprovádět reset ani slepý přesun do dirty původního main.
- **Neověřeno:** aktuální počty starých/offgrid dokumentů, skutečný objem fontových
  outlines a běžné produkční payloady. Read-only inventář v autorizované etapě
  rozhodne rozsah konverzní práce; nebrání implementaci kontraktu a fixtures.
- **Rozhodnutí:** sparse deklarace místo resolved snapshots; integer obvod místo
  všech grid buněk; materializované nodes pro render; jedna aggregate revize a
  explicitní proposal místo CRDT. Omezuje se duplicita a počet nových veřejných seams.
- **Kompromis:** importer zachová vzhled a identity, neobnoví historický produktový
  ani stylový záměr, který nikdy nebyl uložen. Nejasnosti mají receipt a vyžadují
  přezkum, nikoliv optimistickou heuristiku.
- **Pozdější verze:** pojmenované styly, další scope, pokročilé font faces/shaping
  potřebují explicitní rozšíření kontraktu. Plán omezuje budoucí drastický refaktor,
  nemůže slíbit, že žádná další migrace nebude nikdy potřeba.
- **Produkční blocker:** konkrétní tenant/rollout není určen. Nepouštět převod ani
  deployment z této plánovací session. Při pozdější autorizaci připravit řešení
  všech unresolved záznamů a write-window, teprve poté přepnout writer.

## Dokončení

- Existuje jeden cílový interní model, resolver a seating/placement owner.
- Ukládá se vlastní záměr, ne jen odhad z výsledné hodnoty.
- SQL, core a distribuovaný kernel se shodují na kontraktových fixtures.
- Save/read v obou klientech zachová styl, glyphy, fyzické i obchodní identity.
- Všechny položky mazacího seznamu jsou odstraněny nebo omezeny na importer.
- Každá nejednoznačnost má report; unresolved záznam se nesmí přepnout na nový writer.
- Undo/redo, async Save a attach nemají nehlídanou vedlejší cestu.
- UI a výkonové brány jsou doložené na uloženém a znovu načteném dokumentu.
- Produkční kroky nejsou považovány za hotové na základě lokálního průchodu.


Implementation clarification 2026-10-20: a typed assembly root may carry the same
closed `seating` profile as a table. Count commands read that explicit profile,
so pasting a vehicle/row into a document with different physical defaults does
not silently change its future spacing or new-seat dimensions. A fragment
crossing document style/physical contexts materializes the source context into
ordinary local style declarations and root profiles once. No new render cascade
or fragment-specific runtime styling layer is introduced.
