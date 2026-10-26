# Vyhodnocení externího CRO auditu a plán úprav

Datum: 26. 10. 2026
Stav: schválený zúžený rozsah implementován a ověřen; produkční nasazení je samostatný krok
Ověření: standard pro autentizaci a sdílené navigační kontrakty.

## Schválený implementační rozsah

- Implementovat dokončení „Založit akci“ přes email i Google a vstupy pořadatele v katalogu.
- Nákupní formulář a jeho obsah zůstávají pořadateli (uživatel výslovně potvrdil). Původní vlna 2 se neprovádí.
- Ceník a cenový obsah odloženy. Původní vlna 3 se neprovádí.
- U měření pouze ověřit stávající Cloudflare integraci a její skutečné možnosti. Nezavádět funnel, tracker, nové databázové atribuce ani reporty. Původní vlna 5 je omezena na ověření.
- Implementovat a cíleně ověřit. Toto zadání neobsahuje nové produkční nasazení.

### Konkrétní provedení tohoto rozsahu

1. Sdílený JS parser rozpozná canonical `/login?create=1` i vstupní `/events?create=1`. Google použije tento známý návratový kontrakt; ostatní query a návratové cesty zůstávají omezené stávajícím allowlistem.
2. Založení po autentizaci pošle přes existující `/flutter?redirect=...` handoff explicitní interní continuation `/organizer-action/create`. Není potřeba nová stránka ani AutoRoute generování: stávající LoginPage již ověřuje relaci a předává typed continuation do `handlePostLoginNavigation`. Tam bude jediný dispatcher akce vytvoření. Reload interního handoffu se vrací na canonical webový registrační vstup.
3. Zpřístupnit existující creation helper používaný nápovědou a sdílet jeho volbu jednotky, capability check, obnovení draftu a jediný wizard. Odstranit fallback přes nápovědní settings. Při změně přihlášeného účtu během async volby odmítnout pokračování. Běžný login dál otevírá správu.
4. V katalogu vytvořit malý sdílený blok pro homepage, městskou stránku a detail. Detail má oddělené Opravit údaje a Založit prodej; první odkaz používá již existující moderovaný návrh, druhý canonical webové založení. Bez automatického přebírání záznamů a bez předvyplnění/neověřených pravomocí.
5. Ověřit skutečné požadavky Cloudflare beaconu a jeho privacy hranice. Oficiální absence UTM/custom events je omezení Web Analytics, nikoli důvod přidávat další nástroj bez zadání.

Dále uvedené hodnocení auditu zůstává důkazním podkladem; odložené vlny nejsou součástí této implementace.

## Výsledek a výchozí stav

Cílem je odstranit skutečné překážky registrace pořadatele, rozhodnutí o službě a nákupu vstupenky. Nepřepisovat fungující produkt podle tři dny starého snímku. Dopad na konverze zatím není změřený.

Podklad: `/Users/miakh/Downloads/2026-10-23-cro-audit-vstupenky-online.md`, včetně obou příloh. Audit popisuje stav k 23. 10.; přílohy jsou revize jeho předchozích verzí, nikoli další nezávislé audity současné produkce. Původní surová měření nebyla součástí tohoto souboru.

Produkční baseline původního auditu: vstupenky.online `0.20.410+911`, tenant commit `8e2775420acea8f8c220960ec8aeef6b35b1cc2b`, canonical main `e5d5b2f30b9545de0a97e6c16e93ee2161e111c7`.

Dne 26. 10. proběhl anonymní průchod izolovaným headless prohlížečem: homepage, `/login?create=1`, formulář Country bálu, katalogový detail, město Břeclav a formulář přidání plesu. Druhý průchod připnul českou lokalizaci a zachytil pouze veřejná metadata z odpovědí API. Nic nebylo odesláno, nebyl založen účet ani rezervováno místo. Byla dohledána celá návaznost JS -> Flutter -> registrační SQL a draft -> uložení -> finalizace -> zahájení prodeje.

Trvalý souhrn důkazů: `docs/plans/cro-audit-evidence-2026-10-26.json`. Podrobné dočasné logy, skripty a snímky: `/tmp/festapp-cro-deep-20261026/`. Prošly 17 JS testů autentizace/formuláře, 23 Flutter testů průvodce, 9 katalogových testů a tři SQL sady draft/finalize/sales. V lokální databázi byla starší varianta finalizeru lišící se emailovým bannerem: konečné tři SQL sady proto načetly canonical finalizer z repozitáře uvnitř transakce, provedly testy a vše vrátily přes ROLLBACK. Změna backendu nebyla ponechána ani aplikována do produkce.

Ztráta záměru přes Google byla reprodukována skutečným `GoogleAuthService.start()` a `complete()`: vstup `/login?create=1`, uložený i výsledný návrat `/login`. Pouze externí broker a přijetí relace byly nahrazeny fixture; skutečné Google přihlášení ani emailová doručitelnost tím nejsou ověřené. Nové měření výkonu má tři platné běhy se studenou HTTP cache, vypnutým service workerem, viewportem 412 x 844, latencí 150 ms, downloadem 200000 B/s a CPU slowdown 4. Je to laboratorní měření na této stanici, nikoli p75 skutečných návštěvníků.

## Verdikt ke každému nálezu

| Nález | Verdikt k 26. 10. | Co je doložené a co z toho plyne |
|---|---|---|
| Z1: založení a registrace | **Původní vzhled a formulář opraveny; návaznost má potvrzenou chybu.** | Webová registrace má jen e-mail, jméno a příjmení. Reprodukce skutečným JS klientem potvrdila, že Google vrací `/login` bez `create=1`; `safeAuthReturnPath('/login?create=1')` navíc vrací `/`. Po přihlášení handler vede uživatele do správy jednotky. Registrační SQL už vytváří vlastní jednotku s rolemi manager/editor, takže nový pořadatel typicky skončí v prázdném přehledu místo rovnou v založení akce. Emailová registrace legitimně čeká na přihlášení heslem zaslaným emailem; tento krok nesmí být obcházen. |
| Z2: chybějící cena | **Legitimní, stále otevřené.** | Úvodní stránka nadále říká, že se cena služby domlouvá samostatně. Neobsahuje cenový model ani reprezentativní kalkulaci. To je informační nedostatek; pokles konverze není prokázán. Založení akce zdarma je výslovný požadavek uživatele a zůstává. Je třeba vysvětlit jeho rozsah a případné placené služby. |
| Z3: cesta pořadatele z katalogu | **Legitimní chybějící vstup; část podpůrných tvrzení už neplatí.** | Odkaz je na mobilu skrytý pravidlem `.organizer-link{display:none}` do 1050 px. Detail a městská stránka nemají kontextovou nabídku pro pořadatele. Canonical homepage je správným cílem, ale bez zdroje. Příjem návrhů už má povinný neveřejný email, souhlas a moderaci; toto není potřeba znovu stavět. API a testy potvrzují idempotentní příjem a soukromý outbox. Velikost katalogu ani hypotetický obchodní přínos nedokládají počet zákazníků. |
| Z4: chybějící měření | **Funnel ani atribuce nejsou v prozkoumané cestě implementované; celková absence měření není dokázaná.** | Veřejné Cloudflare analytics existují. `/login`, capability URL a embed jsou záměrně vyloučené. `no-referrer` je stále v HTML homepage, ačkoli HTTP header používá `origin`; samotný header tedy problém neřeší. Obchodní zdroj se nikde ve zkoumané cestě draftů nepersistuje. Soukromé reporty nebyly zpřístupněny. Neinstalovat plošný tracker do autentizace kvůli této připomínce. |
| Z5: neznámá aktivace po registraci | **Obecná kritika průvodce není podložena; technické základy jsou ověřené.** | SQL testy prokázaly idempotentní vytvoření, uložení, konflikt revizí, kontrolu cizího draftu, finalizaci a režimy preparation/scheduled/immediate. 23 Flutter testů potvrdilo otázky, obnovení kroku a platební připravenost. Chybějící přímý vstup do tohoto průvodce je konkrétní problém Z1. Z testů nelze odvodit srozumitelnost pro skutečné pořadatele. |
| Z6: ukázka není nahoře, různé názvy CTA | **Hlavní část již opravená.** | Hero má „Založit akci zdarma“ a „Domluvit ukázku“. Název hlavní akce je sjednocený; mobilní hlavička používá zkrácené „Založit zdarma“. Jedna pomocná věta pod CTA je možný drobný doplněk, nikoli důvod dalšího redesignu. |
| Z7: slabší důvěra a FAQ | **Rozumné obsahové doporučení, nikoli prokázaný konverzní problém.** | Ve viditelném FAQ jsou jen účet, platby/doručení a cena. Chybí rychlé vysvětlení provozních situací. Skutečné reference již existují, ale nejsou to citace pořadatelů. Citace, fotografii a čísla lze přidat jen z ověřených podkladů a s oprávněním k použití. |
| Z8: 18 obrazovek, dlouhá galerie a MCP | **Pro současnou homepage neplatí.** | Nový průchod 390 x 844 měl výšku 7614 px, přibližně devět obrazovek; rozměr se mění podle viewportu a načteného obsahu. Homepage obsahuje nula `.output-card` a žádnou `.technical-options`. Kód českého rendereru technickou sekci odstraňuje. Není důvod realizovat starý návrh dalšího zkracování podle osmi historických šablon. |
| Z9: chybí kontext nákupní akce | **Potvrzená chyba prezentace a omezený datový kontrakt.** | Veřejná odpověď Country bálu obsahuje start `2026-11-14T18:00:00+00:00` a konec `22:59:00+00:00`, UI je neukazuje. API nevrací místo ani časovou zónu akce. Pokračovat je neaktivní a nemá `aria-describedby`. Ceny 150 Kč a večeře 160 Kč už jsou v popisu; jejich absence ani neexistence souhrnu po výběru neplatí. Součet vlastní `FormSession`/`PriceWidget`. |
| Z10: LCP 3,4 s | **Nové měření nález nepotvrdilo; nyní bez opravné priority.** | Tři platné mobilní laboratorní běhy: LCP 2056/2056/2048 ms, CLS přibližně 0,0145. LCP kandidát je textový `span.ink` „Všechno na svém místě.“, nikoli plakát z referencí. Nelze z toho slibovat stejné výsledky na všech telefonech. Plošná konverze plakátů ani fontů není doloženou opravou tohoto nálezu. |

## Rozhodnutí a hranice

- Zachovat současný vizuální styl, headline, produktové ukázky a obě hlavní CTA. Změnu hlavního sdělení ani zúžení celé služby výhradně na plesy audit neprokazuje.
- Založení akce zdarma je platné zadání uživatele. Konkrétní cenu další služby, DPH a rozsah pomoci musí dodat provozovatel; nevymýšlet částky ani SLA.
- Vstup pořadatele, jeho identita, obchodní zdroj a právo spravovat konkrétní akci jsou odlišné věci. Parametr URL nikdy neuděluje oprávnění.
- Úpravy katalogu patří do repozitáře `/Users/miakh/source/plesuj`; Festapp vlastní autentizaci, drafty, prodej a objednávky. Před implementací v katalogu načíst jeho pravidla a ověřit aktuální canonical checkout, protože základní pracovní strom má rozpracované změny.
- Následně schválená implementace je omezena první sekcí tohoto plánu. Produkční data, kontaktování lidí, cenový obsah, nákupní formulář a další nasazení zůstávají mimo toto zadání.
- Žádný nový tracker, automatické oslovování ani CRM jako vedlejší produkt. Potřebu a podmínky případného měření vyřešit před jeho nasazením.

## Pořadí realizace

### 1. Dovést „Založit akci“ do existujícího průvodce

**Priorita:** P0, malá až střední změna autentizačního pokračování; samostatně krátké ověření použitelnosti.

**Vlastníci a důkazy:** JS `organizer_intent.js`, `google_auth_service.js` (`safeAuthReturnPath`, `start`, `_complete`) a `login_modal.js` (`_handleRegister`, `_handleLogin`, `showGoogleResult`). Flutter `lib/components/navigation/help_destination_picker.dart` už implementuje výběr jednotky, vytvoření první jednotky, kontrolu capability, nabídku uložených draftů a otevření `OccasionSetupPage`; nemá se znovu implementovat. SQL `users/initialize_registration_unit_v1.sql` už vytváří vlastní jednotku při emailové i externě ověřené registraci.

**Změny:**

1. V `organizer_intent.js` zavést sdílený parser explicitního záměru `create=1`. Canonical veřejný vstup zůstane `/login?create=1`; stávající `/events?create=1` zůstane úzkou vstupní přesměrovací hranicí. Parser použije také Google návratový filtr. Nevytvářet obecný parametr `next` nebo `redirect` pro libovolné URL.
2. V `GoogleAuthService.start()` sestavit návratovou cestu z tohoto parseru místo samotného pathname. `safeAuthReturnPath()` pro ni povolí právě známý kontrakt; `_complete()`/`_accept()` jej zachovají. Stejný záměr zůstane při přepnutí registrovat/přihlásit a reloadu po heslovém loginu. Emailový tok zůstane bezpečně: registrace -> doručení přihlašovacích údajů -> přihlášení -> založení. Nevynechávat ověření identity.
3. Přidat interní Dart vstup `/organizer-action/create` a route obsluhu v `lib/app_router.dart`/`lib/router_service.dart`. Web do něj po ověření identity vstoupí přes existující Flutter handoff. Samotná interní route znovu vyžaduje autentizaci a serverovou capability. Veřejný `/login` zůstává webovým dialogem.
4. Vyjmout společnou implementaci `_createHelpOccasion()` do jednoho znovupoužitelného creation entry helperu. Použijí jej jak interní organizer route, tak původní nápovědní picker. Zachovat pořadí: oprávněná jednotka -> existující draft nebo vědomé „Nová akce“ -> `OccasionCreationHelper.createNewOccasion()` / `OccasionSetupPage.open()`. Při více jednotkách dát výběr; při jedné nepřidávat mezikrok. Bez jednotky použít existující `UnitCreationHelper` jen pokud server dovoluje její založení.
5. `handleOrganizerIntent()` rozliší vytvoření od obyčejného přihlášení. `create=1` otevře tento vstup, obyčejný login může dál pokračovat do správy. Odstranit současnou náhradu založení přes `helpActionFlutterPath('settings')`; uživatel nemá být posílán nejdřív do volby nápovědní destinace. Nevytvářet draft automaticky při každém načtení route; nový UUID vznikne až při skutečné volbě nové akce, opakování používá již existující idempotentní RPC.

**Odstranění:** zahazování záměru při OAuth, generické otevření unit dashboardu pro explicitní create a použití nápovědního `settings` jako náhražky. Starý private `_createHelpOccasion()` nebude mít paralelní kopii. Nenahrazovat registrační backend ani zavádět druhou databázi draftů.

**Ověření:** změnit reprodukci Google tak, aby testovala skutečné `start()` i `complete()`, ne pouze funkci na řetězci. Matice: nový/existující účet; 0/1/více jednotek; žádný/jeden/více draftů; Google/email; reload/zrušení; zakázané založení. Zachovat testy `help_action.test.js`, bezpečných návratů MCP a otevřené objednávky. Dart test creation helperu musí ověřit odmítnutí cizího draftu a že reload bez potvrzení nevytvoří další. Stávající průvodce se nemění; relevantní smlouvy už ověřily `test/sessions/shared_default_2_test.dart --plain-name occasion_setup_story` a tři SQL sady drafts/finalize/sales.

**Hotovo:** kliknutí opravdu končí v nové nebo zvolené rozpracované akci. Neskončí jen v obecném přehledu a nevyžaduje výběr nápovědní destinace. Vstupní parametr nemůže otevřít cizí draft a opakování nezaloží další. Průvodce zůstává jediný. Pozorování 2-3 pořadatelů může následně odhalit další UX úpravy, ale není podmínkou této konkrétní opravy.

### 2. Zpřehlednit nákupní formulář

**Priorita:** P1, před obsahovým přepracováním marketingu.

**Vlastníci:** `form_models.js`, `form_renderer.js`, `form_page.js`, `widgets/price_widget.js`, `web_client/src/services/time_helper.js`; SQL `database/functions/others/get_occasion_seo_data.sql` a již existující projekce `seo` v `eshop_forms/get_form_by_link.sql`.

**Změny:**

1. Rozšířit stávající `get_occasion_seo_data()` o dvě vyjmenovaná veřejná pole `timezone` a `place_name` ze `occasions.data`. Termín, název a konec už tato projekce obsahuje a `get_form_by_link` ji vrací i pro zavřený formulář. Neposílat celý `occasion.data`, nepřidávat druhý API request a nescrapovat datum z HTML pořadatele.
2. V `FormModel` vytvořit veřejný event context z existujícího `seo` a renderovat malý blok „14. listopadu 2026, 19:00 · [skutečný sál]“ před vlastním obsahem pořadatele. Bez nového hlavního nadpisu a bez opakování cen. Chybějící sál se nezobrazí a pořadateli se v existujícím nastavení nabídne doplnění; neodhadovat ho z města nebo názvu akce.
3. Přidat do `TimeHelper` explicitní formátování s `Intl.DateTimeFormat` a časovou zónou akce, při chybějící zóně s existujícím canonical fallbackem Europe/Prague. Současná `getMinimalisticDateRange()` používá časovou zónu návštěvníka a pro tento nový blok nestačí. Ostatní existující datumové kontrakty nepřevádět plošně.
4. U tlačítka přidat stabilní lokalizovaný stavový text a vazbu `aria-describedby`: pro blueprint bez míst „Pro pokračování vyberte alespoň jedno místo.“ Při povoleném pokračování jej skrýt nebo změnit podle stavu. Stav odvozovat od stejné session, která dnes povoluje tlačítko, nikoli z druhého počítání DOM prvků.

Odlišit blueprint, obecné ticket formuláře, čekací listinu a bezvstupenkovou registraci. Zachovat `FormSession` a `PriceWidget` jako vlastníky výběru a součtu včetně doplňků. Před výběrem je doložená nabídka variant vhodnější než obecné „cena od“, které by mohlo zaměnit doplněk nebo dětskou variantu za běžné vstupné.

**Kompatibilita:** respektovat `header_off`, vlastní hlavičky pořadatelů, embed, čekací listinu a formuláře bez vstupenek. Nezobrazovat duplicitní nadpisy a nevymýšlet datum nebo sál z textu. Starší formulář bez metadat funguje dál.

**Pořadí změny kontraktu:** přidat jen veřejná pole do SQL a ověřit jejich projekci; potom webový konzument. Starý klient neznámá pole ignoruje, nový klient funguje i bez nich. Žádná změna tabulek ani hromadné přepisování starých akcí.

**Ověření:** public SEO SQL kontrakt, `price_widget.test.js`, `form_loading.test.js` a nový cílený test headeru/nápovědy. Čas 18:00 UTC musí v listopadu odpovídat 19:00 v Europe/Prague i při návštěvnickém prohlížeči nastaveném na jinou zónu; zahrnout letní čas a přechod přes půlnoc. Fixture varianty pro vlastní hlavičku, chybějící místo, closed/header_off, embed, waiting a formulář bez vstupenek. Testovací nákup/QR pouze na disposable prostředí, ne na Country bálu.

**Hotovo:** datum/místo jsou viditelné, pokud existují; neaktivní pokračování je srozumitelné; výsledná cena má jediného vlastníka a nic se nezměnilo na rezervacích a platebních side effects.

### 3. Vysvětlit cenu a provoz služby

**Priorita:** P1; implementaci konkrétního ceníku předchází rozhodnutí provozovatele.

**Vlastníci:** `automation/release/organizers/content.json`, `page.html`, `render_content.mjs`, případně `page_definitions.mjs` pro samostatnou stránku ceny.

**Rozhodnutí potřebné od provozovatele:** co kromě založení je zdarma, za co se platí, zda existuje paušál/procento/cena za akci, zda a jak lze uvést kalkulaci pro 200 hostů, DPH, příprava plánku, zahrnutá podpora a další náklady. Není to technický blocker pro ostatní vlny. Konkrétní návrh struktury: **Založení akce: zdarma. Platby QR převodem: bez transakčního poplatku služby. Provoz prodeje a pomoc s přípravou: schválený model + co obsahuje.** Poslední část se publikuje až se skutečnými podmínkami, nikoli s placeholderem nebo vymyšlenou částkou.

**Změny:** vložit krátký blok „Cena služby“ poblíž plateb a propojit FAQ. Oddělit zdarma založený účet/akci, cenu provozované služby, QR převod a dostupnost karet. U individuální ceny uvést alespoň konkrétní rozsah služby a podklady potřebné pro nabídku. Bez schválených čísel nenahrazovat neurčité nacenění vymyšleným ceníkem.

Doplnit stručné FAQ s odkazy do již existující nápovědy: párování plateb, nezaplacené objednávky, hotovost, více kontrolorů, offline ověření a storna. Každá odpověď musí odpovídat aktuálnímu chování a odpovědnosti pořadatele. Citace zákazníků a fotografie jsou volitelný další krok po získání skutečných podkladů; bez nich ponechat pravdivé reference akcí.

**Ověření:** jeden společný obsahový a mobilní průchod; příslušné generator/organizer testy, pokud se změní struktura nebo linky. Netestovat marketingové věty řetězcovými snapshoty. CTA zůstávají „Založit akci zdarma“ a „Domluvit ukázku“.

**Hotovo:** pořadatel rozliší, co má zdarma a za co platí; u zveřejněné částky zná podmínky a rozsah. Pokud částku provozovatel nechce zveřejnit, plán zaznamená toto rozhodnutí a cenový nález zůstane částečně otevřený.

### 4. Přidat malý, dokončený vstup pořadatele z katalogu

**Priorita:** P1 po dohodě o minimálním postupu obsluhy; rozsáhlé automatické přebírání záznamů není první krok.

**Vlastníci v plesuj:** `src/pages/DetailPage.tsx`, `LocalityPage.tsx`, `src/app/App.tsx`, `src/styles/app.css`, `src/domain/config.ts`. Stávající příjem oprav vlastní `ProposalPage.tsx`, `src/domain/submission.ts`, `worker/proposal.js` a `worker/submissions.js`; je dokončený včetně kontaktu, moderace a outboxu.

**Změny:** na mobilní katalogové homepage přidat viditelný textový vstup pro pořadatele vedle podpůrné navigace pod hledáním; nepřecpat již plnou hlavičku seznam/mapa. Na detailu blok **„Pořádáte tuto akci?“** s odkazy **„Opravit údaje“** a **„Založit prodej vstupenek“**. První zůstane existujícím `/navrhnout?kind=correction&edition=<id>`, druhý povede do veřejného vstupu Festappu. Na městské stránce kratší blok **„Pořádáte ples v Břeclavi?“** se stejnou akcí založení prodeje.

Přenos bude mít explicitní kontrakt: `/login?create=1&source=plesy&entry=detail&edition=<veřejné-id>`, pro město `entry=city&city=<canonical-kód>`, pro obecný odkaz `entry=catalog`. Sdílený JS parser první vlny přijme jen tyto hodnoty a omezené formáty ID; Google návrat si zachová tentýž schválený kontext. Přijímač nebere libovolné URL, kontakty ani celý katalogový objekt. První verze zobrazí kontext původu, ale nepřepisuje podle něj draft ani nenárokuje veřejný záznam. Automatické předvyplnění patří až do pozdější samostatné změny.

**Ověření role:** nadále žádná automatická publikace změn. Zachovat stávající povinný neveřejný kontakt, souhlas s odpovědí a redakční ověření zdroje; samostatné Google přihlášení za potvrzení pořadatele nepovažovat. Nevytvářet druhý formulář ani „Převzít správu“ s novým workflow, když pro minimální opravu stačí existující moderace.

**Odstranění:** obecný odkaz bez kontextu v dotčených organizer CTA; skrytý jediný mobilní vstup. Zachovat samostatnou možnost přidat/opraviť ples bez nákupu služby.

**Ověření:** relevantní `tests/detail-actions.test.mjs`, `proposal-form.test.mjs`, test cílové URL a mobilní viditelnosti. Oprava veřejného záznamu bez potvrzení nesmí jít publikovat. Ověřit zachování kontextu při návratu přes autentizaci ve Festappu. Žádný ostrý návrh ani email při vývojové kontrole.

**Hotovo:** pořadatel na mobilu najde obě cesty, rozumí jejich výsledku a žádost má skutečného příjemce. Nelze změnit cizí akci pouhým přihlášením přes Google.

### 5. Zavést minimální vyhodnocení a teprve potom ladit výkon

**Priorita:** P1 pro definici výsledků a zdroje; P2 pro další nástroje a optimalizace bez prokázaného problému.

**Nejprve:** získat přehled už používaných soukromých reportů. Cloudflare veřejné návštěvy jsou existující vlastník návštěvnosti, nikoli funnel pořadatele. Aktuální [oficiální FAQ Cloudflare](https://developers.cloudflare.com/web-analytics/faq/) potvrzuje, že Web Analytics neukládá query strings/UTM a nepodporuje vlastní události. Přidání parametrů do URL tedy samo funnel nevytvoří. Neukládat kompletní query nebo soukromé návratové adresy do analytics.

**Kontrakt:** rozlišit návštěvu nabídky, vstup k založení, autentizaci, vytvořený draft, zveřejněný prodej a první skutečně uhrazenou objednávku. Zveřejnění ani platbu nedokládat klikem v prohlížeči; odvodit je z canonical stavů backendu. Oddělit testy/demo, hosty, nové a existující pořadatele a opakované ročníky. Výchozí report může být ruční a pouze pro oprávněného provozovatele.

**Konkrétní minimální realizace:**

1. Uchovat omezený kontext vstupu v existujícím auth pokračování. Až při skutečném vzniku draftu uložit do jeho stávajících JSON metadat jen `source`, `entry`, případně `edition`/`city` a čas vstupu. Server tyto hodnoty validuje jako neautoritativní metadata; nepředávat je do role či ACL. Finalizer je přenese do omezených metadata nově vzniklé akce, nikoli do veřejné projekce nebo obsahu zpráv.
2. Vytvořit neveřejný agregovaný report z `occasion_setup_drafts.created_at`, `data.finalizedOccasion`, canonical stavu prodeje (`get_occasion_sale_forms_internal`) a existujícího potvrzeného zaplacení objednávky. Plánované otevření ještě není běžící prodej; vytvořená objednávka ještě není uhrazená. Výchozí výstup: počty a podíly dokončení mezi těmito backendovými stavy podle zdroje/období, bez osobních údajů. Při absenci návštěvního jmenovatele jej nenazývat konverzí návštěvníků.
3. Rezervační odkazy na Cal.com doplnit konstantními `utm_source=vstupenky-online&utm_medium=website&utm_campaign=organizer-demo` a odlišit pozici přes `utm_content=hero|pricing|closing`. [Oficiální dokumentace Cal.com](https://cal.com/help/bookings/utm-tracking) potvrzuje ukládání těchto standardních parametrů u rezervace. Parametry neobsahují identitu ani interní cestu. HTML `no-referrer` lze zachovat; není nutné oslabit politiku celé stránky kvůli jedinému odkazu. Skutečné zobrazení zdroje v hostitelském účtu ověřit až při autorizovaném testu rezervace.

Tato varianta opravuje obchodní zdroj bez plošného nového JS trackeru a bez automatických emailů. Doba uchování a rozsah přístupu k metadatům/reportu musí být součástí rozhodnutí před změnou persistence; není důvod přidávat další identifikátor osoby.

**Ověření:** stejný testovací průchod nesmí vyrobit opakovaným callbackem další registraci/draft/platbu ve statistikách. SQL reporty ověřit na disposable datech; bez jmenovatele návštěv nepublikovat „konverzní poměr“. Počet všech účtů Festappu není počet pořadatelů. Nasazení dalšího trackeru nebo automatických zpráv není výchozí součástí této vlny.

**Výkon:** nové měření je hotové, viz důkazy a Z10. Zařadit jako baseline, nyní neprovádět plošné přepisy obrázků/fontů ani další krácení homepage. Pokud pozdější field data nebo stejný laboratorní profil ukážou regresi, nejprve určit konkrétní LCP prvek; aktuálně to byl text, nikoli reference plakátu. Optimalizaci přenosu spojit s doloženým bottleneckem a zachovat češtinu i rozvržení.

**Hotovo:** existuje srozumitelná baseline reportu s definicemi a limity. Případná optimalizace má doloženou příčinu a porovnání, ne pouze jinou příponu souboru.

## Co z auditu nedělat automaticky

- Nevytvářet nový onboarding, CRM a automatické ověřování pořadatelů jen proto, že autor neviděl administraci.
- Znovu nezkracovat celou homepage podle již neplatných 18 obrazovek.
- Nepřepisovat hlavní sdělení, nepřidávat slib reakce do 24 hodin a neposílat každému účtu obchodní zprávy.
- Nepoužívat záznamy katalogu jako reference zákazníků a počet ročníků jako počet získatelných pořadatelů.
- Nezavádět druhý výpočet cen nebo nový zdroj termínů vedle canonical modelu.

## Otevřené vstupy a zbytková rizika

1. Provozovatel musí dodat zveřejnitelný cenový model a skutečnou kapacitu podpory; bez nich nelze dokončit cenový blok ani slíbit ruční obsluhu žádostí.
2. Country bál je skutečně ověřený vzorek nákupního formuláře; nejde o důkaz chyby obsahu všech akcí. Implementace musí respektovat ostatní režimy a vlastní obsah pořadatelů. Místo se musí doplnit v canonical datech tam, kde není; šablona ho sama nevymyslí.
3. Ztráta `create=1` byla reprodukována přes skutečný JS start/complete s mockovaným externím brokerem. Ostrá registrace, skutečný Google provider, doručitelnost emailu, rezervace Cal.com ani platba během tohoto ověření provedeny nebyly. Technické průvodcové a SQL kontrakty byly ověřeny odděleně; nejde o provedený úplný browser E2E nákup.
4. Soukromé metriky, backendové reporty a skutečný obchodní přínos katalogu nejsou dostupným důkazem. Neplánovat procentuální růst ani pevné termíny na základě odhadů externisty.
5. Před realizací aktualizovat base main a produkční verzi. Dřívější pracovní strom `/Users/miakh/source/festapp` je výrazně odlišný od canonical main; nepřenášet z něj celé soubory přes novější implementaci.

## Dokončení a nasazení

Každá vlna končí doloženým výsledkem uvedeným výše; schválená technická realizace nemusí čekat na všechny obsahové podklady. Nasazení plánovat po ucelených změnách s datem v reportu, aby šlo odlišit stav před a po.

Pro Festapp použít po výslovném zadání realizace běžné targeted kontroly, případné databázové změny jako canonical SQL a pouze autorizovaný tenant. Produkční web sestavit lokálně a nasadit přes `automation/deploy_direct.sh`, se zachováním manifestu, drift kontroly, ancestry a live probes. Katalog má vlastní release pravidla; nasazení jednoho repozitáře nesmí předpokládat nasazení druhého.

Obsahový blok bez podkladů zůstává otevřený, nikoli vyplněný placeholderem. K uzavření právě schválené implementace je třeba doložené pokračování autentizace, dokončené katalogové vstupy a ověřený příjem dat Cloudflare. Cenové rozhodnutí, formulář a rozšířené měření jsou odložené. Z7 a Z10 nevyžadují změnu produktu, pokud nové podklady její potřebu nepotvrdí.


## Výsledek schválené implementace

- Festapp pracovní strom: `/Users/miakh/source/festapp-login-cta-release-20261026`, base main `b3fc58ea2`. Katalog: `/Users/miakh/source/plesuj-organizer-entry-20261026`, base main `dd174ff`.
- Vytvoření akce má jeden explicitní záměr a sdílený creation helper; běžné přihlášení zůstává oddělené. Google zachovává `create=1` i přes ověření existujícího účtu. Reload interního handoffu vrací uživatele do stejného webového vstupu.
- Katalog má jeden nový sdílený blok pro homepage, město a detail. Původní samostatný detailový odkaz na opravu byl přesunut do tohoto bloku; moderovaný příjem a identita ročníku zůstaly zachované.
- Ověřeno: 87 unikátních webových testů (původní batch 86 a jeden doplněný test skutečného bootstrapu), 7 Flutter testů, 10 katalogových testů a TypeScript typecheck. Dart analyzátor nenalezl chyby ani warnings; hlásil 19 info diagnostik ve zkoumaných stávajících modulech.
- Tři statické stránky katalogu prošly izolovaným prohlížečem při šířkách 390 a 1280 px: bez vodorovného přetékání, vstup viditelný, odkazy nejméně 44 px vysoké. Mechanická design kontrola: bez nálezů.
- Cloudflare: po jednom beaconu na každém webu, přechod katalog -> Praha bez reloadu a bez druhého beaconu. První pokus zablokoval místní DNS (doména beaconu -> 0.0.0.0). Pouze samostatný headless testovací prohlížeč dostal dočasné resolver pravidlo; systémové DNS ani uživatelův prohlížeč nebyly změněny. Cloudflare následně přijal čtyři skutečné RUM POST požadavky s HTTP 204. Nejde o readback soukromého dashboardu ani důkaz měření registrací a prodejů.
- Google broker a přijetí relace jsou v integračním testu fixture; skutečný klientský start, callback, account proof a návrat byly vykonané. Ostré účty, emaily, rezervace a platby nebyly vytvořeny. Databázový kontrakt se neměnil.
- Uživatel následně výslovně zadal dokončení a merge do main obou repozitářů. Výsledný stav a SHA budou ověřeny při publikaci. Produkční deploy zůstává samostatným krokem.

Podrobné dočasné logy: `/tmp/festapp-organizer-js-tests.log`, `/tmp/festapp-organizer-bootstrap-tests.log`, `/tmp/festapp-organizer-flutter-tests.log`, `/tmp/plesuj-organizer-tests.log`, `/tmp/plesuj-organizer-typecheck.log`. Důkaz Cloudflare a statických náhledů je přiložen v `docs/plans/organizer-entry-verification-2026-10-26.json`.
