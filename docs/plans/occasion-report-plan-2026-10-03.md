# Grafický report akce s jediným RPC načtením

Datum: 2026-10-03
Stav: Implementováno a ověřeno; následně autorizováno začlenění do main a live nasazení. Publikační a provozní stav je zaznamenán níže.
Ověření při implementaci: standard (finanční údaje, oprávnění a veřejný RPC kontrakt).

## Výsledek a rozsah

Současnou kartu reportu e-shopu nahradí responzivní grafický přehled s vysvětlivkami. Text zůstane dostupný v nabídce „Zobrazit textově“ a „Stáhnout jako TXT“. Jedno načtení získá celý report jednou RPC. Přepnutí zobrazení a export další síťový požadavek nevyvolají.

Rozsah: Flutter ReportTab, DbEshop, model reportu, SQL report a jeho testy, lokalizace a TXT export. Zachovat současné umístění a oprávnění. Nezahrnovat časové trendy, filtr období, detail jednotlivých objednávek, nové realtime odběry, předpočítané tabulky, změny platebních workflow nebo rollout dalších tenantů. Současná data představují aktuální stav, nikoli historii prodeje.

Předpoklad: uživatel míní report e-shopu nalezený v ReportTab. Konverzace navazuje na tento konkrétní návrh. Případnou změnu cílové obrazovky promítnout do plánu před implementací.

## Ověřený současný stav

- `lib/components/eshop/views/report_tab.dart`: ReportTab načítá text v didChangeDependencies bez ochrany před opakovaným načtením. Nemá ochranu před opožděným výsledkem po změně akce/dispose a nezobrazuje vlastní stav chyby.
- `lib/components/eshop/db_eshop.dart`: getReportForOccasion volá get_report_ws; při neúspěšném code vrátí prázdný řetězec.
- `database/functions/eshop/get_report_ws.sql`: vstup occasion_link text, návrat jsonb `{code, data}`; data je text. Vyhledává akci uvnitř organizace přihlášeného uživatele a kontroluje get_is_editor_order_view_on_occasion.
- `database/functions/eshop/get_report_for_occasion.sql`: výpočty i skládání textu v jedné funkci. Větev pro jednu měnu počítá zbývající částku s vratkami, větev pro více měn bez nich. Ruční transakce sčítá bez oddělení znamének; „Banka“ je zbytek přijatých plateb po odečtení ručních transakcí. Produkty slučuje podle názvů a za zaplacené považuje vše mimo ordered/storno.
- `database/functions/eshop_orders/recalculate_order_payment_status.sql`: stav paid může znamenat již uhrazenou zálohu, nikoli celou cenu.
- `database/functions/eshop_transactions/apply_transaction_pairing.sql`: aktualizuje payment_info.paid jako součet transakcí mimo typ `return` a returned jako absolutní součet transakcí typu `return`; samotné znaménko nerozhoduje. Report nemá znovu implementovat párování.
- `database/functions/eshop_orders/update_order_and_tickets_to_storno.sql`: storno nastaví cenu objednávky na nulu. Aktuální price nelze vydávat za historickou cenu prodeje.
- `database/tables/tables.sql`: základní definice orders nemá UNIQUE na payment_info. Předpoklad jedné platební informace na jednu objednávku není doložen.
- Přímí nalezení klienti: DbEshop a ReportTab. SQL testy `get_report_tenant_scope_test.sql`, `eshop/integration/mixed_cart_flow_test.sql` a `eshop/integration/on_site_surcharge_flow_test.sql` kontrolují nynější text.
- Historická migrace `20260218120000_fix_all_security_lints.sql` zmiňuje další staré varianty reportových funkcí. Neprokazuje jejich současnou existenci nebo použití; vyžadují kontrolu závislostí při implementaci.
- `file_saver` již existuje v pubspec.yaml a používá se v eshop_columns.dart. Nová knihovna pro export není potřeba.

## Rozhodnutí: zachovat jednu RPC a rozšířit odpověď

Jediné klientské volání zůstane:

```text
public.get_report_ws(occasion_link text) -> jsonb
```

Zachovat signaturu a původní textové `data`. Přidat `report` se strukturovanými daty. Starší instalovaní klienti nadále přečtou data, nový klient dostane grafiku i text jedním požadavkem. Nezavádět druhou RPC, parametr přepínající formát, V2 endpoint ani fallback s dalším síťovým voláním.

Úspěšná odpověď:

```text
code: 200
data: string                         # TXT ze stejného report objektu
report:
  schema_version: 1
  occasion: {id: string, title: string}
  generated_at: ISO-8601 UTC
  spots: {total: integer, occupied: integer, free: integer}
  orders: {total: integer, by_state: [{state: string, count: integer}]}
  tickets: {total: integer, by_state: [{state: string, count: integer}]}
  money_by_currency: [
    {currency: string,
     current_order_value: decimal-string,
     received: decimal-string, returned: decimal-string, net_received: decimal-string,
     manual_received: decimal-string, other_received: decimal-string,
     has_deposits: boolean, deposit_received_gross: decimal-string,
     beyond_deposit_received_gross: decimal-string}
  ]
  products: [{type_id: string|null, type_title: string|null,
              product_id: string, product_title: string, confirmed_count: integer}]
  warnings: [{code: string, count: integer}]
```

Všechny klíče reportu jsou přítomné. Prázdná akce vrací nulové počty a prázdná pole, nikoli null report. Neznámé a null stavy se explicitně zařadí (null pod stabilním klíčem `unknown`), aby součet kategorií odpovídal total. Bezpečná čísla peněz jsou decimal-string z SQL numeric; klient je nepřepočítává přes double. ID jsou řetězce kvůli přesnosti webového klienta. Pořadí polí musí být deterministické.

Text je malá prezentační duplicita agregovaných údajů záměrně přenášená kvůli kompatibilitě a okamžitému exportu. Výpočty se neduplikují. Nepřenášet objednávky, vstupenky, transakce, osobní údaje nebo celá databázová row JSON. Velikost odpovědi roste s počtem produktů a měn, nikoli s počtem objednávek.

Chyba zachová obálku s neúspěšným code a bezpečnou message, bez reportu a SQLERRM/detail klientovi. Použít existující konvenci kódů po ověření lokálních RPC čteček; 200 vyhradit skutečnému úspěchu. Klient musí vyhodit zpracovatelnou chybu, nikoli vracet prázdný text. schema_version slouží k validaci dat, není druhou implementační cestou. Chybějící report na starém backendu zobrazí chybu dostupnosti reportu bez druhého požadavku.

## Definice metrik a vysvětlivky

| Oblast | Pravidlo a vysvětlivka |
|---|---|
| Místa | Počet eshop.spots dané akce; obsazené mají order_product_ticket, volné jej nemají. Nejde automaticky o celkovou kapacitu všech typů vstupenek ani o dočasné blokace míst. Bez míst nevykreslit falešný údaj o vyprodanosti. |
| Objednávky | Každá objednávka akce právě jednou, rozdělení podle aktuálního surového stavu. Nezaměnit stav paid s plně uhrazenou cenou. |
| Vstupenky | Každá vstupenka akce s existující položkou order_product_ticket právě jednou, shodně s dosavadním rozsahem; použít EXISTS nebo unikátní ID, aby více produktů nenásobilo počet. Kategorie jsou aktuální stavy, nikoli průchod prodejním trychtýřem. |
| Hodnota objednávek | Součet aktuálních orders.price za měnu; null jako nula s upozorněním na chybějící cenu. Popisek „Aktuální hodnota objednávek“, nikoli historické tržby. |
| Přijato, vráceno, čistý příjem | paid, returned z unikátních payment_info přiřazených akci, netto = paid - returned. I storno může mít peněžní pohyb. Stejný výpočet pro každou měnu. |
| Ručně evidované příjmy | Jen kladné manual transakce daných payment_info. Popisek „Ručně evidováno“, s vysvětlením běžného použití pro hotovost; nevydávat automaticky všechny ostatní příjmy za bankovní. |
| Ostatní příjmy | received - manual_received. Při záporném výsledku ukázat upozornění na nesoulad, žádné tiché ořezání nebo graf s negativním segmentem. Vrácené částky držet samostatně. |
| Zálohy a platby nad zálohu | Na unikátní payment_info s deposit_amount: min(paid, deposit_amount), max(paid - deposit_amount, 0). Jde o hrubé přijaté platby před vratkami, nikoli nedoplatek nebo důkaz dokončené objednávky. Nezaměnit za úplný rozpad všech příjmů: objednávky bez zálohy do těchto dvou hodnot nevstupují. |
| Produkty | Počet položek u objednávek ve explicitních potvrzených stavech paid/sent/used. Názvem „Produkty v potvrzených objednávkách“ přiznat i zálohové objednávky. Agregovat podle ID typu a produktu, nikoli názvu; chybějící typ zachovat jako „Bez typu“. Ověřit skutečnou jednotku množství v order_product_ticket před zápisem dotazu. |

„Zbývá zaplatit“ v prvním provedení nezobrazovat. Prostý rozdíl součtů nesprávně kompenzuje přeplatky jiných objednávek a storna; není bezpečné jej přejmenovat na pohledávky. Tento plán vědomě zachovává textový režim, nikoli chybnou finanční interpretaci starého textu. Skutečné pohledávky vyžadují samostatně doložené přiřazení plateb ke konkrétním závazkům. Na obrazovce je nahradí jednoznačné přijaté platby, vratky a čistý příjem.

Před uzavřením první implementační vlny ověřit vazby payment_info v aktuálním schématu a v cestách storna/převodu objednávky. Sdílené payment_info stejné akce a měny počítat jednou. Sdílení napříč akcemi nebo nesoulad měny nesmí vést k započítání celé platby do obou akcí: finanční přehled v takovém případě explicitně zneplatnit bezpečnou chybou. Pokud doložený doménový model takové sdílení umožňuje, nejprve upravit plán o existující pravidlo alokace, nevymýšlet poměrové rozdělení. Nezobrazovat identifikátory nebo částky cizí akce. Chybějící payment_info značí nulu přijatých plateb, ne úhradu.

## SQL návrh, bezpečnost a výkon

1. get_report_ws je jediný autorizovaný vstup aplikace. Zachovat public schema, SECURITY DEFINER, explicitní search_path a tenantově omezené rozlišení occasion_link. Pro zamítnutí a neexistující akci neodhalovat cizí údaje. Otestovat volání jako skutečné anon/authenticated role, ne jen nastavení JWT pod vlastníkem DB.
2. Vytvořit celý report v jediném agregačním SQL příkazu se společným snapshotem. Autorizační podmínku svázat i s tímto dotazem; nestačí několik nezávislých SELECT pro jednotlivé bloky. Použít CTE/scoped subqueries: orders_scope, jedinečné payment IDs, transactions_by_payment, spots, tickets a products. Nejde o požadavek jediného fyzického scanu všech tabulek.
3. Každá agregace má vlastní správnou granularitu. Peníze nikdy nesčítat přes JOIN objednávka x položky x transakce. Transakce předagregovat za payment_info, rozsah omezit hned na danou akci. Totály stavů, měn a produktů sestavit až z těchto množin.
4. Interní `public.format_occasion_report_text(report jsonb) RETURNS text` pouze formátuje již hotový objekt, nedotazuje tabulky a nemá SECURITY DEFINER. Vrací text v původním stylu s novými přesnými popisky a vysvětlivkami. Nejde o další klientskou RPC; odebrat EXECUTE rolím PUBLIC/anon/authenticated, ověřit práva skutečného vlastníka volající funkce. Žádný druhý výpočet ani parsing textu v klientu.
5. Nekopírovat dosavadní smyčku dotazů po měnách ani korelovaný dotaz po každé objednávce. Money agregovat GROUP BY currency jedním společným postupem.
6. Indexy navrhovat až z EXPLAIN (ANALYZE, BUFFERS) na izolované DB se syntetickou větší akcí a cizími akcemi. Prověřit orders(occasion), spots(occasion), tickets(occasion), order_product_ticket(order/ticket/product) a transactions(payment_info); nepřidávat duplicity existujících indexů. Nesmí vzniknout full scan transakcí všech tenantů pro každou objednávku. Uvést skutečný plán, počet řádků, dobu a velikost odpovědi, neslibovat nedoložené milisekundy.
7. Bez zápisů, triggerů, background jobů, materializovaných souhrnů a automatického importu bankovních transakcí. Jde o přehled dat už uložených v DB.

## Flutter, načítání a rozvržení

- Přidat `lib/components/eshop/models/occasion_report_model.dart` pro obálku report + text a validaci kontraktu. DbEshop.getReportForOccasion vrátí typovaný model. Peníze předávat prezentačnímu formátování bez klientského přepočítávání metrik.
- ReportTab drží jeden snapshot pro aktuální akci a identitu/organizaci uživatele. Načíst při prvním otevření; znovu pouze při změně tohoto klíče a po vědomém „Obnovit“. didChangeDependencies porovná klíč; stejné závislosti/rebuild nesmějí vyvolat request. Žádný timer/polling ani trvalá globální cache.
- Sloučit opakované požadavky pro stejný klíč během načítání; tlačítko obnovy během requestu deaktivovat. Generation token + mounted ochrání před výsledkem staré akce a setState po dispose. Při změně identity nebo akce okamžitě zahodit předchozí snapshot. Pokud existující lifecycle kartu unmountuje, další otevření může legitimně načíst nový snapshot; nepřidávat kvůli tomu globální stav.
- První načítání: skeleton/indikátor. První chyba: vysvětlení + ruční opakování. Obnova může držet starší data se zřetelným časem a stavem chyby; při ztrátě oprávnění je vždy skrýt. Žádný nekonečný retry ani prázdná obrazovka.
- Hlavička: název akce, čas vytvoření snapshotu, Obnovit, nabídka text/export. TXT vyrobit z již přijatého data pomocí existujícího file_saver, UTF-8 a bezpečný název souboru. Zobrazení textu umožní výběr a kopírování bez requestu.
- Nahoře karty objednávek, vstupenek, míst (jen pokud existují) a čistého příjmu po jednotlivých měnách. Měny nikdy nesčítat.
- Níže pruh obsazenosti, samostatné sloupce pro stavy objednávek a vstupenek, finance a tabulka produktů. Bez historické osy a funnelu. Pro tyto jednoduché grafy preferovat běžné Flutter widgety se sémantikou před novou grafovou knihovnou.
- Každý graf má hodnoty, legendu a přístupný text. Nula nesmí dělit nulou. Neznámé stavy zobrazit; stejné názvy produktů neslučovat. Na mobilu jeden sloupec, široké tabulky nahradit čitelným seznamem.
- Jednověté vysvětlení hlavních metrik přímo u sekce; doplňující detaily otevřít kliknutím dostupným i dotykem a klávesnicí. Tooltip nesmí být jediným zdrojem vysvětlení. Lokalizaci vést přes existující *_strings.dart vzor a překlady; vyhledat vlastníka OrdersStrings před editací.

### Mobil jako podmínka dokončení

- Ověřit šířky 360 a 390 logických pixelů a zvětšení textu na 200 %. Celá stránka nesmí vyžadovat vodorovný posun, ořezávat částky, popisky ani ovládání.
- Karty řadit pod sebe podle dostupného prostoru. Hlavičku zalomit, hlavní obsah nesmí vytlačit tlačítka obnovy a nabídky mimo obrazovku. Interaktivní cíle alespoň 48 x 48 logických pixelů.
- Grafy stavů preferovat jako vodorovné pruhy s počtem a zalomitelným názvem. Na telefonu produkty zobrazit jako seznam s názvem a počtem; žádná zmenšená desktopová tabulka. Dlouhé názvy produktů a velké částky patří mezi testovací data.
- Vysvětlivky otevřít klepnutím do přístupného panelu/dialogu; nespoléhat na hover. Panel musí jít zavřít systémovým návratem i viditelným ovládáním a respektovat bezpečné okraje obrazovky.
- Textový režim zalamuje řádky a umožňuje výběr textu. Export funguje přes podporovanou platformní implementaci file_saver; ověřit mobilní web a podporovaný nativní mobilní cíl odděleně, případné omezení přesně uvést.
- Do widget testu přidat úzký viewport, velký text a dlouhé popisky bez overflow. Při závěrečné vizuální kontrole ověřit také reálnou čitelnost, dotykové otevření vysvětlivek a dostupnost exportu. Pokud mobilní runtime není dostupný, vykázat neověřenou platformu, nikoli označit mobil za otestovaný.

## Implementační vlny

### 1. Kontrakt a správné agregace

Změny: get_report_ws.sql, nový čistý formatter SQL, model specifikace výše, kanonická SQL migrace dle aktuálního release workflow. Ověřit platební vazby a jednotku produktů popsané výše a zapsat zjištění do tohoto plánu. Zajistit dopřednou kompatibilitu: text data zůstává string, nové report je aditivní. Finanční chyby nevydávat za úspěšný text.

Testy: rozšířit `database/tests/get_report_tenant_scope_test.sql`, přidat `database/tests/eshop/occasion_report_test.sql`. Pokrýt nuly, více měn včetně vratek, kladné/záporné manual transakce, přeplatky, zálohu bez plné úhrady, storno s platbou, sdílené payment_info, více položek jedné vstupenky, shodné názvy produktů, neznámé stavy a nepřístupnou akci. Test musí ověřit číselné výsledky, nikoli jen existenci klíčů. Test oprávnění nesmí projít díky superuserovi.

Výstup: jeden autorizovaný call poskytuje správný objekt i souhlasný text; EXPLAIN na lokálních syntetických datech nevykazuje násobení řádků/N+1. Žádná produkční migrace v této vlně.

### 2. Grafický klient a načítání

Změny: DbEshop, nový model, ReportTab a malé prezentační widgety podle potřeby, lokalizace a export. Oddělit parsování odpovědi od vykreslení; pro widget test umožnit injekci loaderu bez globálního service frameworku. Odstranit text jako výchozí obsah a prázdný řetězec jako reprezentaci chyby.

Testy: model kontraktu a widget test loaderu - první otevření jeden call; rebuild, graf/text a export žádný nový call; obnova právě jeden call; změna akce/identity ignoruje pozdní výsledek; chyba a dispose jsou bezpečné. Pokrýt prázdný a víceměnový report, viditelné vysvětlivky a sémantiku grafu. Test neporovnává doslovně celou lokalizovanou obrazovku.

Výstup: grafika i text vycházejí z téhož snapshotu; mobilní layout a přístupné ovládání jsou ověřené. Obnova nezpůsobí souběžné požadavky.

### 3. Odstranění starých výpočtů a připravenost na nasazení

Migrovat oba existující integrační testy záloh na strukturované metriky přes autorizovaný get_report_ws; zachovat test skutečného platebního workflow. Nahradit textové testy tenant scope kontrolou správného occasion ID i původního typu data.

Odstranit kanonický `get_report_for_occasion(bigint)` a jeho zdroj až po kontrole pg_depend, katalogu funkcí a volajících ve schématu izolované DB. Nepoužívat DROP CASCADE. Historické migrace nepřepisovat. Staré varianty z security migrace prověřit cíleně v aktuálním baseline; případné aktivní závislosti vyřešit před dropem. Pokud je přímý starý endpoint doloženým používaným veřejným kontraktem, zaznamenat jej jako explicitní kompatibilní adaptér bez vlastních agregací a se stejnou autorizací; bez důkazu takový adaptér nezavádět.

Výstup: get_report_ws je jediný aplikační report endpoint, staré paralelní agregace a neautorizované čtecí cesty jsou pryč; README popisuje rozšířený kontrakt. Připravena dopředná migrace bez změny obchodních dat.

## Ledger odstranění a kompatibility

| Artefakt | Cílový stav | Důkaz |
|---|---|---|
| get_report_ws(text) | Zachovat signaturu, rozšířit odpověď | Starý klient čte data string, nový report objekt |
| get_report_for_occasion(bigint) | Odstranit staré agregace i funkci po kontrole závislostí | rg, katalog a cílené testy |
| Historické varianty reportových funkcí | Inventura a odstranění aktivního obcházení oprávnění; žádné slepé dropy | pg_proc/pg_depend a role test |
| Text | Zachovat sekundární UI a kompatibilní pole data | Shoda s report objektem; žádný extra request |
| Dvě měnové větve a dotazy v cyklu | Odstranit | Jedna GROUP BY agregace, číselné testy |
| Prázdný text při chybě, opakovaný load při rebuild | Odstranit | Model a widget test |
| Historické migrace | Ponechat neměnné | Nová migrační změna |

## Ověření a provozní pořadí

Plán vznikl z repozitáře, bez spuštění testů nebo přístupu do produkce. Implementace vyžaduje standardní cílené ověření, nikoli testování po každé drobné editaci.

- SQL: izolovaná DB dle CONTRIBUTING.md. `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js <konkrétní test>` pro nový test, tenant scope a oba dotčené integrační testy. Bootstrap použít jen je-li potřeba aktualizovat izolovaný schema baseline.
- Flutter: `fvm flutter test test/components/eshop/occasion_report_test.dart` (model + widget chování) a cílené `fvm dart analyze` změněných Dart souborů. Přizpůsobit cestu skutečnému rozdělení testů bez ztráty pokrytí.
- Před integračním handoffem dodržet rovněž povinné repository gates z CONTRIBUTING.md, včetně `./automation/test_all.sh` tam, kde je vyžadována Verify Integrity. Pokud prostředí brání běhu, uvést přesný neprovedený check.
- UI ověřit v izolované background session podle agent-browser pravidel, pokud je potřeba ověřit layout; nikdy nepoužívat produkční data jako testovací fixture.
- Před nasazením schváleným workflow ověřit aktivaci cílového self-hosted backendu podle ai_context.md; zastaralé instrukce o cloudových zdrojích v CONTRIBUTING.md nepoužít. Tento úkol neopravňuje k nasazení, pushi ani migraci produkce.
- Nasazení po samostatném zadání: backend s aditivní odpovědí první, nový klient druhý. Pracovat na main a pouze s později výslovně zvoleným tenantem. Žádný automatický rollout prod/*.
- Rollback klienta je bezpečný díky zachovanému data. Backend rollback nesmí odebrat report, dokud jej používají nové instalace. Preferovat opravu dopředu; neopakovat staré chybné výpočty jako fallback.

## Hotovo znamená

Grafický report s vysvětlivkami je výchozí, text i TXT export jsou sekundární. Jediná RPC získá agregovaný snapshot bez detailních řádků. Překreslení a export nenačítají data znovu. Stará a nová prezentace sdílí výpočty, měny zůstávají oddělené, platby se nenásobí přes položky a grafy nezaměňují stav za úplnou úhradu. Oprávnění a tenant scope platí na všech dostupných čtecích cestách. Testy a požadované gates prošly nebo jsou konkrétně označené jako blokované. Nasazení se vykazuje odděleně od dokončené implementace.

Zbytkové nejistoty: skutečné distribuované velikosti akcí a produkční indexy nebyly měřeny; historické SQL aliasy a sdílení payment_info se musí ověřit v první/třetí vlně. Finanční přehled není účetní uzávěrka ani report historických cen. Stav placených pohledávek není součástí tohoto návrhu.

## Zjištění při implementaci (2026-10-03)

- `database/tables/tables.sql`: orders.payment_info je neunikátní FK. Lokální aktuální katalog nemá UNIQUE index na této vazbě. Report proto deduplikuje payment_info; žádné pravidlo poměrové alokace není doloženo.
- `order_product_ticket` nemá quantity; jeden řádek je jedna produktová položka. Nový test ověřuje tři položky a jednu vstupenku sdílenou dvěma položkami.
- `apply_transaction_pairing.sql` vybírá vratky podle typu `return`, nikoli znaménka. Report čte uložené paid/returned a párování nepřepočítává; ruční příjmy zůstávají pouze kladné manual transakce.
- `update_order_and_tickets_to_storno.sql` zachovává payment_info a nuluje cenu. `confirm_blueprint_order_change.sql` stornuje konfliktní vstupenky a vytváří novou objednávku přes formulář ve stejné akci; nedokládá alokaci plateb napříč akcemi.
- Katalog izolované DB před migrací obsahoval get_report_for_occasion(bigint), get_report_for_occasion_with_security(text), get_report_for_occasion_ws(text), get_report_ws(text). Dva historické form-link aliasy pouze volaly bigint helper. Žádní aplikační volající aliasů ani pg_depend závislosti nebyli nalezeni; těla funkcí byla zkontrolována zvlášť, protože PL/pgSQL textové reference pg_depend nezachytí. get_report_for_occasiont nebyl přítomen. Migrace odstraňuje právě tři doložené staré funkce, bez CASCADE; historický baseline a migrace jsou neměnné.
- Po lokální migraci zůstal pouze get_report_ws(text). Vlastník postgres má EXECUTE na privátní formatter; authenticated a anon jej nemají. Cílené testy volají skutečnou authenticated roli; anon RPC spustit nemůže.
- Výkon: 50 000 syntetických objednávek (5 000 cílové akce), 50 000 payment_info, 100 000 transakcí, 15 000 položek, 5 000 vstupenek a míst. EXPLAIN ANALYZE BUFFERS je v `docs/plans/evidence/occasion-report-explain.txt`, reprodukce v sousedním SQL. Před indexy 64.967 ms, po dvou indexech orders(occasion), orders(payment_info) 38.531 ms; odpověď 1 677 bajtů. Transakce mají jeden společný scan, nikdy full scan pro každou objednávku. Planner v této velikosti preferuje scan transakcí před indexem; indexy bez měřeného přínosu nebyly přidány. Nejde o produkční SLA.
- Při chybě obnovy klient konzervativně skryje snapshot i při transportní chybě, takže nemůže ponechat data po ztrátě oprávnění. Auth změny i RightsService notifier invalidují kontext. Žádná globální cache nebo další RPC.

## Závěrečné ověření a provozní omezení

- Cílené SQL: occasion_report_test, get_report_tenant_scope_test, mixed_cart_flow_test, on_site_surcharge_flow_test prošly. Závěrečné doplnění navíc ověřuje samostatné storno s přijatou platbou/vratkou a číselné platby nad zálohu v obou původních platebních workflow.
- Flutter: `fvm flutter test test/components/eshop/occasion_report_test.dart` - 9 testů prošlo. Kontrakt/decimal precision, chyby starého backendu, lifecycle/rebuild/export/obnova, opožděné výsledky, změna identity, dispose, revokace přístupu, prázdná akce, mobil 360/390 s textem 200 %, desktopová tabulka a sémantika pruhů.
- `fvm dart analyze` pro DbEshop, ReportTab, model a ReportStrings nemá chyby nebo nové diagnostiky. Zůstaly tři předchozí info `use_build_context_synchronously` v nesouvisejících metodách DbEshop (nyní řádky 99, 134, 151). `git diff --check` prošel.
- Lokalizace: spuštěny unify_translations.js a reorder_cs_like_en.js. Nový blok OccasionReport je shodný ve Flutter a web překladech; následně zachováno původní pořadí/whitespace nesouvisejících překladových bloků, aby nebyly součástí změny.
- Vizuální kontrola: finální syntetický harness `test/components/eshop/occasion_report_preview.dart`, izolovaný headless Chrome s explicitním prázdným agent-browser configem (globální config vybírá Panerelay). Šířky 360/390 a text 200 %, zalomená hlavička, vysvětlivka otevřená kliknutím a zavřená viditelným ovládáním/klávesou, dlouhé názvy a částky, produkty jako seznam. Document scrollWidth odpovídá viewportu, widget testy nehlásí overflow; menu a vysvětlivky mají minimálně 48 x 48.
- Mobilní webový export: Chrome s emulací iPhone 14, skutečné vyvolání nabídky TXT a browser download; ověřeno 114 bajtů syntetického textu v UTF-8 včetně české diakritiky. Jde o emulovaný mobilní web, fyzický telefon/Safari nebyl testován.
- Nativní export: `fvm flutter build ios --simulator --debug --target test/components/eshop/occasion_report_preview.dart --dart-define=REPORT_PREVIEW_NATIVE_EXPORT=true` prošel. Ve vlastním izolovaném iPhone 17 simulátoru s iOS 26.5 skutečný file_saver vytvořil Documents/occasion_report_native_smoke.txt, ověřeno 114 bajtů a UTF-8 obsah. Tento smoke ověřuje nativní plugin; nativní ovládání nabídky automatizováno nebylo. Android runtime ani fyzické mobilní zařízení nebyly ověřeny.
- Úplný `./automation/test_all.sh` s explicitním lokálním DATABASE_URL a lokálními HTTP env overrides: 101 SQL testů prošlo; 861 Flutter testů prošlo, 1 skipped; 212 Deno testů prošlo; bank-import integrace 3 prošly a 27 testů externího image workeru je na lokální DB standardně skipped.
- Úplný gate **není zelený**: web má 203 passed / 11 failed. Devět `web_client/tests/core/rpc_security.test.js` případů vyžaduje lokální REST API na 127.0.0.1:55431, které neběží (ECONNREFUSED); izolovaná PostgreSQL DB běží samostatně. Dva `supabase_client_config.test.js` případy očekávají historický cloud URL, zatímco aktuální aktivace vybírá api.festapp.net. Tyto testy byly spuštěny proti lokálnímu cíli, ne produkci.
- `automation/tests/update_prompt.test.sh` také selhal: fixture aktivace generation 0 proti požadované generation 1 a transition fixture stránky delete-account míří na nesprávný backend. Report nemění tyto fixtures nebo backend aktivaci. Po tomto bodě runner skončil; všechny jeho zbývající gates byly proto spuštěny samostatně a prošly: update_prompt_behavior, flutter_bootstrap_guard, client_sync_cutover, pwa_offline, project_version, font_config a závěrečná skupina PWA/infrastructure kontraktů (97 passed).
- Lokální migrace byla aplikována pouze na izolovanou DB 127.0.0.1:55432. Katalog po migraci nemá staré reportové funkce ani jejich textové reference v dalších funkcích. Produkční migrace, deployment, commit, push a rollout nebyly provedeny. Nasazení zůstává samostatným provozním krokem: nejprve aditivní backend, potom klient.

## Příprava live nasazení po samostatném zadání

Uživatel následně autorizoval začlenění do main a nasazení pouze na live.festapp.net (prod/festapp, Pages festapplive, canonical organization 1). Změna je izolovaná nad aktuálním origin/main; ostatní rozpracované změny původního checkoutu nejsou zahrnuty. Main vyžaduje podle GitHub branch protection PR s jedním schválením; administrativní bypass se nepoužívá.

Při přípravě byly opraveny skutečné blokující testové fixtures: testy obnovy session používají deterministický lokální resolver bez čtení živého manifestu, test release manifestu rozlišuje canonical generation 1 a legacy generation 0, a transition fixture obnovuje odpovídající deletion endpoint. Tyto změny pouze opravují testy, nemění autentizaci produkce. Nová migrace přenechává vnější transakci release runneru, aby instalace a ledger byly atomické i při Access SQL fallbacku.

Cloudflare Pages OAuth je dostupné. Backendový Access CLI nemá platný cached token. Trvalý přístup pro agenta je zatím pouze dokumentovaný návrh, není provisionovaný; produkční SQL a deployment proto zatím nebyly provedeny. Aktivační dokument live potvrzuje tenant festapp / canonical / generation 1. Před migrací zbývá databázová identita, organizace 1 a katalogový dependency preflight na skutečném backendu.

Příprava nad origin/main 8e757ca1a: 205 web testů passed / 9 vyžadujících live security HTTP endpoint skipped, 102 SQL passed, 927 Flutter passed / 1 skipped, 212 Deno passed, integrace 3 passed / 27 externí image-worker skipped. Po opravě kolidujícího migračního timestampu byly všechny automation gates znovu spuštěny a prošly. Jedinečná reportová migrace je nyní `20261003190100_occasion_report_snapshot.sql`; timestamp 20261003170000 již patří ticket_canvas_color na aktuálním main. Cílená Dart analýza má pouze stejné tři předchozí infos v DbEshop. Není potřeba znovu spouštět již prošlé neovlivněné SQL/Flutter/Web/Deno testy po změně názvu migračního souboru.
