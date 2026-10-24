# Konkrétní product type na vstupence - canonical cutover

> Historical plan or dated evidence. Statuses, versions, authorization and pending steps below apply to the recorded phase, not automatically to today. Use [current documentation](../../README.md) for operating procedures; archiving does not close unverified gates.


Datum: 2026-10-13  
Stav: Implementováno a následně nasazeno; rozsah backendu a jednotlivých webových oprav dokládá [realizační záznam](ticket-product-type-cutover-implementation-2026-10-13.md). Starší přípravné podmínky níže nejsou aktuální seznam úkolů.  
Verification: standard (datová migrace, autorizace, sdílený kontrakt PDF)

## Výsledek a hranice

Editor vstupenky umožní přidat textové pole pro konkrétní `eshop.product_types.id`, například VIP večeři, odvoz nebo libovolnou jinou skupinu produktů. Pole bude mít vlastní upravitelný popisek. Náhled ukáže skutečný příklad z viditelných produktů této skupiny. Vydaná vstupenka zobrazí pouze produkt přiřazený k dané vstupence. Výběr nebude záviset na `product_types.type`, názvu produktu ani odhadu podle textu.

Existující konfigurace a historické objednávky musí po převodu dál fungovat. Součástí práce jsou Flutter editor/canvas, SQL ukládání a validace, Edge náhled a společný PDF renderer, kopírování akce, migrace uložených i implicitních šablon, testy a dokumentace. Neprovádí se změna cen, rezervací, plateb, scanneru ani přepis objednávek.

**Rozsah odstranění `product_types.type`:** tento plán odstraňuje jeho použití pro výběr a tisk produktových polí vstupenky. Sloupec zatím zůstává pro další doménové chování, zejména `spot` a formuláře. Jeho globální zrušení by znamenalo samostatnou migraci rezervací a formulářového enginu a nelze ho vydávat za součást tohoto ohraničeného cutoveru. Jednorázový převod smí číst `food`/`taxi`; cílový runtime nikoli.

Plán autorizuje pouze přípravu. Produkční SQL, deploy, commit a push vyžadují samostatné zadání. Release klienta je pro jeden vybraný tenant. Sdílené Edge Functions a DB nejsou izolované produkční větví: odstranění starého runtime musí mít inventuru všech jejich skutečných konzumentů a explicitně schválený datový rozsah. Nepřevádět další organizace mlčky.

## Ověřený stav a důsledky

Podklad je aktuální pracovní strom větve `feat/occasion-setup-wizard-20261007`, HEAD `eb23047248d59bf86345b9e0b79db4a988275231`. Obsahuje rozsáhlé cizí necommitované změny, včetně `duplicate_occasion.sql` a testů ticket layoutu. Implementace musí zachovat tyto změny a nejprve potvrdit svůj pracovní základ.

| Fakt v repozitáři | Konkrétní evidence | Důsledek |
|---|---|---|
| Produktové pole je pevné `food`, prefix je `Večeře:` | `supabase/functions/_shared/ticketRenderData.ts`: `normalizeTicketData` | Nové pole potřebuje explicitní ID a konfigurovatelný popisek. |
| Výběr bere první vazbu dle `order_product_ticket.id` a mapu podle řetězce typu; existuje fallback `o.product_type === 'food'` | Tamtéž; `ticketGeneration.ts`: `prepareTicketRenderer` | Odstranit mapu podle typu i fallback; zachovat deterministické pořadí. |
| `taxi` existuje v doménovém modelu, ale současný layout a normalizer nemají taxi binding | `lib/components/eshop/models/product_model.dart`: `taxiType`; `ticketLayout.ts`: `bindings` | Existence produktu odvoz nedokazuje, že se dnes tiskne. Migrovat konfiguraci, ne automaticky každý taxi produkt. |
| Layout má verze 1/2, max. 11 prvků a unikátní binding | `ticketLayout.ts`: `validateLayout`; Dart `models/ticket_layout.dart`; SQL `others/ticket_layout.sql` | Pouhé přidání dalšího bindingu nestačí pro více product typů. |
| Render data a flow jsou adresované bindingem | `_shared/generateTicket.ts`, `ticketLayout.ts`: `positionedElements`; Dart canvas a `TicketTemplate.positionedElements` | Převést render data a flow na identitu prvku, jinak se produktová pole přepisují. |
| Editor pouze spravuje již přítomné prvky | `views/ticket_layout_editor.dart`: `elements`; `ticket_layout_properties.dart` | Přidat explicitní akce přidání/změny/odstranění product type pole, včetně undo/redo. |
| Náhled zná produkty, ale odvozuje string `type`; chybí názvy skupin a vazby na formuláře | `preview-ticket-layout/products.ts`; `eshop/get_products_and_types.sql` | Pro picker je potřeba rozšířit existující datový kontrakt bezpečně a aditivně. |
| Veřejný formulář vybírá viditelná pole a non-hidden produkty | `eshop_forms/get_form_by_link.sql`, vazba `form_fields.product_type` | Dostupnost v nabídce řešit přes ID a viditelnost; nepoužívat `type`. |
| Preview vybírá admission+food a jejich cenu; prázdný katalog používá ilustraci | `ticketRenderData.ts`: `sampleData` | Nový příklad musí odpovídat právě vybranému ID, nikoli obecné ukázce večeře. |
| PDF pro email a download má společný renderer | `_shared/emailRenderer.ts`: `renderQueuedEmail`; `download-ticket/index.ts`; `ticketGeneration.ts` | Změna zasáhne i čekající emaily a opakované stažení starých objednávek. |
| Ticket detail obsahuje product ID, ale nepřenáší product type ani název | `eshop/get_tickets_with_details.sql` | ID mapu naplnit katalogem včetně skrytých produktů; absence položky je chyba dat, nikoli prázdné pole. |
| Ukládání má verzi agregátu a explicitní očekávaný layout | `ticket_layout_saver.dart`, `features/ticket_feature.dart`, `save_occasion_client_sync_v1.sql`, `update_occasion.sql`, `merge_ticket_layout_features` | Zachovat konflikt/replay semantiku a doplnit validaci ID v kontextu akce. |
| Kopie akce kopíruje features beze změny, product types dostanou nová ID | `others/duplicate_occasion.sql`: `duplicate_occasion_internal_v1`, `tmp_product_types` | Přemapovat layout po vytvoření typů a před dokončením transakce. |
| Chybějící layout importuje geometrii za běhu a znovu vytváří `food` | `_shared/ticketTemplateImport.ts`: `importTicketTemplate`; `resolveTicketTemplate` | Zahrnout i implicitní wide template a chybějící slot; samotné přepsání uložených JSON nestačí. |

Produkční stav byl 2026-10-13 ověřen read-only přes canonical chráněné SSH připojení. Profil `prod/festapptickets` a živá aktivace potvrzují tenant `festapptickets`, generation 1 a organization 3; SQL potvrzuje `vstupenky.online`. Prázdný development checkout není produkčním profilem. [Reprodukovatelná evidence a dotazy](../../plans/ticket-product-type-cutover-evidence-2026-10-13/README.md) obsahují konkrétní ID a agregované výsledky bez zákaznických údajů.

Organization 3 má 77 akcí, 73 ticket features (21 enabled), 15 uložených layoutů (11 schema 1, 4 schema 2) a 58 implicitních konfigurací. Osm food typů je navázaných na formuláře, žádná akce nemá více food typů. Čtrnáct uložených food polí se dělí na čtyři používané vazby (`occasion 82 -> type 104`, `97 -> 119`, `111 -> 135`, `32316 -> 651`) a deset nevyužitých polí bez food typu. Jeden named layout nemá food pole.

Čtyři taxi typy existují jako formulářové produkty, ale žádný uložený layout nemá taxi binding. Ve starém tiskovém kontraktu tedy není odvoz k migraci; nová obecná pole ho umožní explicitně přidat. Inventory zjistila i skryté historicky objednané food produkty a hidden form field. Uzavřený formulář nebo skrytí pole nesmí zrušit historickou vazbu.

Kontrola má 0 cross-occasion form/ticket product vazeb. Všech 669 záznamů bez product joinu má `product IS NULL` a ticket state `storno`; nejde o chybějící aktivní product ID. Sdílený backend má ticket features ještě v dalších 11 organizacích, takže gate společného release je skutečný, nikoli hypotetický. Nebyl ověřen nasazený Edge digest, čekající queue obsah ani dostupnost všech artwork/font resources.

## Cílový kontrakt

### Persistence a vlastníci

`ticket.layout` zůstává v occasion features. Zavést `schemaVersion: 3`, vycházející z font kontraktu verze 2. Aktivní runtime po cutoveru přijímá pouze verzi 3. Verze 1/2 čte jen jednorázový migrační nástroj; nemá runtime alias ani automatický převod při renderu. Historické aplikované migrace zůstávají nedotčené.

Nový produktový element:

```json
{
  "id": "vip-meal",
  "binding": "productType",
  "productTypeId": 123,
  "label": "VIP menu",
  "box": { "x": 20, "y": 150, "width": 180, "height": 24 },
  "visible": true,
  "locked": false,
  "style": { "fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "left" }
}
```

Číslo 123 je pouze vysvětlující příklad kontraktu, ne migrační mapování. `productTypeId` je kladné JS-safe integer existujícího typu v téže akci. Nepovolit ID cizí akce ani pole s ID bez bindingu `productType`. `label` je povinný string, trimovaný, max. 120 znaků; prázdný string znamená tisk bez prefixu. Název skupiny se při přidání použije jako výchozí popisek, uložený popisek se při změně názvu skupiny nemění.

Singleton bindingy (`qr`, `ticketSymbol`, `spotGroup`, `note`, `price`, `occasionTitle`, `occasionDatePlace`, `orderName`, `logo`, `footer`) zůstávají unikátní. Binding `productType` se může opakovat pro různá ID; v jednom template nepovolit duplicitní `productTypeId`. Každý element má unikátní `id`. Limit zvýšit na 32 prvků se zachováním limitu layout JSON 32 KiB a requestu 40 KiB; UI nesmí vytvořit dokument, který server kvůli velikosti odmítá bez vysvětlení.

Render data jsou `Record<elementId, string | null>`. Flow obsahuje existující **ID elementů**, nikoli bindingy; nepovolovat duplicity, neexistující odkazy, QR ani logo. Metadata bindingů slouží pouze výběru zdroje hodnot a UI. Warning vrací ID prvku, UI ho přeloží na konkrétní název pole. QR payload získá jednoznačně z QR elementu, symbol ze symbol elementu.

Kanonickým vlastníkem produktového výběru a formátování je `_shared/ticketRenderData.ts`, použitý preview i produkčním rendererem. SQL je autoritativní vlastníkem přípustnosti uložené reference. Flutter jen ukládá kontrakt, kreslí serverem normalizované ukázky a spravuje dokument; nesmí mít vlastní klasifikaci ani rozhodování o dostupnosti produktů. Mechanická lokální projekce labelu a element ID je níže výslovně definovaná, aby šel text měnit bez síťového requestu.

### Výběr a tisk

1. Pro konkrétní ticket seřadit `order_product_ticket` dle ID a spojit `product` s katalogem podle product ID. Match je pouze `product.product_type === element.productTypeId`.
2. Zachovat současné chování prvního match. Tisknout `data.short_title` / RPC `short_title`, pokud jsou po trim neprázdné, jinak `title`. Nezavádět nový součet množství ani seznam všech variant.
3. Neexistující match znamená `null`; prefix se netiskne. Prázdný nebo whitespace short title nesmí přebít neprázdný plný název. Neprázdný label vytvoří `label + ': ' + název`.
4. Skrytý, vyprodaný nebo již nenabízený produkt na zakoupeném ticketu se nadále tiskne. Production rendering nepoužívá prodejní filtr. Null product vazbu na stornované vstupence ignorovat (produkční inventura potvrdila 669 těchto záznamů). Chybějící nenulový referencovaný produkt, cizí occasion nebo porušená aktivní vazba jsou explicitní chyby; žádný fallback na `food`, `taxi`, titul nebo ukázková data.
5. Ceny skutečných ticketů zůstávají ze současných order snapshotů. Náhled není účetní kalkulace a nesmí ovlivnit objednávku. Hidden note nesmí vstoupit do render data.

### Picker a živý náhled

`resolve` vrátí vedle resources autorizovaný katalog typů: `id`, `title`, příznak nabídky ve formuláři a deterministický příklad produktu (`id`, tisknutelný title, cena/měna, pořadí). Rozšířit `get_products_and_types` aditivně o title/occasion typů, order produktů a minimální form-reference metadata. Nesdílet kompletní admin bundle s objednávkami, inventářem a osobními údaji. Zachovat stávající caller kontrakt a jeho zabezpečení; endpoint autorizuje occasion před načtením dat. Nové interní SQL helpers mají výslovné grants/revokes a stejný permissions boundary.

Picker nabízí pouze typy z aktuální akce použité alespoň v jednom poli formuláře této akce. Podle upřesnění uživatele během implementace může být toto pole i skryté; samotná existence viditelných produktů bez formulářové vazby pro novou nabídku nestačí. Ukáže název a příklad, případně `Bez dostupného příkladu`. Typy bez existující formulářové vazby nejsou v nové nabídce; již uložená pole ale zůstávají viditelná a odstranitelná. Neschovávat existující konfiguraci jen kvůli zrušení prodeje. V této fázi non-hidden neznamená garantovanou skladovou dostupnost; náhled nic nerezervuje. Určení relevantního formuláře viz D6.

Příklad vezme první non-hidden produkt **vybraného** typu podle `order` (null jako 0), potom ID; používá stejný formatter jako reálný ticket. Nikdy nevezme produkt jiné skupiny. Bez příkladu je pole prázdné, UI vysvětlí proč; v produkčním editoru nepodsouvat ilustrativní steak. Ilustrativní data mohou zůstat jen v explicitně označených lokálních fixtures.

Změna výběru/prefixu se vykreslí lokálně bez implicitního PDF requestu. `resolve` poskytne příklady pro celý oprávněný katalog, kde `example.value` je serverem trimovaný a zvolený short/full title nebo null. Lokální preview adapter pouze hledá přes `productTypeId`, přiřadí výsledek k `element.id` a spojí neprázdný label s `': '` a value. Nesestavuje vlastní syntetický order, nefiltruje produkty a nevolí short title; tento mechanický boundary adapter není druhý product-selection engine. Shared contract fixtures ověří shodný výsledný text s TS formatterem. Rozlišení pole bez příkladu je metadata pro UI, nikoli text tisknutý v PDF. `normal`, `long`, `missing` i explicitní PDF preview používají stejný kontrakt. QR zůstane syntetický a nesmí kopírovat zákaznický admission credential. Při preview ceně započítat synteticky vybrané produkty jen jednou, respektovat měnu a nikdy nesčítat různé měny; baseline admission určovat přes kontext ticket/form, nikoli `type === 'spot'`.

## UI kontrakt po doplňující revizi

Revize je nad existujícím kódem, ne nad hotovou implementací. Neznamená vizuální či běhový důkaz; ten se získá cílenými UI testy a krátkým smoke checkem při implementaci. Nové ovládání musí použít stávající Flutter Material, panel prvků/vlastností a hranici 900 px. Není potřeba nový designer screen ani vlastní component library. Začít kontraktem a rendererem, potom zapojit celý UI flow; nevytvářet mezikroky vyžadující deployment částečně kompatibilních vrstev.

### Přidání a úprava pole

1. V panelu **Prvky** je stálé tlačítko **Přidat produktové pole**, dostupné stejně na desktopu i v mobilním panelu. Prázdný seznam vhodných typů ukáže důvod a odkaz na existující správu produktů/formuláře; nevytváří v pickeru další katalog editor.
2. Jedna výběrová obrazovka obsahuje skupinu a pod ní skutečný příklad. Použít standardní scrollovatelný dialog, na úzké obrazovce fullscreen variantu, jeden sloupec. Dlouhé title lze zalomit, plný příklad musí být dostupný ve vybraném detailu. Krátký filtr nad katalogem je lokální; žádné debounce API či paginace. Nezobrazovat `productTypeId` ani `type` jako povinnou uživatelskou znalost. Shodné názvy skupin rozlišit popisem příkladu a formuláře; samotný titulek nestačí.
3. Již vložený typ ukazuje **Už je na vstupence** s akcí vybrat existující pole, nikoli obecně disabled položku. Výběr ještě nemění dokument. **Přidat pole** provede jednu undo operaci, zvolí nový element a otevře jeho vlastnosti; cancel pickeru nic nemění. Focus přejde na výběr/pole a po zavření se vrátí na smysluplný ovládací prvek.
4. Vlastnosti obsahují **Skupina produktů**, **Popisek na vstupence** a read-only **Příklad**. Úvodní label je title skupiny. Při změně skupiny se label změní jen tehdy, pokud stále odpovídá původnímu automatickému labelu; uživatelský label a záměrně prázdný label zachovat. Při změně se box, styl, pořadí a element ID nemění. Prázdný label má vysvětlení **Zobrazí se jen název produktu**. Dvojtečku vkládá formatter, není nutná v uloženém labelu; běžný koncový separator při převzetí defaultu normalizovat, aby nevzniklo `Večeře::`.
5. Seznam prvků zobrazuje konkrétní skupinu, pod ní popisek nebo příklad; dvě product pole nejsou obě označené jen jako **Produkt**. Warning, overflow a prázdný výběr jsou navázané na element ID. Reset stylu nesmí vyhledat první `binding == productType`; použít konkrétní ID/type nebo obecný výchozí textový styl.
6. **Odstranit pole** smaže jen tiskový element a jeho flow reference, nikoli produkt nebo objednávku. Jedna undo operace a okamžitá možnost vrácení stačí, není nutný potvrzovací dialog. Po odstranění opravit selection i po undo/redo, aby panel vlastností neodkazoval na neexistující ID. U locked elementu je změna skupiny/labelu i odstranění zablokované s vysvětlením a možností použít existující odemknutí.

Label kreslit průběžně, ale editaci během jednoho focus úseku seskupit do jedné historie přes existující controller transaction (`beginGesture` / `endGesture`, popř. stejný interní snapshot mechanismus), nikoli uložit undo snapshot pro každou klávesu. Před Save/PDF dokončit textovou transakci. Maximální délku a chybné vstupy vysvětlit u inputu; Save při chybě ukáže konkrétní pole a zachová draft. Nepřidávat obecný state-management framework.

### Bezpečné umístění a změny předlohy

Nové pole nesmí vzniknout mimo plátno ani přes QR, symbol nebo jiný viditelný obsah. Odvodit styl z místního textového stylu, začít viditelným boxem uvnitř ticket area a deterministicky hledat první volné místo na existující grid škále. Počet kandidátů omezit rozměrem plátna, nepouštět neomezenou optimalizaci layoutu. Použít existující geometrické/QR validační helpers; algoritmus nemění rozměry ani pozice původních prvků.

Pokud místo není, přidání nic nezmění a vysvětlí **Pro další pole není místo. Zvětšete plochu vstupenky nebo uvolněte místo.** Výběr skupiny může zůstat otevřený. Žádná automatická změna QR nebo canvasu, žádný uložený nevalidní element. Nevkládat na začátek kompaktního flow bez explicitní editace geometrie.

Při výběru nové grafické předlohy současný editor nahrazuje celý template. Neutrální nové presets nemají product pole, takže tento krok může dříve přidaná pole odebrat: v preview předlohy viditelně uvést počet odebíraných polí a označit použití předlohy jako nahrazení rozložení. Celá výměna je jedna undo operace. Nepřidávat automatické přemisťování všech polí do jiné geometrie jako součást tohoto cutoveru.

### Stavový kontrakt a přístupnost

| Stav | Chování |
|---|---|
| Catalog loading | Nechat draft i ostatní ovládání dostupné; picker ukáže loading, add zatím vysvětleně nedostupné. |
| Catalog failure/offline | Inline chyba a **Zkusit znovu** načte pouze katalog; nesmí znovu inicializovat dokument ani zahodit změny. Nezobrazit jako empty catalog. |
| Žádný vhodný typ | Kontextová prázdná nabídka se směrováním do existující správy; bez syntetické večeře. |
| Skupina existuje, nemá viditelný příklad | Uložené pole zůstává editovatelné; náhled prázdný, vysvětlení pouze v UI. Nezaměnit s chybějícím typem. |
| Skupina už neexistuje nebo patří jiné akci | Zobrazit konkrétní problém v properties; Save/PDF vyžadují opravu/odebrání, nikdy tiché přemapování. |
| Catalog stale při Save | Server je autoritativní; chyba zachová draft, refresh nabídky nezmění label ani výběr automaticky. |
| Save conflict / permission change | Použít stávající konflikt/reload/draft recovery; UI neobchází version ani rights check. |
| Limit 32 prvků / 32 KiB | Vysvětlit konkrétní limit před další mutací; nabídnout úpravu/odebrání pole. |

Standardní Flutter ovládací prvky mají viditelný focus, názvy v semantics a touch targets podle stávající Material UI. Picker lze otevřít, filtrovat, zvolit a zavřít klávesnicí; Escape ruší pouze picker, ne celý editor. Mobilní přidání i úprava používají existující `showMobilePanel`/TabBar cestu, po přidání se zobrazí properties tab. Lokalizovat nové strings přes `ticket_layout_strings.dart` a existující translations; netestovat přesnou formulaci překladů. Prověřit 320 px, 200% zoom a dlouhý název/popisek bez horizontal overflow.

### Occasion setup draft není existující akce

`occasion/setup/occasion_setup_page.dart:_ticketSettings` používá `sourceId`, nebo dokonce první dostupnou akci, jen jako zdroj artwork/font preview. `occasion_form_draft.dart` ukládá produktové typy vložené do draft JSON; část typů nemá persisted IDs. Proto se katalog zdrojové akce **nesmí automaticky stát katalogem nového draftu**.

Pro první implementaci zavést explicitní editor context: běžný persisted occasion má plně funkční product picker, setup draft s explicitně vybraným kopírovaným zdrojem může zachovat již existující product pole jako zdrojové reference s čitelným stavem předlohy. V setup draftu nevytvářet ani nepřevybírat product pole, dokud neexistuje autoritativní mapa produktových typů výsledné akce; vysvětlit **Produktová pole upravíte po vytvoření akce.** Geometrii, popisek a ostatní obsah předlohy lze dál upravit. U blank draftu, který si půjčuje první dostupnou akci jen pro resources, nezobrazit její produktová pole ani nabídku.

Toto je ohraničená podpora stávajícího draft preview, ne nový protokol pro dočasná product type ID a ne implementace publish wizardu. Při skutečné kopii akce funguje již plánované SQL přemapování; budoucí publish draftu musí převést source/draft reference po vytvoření skutečných typů před validací. Žádný `COALESCE(newId, sourceId)` v uloženém layoutu výsledné akce.

Doplňující read-only production query zjistil, že `public.occasion_setup_drafts` v ověřeném canonical runtime vůbec není. Tento producer je tedy v aktuálním checkoutu, jeho persistence není nasazená; nevydávat nedostupnou tabulku za prázdný inventář a nenasazovat nesouvisející wizard migration při tomto cutoveru. Pokud se před implementací/rolloutem změní stav, bounded inventory pouze tohoto draft storage doplní `ticketDraft.layout` a uložené source reference do převodního manifestu.

## Efektivní implementace a hranice práce

- **Jeden koherentní kontrakt, žádné mezireleasy:** schema, TS/SQL/Dart fixtures, renderer a editor změnit jako společný lokální celek. Vlny označují závislosti a review body, nikoli pět samostatných deployů. Nevalidovat každé přesunutí field access; cílené checks spustit po dokončení příslušné vrstvy.
- **Ponechat existující identitu:** singleton element ID při převodu zůstanou stejná (dnes většinou shodná s bindingem). Přístup k datům převést pomocí malého společného helperu na element ID; neměnit font, media, QR, selection ani layout model nad potřebnou míru. Nové product pole ID tvořit lokálně unikátně, bez databázového roundtripu.
- **Jeden katalog snapshot:** resolve načte katalog jednou. Preview retry katalogu používá stejnou autorizovanou loader boundary v lehkém catalog mode, bez PDF/font/image reloadu a bez nové parallel RPC business implementace. Dotaz agreguje form references hromadně, ne SQL query pro každý produkt; nepoužít admin bundle.
- **Opravit statické scénáře:** současný editor všude čte `resources.scenarios[scenario]`, které vznikly při otevření. Nová pole by v nich nebyla. Zavést `previewData(template, scenario, catalog)` a použít jej pro controller `geometryData`, canvas, properties, thumbnails i gallery. Memoizovat podle dokument revision, scénáře a catalog revision, ne znovu JSON-serializovat katalog při každém paintu. Gallery používá data svého template, nikoli aktuálního hlavního dokumentu.
- **Žádné síťové requesty při editaci:** add/change/remove/label/undo/resize nepotřebují resolve ani PDF. Lokální adapter pouze promítá server-normalizované `example.value`, source eligibility a metadata. Text styling i label změny neregenerují QR nebo font bytes. Explicitní PDF zachovává současnou signature/generation ochranu proti pozdnímu výsledku.
- **Katalog indexovat jednou:** server vytváří mapy product ID a product type ID jednou při přípravě rendereru pro order. Pro každý ticket se první match pro všechny požadované typy vybere jedním průchodem seřazených OPT, potom se promítne do prvků. Nepřistupovat k DB pro každý ticket ani element. Ověřit pomocí injected dependency call counts, bez nového benchmark projektu.
- **Jednorázová migrace reuse:** použít existující inventurní SQL a důkazy, současný import/resources/font mapping, command/version infrastructure a copy ID map. Doplnit bounded refresh, hash a apply; nestavět nový migration framework, generický JSON mapper nebo druhý font migration systém. Produkční mapování je již konkrétní, nespekulovat nad neexistujícími food výjimkami.
- **Žádný vedlejší redesign:** nepřidávat inventory selection, množství, seznam variant, per-form templates, live availability polling, custom catalog picker framework, publish wizard, globální font protokol cutover ani globální odstranění `product_types.type`. Zachovat pouze takové schema/font úpravy, které vynucuje canonical product contract.
- **Jedna malá sada důkazů:** shared fixtures pro contract/format parity, focused SQL migration/reference/copy tests, Flutter interaction tests a krátký headless smoke skutečného pickeru. Neopakovat prošlé checks bez změny pokrytého kódu a neprovádět full build všech tenantů. Browser flow je vizuální důkaz, nenahrazuje deterministic tests.

## Rozhodnutí, předpoklady, blokující podmínky

- **D1:** Přechod na explicitní product type ID se týká celého tisku produktových polí, nikoli jen přejmenování večeře na menu. VIP je příklad, ne podmínka implementace.
- **D2:** Geometrii, fonty, QR, viditelnost a ID prvku při převodu zachovat; `food` změnit na `productType`, flow přeložit na ID, label zachovat jako `Večeře`. Uživatelské přejmenování je následná editace. Odvozu zachovat dosavadní label, pokud je doložen.
- **D3:** Podle upřesnění uživatele vybrat konkrétní typ používaný ve formuláři. Legacy kandidáty zúžit přes `form_fields.product_type` ve stejné akci, přednostně non-hidden ticket pole relevantního formuláře. Stav `form.is_open` není podmínka, protože uzavřené formuláře mají historické vstupenky. Jediný použitý kandidát se migruje automaticky; pouhá existence dalšího nepoužívaného typu nevyvolává ruční výběr. Aktuální production inventory nemá žádnou víceznačnou food vazbu. Pokud více různých typů skutečně používají různé relevantní formuláře, rozlišit jejich form context; více kandidátů v témže kontextu či historicky zakoupený vyloučený typ je konkrétní datová výjimka, ne důvod odhadnout první ID.
- **D4:** Chybějící layout pro historickou aktivní konfiguraci materializovat offline se současným importem a resources. U nové akce vytvářet neutrální schema-3 preset bez implicitního produktového pole. Odstranit type-based import; zbývající čistý geometrický import lze ponechat pouze pro doloženého konzumenta, bez produktové klasifikace.
- **A1:** Uživatel chce odstranit určování přes `type` v tiskové větvi. Pokud požaduje zrušení sloupce v celé doméně, před implementací rozšířit autoritativní plán o spot/form cutover; neslibovat odstranění sloupce na základě této analýzy.
- **D6 (uzavřené A2):** Ověřené callers jsou `features/feature_form.dart` a `occasion/setup/occasion_setup_page.dart`, oba přes `TicketSettings`, které dostává pouze occasion ID. Pro existující akci použít occasion-wide sjednocení form references; nepřidávat nový volitelný formId protokol bez skutečného calleru. Průvodce má jiný draft context a jeho source-preview zvláštnost se řeší níže. Migration form context je evidence pro výběr ID, ne nová per-form runtime šablona.
- **D5:** Stejné pravidlo platí pro libovolný dřívější produktový údaj včetně odvozu: migrovat pouze skutečně používanou tiskovou vazbu na typ používaný ve formuláři. Nepoužívaný odvoz ani jiný typ nemigrovat. Production inventory potvrdila pouze formulářové taxi produkty bez tiskového bindingu, takže pro ně tento převod nic nevytváří a nemění jejich objednávkové vazby.
- **F1 (vyřešený původní B1):** Aktivace, tenant organization a read-only produkční konfigurace byly ověřeny canonical cestou; viz evidence. Před apply znovu ověřit aktuální verze a hashe, nikoli používat tento snapshot jako trvalé oprávnění k zápisům.
- **B2 (rozsah schválen 2026-10-13):** Uživatel výslovně schválil převod všech konzumentů sdíleného backendu, s webovým release pouze pro vstupenky.online. Původně nebyl určen autorizovaný rozsah dat pro sdílený backend. Dalších 11 organizací má legacy/implicitní ticket konfigurace; jejich skutečné runtime konzumenty je nutné vymezit před odstraněním starého kontraktu. Řešit schváleným rozšířením rozsahu nebo skutečnou izolací deploye; ne trvalým legacy fallbackem.
- **B3 (vyřešený release preflight):** Read-only inventory a skutečný resource dry-run pro organization 3 dne 2026-10-13 převádí 69 ze 73 konfigurací. Akce 13, 19, 25 a 27 mají nedostupná původní pozadí (`upstream_404`); bez obnovení původních bytů nelze doložit původní bitmapovou geometrii. Původní byty byly nalezeny v canonical storage a se shodnými velikostmi/SHA-256 obnoveny na stávající veřejné URL; následný dry-run je ověřuje. Nedoplňovat náhradní artwork ani nevynechávat historické konfigurace bez rozhodnutí o změně požadavků. Podklady jsou v `/tmp/festapp-product-production-20261013/manifest-org3.json.unresolved.json`.

## Migrační algoritmus a evidence

Připravit verzovaný jednorázový nástroj s odděleným `inventory`, `dry-run`, `apply` a `verify`. Výstup má jen konfigurační ID, počty, candidate IDs, původní/nový digest a důvod klasifikace; žádná jména, emaily, poznámky nebo admission symboly zákazníků.

Inventura zahrne: ticket features i disabled/hidden akce, oba template sloty včetně implicitního slotu použitelného po změně ticket_type, všechny legacy schema verze, typy food/taxi i obecné, form-reference nabídku, skryté/historicky objednané produkty, orphan vazby, neznámé JSON klíče a skutečné reference ve fronte emailů. Číst i konfigurace mimo aktuální viditelný prodej; zákazník může znovu stáhnout historickou vstupenku. Vymezit konzumenty sdíleného rendereru včetně běžících worker instancí a administrativních print cest.

Pro každé legacy food pole sestavit kandidáty podle skutečného použití ve formuláři: join `form_fields.product_type = product_types.id`, `forms.occasion = product_types.occasion = occasion.id`. Legacy `type='food'` použít pouze jako migrační identifikaci staré role; konečný výběr určí formulářová vazba, nikoli počet všech typů v katalogu. Jeden používaný kandidát se převede automaticky i při existenci dalších nepoužívaných typů. Neomezovat historické mapování na otevřené formuláře či viditelné produkty. Pokud je pole dnes hidden, ale má historické zakoupené produkty, zachovat jeho doloženou historickou ID vazbu.

Žádný používaný kandidát a žádný historický food match znamenají nevyužité tiskové pole: odstranit je bez požadavku na ruční mapování. Production inventory takto klasifikuje deset uložených food polí (occasion IDs v evidence). Při odstranění z flow materializovat pouze trvalý posun způsobený vždy prázdným odstraněným polem; ostatním volitelným řádkům ponechat jejich dynamické flow, aby se nelišila geometrie vstupenek s poznámkou a bez ní. Cílený bitmap rehearsal tento detail během implementace doložil. Potom odstranit element/reference; nerozbít note/price geometrii. Nevyužitý produktový typ ani objednávkové záznamy se nemažou. Typ použitý jen v historických objednávkách je používaný historicky, proto nesmí zmizet jen kvůli odstranění nabídky.

Více typů skutečně používaných ve formulářích rozlišit přes relevantní form context. Ověřit agregovaně historické product vazby, aby zúžení neskrývalo zakoupený food produkt jiného typu. Nevyřešená víceznačnost ve stejném kontextu je přesně popsaná výjimka pro refresh manifestu; aktuální inventář ji neobsahuje. Stejné pravidlo použít pro doložené tiskové pole odvozu; production žádné neobsahuje, takže pro taxi nevytvářet převod. Neznámý schema/binding/shape zastaví převod místo tichého odhození.

Případné víceznačné **používané** form-context výjimky řešit konfiguračním manifestem po occasion/form/template/element; další nepoužívané katalogové typy nejsou výjimka. Může vyžadovat více konkrétních polí a vědomou změnu geometrie, kterou je nutné ověřit na historických kombinacích produktů. Automaticky zachovat původní first-match chování mezi více různými typy nelze s jedním ID. Žádný skrytý `legacyTypes` seznam ani pravidlo podle title.

Při materializaci implicitních template získat skutečný background/font bezpečnou existující resource cestou; selhání stažení, neznámý font nebo nevalidní geometrie blokují daný řádek. Nepoužívat přibližný preset jako náhradu. Převést font schema 1 na současná canonical font ID prostřednictvím existujících font mappingů; zachovat známé appearance extension fields. Stávající schema 2 přebírá své font IDs beze změny.

`apply` používá očekávanou verzi/layout hash a zamyká occasion. Přes explicitní servisní/migrační boundary atomicky mění jen ticket layout, zapíše audit a příslušnou client-sync invalidaci/verzi. Ověřit mechanismus v `save_occasion_domain_command_internal_v1` a publisheru; nepoužívat holý UPDATE bez invalidace. Při konfliktu rollback a nová inventura, ne přepsání souběžného editora. Ověřit všechny navržené reference před prvním zápisem schválené dávky. Opakovaný apply se stejným manifestem je no-op, nesmí znovu posunout verzi. Produkční ledger a data musí být transakčně konzistentní.

Nevyžaduje se změna `eshop.products`, `product_types.id`, `order_product_ticket`, order snapshotů, rezervací ani PDF již doručených zákazníkům. Změna znovu generovaných PDF se ověřuje, staré soubory se nepřepisují ani zákazníkům samovolně znovu neposílají.

## Ledger odstranění

| Artefakt | Akce | Důkaz |
|---|---|---|
| `food` binding v aktivních TS/Dart/SQL schématech a presetech | Nahradit `productType` s ID; neutrální presets bez večeře | Validátory odmítnou `food`; absence v aktivních zdrojích. |
| `productTypeMap` podle string typu a `o.product_type === 'food'` | Odstranit, zavést katalog podle product ID | Test nezávislosti na změně `type`; focused search. |
| Type-based admission/food volba v `sampleData` a preview loaderu | Nahradit ID/form context a per-type příklady | Preview dvou obecných typů se stejným `type` je odlišné. |
| Render data / warnings / flow podle bindingu | Převést na element ID | Dvě product pole mají odlišný text, selection i warning. |
| Runtime import, který vytváří implicitní `food` | Materializovat data, odstranit tuto větev | Chybějící historický layout nedosáhne legacy rendereru. |
| Aktivní přijímání layout schema 1/2 | Po datovém převodu odstranit ze save/preview/render | Negative tests + inventura uložených schema verzí. |
| Stará fixtures a tests s očekáváním pouze pevné večeře | Aktivní fixtures převést, migrační fixtures ponechat označené | TS/Dart/SQL sdílejí cílový kontrakt. |
| README a deployment instrukce pro pevný food kontrakt | Aktualizovat | Dokumentace ukazuje konkrétní ID a migrační ordering. |
| Aplikované historické SQL, migrační vstupy a audit | Ponechat jako historii; nejsou runtime fallback | Migrační loader nesmí přepsat canonical SQL zpět starou definicí. |
| `product_types.type` pro spot/form doménu | Ponechat mimo tento cutover | Žádný aktivní ticket product selector na něm nezávisí. |

## Implementační vlny

### 1. Uzavřít inventuru a migrační mapování

**Změny:** přidat jednorázový inventory/dry-run nástroj a jeho lokální fixtures; projít callers `TicketLayoutEditor`, `prepareTicketRenderer` a `resolveTicketTemplate`. Zjistit přímé write/delete cesty product typů a změny `products.product_type`; prověřit schema baseline, grants a live drift. Pro production read-only použít skill `.agents/skills/festapp-backend-access/SKILL.md`, ověřenou aktivaci a explicitní read-only transakci s ověřeným produkčním profilem jako při doložené inventuře.

**Migrace:** zatím jen návrh manifestu. Klasifikovat každý řádek `automatic`, `explicit mapping required`, `invalid`, `already canonical`, včetně odvozu a implicitních template.

**Selhání:** nulový výsledek při nedostupném backendu se nesmí považovat za prázdnou inventuru. Jen konkrétní nevyřešené form-context výjimky a B2 blokují production apply, nikoli implementaci na lokálních fixtures. Nepoužívaný typ není blocker.

**Validace a exit:** lokální fixture inventura reprodukovatelně hlásí 0/1/více kandidátů; existuje úplný manifest schváleného rozsahu a explicitní seznam nevyřešených řádků. D6 a draft context jsou doložené podle callers, B2 má doložený release rozsah; původní B1 je vyřešen.

### 2. Cílové schema, SQL boundary a kopie akce

**Změny:** TS `ticketLayout.ts`, Dart `models/ticket_layout.dart` a SQL `others/ticket_layout.sql` implementují schema 3, `productTypeId`, label, opakovatelnost product bindingu, limit 32 a flow po element ID. Rozdělit strukturální validaci a kontextovou `validate_ticket_layout_references(p_occasion, p_layout)`; context check volá uložená create/update větev i backend preview. `update_occasion.sql` dodá occasion kontext. Unknown keys nesmí otevřít legacy selector; odmítnout legacy selector metadata.

**Migrace:** nová unikátně datovaná forward migration z canonical SQL. Needitovat aplikované migrations. Aktualizovat merge a downgrade/null-layout policy: nový klient nemůže resetem vynutit starý implicitní import, starý editor nemůže přepsat schema 3. Zachovat aggregate version, expected layout a command receipts.

**Lifecycle:** doplnit reference check při delete/reparent product typů a při změně product_type u již objednaného produktu. Blokovat přesun objednaného produktu do jiného typu, který by změnil historický tisk; hidden/title edit neblokovat. Bez persistent business triggeru, audit skutečných RPC a direct grants je povinný. Mazání typů referencovaných layoutem odmítnout, změny dělat přes explicitní boundary. Konkrétní write funkce z wave 1 vložit do implementačního ledgeru. Lokální schema/caller důkaz během implementace opravil původní předpoklad: `delete_form_ws -> delete_form_client_sync_v1 -> delete_form_internal_v1`; soubor `delete_form.sql` definoval již nahrazené místo. Ochranu doplnit do skutečného `delete_form_internal_v1`, odstranit starou definici a sladit canonical wrapper se stávajícím versioned commandem.

**Kopie:** v `duplicate_occasion_internal_v1` přemapovat všechna productTypeId v obou templates přes `tmp_product_types`, až po vytvoření typů. Nevztahovat `COALESCE(new_id, old_id)` na layout references. Neúplná mapa ruší celou kopii. Poté validovat proti nové akci, wrapper `duplicate_occasion_client_sync_v1` zachová atomický commit/replay.

**Validace a exit:** SQL schema/reference/authorization/conflict/copy tests, sdílené Dart/TS/SQL fixtures. Cizí occasion ID, záporné/zlomkové/unsafe ID, chybějící typ, duplicitní ID a nevalidní flow nelze uložit ani předat do preview.

### 3. Jeden renderer a katalog příkladů

**Změny:** `get_products_and_types.sql`, `preview-ticket-layout/products.ts`, `_shared/ticketRenderData.ts`, `ticketGeneration.ts`, `generateTicket.ts`, `ticketLayout.ts`: katalog podle ID, canonical formatter, element data/flow/warnings podle ID, autorizované catalog metadata. `preview-ticket-layout/handler.ts` validuje references dodaného layoutu před resource/PDF renderem a vrátí příklady. `emailRenderer.ts` a download používají stejný renderer bez další logiky.

**Odstranění:** string type mapa, food fallback, ilustrativní večeře v production preview, product classification v importeru. Presets neobsahují automatické produktové pole; upravit `ticketPresets` interní validaci, která dnes vytváří schema 1. Původní importer je pouze zdroj offline migrace, případně prokázaný čistě geometrický adapter bez výběru produktů.

**Selhání:** catalog error neznamená empty catalog; dangling product reference nesmí tiše vymazat zakoupený produkt. Chyba přípravy emailu ponechá frontu retryable, nic neposílá mimo globální queue. Nevydat release s běžící starou instancí procesoru.

**Validace a exit:** Deno tests normalizace, preview auth/references a skutečného PDF; dvě konkrétní ID se stejným string type tisknou odlišné hodnoty, skrytý historický produkt se tiskne, absence match netiskne prefix. Email/download/preview sdílejí výsledný produktový text.

### 4. Editor a lokální canvas

**Změny:** `ticket_layout_service.dart` přenese katalog a normalizované příklady, přidat lehký catalog-only reload ke stávající preview boundary; `views/ticket_settings.dart` aktualizuje supported schema guard a výslovně předá occasion/draft context; `ticket_layout_controller.dart` podporuje add/change/remove a undo/redo celého elementu; `views/ticket_layout_editor.dart` přidá picker a rozlišené názvy; `ticket_layout_properties.dart` selector/label; `ticket_layout_canvas.dart`, `ticket_text.dart` a template positioning používají element ID. Aktualizovat schema checks v `TicketSettings.unsupported`, feature/save/export a font service větvích, které nyní testují `schemaVersion == 2`. Font protokol zůstává 2, není totožný s layout schema 3.

**UX:** Implementovat úplný UI kontrakt výše, včetně picker confirm/cancel, label transakcí, bezpečného počátečního boxu, gallery replacement a source-preview draft contextu. Typ bez příkladu i již skrytá skupina mají vysvětlený stav. QR/symbol nejsou odstranitelné. Změna výběru má jednu undo operaci, cancel neukládá, conflict zachová draft, save přes stávající `TicketLayoutSaver`. Veškeré views používají dynamické previewData podle aktuálního dokumentu; nezůstane stale resources.scenarios lookup.

**Validace a exit:** targeted Flutter tests pokrývají dvě pole, picker confirm/cancel/duplicate selection, automatický versus custom label, no-space add, locked/hidden/missing stavy, grouped label undo, properties selection po remove/undo, gallery replacement, source-preview draft context, local repaint, reload roundtrip a nulové implicitní resolve/PDF requests. Jeden krátký isolated headless smoke ověří desktop i úzký panel, klávesnici a dlouhý název. Explicitní PDF request obsahuje přesný aktuální schema-3 draft. V testu je konkrétní VIP product type a samostatný odvoz bez použití type klasifikace; nepoužívaný odvoz nevytváří migrační pole.

### 5. Převod, kontrakce a důkaz cutoveru

**Změny:** dokončit apply/verify, forward SQL a runbook; převést fixtures `test/fixtures/ticket_layout`, test preview server, historický builder a aktivní README. Zachovat historické PDF jako baseline, vysvětlit změnu pouze produktového kontraktu. Aktivní SQL/Dart/TS runtime podporuje jen schema 3; migration-only převod zůstává mimo runtime imports/deploy dependency graph.

**Migrace:** lokální rehearsal z původních schema 1/2 a implicitních layoutů včetně historických/skrytých konfigurací. Porovnat render text, geometrii, font identity, QR payload a price bez zveřejnění zákaznických dat. Replay/druhý apply je no-op. Atomic apply při konfliktním hash nezapíše částečný layout ani audit.

**Validace a exit:** celý schválený manifest má verified digest; 0 nevyřešených/legacy runtime konfigurací; scanner zdrojů a import graph neobsahuje ticket výběr přes `type`; negative tests potvrzují odmítnutí starého kontraktu. Každá retained historical/migration reference má vysvětlený účel.

## Produkční pořadí a recovery

1. Na canonical `main` připravit jeden reviewable celek a lokální rehearsal. Žádný push, deploy či remote apply není součástí tohoto zadání. Nedoplňovat nesouvisející pending migrations z aktuálního dirty checkoutu.
2. Ověřit cílový tenant profil, live activation, canonical DB identitu, autoritativní main SHA a přesný SQL digest/ledger. Schválit rozsah sdílených DB konzumentů a tenant klienta. Získat předmigrační konfigurace/digests a zálohu; plánová inventura je již doložená, předapply snapshot se musí obnovit.
3. Připravit build klienta a Edge balíčky před odstávkou. Zastavit dotčené layout writes/copy a ticket render/email worker processing; nové queue intents se mohou ukládat, nesmí vzniknout přímé odesílání. Inventory po zastavení zápisů znovu ověří očekávané hashe. Použít dostupné doložené operační pause/fencing mechanismy, jejich konkrétní příkazy doplnit při wave 1.
4. V řízeném okně atomicky aplikovat datový převod a cílové SQL definice/ledger, aktualizovat sync versions/outbox/snapshot invalidace. Je-li materializace offline drahá, předpočítat resources předem a v transakci pouze ověřit hashe a uložit. Nenechat starou službu číst schema 3 ani nový renderer číst nepřevedené schema 1/2.
5. Nasadit všechny sdílené Edge consumers, potom vybraný tenant klient. Zkontrolovat, že běžící instance používají nový balíček. Starý otevřený editor dostane explicitní update/conflict chybu, nesmí degradovat layout. Zkontrolovat readback a syntetické preview před obnovením workeru.
6. Ověřit product text ve stažení a autorizované cestě přípravy queued ticket emailu, bez spontánního rozeslání zákazníkům. Obnovit writes/render worker a ověřit retry, client refresh a published snapshots. Release neoznačit hotový, pokud ostatní shared consumers vyžadují legacy runtime.

Krátké řízené přerušení renderu je záměrná release volba, která umožní cutover bez dvojího business runtime. Pokud není přijatelné, nejdřív upravit release plán na prokázané atomické přepnutí trafficu; nezavádět automaticky dočasný trvalý fallback.

Recovery před přijetím nových schema-3 editací může vrátit celý release a přesnou předmigrační konfiguraci pouze jako explicitní incident krok se zachovaným fencingem a kontrolou verzí. Po přijetí nových editací je běžná recovery forward fix v schema 3; starý renderer nemůže být nasazen nad nová data. Nevracet `type` selector jako opravu. Migrace nic nemaže z objednávek ani zakoupených produktů.

## Ověření

Plánování nevyžaduje spouštění testů. Pro implementaci provést cílené standard checks po koherentně dokončených vrstvách společného změnového celku; jednotlivé passing checks neopakovat bez změny příslušného kódu.

| Důkaz | Test seam / příkaz |
|---|---|
| Kontrakt, type-independent selection, skrytý produkt, short title, multi field, PDF | `deno test --allow-env --allow-net --allow-read supabase/functions/_shared/ticketLayout_test.ts supabase/functions/_shared/ticketRenderData_test.ts supabase/functions/_shared/ticketTemplateImport_test.ts supabase/functions/preview-ticket-layout/products_test.ts supabase/functions/preview-ticket-layout/preview_test.ts` a nové cílené migration/contract test files |
| Editor, roundtrip, conflict, undo, zero implicit PDF | `fvm flutter test test/components/ticket_layout/` a cílené `fvm dart analyze` změněných Dart souborů |
| SQL reference/auth/copy a legacy rejection | S explicitní lokální `DATABASE_URL` spustit `node web_client/scripts/run_db_tests.js database/tests/ticket_layout_settings_test.sql`, nový `database/tests/ticket_product_type_cutover_test.sql` a `database/tests/duplicate_occasion_target_unit_test.sql` |
| Migrační úplnost a retry | Rehearsal inventory/dry-run/apply/verify na disposable DB; 0 unresolved; druhý apply no-op; konflikt ruší transakci |
| Staré cesty nejsou dosažitelné | Scoped `rg` na `food`, `taxi`, `productTypeMap`, `.type`, schema 1/2 v ticket modulech + kontrola actual runtime imports, SQL registrace a deployed package |
| Skutečný stav po autorizovaném deployi | SQL/config readback, canonical layout digests, client-sync refresh, běžící Edge/queue instances; syntetický QR nesmí poskytovat admission credential |

Povinné test cases navíc: žádný/jeden/více kandidátů migrace; více katalogových typů s jedinou používanou form vazbou; odstranění nevyužitého pole; hidden historické form pole; null product na storno ticketu; archived occasion; oba slots; missing slot/imported artwork; obecné typy se stejným `type`; stejný type ID v jiné akci odmítnut; pole jiné vstupenky se netiskne; první matching OPT ID; null/whitespace short title; nulová cena a více měn; nejvýše 32 prvků a byte limits; invalid flow reference; legacy schema/food odmítnuty; kopie obsahuje jen nová product type ID; deletion/reparent race; concurrent layout edit; queue retry po výměně rendereru; hidden note nikdy netisknuta.

Pro tuto UI změnu při implementaci provést jeden krátký browser smoke skutečného pickeru/canvas po passing cílených testech; isolated headless `agent-browser`, task session, bez zásahu do uživatelova Chrome a bez production test objednávek. Nevyžadovat full release gates, dokud nejsou zvlášť zadány.

## Definice hotového a zbytkové riziko

- Každé produktové tiskové pole má konkrétní existující product type ID a svůj popisek; picker zobrazuje relevantní skutečný příklad.
- Preview, Flutter canvas, download a queued email PDF používají shodná data po element ID a nikdy neklasifikují podle `product_types.type`.
- Uložené i dříve implicitní konfigurace ve schváleném rozsahu mají schema 3, jasné mapování a ověřenou geometrii; historické ticket products a prices jsou zachovány.
- Kopie akce přemapuje reference atomicky, stale klient ani direct write nepřekonají validaci.
- Ledger odstranění je splněný; žádný runtime food/taxi fallback ani automatický schema-1/2 adapter. Historické SQL a offline migration fixtures jsou oddělené a označené.
- Cílené kontroly prošly a production steps jsou buď doložené, nebo výslovně uvedené jako dosud neprovedené. Lokální implementace sama neznamená dokončený produkční cutover.

Zbývající hlavní rizika jsou změna dat od okamžiku inventury, nedoložený digest nasazeného Edge balíčku, dostupnost historických media resources a dopad sdíleného rendereru na dalších 11 organizací. Produkční form vazby, food kandidáti a absence odvoz tiskového bindingu jsou ověřené; nevyužité typy nejsou migrační blocker. Aktuální renderer čte názvy z živého katalogu; tento plán zachovává tuto vlastnost, nezavádí nezávislou archivaci původních názvů produktů.

### Upřesnění podle úplné release inventury

Akce 1072509 (organization 8) má čtyři používané food skupiny, ale historická aktivní named šablona žádné food pole netiskne a wide slot není uložený. Ambiguity gate se vztahuje jen na skutečná historická food pole. Chybějící neaktivní slot dostane neutrální canonical preset, jako nový slot v editoru; nesmí vytvořit domnělé historické food pole. Existující uložené slots i aktivní implicitní slot se nadále materializují s původní geometrií. Tuto situaci pokrývá samostatný offline migrační test.

Produkční preflight odhalil odlišné `plpgsql.variable_conflict=error`: původní alias `e` ve flow validaci kolidoval s PL/pgSQL proměnnou. Celá apply transakce rollbackovala. Canonical SQL i dosud neaplikovaná forward migrace používají explicitní `flow_element.value`/`flow_item.value`; validní product-field flow má regresní test ověřený s produkčním nastavením.
