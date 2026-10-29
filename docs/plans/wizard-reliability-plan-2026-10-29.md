# Spolehlivé dokončení průvodce a náhledy e-mailů bez smyček

Datum: 2026-10-29
Stav: lokálně realizováno a cíleně ověřeno; produkční vydání neprovedeno. Výsledek: [receipt](../operations/wizard-reliability-RESULT-2026-10-29.md).
Ověření při realizaci: standard; při nasazení navíc povinné produkční brány
Rozsah tenantů: pouze `prod/festapptickets` / vstupenky.online
Autorizace: uživatel zadal realizaci execution promptu. Implementace a izolované lokální ověření jsou povolené; commit/push a produkční vydání tím nejsou provedené.

## Cíl

Každý nabízený vzhled půjde dokončit. Běžný průvodce nevyžaduje ruční řízení čísel VS; použije stávající kanonickou automatickou politiku a přidělení ponechá backendu. Náhledy při rychlých úpravách a souběžném ukládání nevyvolají nekonečné opakování požadavku, nezatěžují backend a nikdy neukážou výsledek starší revize jako aktuální. Uložené koncepty, vlastní šablony a již vytvořené akce zůstanou zachované.

Autoritativní výchozí důkazy: [UI QA a reprodukce](../operations/wizard-ui-qa-2026-10-29.md), [sanitizované artefakty](../operations/wizard-ui-qa-2026-10-29/). Zkoumaný produktový kód: `2095a9ba49bf1a7cd3a76f9e5be98d8407e95825`, produkční verze `0.20.445+950`, tenant commit `ed1554e14a7ab0e8d79abd390f193e4914b17fcd`. Před realizací fetch aktuálního main a vyhodnocení relevantního posunu; tento SHA není pokyn pracovat ze zastaralého základu.

## Potvrzené skutečnosti

| Fakt | Důkaz | Dopad |
| --- | --- | --- |
| Ocean selhal až při vytvoření na `Unsupported shared font` | UI QA A, `occasion_setup/appearance.sql:16` | Platná nabídka UI neodpovídá backendu |
| 11/18 předvoleb odmítne stejný normalizátor | `palette-validation.txt` | Neopravovat jen jednu předvolbu |
| UI má 10 přesných mapování fontů; SQL zná pouze 3 | `OccasionSetupAppearance.fonts`, SQL CASE v normalizátoru | Doplnit celý současný kontrakt a odstranit jeho ruční rozcházení |
| Existuje kanonický immutable font catalog, seed assetů a generátor | `automation/generate_ticket_font_catalog.mjs`, `supabase/functions/_shared/ticket-assets/font-catalog.json`, `database/seeds/ticket_font_assets.sql` | Nevymýšlet druhý registr fontových souborů, nepřepínat historické ID na jiné bajty |
| V testu bylo výslovně přepnuto z výchozího Random na volitelné Sequence; teprve tato neúplná konfigurace selhala | QA B, `form_settings.sql:133-135` | Výchozí generování není rozbité; běžný wizard nemá vystavovat ruční řízení řady |
| `FormVariableSymbolSettings` nemá validator; wizard přímo mutuje `formDraft.data.variable_symbol` | `form_variable_symbol_settings.dart`, `occasion_setup_page.dart:2594` | Odebrat nízkoúrovňový policy editor z wizardu, validaci ponechat u pokročilého authoringu |
| VS přiděluje kanonický SQL allocator; chybějící policy má výchozí Random | `eshop_payment_references/allocation.sql:reserve_order_payment_reference_internal`, `eshop/generate_payment_variable_symbol.sql` | UI nesmí počítat další VS, spravovat watermark ani předem rezervovat hodnotu |
| Preview při změnách vyvolalo velmi mnoho konfliktů revize | lokální log: 439929 `Draft revision conflict` ve vybraném 4min okně | Nejvyšší priorita; nejdřív omezit a diagnostikovat opakování |
| Preview používá pro aplikační nesoulad revize SQLSTATE 40001 | `occasion_setup/email_preview.sql:28` | Aplikační konflikt je smíchaný se skutečnou serializační chybou transakce |
| 40001 pro aplikační konflikty používají také save/delete/finalize a kontrola fingerprintu účtu v této komponentě | `occasion_setup/drafts.sql`, `finalize.sql` | Auditovat tento omezený okruh; neopravit jen jeden viditelný výskyt |
| `_flush` již má single-flight `_pending`; preview widgety již mají generační guardy | `_OccasionSetupPageState` v `occasion_setup_page.dart`, `occasion_setup_email_preview.dart`, `ticket_delivery_preview.dart` | Zachovat existující vlastníky; nepřidávat druhý systém ukládání ani globální frontu |
| Přímé RPC a Edge preview jsou dva reální konzumenti | `_loadEmailPreview`, `occasion-setup-email-preview/handler.ts` | Testovat a opravit oba vstupy |
| Tři akce po zadání podporovaných hodnot vznikly a výsledky odpovídaly uloženým volbám | QA A/B/C | Oprava nesmí rozbít funkční tvorbu/kopii/obnovu konceptu |
| Relevantní funkce QA backendu a produkce mají shodné definice | `backend-identity.json` | Font/VS nálezy nejsou jen odlišností lokálního SQL |

Neprokázané: která vrstva způsobila každý z opakovaných pokusů preview. Počet DB chyb není počet HTTP požadavků. Hypotéza o automatickém opakování transakce kvůli 40001 vyžaduje W0; nesmí se vydávat za hotovou diagnózu.

## Hranice a závazné invarianty

1. SQL zůstává autoritou validace, oprávnění, finální transakce a receiptů. Flutter validuje dříve kvůli srozumitelné opravě údajů.
2. Náhled je pouze čtení. Nesmí odesílat e-mail, měnit koncept, vytvářet akci ani zvyšovat jeho revizi. Flush legitimních lokálních změn zůstává u existujícího vlastníka konceptu.
3. Každý požadavek preview používá neměnnou dvojici ID/revize potvrzenou uložením a neměnné parametry náhledu. Starý výsledek se nepoužije po nové editaci.
4. Aplikační nesoulad revize/fingerprintu musí skončit konečným konfliktem, ne tranzientním kódem vybízejícím ke slepému opakování. Konflikt nikdy automaticky nepřepíše cizí změny.
5. Kopie formuláře nesmí změnit zdroj. Vypnutí vstupenek nesmí zakázat přihlášku; quantity v tomto režimu zůstává 1.
6. Všechny současné nabídnuté fonty musí mít přesnou shodu family -> immutable face ID mezi UI a SQL. Unknown font/nesouhlas uloženého layoutu se dál odmítá. Historické `preserveSource` layouty zůstávají podporované.
7. Nový formulář ve wizardu použije stávající výchozí Random bez povinného počátečního čísla. Backend vlastní konkrétní přidělení, účetní namespace, kolize i watermarky. Při kopii zůstává explicitní platná policy zachovaná. Volitelná Sequence v pokročilém editoru vyžaduje dolní mez 1-9999999999; tato mez není slibem konkrétního příštího VS.
8. Neprovádět backfill, mazání konceptů ani plošné úpravy šablon. Existující payloady se musí dát znovu otevřít a opravit běžným UI.

Mimo rozsah: změna ticket/PDF rendereru, sjednocení celé aplikace kolem nového frameworku, skutečné rozesílání, Stripe/bankovní synchronizace, ostatní tenanty, přegenerování všech fontů či nahrazení jejich bajtů. Ilustrační částka 800 Kč v ticket preview není tímto plánem prohlášena za potvrzenou čtvrtou chybu; návrh případné změny ilustračních dat vyžaduje samostatně ujasnit kontrakt náhledu.

## Rozhodnutí a otevřené body

- **D1:** Pořadí W0 -> W1 -> W2 -> W3 -> W4. Nejprve bezpečné chování při konfliktu, potom dokončování vzhledů a validace VS, nakonec společná UI regresní kontrola.
- **D2:** Cílový aplikační konflikt pro zasažené wizard RPC bude PostgREST `PT409`, s konečnou HTTP 409 a zachováním stávajícího bezpečného error envelope. Změna se omezí na prokázané aplikační konflikty; skutečné PostgreSQL serializační chyby se nepřepisují.
- **D3:** Výběr deseti setup fontů bude jeden malý sdílený manifest odkazující na existující font catalog. Generovat se z něj budou pouze mapování pro Dart a SQL. Nezakládat nový registr assetů ani měnit jejich identitu.
- **D4:** Z wizardu odstranit selector Random/Sequence a ruční Starting Number. Nový formulář spoléhá na existující default backendu. Pokročilý editor nadále umí explicitní policy; při kopii ji bez pokynu nepřepsat. SQL allocator ani aktivace organizací se v této opravě nemění.
- **D5:** Refaktor je součástí realizace tam, kde odstraní více vlastníků stejného pravidla: samostatný preview modul, jednotná projekce platební konfigurace a generovaný katalog vzhledů. Nedělat plošný přepis celého wizardu ani mechanické dělení dlouhého souboru do souborů bez jasné odpovědnosti.
- **A1 - vyřešeno W0:** Bounded reproduktor bez Flutteru: 0 frontend invokací, 1 HTTP RPC, 957 databázových konfliktů za 261 ms, timeout. Tvrdé zastavení vlastněného REST containeru ukončilo pokus. Jediné přímé SQL volání vyvolá jediný konflikt. Amplifikace tedy existuje pod HTTP hranicí, nikoli pouze ve frontendovém scheduleru. Po PT409: 1 HTTP, 1 DB konflikt, konečná 409 za 21 ms; explicitní nové čtení aktuální revize vrací 200.
- **A2:** Nejprve vydat kompatibilní Edge wrapper a klientské rozpoznání, potom SQL PT409. Starý přímý Dart caller dostane PT409 jako konečnou chybu (409 není retryable SDK status); jeho původní `_drain` ponechá `_dirty=true`, nastaví `saveFailed` a nepokračuje v drainu. `_save` s chybou neplánuje automatický debounce. Starý finalizer konflikt neinterpretuje jako úspěch ani automaticky neopakuje. Změny veřejných chybových kódů vyžadují kompatibilní pořadí nasazení. Starší klient při novém konfliktu musí selhat bezpečně, nikoli znovu odesílat či ztratit koncept. Pokud tento předpoklad u konkrétního calleru neplatí, upravit postup v plánu před publikací.
- **Blokace plánování:** žádná. Produkční zápisy a vydání nejsou nynějším požadavkem na plán autorizované; naplánované kroky nasazení čekají na pokyn k realizaci/vydání.

## Architektonické hranice refaktoru

Refaktor má uklidit skutečné odpovědnosti, nikoli jen přemístit řádky:

- **Preview modul** (např. `setup_email_preview_coordinator.dart`): vlastní přípravu neměnného request contextu, sdílení totožných rozpracovaných čtení, omezené chování při konfliktu a životní cyklus požadavků. Veřejný vstup popisuje druh náhledu a jeho parametry; widgety nedostávají k sestavení RPC mutable `_stored` ani nepočítají revize. Modul používá jediný existující store/flush callback, nevlastní druhé ukládání. `OccasionSetupPage` propojuje editace a modul, jednotlivé preview widgety zobrazují stav a emitují user intent. Přesný interface dopracovat po W0 podle prokázaného souběhu.
- **Platební konfigurace**: wizard vybírá způsob platby, účet a uživatelské podmínky. Autoritativní policy VS a její normalizace zůstávají v současném forms/payment-reference kontraktu. Žádná lokální sekvence, nový čítač ani odvozování next VS v Dart. Pokročilý formulářový editor je výslovně pojmenované místo volitelné změny policy.
- **Vzhledy**: immutable font catalog vlastní identitu/bajty; malý výběrový manifest vlastní nabídku setupu a generuje mapování pro UI/SQL. Žádné dva ruční seznamy, žádná druhá fontová databáze.
- **Draft lifecycle**: dosavadní save owner a transakční finalize/receipt se zachovají. Není důvod přidávat V2 store nebo druhé mutation API. Chyby se klasifikují na jediné hranici a UI dostane rozlišený stav, ne textovou heuristiku.

Refaktor se prokazuje testy na veřejném chování: souběžné náhledy, zachování editů, výsledné vytvoření, zdroj nezměněný kopií a kanonické přidělování. Samotný počet nových tříd není kritérium čistoty.

## W0 - Krátká řízená reprodukce konfliktu

**Změny/provedení:** Obnovit jen izolovaný QA projekt nebo vytvořit nový, ověřit loopback, paused email/worker unset/cron off. Nepoužívat produkci k reprodukci zátěže. Vytvořit/obnovit koncept přes UI, změnit Reply-to a tón, otevřít preview během uložené změny. Zachytit bezpečné metriky: počet UI loader invokací, počet HTTP RPC, počet DB konfliktů a čas do konečné odpovědi. Žádné tokeny ani celé šablony do logu.

Doplnit jedno cílené HTTP čtení preview se zastaralou revizí přes skutečný PostgREST, s krátkým timeoutem a tvrdým limitem pokusů. Kontrastovat s jediným SQL voláním stejné funkce. Tím rozlišit frontendové plánování od transportních/transakčních retry. Vyzkoušet dva současné preview konzumenty i druhé okno editující tentýž koncept. Omezit pokus na sekundy, nepokračovat ve stovkách tisíc chyb.

**Výstup:** Jeden rychlý red-capable reproduktor skutečné hranice a zaznamenaná vrstva opakování. Pokud opakování vzniká i mimo 40001, W1 musí zahrnout tento konkrétní scheduler/retry caller. Žádná změna globálního PostgreSQL/HTTP nastavení kvůli lokálnímu business konfliktu.

## W1 - Konečný konflikt a konzistentní náhled

**Konkrétní změny:**

- `database/functions/occasion_setup/email_preview.sql`: aplikační nesoulad revize přesunout z 40001 na PT409; obě stávající signatury dál delegují stejnému vlastníkovi. Zachovat authorization a finalized-draft guard.
- Omezený audit všech aplikačních 40001 v `occasion_setup/drafts.sql` a `finalize.sql`: stejný kontrakt pro změněný koncept a změněný bankovní fingerprint, s aktualizací jejich konkrétních klientských callerů. Neprovádět repo-wide nahrazování 40001. Zkontrolovat existující obsluhu v `_drain`, store a příslušných Edge wrapperech.
- `supabase/functions/occasion-setup-email-preview/handler.ts`: PT409 mapovat na stávající bezpečný konflikt 409, 42501 dál 403 a neplatný vstup 400. Nepřevádět oprávnění nebo konflikty na nekonečně opakovanou 503.
- `occasion_setup_page.dart:_loadEmailPreview`: po úspěšném `_flush()` zachytit ID, potvrzenou revizi a preview parametry do neměnného request contextu. Nenechat souběžné spotřebitele kombinovat starý snapshot s novou mutable `_stored` revizí.
- Vytvořit výše popsaný preview modul a přesunout do něj skládání požadavku i jeho lifecycle ze state stránky. Stejnou revizi a parametry sdílet při současných totožných čteních. Nesmí vzniknout nový save owner, globální cache ani trvalý cache preview. Klíč zahrnuje revizi, typ zprávy, delivery mode a sample count. Různé typy zpráv nesloučit do nesprávného výsledku.
- Zachovat existující generace/debounce v `occasion_setup_email_preview.dart` a `ticket_delivery_preview.dart`. UI regrese navíc ukázala, že asynchronní aktualizace `communicationDefaults` zneplatní katalog během jeho úvodního čtení; katalog proto plánuje změněný detached snapshot s 300ms debounce a generační ochranou. Pouhý rebuild ani konečný konflikt bez nové editace další read neplánují. Po konfliktu skončit zobrazenou chybou/Retry; nepouštět automatický řetězec reload -> flush -> reload bez nové editace či explicitního opakování. Reálná další editace smí vyžádat nový náhled.
- Potvrzený reload používá existující `_formEpoch` také pro formulářové ovladače komunikace a platebních lhůt. UI test odhalil, že bez nového klíče mohl po potvrzeném zahození lokálních editů fokus vrátit starou controller hodnotu; uložená data se nepřepsala.
- Tlačítko Retry nejprve získá aktuální potvrzenou revizi skrze existující store/flush kontrakt. Cizí změnu nabídne znovu načíst a ponechá bezpečně lokální draft; žádný tichý overwrite ani automatické vytvoření akce.

**Kompatibilita/migrace:** Bez změny parametrů RPC a bez datového backfillu. Nová forward SQL migrace z kanonických zdrojů zachová ACL, search_path i související granty. V přechodu klient rozpozná starý 40001 i PT409; tato omezená kompatibilita je pro již běžící backend/klienty a musí být explicitně otestována. Tranzientní PostgreSQL 40001 nezměnit na aplikací tvrzený nesoulad revize. Nepřidávat V2 endpoint.

**Validace:** SQL kontrakt stale revision/foreign user/finalized, Edge `preview_test.ts` error mapping, Flutter test se dvěma preview konzumenty, opožděnou odpovědí a novou editací. Povinně W0 HTTP reproduktor: konečná 409 bez amplifikace DB chyb, bez neomezeného klientského retry. Testovat i skutečný nový úspěšný Retry, nikoli pouze počítadlo mocku.

**Hotovo:** Neplatná revize nevyvolá násobení požadavků, starý náhled nepřebije nový, dva totožné konzumenti neduplikují tentýž read a konflikt neztratí žádný lokální edit ani vytvoří vedlejší efekt.

## W2 - Všechny nabízené vzhledy podporované serverem

**Konkrétní změny:**

- Přidat malý manifest současného výběru deseti setup fontů (např. `automation/tickets/setup-appearance-fonts.json`) se stávajícími přesnými face ID. Metadata/bajty fontů dál vlastní existující immutable catalog. Tři historické builtin identity zůstanou zachované.
- Úzce zaměřený generátor (např. `automation/generate_setup_appearance_fonts.mjs`) ověří každý odkaz proti `font-catalog.json` a vytvoří `occasion_setup_font_ids.dart` a private SQL resolver v `database/functions/occasion_setup/appearance_fonts.sql`. Poskytnout `--check` pro byte-for-byte drift. Není důvod regenerovat celý Google Fonts catalog.
- `OccasionSetupAppearance.fonts` odkáže na generované mapování. `normalize_occasion_setup_appearance_internal` použije generovaný resolver místo ručního CASE tří fontů. Private helper revokovat pro veřejné volání; nepřidávat SECURITY DEFINER bez potřeby.
- U ticket/PDF varianty dál kontrolovat skutečnou shodu fontId a stylu uloženého layoutu. Samotné přijetí rodiny ve formuláři bez odpovídajícího ticket layoutu není dokončená oprava. U inline QR zachovat dosavadní výjimku z PDF layoutu.
- Původní konkrétní hodnoty v konceptech se nepřepisují. Ocean i ostatní již uložené nepodporované koncepty musí po opravě projít bez ztráty dalších údajů. `custom/preserveSource` zachová historické zdroje.

**Migrace:** Nová forward migration vytvoří resolver před normalizátorem a přenese potřebné ACL. Žádná nová fontová tabulka, fontové soubory, síťové font downloads či backfill. Ověřit, že na cílovém backendu již existují katalogové záznamy použitých přesných ID; pokud ne, doplnit jen chybějící kanonická immutable seed data v téže řízené migraci.

**Validace:** Rozšířit existující `occasion_setup_appearance_test.dart` (již kontroluje 10 fontů proti katalogu) a `database/tests/occasion_setup/appearance_test.sql`: celých 18 předvoleb, všech 10 fontů, aplikace bez vstupenek, PDF a inline QR. Zahrnout unknown font a neshodný layout jako negativní testy. UI skutečně dokončit Ocean a jeden jiný dosud odmítaný font, plus Gala pro regresi podporované varianty.

**Hotovo:** 18/18 předvoleb a 10/10 fontů má klient/server paritu; libovolné neznámé ID je stále odmítnuto a uložený formulář/ticket používají zvolený font.

## W3 - Kanonická politika VS bez ručního řízení v průvodci

**Upřesnění původního nálezu:** Prázdné počáteční číslo se objevilo až poté, co test výslovně přepnul Random na Sequence. Běžný výchozí průchod jej nevyžaduje. Konkrétní VS už přiděluje SQL; registry chrání namespace přijímacího účtu a kolize, Sequence používá dolní mez spolu s dosavadním watermarkem. Oprava tedy není zavést povinné číslo pro všechny uživatele.

**Konkrétní změny:**

- `occasion_setup_page.dart:_payments`: odstranit `FormVariableSymbolSettings`, jeho import a wizard callback, který ručně přepisuje `formDraft.data.variable_symbol`. Běžný průvodce nemá vystavovat interní strategii číslování.
- Nový formulář bez explicitní policy ponechá výchozí chování současného serveru: Random. Nepřidávat vlastní klientskou domněnku o příštím čísle, rezervaci při tvorbě konceptu ani druhý default určovaný podle účtu/dne.
- `form_settings.sql` zůstává jediný autoritativní normalizátor explicitní policy; allocator v `eshop_payment_references/allocation.sql` dál přiděluje skutečné hodnoty při checkoutu ve stávající transakci. Neprovádět změnu algoritmu, registry aktivace, vazby na BankSync ani namespace.
- Kopie formuláře s platnou explicitní Sequence policy ji zachová. Automaticky ji nepřepínat na Random, neresetovat starting number a neodvozovat nový watermark. Již existující koncept se nedestruktivně obnoví.
- Starý koncept či kopírovaný zdroj s neplatnou explicitní policy se nesmí potichu normalizovat na jinou strategii. Zjistit ji pomocí stávajícího authoring/normalizačního kontraktu před závěrečným Create a nabídnout konkrétní opravu v pokročilém nastavení formuláře. Preferovat existující editor v rámci konceptu; nevyžadovat úpravu původního zdroje ani nevytvářet akci jen pro opravu konceptu.
- `FormVariableSymbolSettings` zachovat jako pokročilé nastavení běžného formulářového editoru a případné výslovné opravy legacy konceptu. U skutečné ruční volby Sequence doplnit přímou validaci rozsahu 1-9999999999. Je-li třeba čistá klientská validační funkce, sdílet ji v forms doméně pro existující authoring callery; nevytvářet z ní nového vlastníka allocation pravidel.
- Oddělit projekci platební konfigurace od renderingu stránky. Výsledkem má být jediná serializace formulářových settings, nikoli paralelní změny `formDraft`, `_inlineFormBundle` a další lokální kopie policy. Zachovat podporu bankovní i Stripe větve.

**Migrace:** Žádný backfill, reset řady ani plošný přepis formulářů. Backend stále odmítá neplatnou explicitní policy. Pokud bude nutné zpřístupnit existující validační owner před finalizací, použít autorizovaný authoring boundary bez nového business implementátoru a bez vedlejších efektů; přesný nutný podpis před přidáním zapsat do plánu.

**Validace:**

- Nový placený koncept bez vstupu k VS se vytvoří; jeho první syntetický checkout přes skutečný lokální formulář získá VS ze současného kanonického allocatoru.
- UI wizard nikde v běžném toku nenutí počáteční číslo. Bank/Stripe volba tuto skutečnost nemění.
- Kopie zdroje s Sequence zachová policy; zdrojový formulář zůstane nezměněný a allocator bezpečně respektuje existující namespace/obsazené hodnoty. Použít současné payment-reference testy místo budování nového registru v testu.
- Pokročilý editor: missing/null/0/1/9999999999/10000000000/necelé číslo, přepnutí Random/Sequence, návrat mezi kroky a znovuotevření. SQL negativní test zůstává.
- Starý neplatný koncept dostane konkrétní možnost opravy před Create; po opravě dokončení projde bez ztráty ostatních údajů.

**Hotovo:** Běžný uživatel průvodce nemusí chápat počáteční číslo řady. Přidělování zůstává kanonické a explicitní existující konfigurace se neztrácejí. Pokročilá ruční volba nemůže dojít k obecné chybě až při finálním vytvoření.

## W4 - Společné ověření a příprava jediného vydání

Spustit jeden cílený finální batch na konečných zdrojích, neopakovat již prošlé testy bez změny vstupů:

- Flutter: relevantní appearance, communication/email templates, preview concurrency a story/VS suites; skutečná test discovery je podmínkou. Jeden Flutter proces na pracovním stroji, `--concurrency=1`.
- Core: příslušné nové forms testy, `fvm dart test` v `packages/festapp_core`.
- SQL: `node web_client/scripts/run_db_tests.js database/tests/occasion_setup/appearance_test.sql` proti disposable DB; stejným runnerem spustit `email_preview_test.sql`, `draft_email_templates_test.sql`, `finalize_test.sql` a `sales_test.sql` v tomto adresáři podle dotčených kontraktů. Ne spouštět produkční fixtures.
- Edge: `deno test` s existujícími per-file permissions pro `supabase/functions/occasion-setup-email-preview/preview_test.ts` a dotčené kontrakty. Ověřit obě chyby i úspěch, ne pouze HTTP 200.
- Generated mapping `--check`, zdroj/migrace parita a targeted analyzer pouze dotčených Dart souborů.
- Skutečné UI zopakuje A/B/C z QA, obnovu konceptu po reloadu, rychlé změny Reply-to/tónu/šablony s opožděným preview, souběžné okno, původně chybné dokončení vzhledu, automatický VS bez ručních vstupů, opravu legacy explicitní policy a návrat na výchozí e-mailové hodnoty. Vlastní šablonu ověřit po znovuotevření i v uložené akci. Focus/blur přístupnostních proxy nesmí být nahrazen údajnou změnou modelu; datetime picker není prosté input.fill.
- E-mail queue paused, žádný worker, syntetické adresy. Reálné doručení se nepřidává automaticky do této opravy.

Výstupem je aktualizovaný QA záznam se zdrojem/migrací, časy a počty requestů a uloženými výsledky, plus jasně označené limity externích flow. Nepsat dlouhý nový testovací framework pro tři konkrétní chyby.

## Nasazení a rollback po samostatném pokynu

1. Pracovat v čistém worktree z aktuálního main, zachovat rozpracované integrace a cizí změny v původním pracovním stromu. Hlavní checkout QA vznikl před aktuálním origin/main; nepřebírat jej jako základ automaticky.
2. Změny chybových kódů nejprve připravit jako kompatibilní rozpoznání na klientu/Edge. Při implementaci explicitně ověřit staršího klienta proti novému PT409: musí skončit bezpečnou chybou a zachovat lokální data. Pokud bezpečná kompatibilita neplatí, změnit pořadí na klientské rozšíření před SQL kontraktem a připravit tomu odpovídající dvě řízené fáze; žádný neprokázaný předpoklad.
3. Forward SQL migrace z kanonických zdrojů, žádné přepisování již aplikovaných migrací ani kopírování celého historického ticket-email assembleru, který zahrnuje i nedotčené funkce. Použít repository function extractor / úzký assembler s explicitním seznamem dotčených funkcí a helperu.
4. Při schválené produkční realizaci ověřit activation/tenant/org a SSH cílový backend podle `festapp-backend-access`; migrovat s kontrolou digestů a ledgeru. Pro Edge reload dodržet pauzu/drain e-mailu, kanonický restart existujícího containeru a worker health před obnovením. Neprovádět ad-hoc docker compose rekreaci.
5. Vydat web jen na `prod/festapptickets`, s kanonickou main ancestry, tenant drift kontrolou a navýšenou verzí. Repo pravidla vyžadují lokální Flutter/web build a `automation/deploy_direct.sh`, nikoli dispatch GitHub Deploy. Rutinní release delegovat levnějšímu subagentovi podle AGENTS.md, až bude přesný ověřený source SHA zmrazený.
6. Ověřit živou verzi/assets/legal a omezený běžný wizard smoke. Žádná zátěžová reprodukce na produkci. Ověřit, že běžné preview nedává trvalé konflikty. Pořizovat jen task-owned syntetický koncept v předem určené testovací jednotce; nevytvářet veřejnou akci bez tohoto provozního rozsahu.

Rollback font/VS části nesmí vrátit uživatele k další ztrátě platně uložené volby. Zachovat rozšířený font validator a čtení existujících payloadů. PT409 se po nasazení nevrací na aplikační 40001 jen kvůli UI rollbacku; zachovat bezpečnou hranici a rollbackem UI pouze případně přijít o přesnější hlášku. Neměnit již vytvořené akce ani receipt historii.

## Co odstranit a co zachovat

| Dosavadní cesta | Výsledný stav | Důkaz |
| --- | --- | --- |
| Ruční CASE tří fontů v appearance normalizátoru | Odstranit, používat generovaný resolver současného výběru | generated drift + 18/18 SQL/UI parita |
| Druhá ruční kopie deseti font IDs | Nepřidávat | jediný subset manifest odkazuje do existujícího katalogu |
| Aplikační revision/fingerprint conflict jako 40001 ve vymezených wizard funkcích | Nahradit PT409 | bounded scoped rg a HTTP regresní test |
| Starší klient/backend rozpoznání 40001 | Výslovně omezená provozní kompatibilita, nikoli nový endpoint nebo nekonečný retry | compatibility test při pořadí nasazení; skutečné SQL serialization zůstávají odlišitelné |
| Duplicitní preview čtení stejné uložené revize | Sdílení čtení u jediného preview modulu, využívajícího současný save owner | test se dvěma konzumenty |
| Selector a ruční mutace VS v běžném wizardu | Odstranit; zachovat pokročilé nastavení a explicitní copy policy | UI bez povinného čísla, lokální checkout, source-unchanged test |
| Save vlastník `_flush/_pending`, authorization, receipts | Zachovat | concurrency/auth/finalize regresní testy |
| Schéma/data konceptů, zdrojové formuláře, historické font assets | Zachovat beze změn | A/B/C a source-unchanged assertions |
| Dočasné debug logy, testovací JS hooky, vlastněné servery | Odstranit/ukončit na konci | čistý diff, přehled task-owned procesů |

## Podmínky dokončení

- [x] Původní náhledový reproduktor skončí v omezeném čase bez amplifikace; nová editace i ruční Retry fungují.
- [x] Aplikační konflikt neztratí koncept a nezpůsobí vedlejší účinek; foreign user stále nedostane preview.
- [x] Všechny současné nabídky fontů projdou a neznámé/neshodné fonty dál neprojdou.
- [x] Nový wizard nepotřebuje ruční číslo VS; konkrétní VS přidělí kanonický backend při checkoutu. Platná copy policy se zachová a neplatná legacy policy má jasnou opravu před vytvořením.
- [x] Preview orchestrace, platební projekce a fontová nabídka mají po jednom zřetelném vlastníkovi; žádné další ukládání, registry ani paralelní serializace.
- [x] A/B/C přes skutečné UI odpovídají uloženým výsledkům; vlastní šablona i návrat na inheritance fungují.
- [x] Kanonické SQL, nová migrace, generované soubory a cílené testy se shodují.
- [x] Produkční stav je buď ověřeně vydán v autorizovaném rozsahu, nebo přesně uveden jako dosud neprovedený. Samotné napsání opravy či push nejsou nasazením.
