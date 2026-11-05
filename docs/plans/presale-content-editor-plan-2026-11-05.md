# Jedna stránka před otevřením přihlášek

Datum: 2026-11-05  
Stav: Doporučený návrh po rozboru s GPT-6 Astra, medium reasoning  
Ověřování: úsporný průzkum pro tento návrh; implementace standard kvůli veřejnému kontraktu a převodu obsahu  
Výchozí zdroj: `c798dc207` z `origin/main`  
Rozsah tohoto výstupu: návrh, plán a statický interaktivní koncept. Žádná změna aplikace ani produkčních dat.

## Výsledek pro pořadatele

Pořadatel dostane použitelnou stránku před otevřením bez nutnosti stavět ji z bloků. Základní pohled ukazuje návštěvnický náhled, jednu relevantní volbu upozornění e-mailem a akci **Upravit vzhled a obsah**. Volné skládání je dostupné na vyžádání. Uživatel tento směr výslovně potvrdil a následně upřesnil požadavek na jednoduchý výchozí pohled.

Odpočet, e-mail, vlastní texty a obrázky tvoří jednu uspořádanou stránku. Odpočet je volitelný. Zapnutí e-mailu aktualizuje náhled a vloží jeho blok jednou, ale neotevře samo celý editor.

[Interaktivní koncept](../previews/presale-page-editor-2026-11-05.html) ukazuje základní i rozšířený pohled. Je to interakční návrh s ilustračním odpočtem a bez připojení k backendu, nikoli náhrada skutečných komponent pro implementaci.

## Rozhodnutí a alternativy

| Varianta | Přínos | Omezení | Verdikt |
| --- | --- | --- | --- |
| Zviditelnit dnešní editor v nastavení rozvrhu | Nejmenší zásah | Nadále dva dokumenty, oddělené zapínání funkcí a nejasný náhled | Pouze případný mezikrok, ne cílový stav |
| Jedna stránka, jednoduchý přehled a volitelný editor | Dobré výchozí nastavení, volnost až na vyžádání, jeden vlastník změn | Vyžaduje koordinaci historie a bezpečné sjednocení starého obsahu | Doporučeno |
| Jen hotová rozložení | Málo voleb | Omezuje požadované volné skládání a existující stránky | Použít nanejvýš jako startovní obsah prázdné stránky |

Použije se existující rich-text engine. Nevznikne další page builder ani paralelní JSON seznam bloků vedle HTML.

## Zjištěná fakta

| Fakt | Zdroj | Dopad |
| --- | --- | --- |
| Editor už umí text, obrázky, jednotlivé vložené bloky, přesun nahoru/dolů, mazání a historii. | `lib/components/html/rich_html_editor_controller.dart`: `insertEmbeddedBlock`, `moveBlock`, `removeAtomic`, `undo`; `html_embedded_block.dart` | Pro požadovanou volnost není nutný nový editor. |
| Hlavní dokument je uložen v `schedule.countdown_title`, ale editor je schovaný v rozbaleném rozvrhu a dodaný popisek je skrytý přes `showLabel: false`. | `lib/components/forms/views/form_editor_content.dart`: rozvrh a `_buildHtmlFieldPreview` | Problém je i v pojmenování a umístění celé funkce. |
| Další přepínač zpřístupňuje druhý dokument `before_start_message`, který se přidává pod první. | Tentýž editor; `form_page.dart`; web `form_availability_service.js` | Jedna návštěvnická stránka má dva autorské zdroje. |
| Vložení atomického bloku v obecném editoru mění HTML. Odstranění v rodiči navíc vypíná odpočet nebo pozastavuje sběr; vkládání tyto změny symetricky neřídí. | `RichHtmlEditorController.insertEmbeddedBlock`; callback editoru v `form_editor_content.dart` | Dokument a funkční stav potřebují společného doménového vlastníka. |
| Dnešní `preview=true` přeskakuje stav před otevřením a ukazuje otevřený formulář. | Web `FormAvailabilityService.renderStatus`; `form_page.dart` | Tento přepínač nelze bez změny použít jako náhled nové stránky. |
| Pozastavení sběru zachová upozornění; ukončení uzavře odběry a již nelze obnovit. | `database/functions/sale_opening_notifications/settings.sql` | Přesun/odstranění bloku nesmí trvale ukončit kampaň. |
| Neversionovaný starší save může použít aktuální verzi. | `database/functions/eshop_forms/update_form_client_sync_v1.sql:37` | Pouhé navýšení aggregate version neochrání převedený obsah před všemi staršími klienty. |
| Legacy writer přepisuje metadata; veřejná projekce vrací metadata včetně libovolného nového klíče. | `update_form.sql:132`; `get_effective_form_data.sql` | Archiv nesmí být v běžných veřejných metadatech. |
| Každý starý HTML dokument má limit 65 536 znaků; settings patch 131 072 bajtů, MCP HTTP vstup 48 kb a autorský snapshot 1 MiB. | `form_settings.sql`; `tools/festapp/src/operations/forms.mjs`; `remote/server.mjs`; `admin_form_reads.sql` | Slepé spojení může překročit existující rozpočty. |

## Cílový produktový model

### Dostupnost

Stávající nastavení vlastní ruční otevření/zavření, začátek a konec. Kompozice stránky do těchto údajů nezapisuje. Datum ani čas se nekopírují do obyčejného textu dokumentu.

### Stránka před otevřením

Viditelná samostatná část existujícího editoru formuláře, mimo rozbalovací nastavení odpočtu:

- Hotový návštěvnický náhled s aktuálním tématem formuláře.
- Jedna volba nového sběru e-mailů, pokud ji stav a oprávnění dovolují.
- **Upravit vzhled a obsah** otevře nebo rozbalí kompozici; samo nic nemění ani neoznačí formulář za upravený.
- **Zpět na přehled** pouze změní pohled. Rozpracované úpravy zůstávají v témže rodičovském draftu.
- Běžné **Uložit formulář** zůstává jediným uložením celého agregátu. Nevznikne další povinné Použít/Uložit uvnitř Použít/Uložit.

Rozšířený pohled ukáže nástroje pro text, obrázky, odpočet a e-mail, pořadí bloků, formátování, historii, podobu standardní hlavičky a desktopový/mobilní náhled. Bez libovolných absolutních XY souřadnic; přirozený tok stránky zůstává responzivní. Případné startovní návrhy se nabízejí jen pro prázdný dokument. Nepřepisují již napsaný obsah.

Správa zájemců a nevratné ukončení zůstávají sekundárními akcemi souvisejícími s e-mailovým blokem. Sbírání se neovládá současně na dvou viditelných místech. Stávající oddělená aktivační cesta z menu má vést na stejnou část stránky nebo do ní delegovat; nesmí vytvářet jiný draft či jinou logiku vložení.

### Dobré výchozí nastavení

- Nový formulář dostane explicitně `design.presale_header = event_and_date`; dokument může zůstat prázdný. Odpočet se automaticky nezapíná.
- E-mailový sběr se neaktivuje pouhým otevřením editoru. Vyžaduje výslovné zapnutí a platný budoucí termín.
- Standardní hlavička čte název akce z načtené příležitosti (`FormBundle.occasion.title` / `FormModel.occasionTitle`), s definovanou náhradou názvem formuláře, pokud název akce chybí. Nepoužívá název náhodně vybrané globální příležitosti.
- Termín čte výhradně z rozvrhu a používá existující časovou zónu a lokalizované formátování.
- `design.presale_header` má hodnoty `event_and_date`, `date`, `none`. Volba je pouze v rozšířených úpravách. Nejde o režim default/custom ani druhý dokument.
- Chybějící nový klíč neznamená univerzální přidání hlavičky ke starým stránkám. Při převodu stávající odpočet odpovídá `date`, ostatní stránky `none`, čímž se zachová dosavadní automatická hlavička. Neodhadovat podle textu, zda už obsah obsahuje vlastní nadpis.
- Prázdný dokument je legitimní. Pokud se nic smysluplného nevykreslí, zůstane užitečná zpráva s termínem, i při `none` nebo pozastaveném e-mailu.
- Stávající stránky se při otevření nastavení, zapnutí e-mailu či změně data znovu negenerují. Volba doporučené hlavičky nebo náhrada obsahu je vědomá úprava.

### Po uzavření

Stávající zpráva při zavření zůstává samostatným stavem. Není skrytou druhou částí stránky před otevřením. Tento plán nemění její funkci.

## Vlastníci a kontrakty

### Dokument a doménové změny

`PresaleContentDraft` (nový modul ve forms doméně) pracuje nad `FormEditorDraft`. Vlastní kompozici a příslušné záměry funkcí, ale sám nic neukládá do databáze. Výsledek předá stávajícímu writeru formuláře s původní aggregate/product verzí a příkazovou identitou.

**Jediný aktivní HTML wire field zůstává `schedule.countdown_title`.** V kódu se pojmenuje podle celé stránky, například `presaleContent`, ale nepřidá se vedle něj druhý aktivní `presale.content` s fallbackem. Historický název na drátu je úmyslně zachovaný kompatibilní kontrakt.

Zachovají se samostatné příznaky funkce odpočtu a kampaně; vlastník stránky musí provést jejich příslušné změny v jedné draftové transakci s HTML. Pozice bloku se neukládá ještě do dalšího paralelního seznamu.

`RichHtmlEditor`, `HtmlEmbeddedBlock` a `HtmlSaveCoordinator` zůstávají obecné. Nezískají znalost kampaní ani odesílání e-mailů. `TemplateAuthoringProvider` je specializace pro šablony, ne náhrada obecného integračního bodu pro historii tohoto editoru.

### Jedna historie

Vložení/odstranění funkčního bloku, příslušná změna příznaků a původní poloha tvoří jednu změnu. Text, média i funkční operace mají společné chronologické Undo/Redo. Nelze přidat nezávislou historii metadat vedle nekontrolovaného SuperEditor Undo.

Nutný je úzký, doménově neutrální transakční/historický integrační bod u `RichHtmlEditorController`, který dovolí vlastníkovi stránky svázat HTML a externí draftový stav. Toolbar, klávesové Delete/Backspace, Cut, vložení či nahrazení dokumentu a klávesové Undo/Redo musí projít stejnou koordinací. Neprovádět to jen v callbacku tlačítka Odebrat.

Odstranění e-mailového bloku ihned pozastaví nový sběr v draftu a nabídne jasnou zprávu s **Vrátit**. Vrátit obnoví původní polohu i původní stav, včetně již pozastaveného sběru. Nová následující změna zneplatní starou nabídku Vrátit; nesmí se dodatečně přimíchat zastaralý stav. Potvrzení se vyžaduje až pro nevratné ukončení kampaně.

Obecné vložení HTML, paste nebo MCP text nesmí bez výslovného záměru aktivovat sběr. UI pro vložení e-mailu volá doménový příkaz, nikoli jen obecné vložení značky. Nekoordinované vložení musí být odmítnuto nebo zřetelně inertní s explicitním nastavením; nesmí v náhledu předstírat funkční sběr. V doménovém editoru se odstraní obcházející generická vkládací akce pro tyto dva bloky.

### Náhled a veřejné zobrazení

Flutter `PresaleContent` nahradí timer-centrické `CountdownContent`; skutečný `CountdownWidget` zůstává komponentou odpočtu. Webový `renderPresaleContent` a oba modely sdílejí jednoznačná pravidla pro dokument, standardní hlavičku, způsobilost funkcí a fallback.

Náhled používá skutečné veřejné komponenty příslušné platformy a aktuální rodičovský draft. Nejde přes dnešní `preview=true`, který přeskočí stav před otevřením. Náhled ani jeho stavový přepínač nic neukládají, neodesílají a nepřenášejí HTML draftu do veřejné URL. Stejné fixture případy musí ověřit web i Flutter; pixelová shoda obou platforem se bez měření neslibuje.

Routing `BEFORE_START` v obou klientech musí nově přijmout i hlavičku bez HTML a bez obou funkčních bloků. Dnešní podmínka závislá jen na odpočtu/HTML/e-mailu nesmí nový výchozí pohled shodit do obecného „nedostupné“.

Ruční zavření, dosažení začátku/konce a způsobilost odběru zůstávají pod stávajícími autoritami. Kompozice tyto přechody nepřepisuje. Embed používá stejný dokument a pravidla s rozměry podle kontejneru, ne vlastní kopii obsahu.

## Převod starých dvou dokumentů

### Soukromý archiv a vlastnictví

Před převodem vznikne kanonický soukromý záznam, například `public.form_presale_content_archive`, s identitou formuláře, klíčem převodu, původní aggregate verzí, hashem zdroje, oběma HTML dokumenty a příznaky, stavem převodu a výslednou verzí. Tabulka nesmí být veřejně čitelná; obnova jde výhradně přes autorizovaný editor a stávající typovaný predikát pro autora formuláře. Bez triggerů.

Archiv se nedává do `forms.data`: starý full-metadata writer by jej mohl vymazat a současná veřejná projekce by jej mohla odeslat návštěvníkům. Archiv není druhý aktivní dokument ani renderovací fallback.

### Provozní doplnění podle živého preflightu

Release preflight 5. 11. našel v organizaci 3 sedm formulářů bez existujícího
autorizovaného editora. Migrační operátor proto používá neveřejné
`convert_form_presale_content_internal` jako skutečný PostgreSQL owner, s explicitní
organizací a stejnou zámkovou, hashovou, verzovanou a archivní transakcí. Jde o
`SECURITY INVOKER` core s EXECUTE pouze pro postgres; API role ani service_role
k němu přístup nemají. Veřejná authoring wrapper funkce nad tímto jediným core
nadále vyžaduje `can_author_forms`. Žádná uživatelská práva se nepřidávají a nikdo
se nevydává za chybějícího autora. Obnova v editoru má stále původní oprávnění.

### Algoritmus převodu

1. Před změnami ověřit čistou kompozici a velikosti pro všechny formuláře zvoleného tenanta. Nevypisovat obsah ani osobní data do repozitáře; výstupem jsou počty, velikosti a identifikátory vyžadující řešení.
2. Pod stávajícím zámkem formuláře a očekávanou verzí archivovat originály, pokud tento převod ještě neexistuje. Opakovaný příkaz nesmí znovu připojit stejný text.
3. Nejprve normalizovat původní hlavní fragment v jeho historické hranici. Při zapnutém odpočtu bez explicitního timer slotu vložit implicitní timer na konec tohoto fragmentu, **před** případný vedlejší obsah. Nestačí spojit dokumenty a nechat legacy fallback přidat odpočet až za oba. Zachovat rozdíl `null` versus úmyslně prázdného titulku a jeho systémového výchozího textu; nezaměnit jej za libovolně nově generovaný autorský text nebo natvrdo zapsané datum. Kontrakt této normalizace a lokalizovaného systémového textu musí být vyřešený a otestovaný ve vlně 1 před převodem dat. Potom zachovat původní hlavní HTML a připojit pouze druhý dokument, který byl způsobilý k zobrazení podle přesného starého predikátu větve před otevřením a svého přepínače. Nepoužít jen `show_before_start_message=true`; samotný tento příznak dříve větev neaktivoval. Nevyhodnocovat způsobilost jen podle dnešních hodin nebo dočasného ručního zavření.
4. Skrytý nebo dříve nedosažitelný text ponechat jen v soukromém archivu. Jeho začlenění do veřejného dokumentu je až explicitní akce **Obnovit dřívější skrytý obsah** v rozšířeném editoru a běžné uložení draftu.
5. Původní vedlejší obsah zachovat za hlavním, s definovaným levým zarovnáním a menší typografií. Flutter dnes používá pro hlavní dokument 24 a pro vedlejší `HtmlView` výchozích 18; web má pro vedlejší část vlastní margin a line-height. Vytvořit pojmenovanou migrační obálku podporovanou sanitizerem i oběma renderery, ne neověřený stringový concat. Uchovat obsah, pořadí a záměr prezentace, nikoli slibovat shodný každý pixel.
6. Značky interaktivních bloků z dříve inertního vedlejšího dokumentu nesmí po spojení začít samy fungovat. Převod zachová jejich původní inertní význam a nic nezapne. Primární singletony se vyhodnotí podle starých skutečných renderovacích pravidel a originály zůstanou archivované.
7. Zapsat jeden kanonický dokument, explicitní `design.presale_header`, odstranit aktivní použití starých druhých polí a navýšit aggregate version. Stav kampaně, počet odběrů a fronta zpráv se převodem nesmějí změnit.

### Rozpočty a starší writery

V této specifikaci se velikostní limity svévolně nezvyšují. Před prvním převodem musí preflight prokázat, že výsledek včetně obálky projde stávajícím polem, settings patchem, autorským snapshotem a skutečnou transportní cestou. Pokud ne, produkční převod je zablokován, dokud nebude samostatně dořešený a otestovaný omezený rozpočet. Nikdy netruncovat obsah, nevynechávat druhý dokument a neponechat trvalý dvojí renderer jako tiché řešení. To je známý datový předpoklad, ne povolení ignorovat velké formuláře.

U převedeného formuláře musí jediná vstupní autorita:

- Ignorovat prázdné/null vysloužilé druhé položky ze starých snapshotů jako no-op.
- Odmítnout smysluplnou změnu vysloužilého druhého dokumentu s jasnou chybou aktualizace/načtení nové verze.
- Nepovolit neversionované změny chráněného předotevíracího dokumentu ani nové hlavičky. Stará metadata nesmějí smazat nový klíč jen jeho vynecháním/null hodnotou; explicitní `none` je vědomá volba aktuálního klienta.
- U nesouvisejících starších zápisů připustit jen prokazatelný no-op chráněné části; nepředstírat, že chybějící expected version znamená bezpečné optimistic locking.
- Uchovat soukromý záznam převodu mimo nahrazovaná veřejná metadata.

Aktuální UI a MCP následně zapisují jen jediný aktivní dokument. Legacy ingress zůstane jako výslovně vymezená hranice pro již vydané klienty, nikoli jako druhá autorská cesta nebo opakovaný převod při každém čtení.

## Invarianty a chování

| Situace | Očekávaný výsledek |
| --- | --- |
| Otevření přehledu nebo úprav | Žádná změna dokumentu, příznaků, historie ani dirty stavu |
| Nový formulář | Užitečná automatická hlavička; odpočet a nový sběr nejsou svévolně aktivované |
| Zapnutí e-mailu | Jedno vložení nebo obnovení bloku, zachované texty/obrázky/pořadí, aktualizovaný náhled; editor zůstane podle volby uživatele zavřený |
| E-mail bez odpočtu | Běžná validní stránka, bez implicitního zapnutí odpočtu |
| Odpočet bez e-mailu | Nevytvoří se kampaň ani odběr |
| Oba bloky | Každý nejvýš jednou, pořadí řídí dokument na obou platformách |
| Pauza | Blok i poloha zůstanou v editoru, veřejný sběr zmizí; dosavadní upozornění zůstávají |
| Odstranění a Vrátit | Jedna vratná transakce obnoví obsah, polohu i přesně původní stav sběru |
| Změna termínu/názvu akce | Aktualizuje sdílenou hlavičku a odpočet, nepřepíše authored HTML |
| Prázdný dokument / vše neaktivní | Užitečná zpráva s termínem, žádná prázdná nedostupná stránka |
| Ukončená kampaň | Žádné falešné tlačítko obnovy; ostatní obsah a autorizovaná historie zůstanou dostupné |
| Návrat ze skládání | Stejný dokument a parent draft; nevzniká další režim nebo další uložená kopie |

## Implementační vlny

### 1. Kompoziční model, historie a bezpečnost převodu

- Zavést `PresaleContentDraft` a kontrakt hlavičky ve forms doméně a `packages/festapp_core`.
- Rozšířit úzké historie/transaction seam v `RichHtmlEditorController`; obecný editor musí zůstat bez kampaní.
- Přidat čistý legacy převod a jeho fixture případy. Ověřit varianty null, prázdný string, prázdný odstavec, skrytý/dosažitelný/nedosažitelný vedlejší text, inertní značky a maximální velikosti. Samostatná fixture musí pokrýt zapnutý implicitní odpočet bez slotu a vedlejší text/obrázek: výsledné pořadí musí zůstat primární obsah, timer, vedlejší obsah ve starém i novém readeru.
- Udělat jen autorizovaný agregovaný size preflight zvoleného tenanta před produkčním převodem.
- Ověřit složené insert/remove/undo/redo, klávesové Cut/Delete a pořadí s textovou editací.
- Výstup: žádná poloviční změna HTML/příznaků; podmínky převodu jsou strojově ověřené. Nesplněný rozpočet blokuje další převod.

### 2. Soukromý archiv a ochrana existujících writerů

- Kanonické SQL pro archiv, autorizované čtení/obnovu a idempotentní převod pod stávajícím form lockem.
- Upravit `update_form_client_sync_v1.sql`, `update_form.sql`, `form_settings.sql` a příslušný admin settings/authoring boundary tak, aby starý snapshot nevrátil druhý dokument a nesmazal hlavičku.
- Zaregistrovat `design.presale_header` v kanonickém modelu, SQL whitelistu a `tools/festapp/src/operations/forms.mjs`.
- Ověřit transakční rollback, retry stejného převodu, konflikt verze, starý neversionovaný save a zákaz veřejného čtení archivu. Žádné aplikační triggery.
- Výstup: backend je připravený na převod i současné starší klienty, bez nového veřejného úniku skrytého textu.

### 3. Jednoduchý přehled a editor na vyžádání

- V `form_editor_content.dart` přesunout celou stránku z rozvrhu do viditelné části **Stránka před otevřením**.
- Implementovat kompaktní výchozí pohled a rozšířenou kompozici nad stejným draftem. Datum zůstane v dostupnosti.
- Propojit všechny aktivace, včetně průvodce vytvořením akce a stávajícího menu upozornění, se stejnými doménovými příkazy. Prověřit konkrétní setup entrypointy při přesunu callerů, ne vytvářet novou kopii inicializace.
- Obecnou vkládací akci pro funkční bloky v tomto kontextu nahradit koordinovanou doménovou akcí. Zachovat rendering a standardní textové/médiové nástroje engine.
- Správa zájemců a ukončení zůstanou sekundární; odstraní se duplicitní současné ovládání sběru.
- Ověřit opening/customization bez dirty stavu, opakované aktivace, readonly práva, zrušenou kampaň, návrat do draftu, média a jeden parent Save.
- Výstup: běžný uživatel vidí jen hotovou stránku a základní volbu, pokročilý může libovolně skládat obsah.

### 4. Skutečný náhled a veřejné renderery

- Upravit skutečný `BEFORE_START` routing pro nový výchozí případ: prázdné HTML, oba bloky vypnuté, standardní hlavička zapnutá. Musí projít do předotevíracího rendereru, nikoli do obecného nedostupného stavu.
- Přesunout Flutter obsah do pojmenovaného `PresaleContent`; sjednotit s web `widgets/presale_content.js` a jejich modely pravidla hlavičky, singletonů a fallbacku.
- Náhled draftu volá tytéž veřejné komponenty, s inertními submit akcemi a správným stavem před otevřením.
- Ověřit společné fixture pro všechny kombinace bloků, hlaviček a dostupnosti; desktop/mobile, světlý/tmavý vzhled, úzké embed kontejnery a změny velikosti textu.
- Výstup: pořadí a obsah náhledu odpovídají veřejné stránce; dnešní bypass otevřeného formuláře není vydáván za předotevírací náhled.

### 5. Převod dat a odstranění aktivních starých cest

- Pro schválený tenant nejprve nasadit backend s ochranou starých writerů a archivem, potom převádět pod zámkem jednotlivých formulářů. Archiv a zápis tvoří jednu transakci.
- Převod zachovává dosavadní zobrazování přes existující wire key; starý čtenář nemusí znát nový název pole.
- Před finálním veřejným cutoverem nesmí zůstat žádný nevyřešený oversized/pending/blocked formulář v podporované množině. Neřešit je tichým fallbackem.
- Odstranit druhý editor a aktivní čtení `show_before_start_message` / `before_start_message`, včetně veřejného webu, Flutteru a aktuálního MCP writeru. Zachovat pouze jmenovanou archivní a legacy ingress hranici.
- Aktualizovat formulářový README, návody, veřejné MCP schéma a generovanou referenci přes `pnpm --dir tools/festapp run docs:generate` a ověřit `docs:check`.
- Výstup: jedna návštěvnická stránka, jeden aktivní dokument a žádné druhé aktivní renderování ani nechráněný legacy zápis.

## Co se odstraní a co vědomě zůstane

| Prvek | Cílový stav | Důkaz |
| --- | --- | --- |
| Obsah schovaný pod rozvrhem/odpočtem | Odstranit původní autorský vstup | Kontrola skutečného editoru a scoped `rg` callerů |
| Samostatný druhý message editor | Odstranit po úspěšném převodu | UI test a absence druhého writeru |
| Aktivní veřejné připojování `before_start_message` | Odstranit | Shodné fixture web/Flutter a scoped search |
| `CountdownContent` jako název celé stránky | Nahradit `PresaleContent` | Analyzér po přesunu všech symbolových callerů |
| `CountdownWidget` | Zachovat pro samotný timer | Příslušný widget stále funguje bez e-mailu |
| `schedule.countdown_title` na drátu | Zachovat jako jediný aktivní dokument | Schéma a writer testy, žádný paralelní HTML klíč |
| Soukromý historický archiv | Zachovat jako autorizovanou obnovu | Není v public projekci ani v repozitáři s daty |
| Legacy vstup vydaných klientů | Jeden výslovně omezený převod/no-op/reject boundary | Testy neversionovaných a vysloužilých zápisů |
| Aktuální `preview=true` | Zachovat pro náhled otevřeného formuláře, nepoužívat pro tuto stránku | Dva jasně pojmenované záměry, žádný falešný presale náhled |

## Ověření a provozní hranice

Pro návrh neprobíhaly aplikační testy ani produkční inventura obsahu. Interaktivní statický koncept prošel kontrolou JavaScriptu a samostatnou browser kontrolou desktop/mobile, přesunů, singletonů, zapnutí/pauzy, složeného Vrátit/Znovu a nezapisujících stavových ukázek. Po posledním zjednodušení prošlo také skrytí všech pokročilých voleb, nezměněný dirty stav při jejich otevření a zachování obsahu při návratu do přehledu.

Implementace použije smysluplné cílené kontroly: `packages/festapp_core` modelové testy, testy forms editoru a HTML historie, JS presale/translation/security testy a reálné lokální SQL testy převodu a konfliktů. Přesné nově vzniklé test soubory pojmenovat podle doménových invariantů; nepřidávat testy jen podle tvaru implementace. Flutter úlohy vždy jednotlivě a testy s `--concurrency=1`.

Produkční migrace, commit/push a release nejsou provedené tímto návrhem. Až bude požadována implementace, použít platné autorizace dané session; tento dokument sám nezakládá oprávnění měnit data. Při releasu zachovat standardní source CI, tenant drift a nasazení jen schváleného tenanta. Odstranění starých rendererů je podmíněné dokončeným převodem, ne jen novou obrazovkou.

Rollback UI nesmí obnovit dvě aktivní kopie obsahu ani odstranit ochranu převedených formulářů. Originály zůstanou v soukromém archivu; jejich obnova je vědomá verzovaná editace, nikoli slepé vrácení staré full-metadata kopie.

## Neověřené předpoklady a jediná zbývající datová brána

Živý počet a velikosti starších dokumentů se v tomto návrhu nezjišťovaly. Vlastníkem ověření je implementátor první vlny, který před jakoukoli konverzí vrátí agregovaný preflight a nesmí obejít velikostní blokaci. Interakční směr je rozhodnutý uživatelem: volné skládání, ale výchozí jednoduchost a pokročilé možnosti až na vyžádání. Nečeká se na další volbu vizuálního stylu nebo na výběr nového editorového engine.
