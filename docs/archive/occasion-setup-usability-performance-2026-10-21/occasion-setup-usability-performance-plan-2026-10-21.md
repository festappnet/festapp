> Archiv realizovaného zadání. Stav nasazení a důkazy shrnuje [výsledek](../../plans/occasion-setup-usability-performance-RESULT-2026-10-21.md).

# Rychlejší a jednodušší vytváření událostí

Datum: 2026-10-21  
Stav: realizace probíhá nad aktuálním main; korekce runtime a souhlas s publikací níže  
Verification: standard pro SQL, platby, veřejné odkazy a sdílené chování; nízkonákladové ověření kosmetiky

## Výsledek a hranice

Správce vstupenky.online vytvoří událost od nuly nebo z předlohy bez zbytečných potvrzení, s platnými výchozími hodnotami a funkčním plánkem. Přehled jasně rozliší dostupnost událostí. Výsledek doložit srovnatelným měřením před/po a ověřením persistence, nikoli jen screenshoty.

Autoritativní zadání této úpravy je tento plán, který zachycuje všech 20 obrázkových požadavků z handoffu `/var/folders/k4/bf8sn81n6395dn845t2gvjbm0000gn/T/festapp-udalosti-handoff-ygg3oy1b/handoff.md`. Originály screenshotů a jejich kopie jsou v jeho složce `images/01.png` až `20.png`. Jejich dostupnost není podmínkou porozumění požadavkům v tabulce níže. Plán navazuje na původní návrh `occasion-setup-wizard-plan-2026-09-25.md`; historické popisy implementace v něm nejsou důkazem dnešního runtime.

Rozsah: sdílený zdroj na main, chování cílového tenantu vstupenky.online, průvodce, potřebné společné formulářové komponenty, předlohy, plánek a karty. Zachovat ostatní tenanty a existující oprávnění. Publikace a nasazení pro vybraný tenant jsou nově schváleny uživatelem. Převod produkčních zdrojových plánků a zásahy do Plesuj zůstávají mimo rozsah.

## Realizační korekce 2026-10-21

- Uživatel samostatně autorizoval úplnou realizaci, publikaci a produkční nasazení společně se všemi ready PR. Jediný tenant je `prod/festapptickets` (`https://vstupenky.online`); ostatní produkční větve nejsou v rozsahu. Otevřená PR při kontrole nebyla, relevantní ready PR jsou již v main.
- Původní checkout `eb2304724` má přes 2300 rozpracovaných cest a výrazně zaostává za upstreamem. Autoritativní runtime odpovídající screenshotům je main `f4aa0b6ed`, včetně PR #548-551. Implementace pokračuje v izolovaném worktree `../festapp-setup-usability-20261021`; níže uvedená rekognoskace starého checkoutu je historická, nikoli dnešní runtime.
- Main již vlastní moderní schemaVersion-2 editor, authoring zdroje, skutečný výběr banky, draft cenové vlny a sale status karet. Tyto implementace se zachovávají. Starý grid není dnešním editorem. SchemaVersion-1 se adaptuje existujícím importerem uvnitř konceptu; grid bez schválené geometrie se nezamlčí jako prázdný úspěch a neprovádí se jeho produkční konverze.
- A2 uživatel vyjasnil: podtržítka mají být obecně povolena a výchozí převaděč má mezery nahrazovat `_`. Stávající adresy se nemění. SQL/Dart přijímají pomlčky i podtržítka; JS čtenáři již obě reprezentace přijímají.
- Main mezitím zavedl explicitní volbu zahájení prodeje (příprava/plán/ihned). Zachovává se její kanonická sémantika formuláře a odděluje se od veřejného uvedení události. Finalizace vždy založí skrytou událost. Záměr dohledatelnosti se uloží a použije teprve samostatná výslovná akce Zveřejnit, která používá existující verzovaný save události. Propagace zůstává samostatným zvýrazněním a neplní roli dohledatelnosti.
- Porovnávací baseline vzniká nad čistým main a stejnou syntetickou fixture šesti předloh po 180 sedadlech v odděleném aktuálním backendu. Dřívější měření starého checkoutu se nepoužívá k tvrzení o zrychlení cílového runtime. Loopback fixture používá reálný kanonický app-config v219; běžný bootstrap zůstává beze změny.

## Ověřený výchozí stav

Rekognoskace proběhla nad pracovním stromem `/Users/miakh/source/festapp`, větev `feat/occasion-setup-wizard-20261007`, HEAD `eb23047248d59bf86345b9e0b79db4a988275231`. Při inventuře bylo 2337 změněných cest. Mnohé relevantní soubory jsou již upravené. Toto je identifikace pozorovaného stavu, nikoli čistá reprodukovatelná revize. Před implementací zaznamenat aktuální relevantní diff; nepřepínat ani resetovat rozpracovanou větev naslepo. Sdílený výsledek patří na main podle pravidel repozitáře, až v samostatně autorizované publikační fázi.

| Fakt potvrzený v kódu | Vlastník / důkaz | Důsledek |
|---|---|---|
| Průvodce je debug opt-in; kopie a běžná tvorba mají rozdílné vstupy. | `lib/app_config.dart: AppConfig.occasionSetupEnabled`; `occasion/occasion_creation_helper.dart: createNewOccasion`, `_openSetup` | Nezaměnit současný lokální průvodce za aktuální produkční build. Neměnit release flag jako vedlejší opravu. |
| Vstup vytvoří koncept, uloží počáteční data a stránka načte zdroje. | `_openSetup`; `setup/occasion_setup_page.dart: _loadSources` | Změřit každý RPC zvlášť i dobu do použitelného UI. |
| SQL inicializuje dočasnou událost v rollback podtransakci a hledá ji v úplném manifestu. Manifest skládá formuláře, produkty, plánky, program a informace všech událostí jednotky. | `database/functions/occasion_setup/drafts.sql: build_occasion_setup_configuration`; `sources.sql: get_occasion_setup_sources` | Potvrzená zbytečně široká práce; její skutečný časový podíl dosud není změřen. |
| Každá změna plánuje autosave s 600ms debounce; `_drain` serializuje celý koncept. | `occasion_setup_page.dart: _change`, `_save`, `_flush`, `_drain` | Neodstranit frontu, revize ani ochranu před souběhem kvůli rychlosti. Rozlišit čekání na save od navigace. |
| Story ukládá stabilní číselný krok a `storyQuestion`. | `occasion_setup_story.dart`; `occasion_setup_draft.dart: supportedSteps` | Zkrácení UI nesmí přečíslovat persistentní kroky ani rozbít obnovení starých konceptů. |
| Výchozí časy SQL i některé Dart fallbacky přebírají aktuální minuty; lokální wizard již při posunu startu opravuje příliš časný konec. | `drafts.sql`; `occasion_setup_page.dart: initState`, `_basics` | Upravit defaulty u jejich vlastníka, zachovat už hotovou ochranu termínu. |
| Splatnost wizardu má fallback `7`, `_paymentsReady` vyžaduje >0 a `_persistFormControls` zapisuje pouze >0. | `occasion_setup_page.dart` | Nula je dnes v této větvi nesprávně blokována; opravit logiku i formulář. |
| Běžné nastavení formuláře při dědění nechává pole prázdné. | `forms/views/form_settings_content.dart: _loadData`, controller splatnosti a helperText | Zobrazit efektivní hodnotu bez materializace override při nesouvisejícím uložení. |
| Odkazy už používají kanonický `CopyButton` a oddělený uložený baseline. | `_shared/copy_button.dart`; `forms/views/form_public_link.dart: PublicLink` | Znovu použít, kopírovat pouze serverem uloženou adresu. |
| Nové explicitní slugy dnes přijímají pomlčky, ne podtržítka. | `form_public_link.dart: isValidPublicSlug`; `database/functions/public_links/registry.sql`; `occasion/README.md` | Požadavek na `_` je změna veřejného kontraktu, ne kosmetický replace. |
| Existuje vyhledávací a časově seskupený picker. | `_shared/project_picker_widget.dart: ProjectPicker`; `_shared/app_panel_helper.dart` | Znovu použít vizuální jazyk a stabilní ID; neidentifikovat předlohu podle názvu. |
| Lokální prostředí má oddělený backend a konfigurace šesti předloh; jejich dnešní dostupnost není prokázána. | `docs/development/occasion-setup-local.md`; `automation/run_occasion_setup_local.py` | Nejprve ověřit skutečný lokální stav. Restart neaplikuje automaticky všechny nové migrace/finalize.sql. |

Plánky nezávisle prozkoumal vyžádaný subagent **gpt-6-astra, medium**. Konkrétní text chyby ze screenshotu se v prozkoumaném aktuálním kódu nenašel. Příčinu této konkrétní runtime chyby proto nelze vydávat za diagnostikovanou. Současně bylo doloženo: `_choice` přebírá `plans.first`, počet míst je délka `blueprintObjects`, přepnutí na Bez plánku je nevyčistí a finalizace vytváří plánek podle neprázdných objektů bez respektování režimu. Detail řeší vlna 2.

## Cílové invarianty a rozhodnutí

1. SQL zůstává vlastníkem oprávnění, kanonických defaultů, veřejných slugů a atomické finalizace. Dart je vlastníkem UI a přechodného editačního stavu. Nevytvářet druhou implementaci plateb, vln nebo konverze plánku.
2. Do konceptu se kopíruje pouze konfigurace. Žádní účastníci, objednávky, obsazenost, tajemství rezervací ani zápis do zdrojového plánku. Produkty a jejich vazby dostanou při finalizaci nová ID.
3. „Bez plánku“ znamená žádný aktivní plánek ve formuláři a žádnou materializaci plánku při finalizaci. Platný zvolený plánek automaticky znamená výběr míst. Uživatel neovládá druhý nesouhlasný přepínač.
4. Autosave zachovává editace při chybě, konflikt nepřepisuje cizí revizi. Finalizace používá stejný command UUID při nejistém výsledku a nevytvoří duplicitní událost.
5. Nová událost vzniká skrytá a prodej uzavřený, jak dělá současná finalizace. Volba veřejné dohledatelnosti nesmí potichu otevřít prodej ani přejmenovat promotion na jinou funkci. Uložený záměr zveřejnění musí mít jednoznačnou sémantiku při pozdějším publikování.
6. Částky, oprávnění a skutečná validita účtu zůstávají kontrolované na serveru. Pouze redundantní checkbox se odstraní. Automatický účet musí být skutečně vyhodnocenou platnou trasou, nikoli pouhým textem v dropdownu.
7. Efektivní splatnost = explicitní hodnota formuláře, jinak existující zděděná hodnota podle kanonického resolveru. `null` uchovává dědění; `0` znamená okamžitě. Pouhá návštěva či jiná editace nesmí uložit zobrazený default jako override.
8. Zachovat `current_step`, obnovení starších konceptů a funkce pozdější administrace. Odstraňuje se zbytečné UI z tohoto toku, nikoli jeho globální funkce.

## Pokrytí všech požadavků

| Obrázky | Cílové chování | Realizace / podmínka |
|---|---|---|
| 1-2 | Od nuly jako jasná volba; předloha s vyhledáváním, názvem, datem, skupinami nadcházející/proběhlé a označeným výběrem. | `ProjectPicker` nebo existující obal; výběr dle occasion ID, jednotka v klíči cache. Chybový/prazdný stav nesmí blokovat Od nuly. |
| 3 | Výchozí čas zaokrouhlit nahoru na půlhodinu; přesný slot ponechat. | 21:17 -> 21:30, 23:47 -> další den 00:00; sekundy vynulovat. Jedno zachycené now. Zachovat explicitní minuty a platný konec; časová zóna akce a DST. |
| 4 | Místo a popis pro vstupenky.online neblokují tvorbu; samostatné otázky vypustit, pokud ještě existují v cílové verzi. | Ověřit i server a přechody; v tomto checkoutu takové samostatné otázky už nejsou. Nepřidávat je zpět kvůli screenshotu. |
| 5 | Návrh dostupné adresy uvnitř pole jako trailing akce. | Napojit existující serverový allocator; návrh není rezervace. Konflikt řeší server při save. Podtržítka viz rozhodnutí A2. |
| 6 | Text používá přihlašování pro registraci a předprodej pro vstupenky. | Odvodit z existujícího doménového typu formuláře, ne z překladu názvu; stejné pravidlo v souhrnu a stavech. |
| 7 | Nová vlna nabídne platný budoucí termín přibližně za měsíc. | `eshop/views/product_price_waves_dialog.dart: _WaveTermDialog` a kanonický model vln. Pravidlo níže. Nezavádět další scheduler. |
| 8 | Vybraný platný účet nevyžaduje extra potvrzovací checkbox. | Odstranit UI, validační podmínku a dead draft klíč pouze po dohledání aktuální implementace. Zachovat kontrolu účtu, měny, jednotky a oprávnění. |
| 9 | Pole ukazuje skutečně efektivní splatnost a uchovává dědění. | Opravit wizard i použitý sdílený editor, rozlišit změněno uživatelem/reset na zděděné, otestovat nulu. |
| 10 | Tlačítko výchozího nastavení má mezeru vůči vysvětlení. | Upravit aktuálního vlastníka po runtime identifikaci, použít běžné mezery a rozměry. |
| 11-12 | Celý tok plánek - koncept - editor - uložení funguje a výběr míst se odvodí. | Vlna 2, včetně staré reprezentace a selhání. |
| 13 | Odbavení není otázkou základního průvodce. | Zachovat pozdější nastavení skenování; při současné absenci jen ověřit. |
| 14 | Veřejné uvedení/dohledatelnost odpovídá reálné veřejné viditelnosti. | Rozlišit `is_hidden`, `is_open`, `is_promoted` a veřejné listovací SQL. Pokud toggle ovládá jen promotion, nelze jej pouze přejmenovat. |
| 15 | Bez zbytečného zákaznického náhledu v průvodci. | Odstranit příslušnou sekci a její fetch/inicializaci, pokud existují. Zachovat editor skutečného prodejního formuláře a užitečný editor vzhledu vstupenky. |
| 16 | Odkaz využívá sdílený kopírovací widget. | `CopyButton`/`FormPublicLink`; při neuložené adrese pouze text, po finalizaci skutečný uložený odkaz. |
| 17-19 | Status blíže pravému okraji; bez vlastního hover zvýraznění a redundantního tooltipu. | Nejprve určit skutečný widget screenshotu. `OccasionEditCard` v tomto checkoutu odpovídající status nemá; nemažte jeho tooltipy statistik jako náhradu. |
| 20 | Nepovolené karty jsou zřetelně šedé, text čitelný. | Nezaměňovat plánovaný prodej za zákaz. Správce stále otevře editaci/menu; žádná plošná blokující vrstva. Ověřit konkrétní stavový resolver. |

**Pravidlo vln:** Použít časovou sémantiku stávajících vln. Návrh = stejné místní datum/čas za kalendářní měsíc (neexistující den oříznout na konec měsíce). Dolní mez = pozdější z nyní a posledního relevantního naplánovaného termínu; horní mez = poslední přípustný okamžik před koncem akce podle stávající přesnosti plánování. Je-li měsíční návrh mimo interval, zvolit platný slot uvnitř něj. Pokud interval neobsahuje žádný slot, novou vlnu nevytvářet a stručně vysvětlit proč. Existující/editovaná vlna si ponechá svůj čas. Chybějící konec se neodhaduje; vyžádat jeho doplnění. Stejné časy nesmí nevědomky rozdělit či duplicitně vytvořit sdílenou vlnu.

## Realizační vlny

### 0. Zafixovat runtime a změřit baseline

- Zaznamenat HEAD, relevantní dirty diff, build režim, vstupní route, tenant schopnosti, browser/host, fixture a backend verzi. Zjistit, zda UI z obrázků je jiný build/větev. Žádný automatický deploy ani přepínání cizí práce.
- Přečíst browser a lokální E2E skills. Použít izolovaný headless `agent-browser`, task-specific session a dostupné autorizované lokální fixtures. Nejprve využít již běžící projektový server. Před případným Flutter startem ověřit jediný volný Flutter slot; cizí proces nezastavovat.
- Podle `docs/development/occasion-setup-local.md` zkontrolovat loopback backend a skutečné RPC v něm. Chybějící soukromý snapshot nenahrazovat stažením produkčních dat bez příslušné kontroly a oprávnění; použít syntetické legacy a moderní fixtures. Data konceptu/finalizaci testovat pouze lokálně.
- Změřit přehled, otevření nové tvorby, první/opakované předlohy, jeden běžný přechod, převzetí plánku, editor, save a finalizaci. Start = akce uživatele, konec = použitelné UI; zvlášť stav Uloženo. Alespoň 1 první a 3 opakované běhy, všechny vzorky a medián, žádné p95 ze tří běhů. Oddělit debug/release a lokální/produkční čísla.
- Uložit stručný záznam `docs/plans/evidence/occasion-setup-performance-2026-10-21.md`: ms, počet RPC, payload bytes, chyby a čas serializace/renderu tam, kde je potřeba. Bez tokenů a osobních dat. Časy zatím neexistují a nebudou domýšleny.
- Výstup: reprodukovatelná baseline a přiřazení každého odlišného screenshotového prvku k aktuálnímu vlastníkovi nebo doloženému již vyřešenému požadavku. Bez přístupu k danému runtime označit rozdíl a dokončit lokální práci, netvrdit produkční příčinu.

### 1. Zmenšit prokázanou práci na kritické cestě

- V `sources.sql` oddělit lehký seznam metadat od detailu vybrané předlohy. Detail stále sanitizuje všechna data a ověřuje práva ke zdroji i cílové jednotce/organizaci, včetně podporovaného kopírování mezi jednotkami stejného tenantu.
- V `drafts.sql: build_occasion_setup_configuration` číst jen právě vzniklou dočasnou událost přes stejnou interní projekci detailu. Zachovat kanonický inicializační algoritmus a rollback podtransakci; nahradit pouze celounitový průchod. Defaulty neduplikovat do Dartu.
- `_loadSources` načítá metadata; detail až při výběru. Sdílet dokončený/in-flight request pouze v bezpečném kontextu jednotky a přihlášení, invalidovat po změně zdroje. Starší odpověď nesmí přepsat novější výběr. Chyba detailu ponechá poslední platnou konfiguraci.
- Neměnit veřejný kontrakt existujícího RPC nekompatibilně: dohledat všechny volající. Přidat cílené RPC, převést aktuální wizard a dočasné staré RPC ponechat jen pro prokázané staré klienty, s uvedeným vlastníkem a podmínkou odstranění. Neuchovávat souběžné implementace projekce.
- UI shell a Od nuly jsou dostupné během načítání předloh. Optimalizaci create+save nebo autosave přidat jen při naměřené významnosti; zachovat idempotenci a revize, nevyvolávat save při pouhém přepsání prezentačního labelu zdroje.
- Ověření/exit: SQL sources/drafts testy, odmítnutí cizího zdroje, menší payload a žádné celé konfigurace všech zdrojů na startu. Srovnat stejný scénář s baseline; pokud zůstává dominantní jiná příčina, opravit ji podle trace a aktualizovat tuto vlnu.

### 2. Jednoznačný a bezpečný stav plánku

- V `occasion_setup_page.dart: _choice`, `_applyBlueprint`, `_openBlueprint`, `_blueprintReady` rozlišit bez plánku, načítání kandidáta, připravený plánek a chybu. Režim a platná konfigurace tvoří jeden kontrakt, ne dvě nezávislé pravdy.
- Vymezit malého typovaného vlastníka konfigurace konceptu se stabilními ID režimů a vybraného zdrojového plánku; přeložené popisky nesmí být persistentní identita. Staré řetězcové režimy převést při čtení konceptu. Prázdný rozpracovaný plánek lze uložit, ale nelze s ním dokončit událost.
- Převzít používá plánek odkazovaný vybraným formulářem; při více kandidátech ukázat výběr, nepoužívat `plans.first`. Žádný kandidát znamená vysvětlení s možností vytvořit nový či pokračovat bez plánku, nikoli nulový údaj maskující selhání.
- Adaptovat staré podporované reprezentace na existující editor na hranici načítání konfigurace, do kopie konceptu. Nejprve porovnat skutečný runtime a aktuální grid/object API; současný README není důkaz shody. Použít existující model/adapter, nikoli psát další editor či spouštět produkční migraci. Nepodporovaný vstup zachová dosavadní koncept a nabídne opakování, jiný zdroj nebo nový plánek bez ztráty ostatních dat.
- Počet míst odvodit z prodejných sedadel přes kanonický adapter, ne z počtu všech objektů/dekorací. Zachovat geometrii, skupiny, pozadí, popisky a vazby produktů. Nevkládat reálná zdrojová ID objednávek či rezervací.
- Bez plánku odpojí aktivní objekty/skupiny/vazbu formuláře i případný boolean výběru míst. Pokud UX zachová rozpracovanou variantu pro návrat, musí být explicitně neaktivní a finalizace ji nesmí číst. Preferovat jednoduché potvrzené zahození před novým stínovým modelem.
- `finalize.sql` validuje stejnou sémantiku režimu; Bez plánku nic nematerializuje. Nový/Převzít vyžaduje validní prodejná místa a produkty; nesmí potichu dokončit bez požadovaného plánku. Automatické seat selection promítnout do skutečného formuláře i veřejného klienta.
- Konkrétní druhý vlastník je `TicketEditorWidgets.buildTicketEditor` / `buildSpotFieldEditor` a `FormEditorDraft.usesSeatSelection`: příznak je odvozen od pole `spot`, nikoli samotného blueprint feature. V kontextu wizardu normalizovat pole před serializací i při SQL finalizaci. Bez plánku ponechat produkty dostupné pro běžný prodej, ne je spolu s polem míst znepřístupnit.
- Uložení editoru změní pouze koncept. Selhání uloží lokální změny do existující retry fronty, konflikt nabídne bezpečné znovunačtení. Nezavírat editor ztrátově a neskrýt chybu změnou textu.
- Aktuální prototype editor hlásí save po synchronním callbacku, zatímco durable autosave teprve čeká; callback se volá i při dispose. Výslovně sjednotit Zpět/Zahodit/Uložit: buď hlásit jen předání změn do konceptu, nebo čekat na skutečný save. Žádné nečekané uložení při zahození. Chybu přípravy oddělit od transportní chyby. Určité zamítnutí finalizace musí dovolit opravu, nejistý síťový výsledek zachová command ID a snapshot.
- Ověření/exit: fixture moderního i staršího plánku, dekorace, více plánků, nulová sedadla, bez plánku po převzetí, selhaný save, konflikt revizí a opakovaná finalizace. Zdroj beze změn, jedna výsledná událost, správné nové produktové vazby a žádná obsazenost.

### 3. Jeden souvislý balík změn průvodce

- Implementovat tabulku 1-16 nad aktuálním story tokem. Již chybějící zbytečné otázky znovu nezavádět. Zachovat `current_step` a znormalizovat odstraněné `storyQuestion` na nejbližší platný krok. Aktualizovat progress, souhrn, skoky k chybě a Zpět/Pokračovat.
- Půlhodinové defaulty zavést v kanonické konfiguraci, přímý dialog/fallbacky sjednotit bez přepsání explicitních dat zdroje či rozepsaného konceptu. Posun startu posune automatický konec konzistentně; vědomě neplatný ruční konec zůstává viditelnou validační chybou.
- Splatnost a účet dokončit přes formulářový model, nikoli jen draft prezentační řetězec. Dohledat existující resolver efektivních hodnot a skutečnou cestu platební validace/finalizace; současné `draftFormBundle` má prázdné bankovní účty a finalizace odstraňuje převzatý `bank_account`. Nepovažovat text Automaticky podle měny za hotovou integraci výběru účtu.
- Přejmenování veřejné dohledatelnosti udělat až po dohledání veřejných čtenářů a publikačního chování. Bezpečný výsledek: oddělit přípravu veřejného uvedení od otevření prodeje; skutečné zveřejnění musí mít explicitní existující publikační akci. Neslibovat veřejný výsledek, který uložené příznaky nevytvářejí.
- Pravidlo nové vlny patří do existujícího vlastníka plánování; před změnou ověřit, zda screenshotový wizard ukládá vlny do konceptu nebo jde o sdílený editor nad živou událostí. Draft režim nesmí zavolat mutaci zdrojové události.
- Ověření/exit: data po obnovení i po finalizaci odpovídají UI, nula funguje, inherited zůstává null, explicitní hodnota přetrvá, termíny jsou platné, žádná skrytá blokující validace a ticketing tenant nezíská povinnosti aplikace s programem.

### 4. Přehled a závěrečné ověření

- Po identifikaci správného status widgetu upravit pravé odsazení, odstranit jeho interaktivní vzhled a duplicitní tooltip. Kandidáti `unit/views/occasion_edit_card.dart`, `occasion_card.dart`, jejich skuteční volající; nepřenášet pravidlo na všechny hovery.
- Rozlišit skrytou/nepovolenou akci, pauzu prodeje, budoucí spuštění a proběhlou akci pomocí existující dostupnostní logiky. Šedé karty zůstávají čitelné a administrativně ovladatelné. Ověřit šířky 390 a 1440 px, dlouhé názvy, klávesnici a světlý/tmavý režim.
- Projít oba vstupy Od nuly/Předloha a kopii z karty, uložit, odejít, obnovit a dokončit lokálně. Jeden slučovaný průchod browserem má pokrýt UI i výkon; neprovádět samostatné plné QA po každém poli.
- Zopakovat stejnou měřicí matici jako ve vlně 0. Uvést skutečné absolutní hodnoty a rozdíly, bez slibu předem vymyšleného procenta. Kde trvání nekleslo, uvést naměřený limit a příčinu; nezamlčet regresi.
- Exit: všechny řádky požadavků mají implementaci nebo důkaz již správného aktuálního chování, cílené kontroly prošly, v handoffu jsou zbylá runtime/autorizační omezení.

## Co odstranit a co zachovat

| Artefakt | Konečný stav | Důkaz |
|---|---|---|
| Celé konfigurace všech předloh na startupu wizardu | Nahradit metadata + detail a sdílenou interní projekci | Network trace a SQL test rozhraní |
| Výběr předlohy podle labelu, `plans.first`, raw objects.length jako počet míst | Nahradit stabilními ID, vazbou formuláře a kanonickým počtem sedadel | Duplicitní názvy, více plánků a dekorace ve fixture |
| Nezávislý přepínač výběru míst | Odstranit z wizardu a jeho blokující validace, je-li v cílové verzi | UI + uložený formulář + veřejný tok |
| Potvrzení účtu, zákaznický náhled, nastavení odbavení v základním toku | Odstranit jen existující wizard UI, dead validační větve a související fetch | Průchod bez skrytých podmínek |
| Fallback 7 v wizardu, validace splatnosti >0 | Nahradit efektivním resolverem a >=0 pro explicitní hodnotu | Dědění/null, 0 a explicitní počet dní |
| Lokální imitace Kopírovat, hover statusu | Použít sdílený widget; odstranit pouze redundantní status efekt | Uložený URL baseline a cílený vizuální průchod |
| Staré koncepty, historické slugy, administrace odbavení, editor vstupenky | Zachovat kompatibilitu a existující oprávnění | Resume, starý odkaz a následné nastavení |

## Ověření bez zbytečných buildů

Plánování nespouští testy ani Flutter. Implementace má jedno cílené SQL ověření po souvislé změně backendu a jeden cílený klientský batch po dokončení souvisejících úprav; další běh pouze po nové změně/failu. Bez plošného release buildu pro kosmetiku. Všechny Flutter úlohy sériově, testy `--concurrency=1`.

- Analyzer: `fvm dart analyze lib/components/occasion/setup lib/components/occasion/occasion_creation_helper.dart lib/components/unit/views/occasions_screen.dart` + pouze skutečně změněné sdílené soubory.
- Testy story: `fvm flutter test --concurrency=1 test/components/occasion/occasion_setup_story_test.dart test/components/occasion/occasion_setup_story_shell_test.dart`.
- Doplnit behaviorální testy časů, návrhu vln, platebních defaultů a plánku do jejich existujících vlastníků. Soubory `*_cases.dart` nejsou samostatné běžné test rooty: použít skutečné registrované suite a filtr, např. `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart --plain-name blueprint_draft_product`; ostatní vlastníky dohledat přes scoped rg v `test/sessions` nebo core balíčku. Zachovat pravidla klasifikace testů v CONTRIBUTING.md.
- SQL nad ověřeným loopback backendem: `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:56822/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/occasion_setup`. Ověřit nenulový počet vybraných testů a souhrn. Rozšířit o konkrétní platební/public-link/vlnový test jen při změně jejich kontraktu.
- Před testy výslovně aplikovat změněné kanonické SQL do izolovaného backendu, v závislostním pořadí; restart launcheru sám nezaručí nové finalize.sql. Nevolat bootstrap destruktivně nad rozpracovanou lokální DB. Nová RPC/SQL změny dodat i jako správnou repozitářovou migraci, žádná aplikace do produkce.
- Smysluplné případy: různé jednotky/tenanty a odebraná práva; dvě revize; timeout/retry finalizace; půlnoc a DST; neplatný ruční konec; akce před měsíčním návrhem vlny a bez dalšího slotu; inherited/explicit/0; cizí účet; starší plánek; přepnutí na Bez plánku. Netestovat přesné znění přeložených popisků nebo každý padding.
- Browser: izolovaný headless podle skills; kontrola viditelnosti/splnění dat a jeden potřebný vizuální průchod. Pokud Flutter canvas nejde posoudit accessibility snapshotem, použít screenshot. Deterministické repo E2E brány nenahrazovat přímým Playwright spouštěním.

## Rozhodnutí a omezení po realizaci

- **A1 - verze screenshotů:** přesná implementace z obrázků ani konkrétní conversion error nebyly v runtime ověřeny. Vlastník: realizátor vlny 0. Dopad: nelze tvrdit příčinu produkční pomalosti/chyby. Chybějící přístup brání jen těmto tvrzením, nikoli lokální implementaci ostatních bodů.
- **A2 - podtržítka - uzavřeno:** uživatel potvrdil obecné povolení `_` pro adresy událostí i formulářů a výchozí převod mezer na `_`. SQL allocator a Dart validace sdílejí povolené oddělovače; existující JS čtení je přijímá. Návrh adresy používá existující serverovou funkci. Žádné hromadné přejmenování existujících adres. SQL test dokládá nové adresy i zachované aliasy.
- **A3 - viditelnost/karty:** konkrétní status komponenta a význam nepovolené karty nejsou v tomto snapshotu určeny. Rozhodnout z runtime a kanonických flagů ve vlně 0, ne z podobného názvu souboru. Zachovat oddělení zvýraznění, veřejné dohledatelnosti a otevřeného prodeje.
- **A4 - legacy plánek:** adaptace jde pouze v rámci prokazatelně podporovaných dat. Pokud vyžaduje zásadní nový formát nebo produkční převod, zaznamenat přesnou překážku a návrh; nezatajovat selhání pod obecným hlášením a nepřekročit oprávnění.

## Organizace práce a dokončení

Jeden hlavní realizátor drží měření, průvodce a integraci. **Astra Medium** dostane ohraničený balík plánku: stavový kontrakt, adaptaci a SQL/klientské testy po určení používaného API; při sdíleném souboru wizardu dá hlavnímu realizátorovi konkrétní návrh nebo má přidělený výhradní editační úsek. Nezakládat další agenty na kosmetiku či opakované audity. Práce na kartách může běžet během čekání na backend, nikoli souběžně s konfliktní editací. Flutter slot je společný pro všechny.

Hotovo znamená: měření před/po ve stejném prostředí, fungující převzetí i nový plánek bez zápisu do zdroje, bezpečný save/retry/finalize, správné datumové/platební defaulty, pokrytá tabulka požadavků, odstraněné zbytečné kroky i jejich validace, obnovení starších konceptů a cílené kontroly. Neuzavřené podtržítko nebo nedostupná produkční reprodukce musí být výslovně uvedeny; nejsou splněny pouhým dokončením ostatních částí.

Implementace končí lokálním ověřeným výsledkem a krátkým handoffem. Commit, push, nasazení nebo produkční migrace vyžadují samostatné zadání. Případný budoucí release se týká jen výslovně vybraného vstupenky.online tenantu, zachová main/tenant ancestry a pravidla přímého lokálního deploye. Backendové rozšíření musí předcházet novému klientovi; odstranění prokázaně používaného starého RPC až po autorizované aktualizaci jeho klientů. Lokální rollback vrací vlastní patch, nikdy reset celého rozpracovaného stromu ani zdrojová data.


## Výsledek realizace

Autoritativní implementace je na aktuálním main, v izolovaném worktree. Měření a jeho omezení jsou v [evidenci](evidence/README.md). Úvodní zdroje mají v syntetické sadě 936 B místo 329376 B; opakované UI přechody zůstaly podobné. Nelze z toho tvrdit příčinu produkční pomalosti.

Schéma2 a podporované schéma1 používají kanonický editor a explicitní awaited save do konceptu. Prostý starý grid bez podporované geometrie není automaticky převáděn; zobrazí konkrétní překážku a umožní nový nebo jiný plánek. Zdrojová událost se nemění. Skutečný browser reprodukoval chybu Map<dynamic,dynamic> při otevření převzatého formuláře před JSON roundtripem; oprava vlastní typ nového pole a přímý regresní test.

Uživatel v této relaci výslovně autorizoval commit, push i produkční nasazení se všemi připravenými změnami, pouze prod/festapptickets. Tím nahradil původní omezení tohoto plánu na lokální handoff. Existující starší mezery migračního ledgeru nejsou součástí nového SQL balíku a nepřehrávají se naslepo.
