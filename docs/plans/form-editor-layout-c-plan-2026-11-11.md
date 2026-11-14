# Editor formuláře: srozumitelné akce a osnova na široké obrazovce

Datum: 2026-11-11
Stav: připraveno k implementaci; tato úloha vytváří pouze plán
Ověřování: low-risk; jedna cílená závěrečná dávka po ucelené změně

## Výsledek a závazná podoba

Základem je varianta C z `docs/previews/form-editor-variants/variant-c.html`, opravená podle posledního pokynu uživatele. Přednost mají následující pravidla před zjednodušením v HTML ukázce:

1. **Celý současný blok Dostupnost / Kapacita a náhradníci / Rozvrh a limity / Obsah zavřeného formuláře zůstane nahoře v původní podobě.** Zachovat jeho komponenty, vnitřní rozbalení, podmínky viditelnosti a chování. Nenahrazovat jej stavovým řádkem, neskrývat celý blok pod tlačítko a nepřesouvat do Nastavení.
2. Pod ním zůstane současný plnohodnotný úvodní HTML editor. Dostane srozumitelný popisek a akci pro editaci, ale obsah a schopnosti editoru zůstanou stejné.
3. Pod úvodem zůstane souvislý seznam všech hlavních polí včetně vstupenek a produktů. Nejde o režim, který zobrazuje vždy jen jedno pole.
4. Na široké obrazovce bude vlevo osnova: dostupnost, úvod a aktuální hlavní pole v jejich pořadí. Na telefonu a užším displeji se osnova vůbec nevytváří a nezabírá místo.
5. Akce Náhled formuláře a Veřejná stránka dostanou trvalé slovní popisky nad obsahem. Přidat pole bude u seznamu polí, nikoli jako samostatné plovoucí plus v pravém rohu.
6. Zůstanou čtyři současné hlavní záložky: Formulář, Nastavení, Design, Odpovědi. Uložit / Zahodit změny zůstanou ve stávající spodní liště.

Změna řeší pracovní rozložení a význam akcí. Neobsahuje redesign vnitřku dostupnosti, přepis produktového editoru ani nové doménové funkce.

## Rozsah a autorita

- Implementace patří do sdíleného kódu `main`; žádná automatická propagace do `prod/*`.
- Nynější pracovní kopie je na větvi `docs/festapp-tickets-readme-20261107`, HEAD při průzkumu `742d614b7`, a obsahuje rozsáhlé rozpracované změny. Před implementací zjistit aktuální vlastnictví změn a zvolit pracovní místo podle pravidel repozitáře. Nepřepínat násilně větev, neuklízet cizí změny a nekopírovat celý znečištěný diff na main.
- Tento plán neautorizuje implementaci, commit, push, migraci ani nasazení. Případná pozdější publikace musí splnit `CONTRIBUTING.md` a kanonické CI mirror lanes.
- Žádné SQL, RPC, veřejné webové formuláře, schéma, datové kontrakty ani platby se touto změnou nemění.
- Použít `material_ui`, současné téma a lokalizované `FormStrings` / `CommonStrings`. Neportovat HTML/CSS prototyp do Flutteru doslovně.

## Ověřený současný stav

| Fakt a zdroj | Důsledek pro implementaci |
|---|---|
| `views/form_tab.dart`, `FormTab`: čtyři routované záložky; `FormEditorPage` předává `FormRouteScope.identity` do editoru. | Neměnit routy, deep linky, identitu formuláře ani počet záložek. |
| `views/form_editor_content.dart`, `_buildHtmlParent`: běžný editor, samostatný prototype a větev `embedded`. | Rozložení musí respektovat všechny tři režimy; vloženému editoru nepřidávat druhý toolbar a lištu ukládání. |
| `_buildFormOpenToggleAndOffTextEditor` skládá dostupnost, kapacitu, rozvrh a obsah zavřeného formuláře. | Ponechat tuto větev funkčně i vizuálně beze změny. |
| `_htmlSave`, `_snapshot`, `_draftRevision`, `saveChanges`, `cancelEdit` vlastní koncept a ukládání. | Osnova nesmí tyto mechanismy obcházet ani spouštět uložení. |
| `_openPublicForm` při změnách nabízí pokračovat, zobrazit uložené nebo uložit a zobrazit; `preview=true` mění veřejné omezení dostupnosti. | Obě nové pojmenované akce zavolají stávající metodu s příslušným parametrem. Žádný příslib živého náhledu konceptu. |
| `widgets_editor/form_fields_generator.dart` vlastní zvolený blok, seznam hlavních polí a přesouvání. Hlavní pole filtruje přes `isTicketField != true`. | Osnova vychází ze stejné projekce a nesmí obsahovat podřízená pole vstupenek jako další hlavní položky. |
| `_addFieldOfType` přidává na konec a následně posouvá; `_availableFieldTypes` hlídá opakovatelné a jedinečné typy. | Zachovat oba mechanismy. Nedoplňovat nová pravidla dostupnosti do toolbaru nebo osnovy. |
| `FormFieldDraft` je mutovatelný koncept, existující blok má `ValueKey(id)` nebo `ObjectKey(field)`. | Identita položky osnovy nesmí být index ani název; nová pole nemají databázové ID. |
| `test/components/forms/forms_editor_widget_cases.dart` registruje akční a mobilní případy, následně `test/sessions/czech_catalog_2_cases.dart` a `shared_czech_test.dart`. | Nové případy vložit do skutečně registrovaných suites; samotný nový `*_cases.dart` nestačí. |

## Matice zachování funkcí

| Oblast | Co zůstává | Vlastník |
|---|---|---|
| Dostupnost | otevření/zavření, aktuální stav, rozvrh, validace časů, kapacita, obsazená/nabídnutá místa, náhradníci a lhůty, zvláštní pravidla plánku | současný blok v `form_editor_content.dart`, `form_capacity_settings.dart` |
| Mimo prodej | obsah před otevřením a po uzavření, HTML/bloky, sběr e-mailů a upozornění, záhlaví, odpočet, mobilní varianta, podmíněná obnova archivu | `form_unavailable_content_editor.dart`, `presale_content_editor.dart` |
| Úvod | současný obsah, formátování, média, aktivní neuložený HTML koncept | `EditableHtmlField` a `HtmlSaveCoordinator` |
| Pole | všechny dostupné typy, jejich omezení, názvy, popisy, povinnost, viditelnost, volby, validace, pořadí přetažením a chráněné odstranění | `FormFieldsGenerator`, současné specializované editory |
| Vstupenky/produkty | maximum na objednávku, ceny a detaily, skupiny, vícenásobný výběr, přidání produktu a typu, připojení existujícího typu, výběr míst, poznámka, podmíněné informace o záloze | současné ticket/product editory |
| Obecné nastavení | název, veřejný odkaz a historie/sdílení, upomínky a interval, splatnost, platební metody/účet/poskytovatelé, číslování/VS, zpráva pro příjemce, měření, tón komunikace, odstranění formuláře | `FormSettingsContent`, beze změny |
| Design a odpovědi | všechny stávající funkce, oprávnění a samostatné koncepty | `FormDesignContent`, `FormResponsesContent`, beze změny |
| Navigace/uložení | výběr formuláře, vytvoření/kopírování, oba náhledy, uložit/zahodit, ochrana neuloženého konceptu při odchodu | současné metody a `RetainedDraftGuard` |
| Oprávnění/režimy | editace oproti čtení, demo, prototype a embedded, podmíněné features | současné capability a feature kontroly |

Matice je implementační kontrolní seznam, nikoli požadavek znovu implementovat všechny uvedené funkce. Nezměněné komponenty se opětovně použijí.

## Cílové rozložení

### Široké okno

- Nad pracovním obsahem kompaktní řádek s Náhled formuláře a Veřejná stránka. Nemíchat sem akci přidání produktu.
- Dvousloupcová pracovní plocha: osnova přibližně 216 px, mezera přibližně 24 px, stávající omezená šířka formuláře podle `StylesConfig.formMaxWidth`.
- Dostupnost, úvod a pole jsou v pravém sloupci v dosavadním pořadí. Dostupnost má stále celý původní blok.
- Nad seznamem polí textové Přidat pole, druhý vstup na konci seznamu pro dlouhé formuláře. Oba používají tutéž akci a výběr typů.
- Osnova zůstává dostupná při posouvání; pokud je dlouhá, může mít samostatný scroll. Hlavní obsah má jediný vlastněný vertikální scroll; nevytvářet soupeřící scroll controller pro samotná pole.
- Osnova není druhý editor, nemá vlastní mazání ani přetahování a neukládá změny. Aktivní položka odpovídá vybranému bloku, nikoli spekulativnímu scroll-spy mechanismu.

### Telefon a užší okno

- Jeden sloupec s původní dostupností, úvodem a poli. Žádná osnova, její skrytá focusovatelná kopie ani prázdný sloupec.
- Akce náhledů mají text a mohou přejít na druhý řádek; nesmí se vrátit na nerozlišitelnou dvojici ikon.
- Přidat pole zůstává v toku u polí, spodní `EditorActionBar` zůstane dostupný a obsah má potřebný spodní inset.
- První rozhodovací hranice pro osnovu je 1100 logických px lokálně dostupné šířky. Použít `LayoutBuilder`, nikoli šířku celého monitoru. Pokud se nevejde 216 px + mezera + současná šířka formuláře + padding, hranici zvýšit; nezúžit stávající formulář jen kvůli osnově. Toto je ohraničená implementační kontrola, nikoli otevřený redesign.
- Ověřit také zvětšené písmo; pro konkrétní úzké rozložení dát přednost skrytí osnovy před ořezem textů.

### Správa celého formuláře

Vytvořit / Zkopírovat formulář zůstane u výběru aktuálního formuláře jako pojmenovaná položka jeho nabídky v `form_tab.dart`. Použít stejný existující handler, `formsCreate` kontrolu, demo omezení a `RetainedDraftGuard.leaveOwner`. Původní výrazné plus nahoře se po přesměrování odstraní. Výběr jiného formuláře a indikace právě vybraného formuláře zůstávají funkční. Žádné druhé tlačítko s nejasnou působností.

## Architektura a kvalita kódu

### Vlastnictví

- `FormEditorContent` nadále vlastní bundle, koncept, HTML koordinátor, načítání, chyby, uložení/zahození a vrchní scroll.
- `FormFieldsGenerator` nadále vlastní výběr, projekci hlavních polí, pořadí a jejich skutečné editory. Nepřesouvat obchodní pravidla do nové navigace.
- Malý prezentační `FormEditorToolbar` přijímá pouze dostupné callbacky/stavy a zobrazuje pojmenované akce. Nečte DB, nedělá navigaci sám a nekopíruje kontroly oprávnění.
- `FormEditorOutline` dostane aktuální navigační položky a callback pro výběr. Nepracuje s JSON, RPC, ukládáním ani produkty.
- Pro navigaci do existujícího generátoru zavést jeden lokální UI controller, například `FormFieldsNavigationController`: read-only položky osnovy a `revealField(FormFieldDraft field)`. Nepřidávat globální službu ani event bus. Controller nevlastní kopii dat formuláře; generátor publikuje svoji aktuální projekci a vybranou identitu.
- Generátor vlastní interní registry kotev a obsluhu `revealField`: vybere správný blok a po layoutu jej zviditelní přes existující scroll. Dostupnost a úvod mají kotvy vlastněné rodičem. Nesmí se přistupovat přes `GlobalKey` k cizímu privátnímu `State` nebo volat jeho privátní metody.
- Případné nové soubory v `views/` a `widgets_editor/` vzniknou jen pro tyto skutečné odpovědnosti. Nevytvářet obecný editor framework, repository, druhý draft model ani další stavovou knihovnu.

### Identity, životní cyklus a výkon

- Pro uložené pole použít ID v rámci konkrétního bundle; pro nové pole stabilní identitu objektu konceptu. Index slouží jen k zobrazení pořadí. Přejmenování ani přesun nesmí přepnout na jiné pole.
- Projekce osnovy zahrnuje jen hlavní pole v aktuálním pořadí; fallback názvu používá `FormHelper.fieldTypeToLocale`. Stejnou projekci vlastní generátor, nezavádět nezávislé filtrování/pravidla do sidebaru.
- Obnovit osnovu po vložení, přejmenování, přesunu, změně typu a odstranění. Každá událost používá existující cestu `onChanged`; žádné ukládání při pouhém výběru nebo scrollu.
- Controller má explicitní připojení/odpojení a dispose. Po výměně bundle nebo zahození konceptu zahodit staré kotvy. Post-frame callback před použitím ověří mounted, stejnou identitu bundle a existenci cílového pole.
- Nevolat `notifyListeners` nebo `setState` během build. První publikaci projekce provést bezpečně po frame; další změny z existujících handlerů. Omezit rebuild na příslušnou navigaci/toolbar; nepřegenerovat celý rich HTML editor při každém znaku názvu pole.
- Překročení breakpointu mění pouze kompozici. Zachovat identitu a stav generátoru i HTML editorů; neduplikovat editor do dvou větví. Změna velikosti nesmí zahodit rozepsaný text ani vybrané pole.
- Controller a případné callbacky jsou volitelné pro embedded/prototype. Jejich současný kontrakt se nesmí změnit jen kvůli osnově běžného editoru.

### Přístupnost a lokalizace

Textové názvy akcí, tooltipy pouze jako doplněk, přirozené pořadí Tab a viditelný fokus. Osnova funguje z klávesnice; po aktivaci cílového pole je jasná jeho poloha a výběr bez vstupu do náhodného textového pole. Ovládací prvky mají běžné přístupné Material rozměry. České UI vyká, nové texty jdou přes strings a všech šest existujících překladů. Světlý režim pro kontrolní snímky; podporu dalších režimů aplikace neodstraňovat.

## Delegace a tokenová efektivita

Výslovný pokyn uživatele: **samotné UI implementuje subagent `gpt-6-astra` s reasoningem `medium`**. V Codex použít `fork_turns="none"` a stručné samostatné zadání s odkazem na tento plán, relevantní UI/UX skill, přesným seznamem vlastněných souborů a zachovávanými komponentami. Neodesílat celou historii konverzace. Astra přečte příslušné pokyny repozitáře a UI/UX skill; nevytváří znovu tři návrhy ani další návrhový průzkum.

- Hlavní agent připraví pracovní místo a ověří aktuální stav pouze dotčených souborů. Astře předá souvislý UI balík: toolbar, široké rozložení, osnovu a nutné propojení s generátorem. Předem určí výhradní vlastnictví souborů; hlavní agent je souběžně neupravuje.
- Astra pracuje na schváleném návrhu a zachovává původní dostupnostní blok i stávající logiku. Neprovádí vlastní další delegaci, širší refaktor, build, release ani opakované testovací běhy. Vrátí stručný seznam změněných souborů, změn rozhraní a konkrétních otevřených problémů.
- Hlavní agent převezme integraci, potřebné behaviorální testy a jedinou závěrečnou kontrolní dávku. Předchozí průzkum a tento plán se používají znovu; čtou se jen dotčené části a nově vzniklé rozdíly.
- Browser ověření zůstává delegované Terra podle osobních pravidel. Nejde o druhý návrhový nebo kódový audit.
- Bez dalšího zadání nespouštět jiné nezávislé subagenty nebo paralelní audity. Průběžné zprávy i předání držet stručné. Tokenová úspornost nesnižuje matici zachovávaných funkcí ani povinné kontroly.

## Implementační kroky

### 1. Pojmenované akce a zachování současného těla

Změnit běžnou větev `_buildHtmlParent` v `form_editor_content.dart`: přidat toolbar, pojmenování úvodu, Přidat pole u seznamu a dole. Zachovat volání původního dostupnostního bloku, HTML editoru, generátoru a `EditorActionBar`. Přesunout vytvoření/kopírování do nabídky výběru formuláře přes existující handler v `form_tab.dart`.

Odstranit stack tří FAB a pouze jeho související layoutové offsety. Samostatný i embedded prototype ověřit vůči jejich původnímu režimu. Výstupem je čitelný editor bez změny datových akcí.

### 2. Jedna navigační projekce a responzivní osnova

Přidat lokální UI controller a čistý widget osnovy. Generátor publikuje své existující hlavní položky a umí na vyžádání vybrat/zviditelnit pole. Rodič přidá dostupnost a úvod. Zavést široké rozložení bez duplikace stavových editorů a bez změny zachovaného dostupnostního bloku.

Výstup: osnova odpovídá pořadí/názvům i po editaci, naviguje správně i k novému poli bez ID, při zúžení zmizí bez ztráty konceptu.

### 3. Odstranění nahrazené UI cesty a dokončení

Doplnit pouze potřebné překlady a rozšířit existující behaviorální testy. Odstranit osiřelou `_NoScalingAnimation`, pokud po odstranění FAB nemá dalšího volajícího, nepoužité importy a původní create/copy tlačítko. Neodstraňovat původní doménové metody náhledů, přidání ani výběru formuláře. Neponechávat variantu C za novým feature flagem nebo paralelní V2 implementaci.

Všechny tři kroky tvoří jednu ucelenou změnu; v low-risk režimu nespouštět kontrolní sadu po každém kroku. Strukturální kontrolu při editaci držet lokální; finální dávka níže.

## Ověření implementace

Plánovací fáze testy nespouští. Při implementaci nejprve ověřit, že na workstation neběží jiná Flutter úloha; jednu další nespouštět souběžně a cizí úlohu neukončovat.

Jedna závěrečná dávka, po dokončení změn:

1. `fvm dart analyze <explicitní seznam změněných Dart souborů>` a kontrola překladových JSON. Použít stávající validační nástroje; žádné automatické přeformátování cizích změn.
2. `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart --plain-name forms_editor_widget` pro skutečně registrované akční, produktové a mobilní případy. Do existujícího `form_editor_actions_cases.dart` / `form_field_mobile_layout_cases.dart` přidat potřebné behaviorální scénáře; nepřidávat samostatný neimportovaný cases soubor. Pokud je nutná izolovaná navigační suite, explicitně ji registrovat a rozšířit stejnou dávku. Z výstupu doložit počet provedených testů; nulový výběr není úspěch.
3. Jeden prohlížečový průchod skutečné Flutter UI v izolovaném lokálním prostředí podle `festapp-local-e2e`, pokud je dostupné. Ovládání delegovat Terra subagentovi; případný Flutter server se započítává do limitu jediné Flutter úlohy a běží až po testech. Použít češtinu, přirozená testovací data, světlý režim a ztlumení. Pokud prostředí není dostupné, výslovně uvést chybějící vizuální důkaz; statický HTML náhled ho nenahrazuje.

Cílené testy mají prokázat:

- Dostupnostní blok stále předchází úvodu a polím, zachovává podmíněné části; existující kapacitní případy dál procházejí.
- Široké okno má osnovu; 390 px a mezní šířka ji nemají, obsah nepřetéká. Stejný widget test změní šířku s rozepsaným HTML/názvem pole a ověří zachování konceptu.
- Vložení pole bez ID, přejmenování, přesun a odstranění udržují správnou identitu, pořadí a cíl osnovy; podřízená ticket pole se neduplikují. Odebraný cíl ani starý bundle nespustí odložený scroll do neplatného kontextu.
- Výběr v osnově nemění dirty stav; skutečná editace jej mění. Uložit a Zahodit zůstávají napojené na existující koordinátor.
- Oba náhledy používají správnou stávající akci a respektují dialog při změnách. Read-only, demo, prototype a embedded nedostanou nepovolené akce nebo duplicitní shell.
- Vytvoření/kopírování i změna formuláře zachovají draft guard. Žádný přesunutý vstup neobchází capability podmínky.

Nedělat snapshot test přesných českých vět, rozsáhlé nové golden sady ani nové testy platebního backendu pro nezměněnou logiku. Při selhání jedna cílená diagnóza a oprava; další nevyřešené selhání reportovat podle low-risk pravidel.

Před případnou později autorizovanou publikací jsou navíc povinné dotčené kanonické CI mirror lanes z `automation/test_ci.sh`, podle aktuálního `CONTRIBUTING.md` a výběru lane nad skutečným výsledným diffem. Cílené widget testy nejsou náhradou této publikační brány. Tento plán sám publikaci ani release nespouští.

## Definice hotovo

- Uživatel pozná schválenou C: původní celý dostupnostní blok nahoře, úvod, souvislá pole, široká osnova a pojmenované akce.
- Všechny řádky matice zachování mají konkrétní zachovanou původní cestu; žádná funkce nenahrazena vysvětlujícím placeholderem prototypu.
- Osnova je odvozená navigace se stabilní identitou a bezpečným lifecycle, nikoli další vlastník dat.
- Neexistuje starý stack FAB, druhé create/copy plus, mrtvá animační třída ani paralelní přepínatelný editor.
- Běžný editor, prototype, embedded, read-only a přepnutí šířky zachovávají svoje kontrakty a rozepsané změny.
- Ověření odpovídá rozsahu a má skutečný výsledek. Chybějící browser důkaz či přetrvávající chyba jsou výslovně uvedené.
- Žádné nesouvisející změny, přepis plateb, přesun dostupnosti, migrace nebo neautorizovaná produkční operace.

## Zbývající rizika a ohraničené předpoklady

- Přesná dostupná šířka závisí na okolní navigaci aplikace. Breakpoint 1100 px je výchozí návrh; rozhoduje lokální prostor a zachování současné šířky formuláře.
- Současný generátor drží výběr indexem. Přes UI navigaci je nutné najít index ze stabilní identity; pokud test odhalí chybu existujícího udržení indexu při přesunu, opravit lokálně výběr podle identity, ne redesignovat datový model.
- Relayout může remountovat stavové widgety nebo ztratit HTML koncept. Návrh předepisuje jediný strom editorů a specifický test změny šířky právě proti tomuto riziku.
- HTML náhled některé akce jen simuluje. Autoritou skutečného chování jsou původní Flutter komponenty, matice výše a poslední pokyny uživatele, nikoli HTML JavaScript.
