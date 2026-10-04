# Průvodce založením události

Datum: 2026-09-25\
Stav: fáze 0 — Flutter simulace k posouzení; produkční implementace zatím nezačala\
Ověřování: standard (oprávnění, platební konfigurace, veřejné formuláře a nová SQL operace)

## Výsledek

Správce jednotky založí novou událost v jednom přehledném průvodci. Vyplní základní údaje, zvolí funkce, nastaví registraci/prodej, přidá nebo převezme formulář a blueprint a vybere, které části starší události chce převzít. Od prvního kroku vzniká trvale uložený **draft**: po odchodu je zřetelně označený v administrativním seznamu událostí a pokračuje se přesně tam, kde uživatel skončil. Progress line ukazuje dokončené části; 100 % nastane až po všech potřebných nastaveních a finální kontrole. Ani 100% draft není automaticky veřejný. Nedojde k přenosu objednávek, registrací, rezervací, účastníků ani starých platebních či časově omezených stavů.

**Pořadí práce:** nejdřív projít a vyhodnotit Flutter simulaci `lib/components/occasion/prototype/occasion_setup_demo.dart`, upravit podle připomínek obrazovky a rozhodnutí v tomto plánu, teprve potom začít produkční serverové a Flutter vlny. Simulace používá `ThemeConfig`, Flutter Material a demonstrační režim skutečného `BlueprintTab`. Drafty ukládá pouze do úložiště tohoto prohlížeče; nevolá Supabase a nic nezveřejňuje. Starý statický HTML náhled je nahrazen. Po rozhodnutí se pravidla UX zapíší do plánu; demonstrační kód se nepřejímá jako produkční persistence.

## Rozsah

### Součást

- Jeden průvodce pro „novou prázdnou“ a „podle starší“ události, dostupný z obou dnešních vstupů: seznam událostí jednotky a přepínač událostí v administraci.
- Serverově uložené rozpracované drafty, jejich vyhledání a pokračování v oddělené, jasně označené sekci seznamu událostí. Automatické uložení každé rozpracované části a progress line se skutečným významem 100 %.
- Volba jednotlivých částí předlohy, úprava základních údajů a termínu, nastavení příznaků/funkcí, formulářů, jejich polí a souvisejících produktů, blueprintu/sedadel, programu/míst, informačních bloků a šablon e-mailů.
- Možnost založit prázdný formulář nebo **zkopírovat celý existující formulář přímo do draftu** včetně polí, voleb, typů produktů a produktů; kopie se pak upravuje ve stejném editoru jako běžný formulář. Příznaky „pole připravená“ a „produkty připravené“ nejsou konfigurace. Lze vytvořit prázdný plánek nebo jej převzít s plánem sedadel. Soubor SVG/obrázek pozadí lze přidat během dokončení průvodce.
- Serverový souhrn dostupnosti předlohy a závislostí; atomické vytvoření databázových částí, bezpečné dokončení médií, přehled výsledku, opakování nedokončené části.
- Převod stávající akce „Vytvořit kopii“ na stejný mechanismus s předvolenými sekcemi. Zachovat její dostupnost jen pro dosud oprávněné role.

### Mimo rozsah

- Kopie živých obchodních dat: objednávky, platby, faktury, QR/tikety, odpovědi, účastníci, registrace, rezervace, zámky sedadel, check-in, historie a statistiky.
- Import formuláře ze souboru či externí platformy. „Nahrát formulář“ zde znamená vytvořit jej v editoru nebo převzít již existující formulář; import ze souboru je samostatná produktová funkce.
- Převod dat mezi organizacemi nebo produkčními větvemi. Výběr zdroje zůstává v přístupné organizaci; žádný rollout do dalších tenantů.
- Přepracování editorů formuláře/blueprintu a jejich veřejného běhu. Průvodce je použije pro detailní dokončení v témže toku.

## Omezení a současný stav: ověřená fakta

| Fakt | Důkaz v repozitáři | Dopad |
|---|---|---|
| Založení je dnes krátký dialog pro název, link a termín; volá `DbOccasions.updateOccasion`. | `lib/components/occasion/occasion_creation_helper.dart:16,178–208` | Rozšířit vstup na průvodce, ne přidat další paralelní tvorbu. |
| Dialog se volá ze seznamu i přepínače událostí. | `lib/components/unit/views/occasions_screen.dart:111`; `lib/components/_shared/app_panel_helper.dart:129` | Oba vstupy musí vést na stejný stav a návratový výsledek. |
| Kopie je nyní oddělená akce seznamu, vyžaduje manažera jednotky; SQL kopíruje celou řadu tabulek. | `occasions_screen.dart:130–145`; `database/functions/others/duplicate_occasion.sql:19–319` | Výběr sekcí nelze bezpečně implementovat jen filtrováním výsledku v UI. |
| Kopie SQL mapuje místa, akce, skupiny, blueprinty, produkty, sedadla, formuláře a pole; termíny akcí nechává původní. | `duplicate_occasion.sql:95–317` | Nový serverový copy graph musí mapovat ID a definovat posun termínů. |
| Dnešní kopie znovu používá `bank_account` a pro některé chybějící mapy používá `COALESCE(..., původní ID)`; neukládá některé atributy produktů. | `duplicate_occasion.sql:193–239,282–317` | Nesmí se tiše připojit ke zdrojovým objektům; platební účet a úplnost produktů vyžadují kontrolu. |
| Po SQL kopii se obrázek události a pozadí tiketu kopírují v Dartu. | `lib/components/occasion/db_occasions.dart:189–213` | Média jsou mimo SQL transakci; musí mít stav a opakování. |
| `update_occasion_internal_v1` při zapnuté funkci formuláře vytváří výchozí formulář, při zapnutém blueprintu může vytvořit výchozí blueprint a připojit jej k prvnímu formuláři. | `database/functions/others/update_occasion.sql:193–239` | Wizard musí předejít duplicitnímu výchozímu formuláři/blueprintu a zaručit jejich vazbu. |
| Režim klientských příkazů používá `create_occasion_client_sync_v1` a `duplicate_occasion_client_sync_v1`; oba mají obaly, které drží `client_sync_v1=false` pro nové objekty. | `lib/components/occasion/occasion_commands.dart:47–101`; `supabase/migrations/20260806100000_client_sync_production_hardening.sql:512–599` | Nová cesta musí respektovat idempotentní command transport a publikaci změn. |
| Formulář lze vytvořit/kopírovat samostatně; kopírovací RPC přebírá blueprint ID a účet ze zdroje. | `lib/components/forms/db_forms.dart:35–106`; `database/functions/eshop_forms/duplicate_form_to_occasion.sql:81–140` | Nelze ho bez změny použít pro plnou kopii v wizardu. |
| Blueprint se ukládá přes formulářovou službu, editorem se nahrává SVG či obrázek. | `lib/components/forms/db_forms.dart:223–276`; `lib/components/blueprint/views/blueprint_controls_bar.dart:209–265` | Použít existující editor/validaci pozadí, nevytvářet druhý editor sedadel. |
| Seznam událostí vrací jen zkrácená `features` a `data`; není vhodný jako zdroj plného návrhu kopie. | `database/functions/others/get_all_occasions_for_edit.sql:38–100` | Potřebný je vlastní autorizačně filtrovaný manifest předlohy. |
| Funkce jsou typované a závisejí na podpoře aplikace organizací. | `lib/components/features/feature_service.dart:23–108`; `update_occasion.sql:35–95` | Při převzetí validovat dostupnost a neukazovat nezapnutelné volby. |
| Formulář už má čas otevření/zavření, odpočet, uzavírací text, design, splatnost, připomínky, variabilní symbol, platební zprávu a tón komunikace. | `lib/components/forms/views/form_editor_content.dart:151–306`; `form_settings_content.dart:137–211,417–643`; `form_design_settings.dart:269–475`; `models/form_model.dart:45–67,198–248` | Wizard má zobrazit podstatné volby a menší nastavení ve sbalených blocích, ukládané do stejného kontraktu. |
| Funkce formuláře má ještě režim externího formuláře, externí odkaz/cenu, text rezervačního tlačítka a globální připomínky/splatnost. | `lib/components/features/form_feature.dart:10–85,150–245` | V UI odlišit externí od interní registrace a nezaměnit globální a per-form nastavení. |
| Bankovní účet může být uložen na formuláři; pokud není, `create_ticket_order` vybere první účet jednotky podporující měnu dle priority a vyloučí `CASH`. Admin editor ukazuje účty jednotky ve stejném pořadí. | `database/functions/eshop/create_ticket_order.sql:353–393`; `database/functions/eshop_forms/get_form_for_edit.sql:119–146`; `lib/components/forms/views/form_settings_content.dart:299–370` | Wizard musí zobrazit skutečnou platební trasu pro každou měnu a dovolit platný explicitní účet nebo automatický výběr. |
| Nastavení události už má sbalenou sekci pro link, reply-to adresu a časovou zónu; viditelné jsou i příznaky veřejnosti, skrytí a promování. | `lib/components/occasion_settings/occasion_advanced_settings.dart:36–113`; `occasion_settings_tab.dart:453–535` | Zachovat význam voleb a jejich validaci, ale do průvodce je rozmístit podle frekvence použití. |
| Administrativní seznam nyní dělí pouze existující události na probíhající, budoucí a minulé; karta nemá draft status ani progress. | `lib/components/unit/views/occasions_screen.dart:153–219`; `occasion_edit_card.dart:37–115` | Drafty zobrazit samostatně před těmito skupinami a odlišit i při vyhledávání. |
| `BlueprintTab` běžně načítá podle routy a ukládá do DB; jeho kreslicí plocha je `VenueSeatViewer` z již používaného balíčku. | `lib/components/blueprint/views/blueprint_editor_tab.dart:44–80,137–225,660–704` | Pro draft je potřeba injektovat model a ukládací callback, ne kreslit druhý editor. |

Reprezentativní tok dnes: klik na „novou událost“ → dialog → `DbOccasions.updateOccasion` → podle runtime SQL `update_occasion_203` nebo `create_occasion_client_sync_v1` → výchozí formulář/blueprint podle funkcí → další konfigurace odděleně v `OccasionSettingsTab`, `FormsTab` a `BlueprintTab`. Kopie jde přes jinou akci a `duplicate_occasion` / klientský příkaz plus Dart kopírování médií.

## Cílová smlouva a pravidla

### Vlastník

- Jeden finální serverový příkaz `create_occasion_from_setup_v1(p_command_id uuid, p_draft_id uuid, p_expected_revision bigint)`, v kanonickém SQL a timestampované migraci. Uložený draft obsahuje cílovou jednotku; link, titul, datumy, časovou zónu, popis; vybrané funkce; zdrojovou událost/formulář a manifest sekcí; posun programu a nastavení formulářů/blueprintu. Výstup: ID/link události, ID nových formulářů/blueprintů, mapování pro dokončení médií a stav povinných kontrol. Stejný `p_command_id` vrátí stejný výsledek bez druhé události.
- SQL kontroluje cílového editora; zdrojový manifest a zvolené části jen při oprávnění číst zdroj. Celá kopie odpovídající dnešnímu „Vytvořit kopii“ nadále vyžaduje manažera zdrojové jednotky. Pokud role nestačí, UI daný režim nenabídne a server jej odmítne. Zdroj a cíl musí být ve stejné organizaci, bankovní účet zvlášť validovaný pro cíl.
- Databázová část proběhne v jedné transakci. Žádné fallbacky na ID staré události u vztahů nový formulář ↔ blueprint ↔ pole ↔ produkt ↔ sedadlo ↔ program. Chybějící závislost znamená odmítnutí nebo vědomé vypnutí celé související volby před potvrzením.
- Draft vlastní nový serverový kontrakt `occasion_setup_drafts`, oddělený od `public.occasions`: UUID, cílová organizace/jednotka, autor, JSON nastavení a blueprintu, verze, aktuální krok, stav, časy změn a případné výsledné occasion ID. Všechny nové drafty existují před vytvořením události; veřejné occasion/form RPC je nikdy neuvidí. `lib/components/occasion/setup/` pracuje s tímto kontraktem přes jedinou službu, nikoli s lokálním konceptem jako autoritativním zdrojem.
- Draft operace: `create`, `get/list`, `save(expected_revision)`, `delete` a `finalize(command_id, expected_revision)`. Veškeré čtení i zápis jsou omezené na editory cílové jednotky, zdrojová práva se při finalizaci kontrolují znovu; stavový přechod a idempotence probíhají v SQL transakci. Současné změny dvou editorů vrátí konflikt s možností načíst novější draft, nikdy nepřepíší cizí změny potichu.
- Konečný `create_occasion_from_setup_v1` přijímá ID uloženého draftu a command ID, načte jeho aktuální revizi a provede atomickou finalizaci. Výsledek obsahuje ID/link události a mapování pro dokončení médií. Nemá přijímat neuložený payload přímo z klienta, aby náhled, progress a finální zápis vycházely ze stejného potvrzeného stavu.
- Vytvoření ve wizardu nevolá `update_occasion_internal_v1` s aktivním formulářem/blueprintem před dokončením výběru, protože tato funkce zakládá výchozí objekty jako vedlejší efekt. Nový příkaz sestaví celý graf najednou a příslušné automatické výchozí objekty vytvoří jen v prázdné větvi.

### Stav a životní cyklus

1. **První krok:** server vytvoří draft; v seznamu „Rozpracované koncepty“ se ukáže karta DRAFT i při zatím prázdném názvu. Draft není `public.occasions`. Výběr zdroje načte manifest; změna zdroje vyžaduje potvrzení zahození převzatých částí.
2. **Práce v průvodci:** po každé změně autosave s krátkým debounce a verzí draftu; stav „Ukládám / Uloženo / Nepodařilo se uložit“. Před opuštěním/uzavřením se pokusit o flush; při neúspěchu jasně upozornit, že poslední změny nejsou bezpečně uložené. Obnovení stránky nebo odchod do seznamu otevře uložený krok a hodnoty. Draft se nemaže automaticky; explicitní smazání vyžaduje potvrzení.
3. **Blueprint a formulář v draftu:** existující editory pracují přes injektovaný draft model/repozitář a ukládají změny zpět do draftu, včetně polí, produktů, skupin, sedadel a rozměrů. Dema režim `BlueprintTab.prototype` ukazuje reuse plátna, produkční režim musí dostat skutečný draft adapter. Souborový podklad/obrázek se ukládá do soukromého stagingu pod ID draftu; bez dokončeného uploadu nesmí progress vykazovat hotovou položku.
4. **Dokončení konfigurace:** kontrola se opírá o uloženou revizi draftu; při neshodě obnoví data. Po splnění všech aktivních kroků a potvrzení finální kontroly je progress **100 %**, ale karta zůstává DRAFT, dokud uživatel neprovede oddělený krok „Vytvořit událost“. Procento nesmí být jen poměr navštívených obrazovek.
5. **Finalizace:** SQL atomicky vytvoří `public.occasions` s `is_hidden=true`, `is_open=false`, `is_promoted=false`, připojené formuláře zůstanou `is_open=false`, přemapuje všechny vazby, označí draft `finalized` a uloží occasion ID. Retry stejného command ID vrátí stejné ID. Draft zmizí ze sekce rozpracovaných a nová událost se zobrazí v administraci jako soukromá/neotevřená.
6. **Média a zveřejnění:** staged média se dokončí a dostanou vlastnictví nové události; chyby jsou opakovatelné z její administrace. Otevření registrace/prodeje a veřejné zobrazení je další vědomý krok s readiness kontrolou. Progress 100 % draftu neznamená zveřejnění.

**Výpočet progressu:** šest milníků: (1) zdroj či volba „od nuly“, (2) platný základ, (3) výslovný výběr funkcí/obsahu, (4) dokončené zvolené formuláře/produkty/platby nebo výslovné „bez formuláře“, (5) dokončený blueprint a vazby nebo výslovné „bez blueprintu“, (6) potvrzená finální kontrola. Uložený stav každého milníku je `incomplete`, `needs_attention` nebo `complete`; procento je počet úplných milníků / 6, zaokrouhlený dolů, a 100 lze zobrazit pouze při šesti úplných. Změna nadřazené volby invaliduje dotčený milník i finální kontrolu. Lišta ukazuje také text „X z 6 kroků dokončeno“ a blokující úkoly; číslo samo není jediný signál.

Pravidla připravenosti: veřejný odkaz a interval události jsou platné; interní registrace vyžaduje alespoň jeden uzavřený, úplný formulář, který lze otevřít; prodej s převodem navíc vyžaduje platné produkty, měny a konkrétní oprávněný účet pro každou použitou měnu; prodej se sedadly vyžaduje blueprint připojený k prodávanému formuláři a každé sedadlo navázané na produkt nové události. Externí formulář vyžaduje validní externí URL a jasně označený režim, nikoli prázdný interní formulář. Bezplatný formulář ani platba mimo převod nemají dostat falešný blok kvůli bankovnímu účtu. Záměrné „Otevřít“ přepne jen výslovně vybrané formuláře a událost, nikdy všechny formuláře automaticky. Změny těchto podmínek po otevření musejí projít stejnou kontrolou na serveru.

## Návrh obrazovky a práce s menšími nastaveními

Průvodce má na počítači hlavní sloupec s jedním krokem a úzký trvale viditelný souhrn; na mobilu je souhrn rozbalitelný nad tlačítky. V záhlaví každého kroku je jeden řádek „co bude vytvořeno“. Každá sekce ukazuje důležité volby přímo a detailní volby v jedné či několika pojmenovaných rozbalovacích skupinách. Řádek sbalené skupiny ukazuje zvolené hodnoty, počet změn oproti výchozímu stavu a případnou chybu, například „Platební údaje · CZK → účet 123… · 2 změny“. Detailní volba tedy nezmizí z kontroly jen proto, že je sbalená. Uživatelské názvy a popisky přebírat z existujících `AdministrationStrings`, `CommonStrings`, `FeatureFormSettings` a dalších překladů; interní `blueprint` se v UI nazývá **Plánek** podle `Common.blueprint`. Krok Základ převzít ze stávajícího dialogu `OccasionCreationHelper`: stejná pole název/link, `TimeDateRangePicker`, automatický návrh linku, jeho kontrolu a náhled adresy; rozdíl je průběžné ukládání draftu místo okamžitého vytvoření události.

```text
Nová událost                 Zdroj  ›  Základ  ›  Obsah  ›  Formuláře  ›  Plánek  ›  Kontrola
┌─────────────────────────────────────────────┐  ┌────────────────────────────┐
│ Formulář: Registrace 2027                   │  │ Vznikne                     │
│ Název    [ Registrace 2027             ]     │  │ 1 událost · 1 formulář      │
│ Link     [ registrace2027              ]     │  │ 3 produkty · 120 sedadel    │
│                                             │  │                            │
│ ▸ Čas a dostupnost · zatím zavřený          │  │ Vyžaduje kontrolu           │
│ ▸ Platby · CZK → účet 123… · 2 změny         │  │ • Účet pro EUR              │
│ ▸ Komunikace · tón dle jednotky             │  │ • Pozadí blueprintu         │
│ ▸ Vzhled · převzato z předlohy              │  │                            │
└─────────────────────────────────────────────┘  └────────────────────────────┘
                                    [ Zpět ] [ Pokračovat ]
```

Na mobilu je jediný sloupec: číslo a název kroku, karta, sbalený souhrn, pevně dostupné ovládání Zpět/Pokračovat. Panel souhrnu nesmí překrývat pole ani klávesnici. Výchozí prázdná cesta má nejvýše základní údaje, zapnutí formuláře a souhrn; ostatní kroky se ukážou jen při vybrané funkci nebo zdroji. Přímé „Přeskočit detaily“ používá viditelné výchozí hodnoty uvedené v souhrnu.

| Krok | Vždy viditelné | Sbalené skupiny a konkrétní volby | Kdy se otevře automaticky |
|---|---|---|---|
| Zdroj a obsah | Prázdná/podle starší; zdroj; jednotlivé sekce s počty a závislostmi | „Podrobnosti kopie“: formuláře a pole, produktové typy/produkty, blueprint/sedadla, program/místa, obsah/e-maily; stav nepodporovaných modulů | Rozpor mezi vybranými sekcemi; položka nepřenositelná kvůli právům či vazbě |
| Základ | Název, začátek/konec, časová zóna, výsledný link a stav soukromého návrhu | „Další údaje“: popis, obrázek, reply-to adresa; „Zobrazení“: budoucí veřejnost/promování s vysvětlením, že se teď neaktivují | Neplatný link/časová zóna/e-mail nebo kolize linku |
| Funkce | Krátký seznam použitých funkcí s jasným zapnuto/vypnuto | „Další funkce“: zbývající podporované funkce podle `FeatureService`; „Nastavení registrace“: interní/externí režim, externí URL/cena, text tlačítka, globální interval připomínek | Zapnutá funkce bez potřebné sekce; neplatná externí URL |
| Formuláře | Pro každý formulář karta s původem, názvem, typem, linkem, počtem skutečných polí/produktů a stavem „zatím zavřený“; akce založit/převzít/otevřít editor/odstranit. Převzetí ihned vytvoří nezávislou kopii v draftu, kterou lze upravit. | „Čas a dostupnost“: otevření/uzavření, odpočet, text při uzavření; „Platby“: splatnost, účty a měny, variabilní symbol, počáteční číslo, zpráva pro platbu; „Komunikace“: připomínky, dědění/formální/neformální tón, úvodní text; „Vzhled“: kartový design, preset/barvy, font | Chyba konkrétního formuláře; chybějící účet pro měnu; zděděné datum mimo nový termín |
| Plánek | Vypnuto/prázdný/převzatý, název formuláře, rozměry, počet skupin a sedadel, náhled pozadí | „Plán a pozadí“: rozměry, SVG/obrázek, převzetí pozadí; „Sedadla a produkty“: přiřazení produktů ke skupinám a počet neprodejných míst | Plánek bez formuláře, neznámý produkt nebo neplatný podklad |
| Kontrola | Progress line a oddělený počet potvrzených kroků a částí bez chyb. Viditelný přehled skutečných hodnot: zdroj a vybrané části, název/link/termín události, funkce, původ formuláře, jeho pole včetně typů a voleb, produktové typy a produkty s cenami/měnou/limity, účet/splatnost/komunikace, plánek s rozměry/skupinami/místy a soukromý stav. Každá část má „Upravit“ zpět na příslušný krok. | „Co zbývá“: konkrétní blokující úkoly s odkazy na správný editor; velmi drobné výchozí hodnoty mohou být v „Další nastavení“, ale platební trasa a stav veřejnosti jsou vždy viditelné. Po prohlédnutí celého souhrnu uživatel výslovně potvrdí kontrolu. Teprve tím vznikne 100 % a samostatné tlačítko „Vytvořit událost“. | Jakákoli chyba či upozornění vyžadující rozhodnutí; změna po potvrzení ruší kontrolu a 100 % |

Interakční pravidla:

1. Rozbalovací skupiny jsou ve výchozím stavu sbalené, ale vždy mají popis své uložené hodnoty. Kliknutí na chybový odkaz v souhrnu přejde na krok, rozbalí správnou skupinu a zaostří pole. Chyba se nesmí schovat za zavřeným panelem.
2. „Použít nastavení ze zdroje“, „Ponechat výchozí“ a „Upravit“ jsou u každé relevantní skupiny výslovné stavy. Převzetí formuláře má výchozí detailní hodnoty ze zdroje, prázdný formulář výchozí hodnoty aplikace. Náhled ukáže obě hodnoty, pokud se liší; nikdy neprovede tichý reset při přepnutí zdroje.
3. Změna nadřazené volby (vypnout prodej, přepnout na externí formulář, vypnout blueprint) neodstraní rozpracovanou podřízenou konfiguraci z paměti; označí ji jako neaktivní a souhrn ji nebude vydávat za uloženou. Při návratu ji lze obnovit. Změna zdrojové události naopak vyžaduje potvrzení zahození převzatých částí, ručně zadaný název/termín se ponechá.
4. Při „Další“ se validuje právě krok a nutné vazby na dřívější kroky; celá serverová kontrola se provede znovu při finálním potvrzení. Navigace mezi kroky, klávesnice, focus, čtečky a malá obrazovka mají fungovat bez skrytých tlačítek. Dvojklik na potvrzení odešle jeden command ID.
5. Sbalené skupiny nejsou náhradou detailních editorů. Běžné volby lze nastavit hned, editace jednotlivých polí formuláře a kreslení sedadel probíhá ve stávajících editorech nad draft modelem; návrat z editoru vede zpět do průvodce a uložený stav aktualizuje progress. Souhrn neoznačí jejich kontrolu jako hotovou, pokud je vyžadována.
6. Nedovolené volby nejsou skryté jako záhada: karta ukáže důvod, například „Účet EUR není k této jednotce připojen“ nebo „Blueprint vyžaduje formulář“. Popisky uvádějí důsledek volby, nikoli název databázového sloupce. Počet úkolů v souhrnu rozlišuje blokující a doporučené; volby s finančním dopadem jsou před finálním potvrzením vidět bez rozbalení.

### Platební volba v průvodci

Pro každý formulář spočítat měny z vybraných produktů. Výchozí režim je „Automaticky podle účtů jednotky“ a UI ukáže pro každou měnu konkrétní účet, který nyní vybere stejný algoritmus jako `create_ticket_order` (priorita a ID, bez `CASH`). Pokud existuje více vhodných účtů, nabídnout „Použít konkrétní účet“ jen tehdy, když tento jediný účet podporuje všechny měny daného formuláře; uloží se jako `forms.bank_account`. Při více měnách vyžadujících různé účty ponechat automatický režim a zobrazit přiřazení po měnách. Změna účtů jednotky po založení může změnit automatickou trasu, proto souhrn před otevřením znovu načte aktuální výsledek. Účet ze starší události se nepřebírá automaticky. Chybějící účet vede na správu účtů jednotky a blokuje pouze otevření placeného formuláře s převodem. Průvodce účet nevytváří ani nespojuje s jednotkou sám.

### Datový kontrakt menších voleb

| Ovládání | Kanonické uložení | Při kopii a při nové události |
|---|---|---|
| Časová zóna, reply-to, obrazek, popis | `occasions.data`, `occasions.description` přes `OccasionModel` | Zóna zdroje jako návrh, e-mail/obrázek výslovně vybrat; nové výchozí hodnoty z jednotky. |
| Interní/externí režim, externí URL/cena, text tlačítka; interval připomínek | `occasions.features[]` (`FormFeature`) | Kopírovat jen po zapnutí funkce; v externím režimu netvořit povinný interní formulář. |
| Titul, link, typ, uzavření, hlavička a text při zavření | `forms.title/link/type/is_open/header/header_off` | Link vytvořit jedinečný v organizaci; při založení vždy `is_open=false`; HTML odkazy na starou událost označit. |
| Časové okno a odpočet | `forms.data.schedule` přes `FormModel.startTime/endTime/enableCountdown` | Při kopii nabídnout posun dle termínu události; výsledné lokální časy kontrolovat v cílové zóně. |
| Splatnost, připomínky, variabilní symbol, zpráva pro platbu, tón | `forms.deadline_duration_seconds`, `forms.data` klíče `is_reminder_enabled`, `variable_symbol`, `payment_message`, `communication_tone` | Převzít jako návrh; začátek sekvence VS nikdy automaticky nepředpokládat bezpečný, ověřit kolize v cílovém účtu a nabídnout nový začátek. |
| Bankovní účet | `forms.bank_account` nebo výběr podle `eshop.unit_bank_accounts` | Starý účet nedědit; pro explicitní ID ověřit vazbu na cílovou jednotku, všechny měny a typ odlišný od `CASH`. |
| Vzhled formuláře | `forms.data.design` a `is_card_design` přes `FormModel` | Převzít nebo použít výchozí preset; znovu využít stávající design model. |
| Rozměry/plán/skupiny/sedadla/pozadí | `eshop.blueprints`, `eshop.spots`, `forms.blueprint` | Přemapovat všechny vazby; stav sedadel vyčistit; pozadí jako inline SVG nebo vlastní kopie média. |

Při implementaci ověřit skutečné mapování `communication_tone` a `is_card_design` v modelu a SQL aktualizaci, protože názvy `data` jsou křížově používané. Společné mapování dát do jedné serializace návrhu a použít je pro formulářový editor i wizard; neudržovat dvě nezávislé sady klíčů a výchozích hodnot. Serverový příkaz přijímá jen známé klíče z této tabulky, ne libovolné `data` ze zdroje. Neznámé staré klíče vypsat v manifestu jako „vyžaduje ruční kontrolu“ a nechat je mimo novou událost.

### Matice kopírování a závislostí

| Volba v UI | Co se přenáší | Pravidlo |
|---|---|---|
| Základ | Název jako editovatelný návrh, popis, časová zóna, vybraná nastavení `data` | Vždy nové ID/link/datum; nekopírovat `client_sync_v1`, externí odkazy, skryté provozní příznaky ani promování. |
| Funkce | Pouze zvolené a cílovou organizací podporované typované funkce | Pokud jsou zapnuty formulář/blueprint, jejich závislosti se vytvoří právě jednou; jinak UI vysvětlí chybějící sekci. |
| Formuláře | Zvolené formuláře, pole, datové volby, typy produktů a produkty | Nové klíče/linky/ID; znovu validovat bankovní účet; resetovat otevření, odpovědi a obchodní historii. Formulář lze vzít i jako samostatnou předlohu z povolených zdrojů. |
| Blueprint | Konfigurace, objekty, skupiny, pozadí, sedadla a vazba na zvolený formulář | Přemapovat spot/product/blueprint ID; vymazat secret, expiraci, přiřazení objednávky. Bez formuláře lze připravit blueprint jako návrh jen pokud editor umí vazbu doplnit; jinak vyžadovat formulář. |
| Program a místa | Místa, akce, skupiny a role | Posunout časy akcí o rozdíl začátků událostí, zachovat délky; vyžádat potvrzení položek mimo nové rozmezí. Vazby na nevybrané místo/skupinu řešit výběrem závislosti, ne starým ID. |
| Obsah | Zvolené informační bloky, jejich skryté podklady, šablony e-mailů | Nová ID a vlastnictví cíle; odkazy na starou událost v HTML/URL vypsat k ruční kontrole nebo přemapovat pouze známé vlastní odkazy. |
| Média | Obrázek události, pozadí tiketu a souborové pozadí blueprintu | Před finalizací soukromý staging pod ID draftu; po vytvoření ID převod do cílového vlastníka, stav a retry; inline SVG lze přenést v databázové části po validaci. |

Seznam a sloupce výše jsou smlouva první verze. Inventář/služby, mapa, notifikace, bankovní účty a další zvláštní moduly musí mít v manifestu explicitní stav **kopírovat / nastavit znovu / nepodporováno**, nikoli být tiše označeny za přenesené. `services` v `occasions` kopírovat jen po prověření jejich konkrétních odkazů. Publikační souhrn má ukázat každou nepřenesenou aktivní funkci jako úkol. Žádné automatické přenášení provozních tabulek nad rámec této matice.

## Rozhodnutí, předpoklady, rizika

- **R1:** První průchod vede přes kroky Zdroj → Základ → Funkce a obsah → Formuláře/prodej → Blueprint → Souhrn. Krátká výchozí cesta dovolí přeskočit nepoužívané kroky; dlouhá cesta ponechá všechny volby viditelné.
- **R2:** Výchozí kopie programu posune časy; položky po posunu mimo rozmezí se označí před uložením. Žádný tichý posun historických objednávek, protože se vůbec nekopírují.
- **R3:** Nový SQL příkaz vlastní složenou operaci. Stávající `duplicate_occasion` a `duplicate_occasion_client_sync_v1` se během migrace volajících buď stanou úzkým adaptérem na tuto smlouvu se zachovaným oprávněním, nebo se odstraní po ověření všech volání a podporovaných klientů. Neponechat dva rozdílné grafy kopie.
- **P1 (předpoklad):** „Nahodit formulář“ znamená založit nebo převzít formulář v aplikaci. Pokud je míněn import souboru, rozšiřuje se datový formát a validace; tento plán ho bez upřesnění nezařazuje.
- **P2:** `background_svg` může být inline SVG nebo URL, jak naznačuje editor. Při implementaci rozlišit varianty a ověřit vlastnictví URL; opakované použití zdrojové URL není hluboká kopie.
- **P3:** Některé položky obsahu/programu mohou nést ID ve vnořeném JSON. Před implementací každé sekce udělat omezenou inventuru polí a zdokumentovat mapování v testu; pokud není vazbu možné bezpečně mapovat, vypnout volbu a v souhrnu ji pojmenovat.
- **P4:** `is_hidden=true` nemusí ve všech veřejných RPC samo zaručit nedostupnost formuláře či údajů při znalosti URL. V první serverové vlně ověřit veřejné čtečky a odesílací cesty; pokud obcházejí skrytí, vynutit uzavření návrhu i na jejich autoritativním vstupu před vydáním wizardu.
- **P5:** Předloha se může během vyplňování změnit. Manifest ponese verzi/otisk relevantních zdrojových sekcí; server ho při vytvoření porovná. Při rozdílu vrátí konkrétní změněné sekce a nabídne obnovu návrhu bez ztráty ručně zadaného názvu a termínu. Nikdy nekopírovat neočekávaný novější obsah jen proto, že uživatel souhlasil se starým náhledem.
- **Blokery:** žádný pro návrh. Oprávnění k produkční migraci/nasazení je samostatný krok až po implementaci a ověření.

## Odstranění starých cest

| Artefakt | Cílový stav | Důkaz dokončení |
|---|---|---|
| `OccasionCreationHelper.createNewOccasion` | nahradit jedním průvodcem v obou voláních; helper odstranit | žádné volání ani import helperu |
| Statický HTML prototyp a PNG náhled | nahradit Flutter simulací v první fázi, oba soubory odstranit | v `lib/components/occasion/prototype/` zůstává pouze Flutter demo během rozhodování |
| `_handleCreateCopy` v `occasions_screen.dart` | otevře tentýž průvodce s předvoleným zdrojem | UI test obou vstupů |
| `DbOccasions.duplicateOccasion` a starý Dart postup médií | přesunout na návrat nové operace a řízené dokončení médií | žádná samostatná kopie po starém RPC |
| `duplicate_occasion` SQL a klientský obal | po přesunu volajících odstranit nebo explicitně držet do vydání starých klientů jako úzký adaptér s datem odstranění | vyhledání volání, RPC test; žádná druhá implementace grafu |
| Případný výchozí formulář/blueprint z `update_occasion_internal_v1` | zachovat pro existující běžné úpravy, ale nová operace se s tím nekříží | přesně jeden vybraný formulář/blueprint v testu |

## Implementační vlny

### 0. Flutter simulace a rozhodnutí o podobě průvodce — před implementací

**Změny:** Spustit `lib/components/occasion/prototype/occasion_setup_demo.dart` jako samostatný Flutter web entrypoint se skutečným vzhledem `ThemeConfig` a reálnými Flutter/Festapp komponentami. V simulaci projít založení draftu, odchod do seznamu, obnovu stránky, otevření karty KONCEPT, narůstání progress line, rozbalovací menší nastavení, bankovní účet, založení nebo úplnou kopii formuláře přes existující `CreateOrCopyFormDialog`, úpravu polí a produktů ve skutečném `FormEditorContent` a vytvoření/převzetí plánku ve skutečném `BlueprintTab`; oba editory mají lokální model. Simulace používá pouze lokální mock data, žádná RPC; 100 % se ukáže teprve po finální kontrole a draft zůstane odlišený. Porovnat podobu po konkrétní zpětné vazbě uživatele; starý statický HTML prototyp odstranit.

**Validace:** Cílený `fvm dart analyze` změněných demo a blueprint souborů, jedno spuštění Flutter web v izolovaném profilu, ručně odejít a obnovit draft, dokončit progress na 100 %, zkusit editor a mobilní šířku. Bez testů databáze. **Výstup:** uživatelem potvrzený nebo opravený UX směr zapsaný zde; až potom pokračovat vlnou 1. Neznamená to potvrzení produkčního nasazení.

### 1. Perzistentní draft a administrativní seznam

**Změny:** Přidat `public.occasion_setup_drafts` jako kanonickou tabulku a timestampovanou migraci. Omezit oprávnění k draftům na editory cílové jednotky; RPC pro založení, načtení/seznam, verzovaný autosave a explicitní smazání. Nevracet draft z veřejných occasion/form RPC. Přidat zvláštní „Rozpracované koncepty“ nad probíhající/budoucí/minulé v `OccasionsScreen`, samostatnou kartu DRAFT s procenty a akcí Pokračovat. Search zahrnuje i drafty, jejich stav se nikdy neodvozuje jen z `is_hidden`. Zajistit pravidla souběžné úpravy, uložení posledního kroku a zotavení po přerušení.

**Validace:** SQL test viditelnosti a práv v cílové jednotce, scope organizací, revizního konfliktu, retry create/save/delete a nepřítomnosti draftu ve veřejném endpointu; Flutter test návratu do rozepsaného draftu a odlišení v seznamu. **Výstup:** po odchodu z průvodce zůstane draft uložený a v seznamu jasně rozpoznatelný, žádná occasion ještě neexistuje.

### 2. Manifest a čistý návrh

**Změny:** Přidat autorizačně filtrovaný RPC manifest zdrojové události (počty, typy, názvy, závislosti, verze/otisk, dostupnost pro cílovou jednotku; bez citlivých odpovědí/objednávek). Přidat typovaný `OccasionSetupDraft`, model voleb a validátor ve `lib/components/occasion/setup/`. Návrh musí držet u každé skupiny původ hodnoty (`výchozí`, `převzato`, `upraveno`) a aktivitu závislou na nadřazené volbě. Načíst zdroj podle ID, nepoužívat zkrácený seznam jako detail. Při výběru jen formuláře použít stávající přístupový princip `get_all_viewable_forms_for_copying`, ale serverová kontrola zůstává autoritativní. V této vlně zmapovat veřejné čtečky/odesílání návrhu a potvrdit účinek `is_hidden` a `is_open`.

**Validace:** SQL test zdroj/cíl v různých jednotkách a organizacích, oprávněný editor/manažer/neoprávněný; jednotkový test závislostí a zrušení voleb po změně zdroje. **Výstup:** UI umí bez zápisu přesně zobrazit přenos a omezení.

### 3. Atomický serverový příkaz

**Změny:** Kanonický SQL soubor a migrace pro `create_occasion_from_setup_v1(p_command_id, p_draft_id, p_expected_revision)`. Zachovat pravidla `SECURITY DEFINER`, `search_path`, explicitní role a tenant scope. Načíst právě uloženou revizi draftu, ověřit 100% serverové milníky a práva, validovat link vůči organizaci, termíny a velikosti vstupu. Idempotence přes existující klientský command ID nebo vlastní transakční záznam; opakování se stejným ID vrací stejný výsledek. V jedné transakci vytvořit occasion graf, označit draft finalized a uložit occasion ID. Zavést interní mapování pro vybrané sekce a invariant „žádné staré ID v cílových vazbách“. Zachovat publikaci klientského sync stavu a `client_sync_v1=false` stejně jako současné wrappery. Účty, měna, limity a maximum produktů musí projít úplným kontraktem podle současného schématu. Validovat explicitní účet stejnými podmínkami jako `create_ticket_order`, výchozí trasu po měnách vracet do souhrnu. Převzatá detailní nastavení zapisovat pouze přes whitelist výše, s kontrolou datových typů.

**Validace:** Cílené SQL testy: prázdná událost; kompletní výběr; každá sekce a kombinace závislostí; vynechané sekce; chybná práva; kolize linku; změněný manifest; opakovaný command ID; chybné FK; produktové limity; účet pro jednu/více měn včetně `CASH`; reset sedadla/objednávky a zavření formulářů. **Výstup:** jeden potvrzený požadavek založí jeden soukromý konzistentní graf, chyba nezaloží nic.

### 4. Průvodce a editory

**Změny:** Nová stránka/dialog s responzivním krokováním podle tabulky obrazovek, zřetelným zdrojem, počty vybraných položek, editací title/link/termínu/časové zóny, přehledem funkcí podle `FeatureService`, formulářem a plánkem. Základní pole zůstávají viditelná; menší volby patří do pojmenovaných sbalených sekcí se souhrnem hodnot, počtem změn a chybovým stavem. Každá změna jde přes verzovaný autosave draftu, stav ukládání je viditelný. Použít existující validátory a modely. Formulář se při převzetí materializuje do draftu včetně polí a produktů; jeho stav se počítá z dat a validace editoru, nikdy z ručních checkboxů připravenosti. Refaktorovat formulářový a blueprintový editor na injektovaný datový zdroj/save handler tak, aby stejné ovládání fungovalo nad draftem i nad uloženou událostí. Demo adaptéry `FormEditorContent.prototype` a `BlueprintTab.prototype` nejsou produkční úložiště. Obě vstupní místa i akci „Vytvořit kopii“ přesměrovat sem.

**Validace:** Widget test krátké cesty, přepnutí zdroje, chybějícího oprávnění, zachování rozepsaných detailů, sbaleného souhrnu a automatického otevření sekce s chybou; cílený `fvm dart analyze` na změněné soubory. **Výstup:** neexistuje UI vstup, který novou událost vytvoří mimo průvodce, a každá uložitelná detailní volba je dosažitelná i ověřitelná ze souhrnu.

### 5. Média, připravenost, otevření

**Změny:** Podklady nahrané během draftu uložit do soukromého stagingu a při finalizaci zkopírovat/převést k novému ID vlastníka přes existující image API. Úspěch a chybu ukládat po jednotlivých souborech; retry nikdy nespouští druhou finalizaci. Dodat serverově kontrolovaný readiness výsledek: link, termíny, aktivní funkce, formuláře, cílové produkty/účty a sedadla pro prodej, média vyžadovaná konkrétní konfigurací. Otevření používat stávající nastavení, ale doplnit kontrolu readiness před změnou `occasions.is_open/is_hidden` a `forms.is_open`: ověřit `update_occasion_internal_v1`/klientský save a `update_form`/`update_form_client_sync_v1`, aby starý editor nemohl otevřít nedokončenou událost. Zkontrolovat také `get_form_by_link` a objednávkovou cestu `create_ticket_order`/`send-ticket-order`, protože znalost linku nesmí obejít soukromý stav.

**Validace:** Jednotkový test selhání/retry média bez druhého vytvoření; integrační SQL test odmítnutého otevření neúplné obchodní konfigurace; manuální průchod jedním čistým a jedním kopírovaným draftem v izolovaném dev prostředí včetně návratu z editorů. **Výstup:** po chybě média je dohledatelná soukromá událost s opakováním nedokončené akce; formulář/blueprint lze připravit ještě v draftu; zveřejnění je výslovná akce.

### 6. Převod staré kopie a dokumentace

**Změny:** Převedení všech klientských volání, testů a textů. Udržet nutnou kompatibilitu pro již vydané klienty jen jako adapter na nový copy graph se starou manažerskou kontrolou; do evidence zapsat podporovanou verzi a termín odstranění. Upravit `lib/components/occasion/README.md`, `lib/components/forms/README.md`, `lib/components/blueprint/README.md` a dokumentaci RPC. Neponechat starý `duplicate_occasion` jako alternativní implementaci.

**Validace:** cílené SQL/Dart testy a `rg` pro staré vstupy/RPC; kontrola, že adapter pouze deleguje. **Výstup:** všechna interaktivní založení používají jediný příkaz a starý graf kopie není dosažitelný.

## Nasazení a návrat

Kód a migraci připravit na `main`; žádná automatická propagace do `prod/*`. Produkční SQL nasazení je oddělená autorizovaná operace podle kanonického self-hosted workflow. Pořadí: rozšíření serverového kontraktu → cílené SQL testy → klient s novou cestou → pozorování vytvoření čisté/kopírované události → odstranění staré implementace po kompatibilitním okně. Při rollbacku klienta musí adapter starých klientů dál vytvářet soukromou konzistentní kopii přes stejný graph; rollback nesmí vrátit nechráněné kopírování s původními FK.

## Ověřovací příkazy

- Nové SQL testy umístit do `database/tests/occasion_setup/` a spouštět je jednotlivě přes `node web_client/scripts/run_db_tests.js` s cestou testu (zahrnout rollback a neoprávněného uživatele).
- Dart testy umístit do `test/components/occasion/` a spouštět přes `fvm flutter test test/components/occasion/`; diagnostika změněných souborů: `fvm dart analyze lib/components/occasion/setup lib/components/occasion/db_occasions.dart lib/components/occasion/occasion_commands.dart`.
- Před předáním vyhledat `rg -n 'OccasionCreationHelper|duplicateOccasion|duplicate_occasion' lib database/functions supabase/migrations` a vysvětlit každý zbylý výskyt. Historické migrace se nemažou; cílem je žádný živý druhý copy graph.
- Ručně v izolovaném dev prostředí ověřit krátkou čistou cestu, výběrovou kopii s formulářem/blueprintem, chybu uploadu a opakování bez duplikace. Při tomto ověření nepoužít živá produkční data.

## Definice hotovo

- [ ] Z obou vstupů lze založit prázdnou událost i vybranou kopii, s krokem formuláře a blueprintu.
- [ ] Přenos je výslovný; náhled přesně odpovídá serverem vytvořenému výsledku, výjimky jsou viditelné.
- [ ] Žádná provozní data ani vazby na zdrojovou událost se nepřenášejí; mapování a oprávnění potvrzují SQL testy.
- [ ] Opakovaný požadavek a chyba média nevytvoří další událost; soukromý návrh lze dokončit později.
- [ ] Menší nastavení jsou sbalená s čitelným souhrnem hodnot; chyba skupinu otevře a souhrn ukazuje finanční i publikační důsledky.
- [ ] Bankovní účet odpovídá měně, cílové jednotce a skutečnému výběru objednávkového SQL; kopie nepřebírá zdrojový účet tiše.
- [ ] Všechny vytvořené formuláře a události jsou zpočátku zavřené; otevření prochází readiness kontrolou.
- [ ] Starý UI vstup a samostatný graf kopie jsou převedeny/odstraněny; nutný adapter je omezený a zdokumentovaný.
- [ ] Cílené SQL a Dart testy, analýza změněných souborů a jedna izolovaná ruční cesta projdou před publikací.
