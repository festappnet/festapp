# PR #752: čisté vlastnictví souhlasu a verzovaný přechod měření

Datum: 2026-11-07  
Stav: lokálně realizováno a ověřeno; publikace a produkce neprovedeny  
Ověření: standard - veřejný kontrakt, kontaktní údaje, lifecycle a SQL migrace.

## Výsledek a autorizace

Dokončit stejné PR https://github.com/festappnet/festapp/pull/752 tak, aby jeho deklarovaný produktový záměr fungoval s jednoznačným kontraktem, jediným vlastníkem účinné volby, úplným cleanupem a prokazatelným přechodem mezi verzemi. Tento dokument autorizuje návrh, nikoli provedené změny. Následné zadání execution promptu opraví lokální implementaci a testy. Publikace, merge, produkční migrace a vydání #752 vyžadují samostatné zadání; autorizace vydání #749 se na #752 nepřenáší.

Zachovat deklarovaný záměr PR: na způsobilém formuláři se runtime spustí i bez souhlasu; volba řídí Consent Mode. Konverze purchase/generate_lead přenášejí pouze normalizovaný e-mail a E.164 telefon kupujícího také při odmítnutí. Nezaměňovat tento úmyslný produktový záměr za náhodnou chybu. Povolit jej skutečně v produkci je samostatné rozhodnutí při vydání. Google Consent Mode neizoluje kontakty před libovolným kódem pořadatele.

Do rozsahu patří všech pět nálezů hlubokého review Astry: obnova starého souhlasu, heartbeat po zániku záznamu, zastaralý nested consent ve změnové události, chybějící sémantická revize/kompatibilita a nejasné consent_required. Zahrnout i související zastaralé disposery a Klaro subscriptions. Nevytvářet nový obecný event/workflow framework, druhý policy engine, DB kopii kontaktů ani konfigurátor paralelních Basic/Advanced implementací.

## Pevné body a důkazy

- Zkoumaný PR head: fa427b9835771b21ad73dc040c67bccb90d41b12. Review worktree: /Users/miakh/source/festapp-review-752, detached HEAD; dokumenty jsou zatím lokální.
- Původní review base: 94ba7063c6efac25435121ee2fa7305aae82b7b9. Při přípravě plánu je main již 99dc29ae7f664796f6d1a9916d360ca28535411e: obsahuje #749 a #754 s opravou absolutních storage deadlines. Při realizaci znovu fetch; aktuální stav má přednost. PR #752 je vůči novému main konfliktní.
- Hluboké review Astra Medium: /tmp/festapp-pr752-astra-deep-review.md. Dokument je doplňkový důkaz; rozhodnutí a povinné opravy jsou úplně uvedeny zde.
- /tmp/festapp-pr752-spec-repro.mjs doložil legacy grant -> nový deny -> odpojení -> znovu grant, přežití volby přes revizi A/B a interval starého iframe originu. Tyto reprodukce převést do normálních repo testů, nespoléhat na trvalost /tmp ani jejich absolutní importy.
- /tmp/festapp-pr752-astra-consent-repro.mjs doložil zastaralé festapp_consent v konzumentu zpracovávajícím push okamžitě. Nejde o test skutečného Google kontejneru.
- Prošlo 142 cílených JS testů bez skipů; chybové přechody nepokrývají. Generátory embed/runtime, forward migration --check a git diff --check na zkoumaném head prošly. Nejde o důkaz finálního integrovaného stromu ani nového migračního přechodu.

| Fakt a zdroj | Důsledek |
|---|---|
| embed.template.js readChoice čte buď source, nebo nezávislé record.consent; disconnect nekontroluje identitu bindingu | Opravit vlastníka volby, nikoli přidat další podmínku jen jednomu adaptéru. |
| connectKlaro není vlastněn record.consentDispose | Cleanup musí vlastnit všechny tři vstupy, ne jen moderní source. |
| syncConsent spouští heartbeat; scan při změně originu interval nemaže | Jeden disposer záznamu musí rušit všechny jeho zdroje a callbacky. |
| bootstrap.js consent update mění lokální context, ale push neobsahuje nested festapp_consent | Jeden společný snapshot/projection pro init, změnu i konverzi. |
| SQL processing_revision neobsahuje změnu chování; CMP cookie je klíčována tímto hashem | Nová sémantika musí změnit hash a podporu kódu musí ověřit handshake. |
| SQL status a MCP measurementStatus drží consent_required literal true | Neprovádět izolované přepnutí na false ani rozbití strict MCP status schématu. |

## Aktualizace vstupů při realizaci

Fetch při realizaci našel PR head 8af7d6435a9d763db1d1e55e2fb06d83b3f70dde. Tento commit již integruje main 99dc29ae7 a kapacitní wording. Implementační worktree je /Users/miakh/source/festapp-pr752-cutover, větev fix/pr752-canonical-measurement. Souběžný release worktree pr752-release má cizí rozpracované změny; nebyl upravován. Základem je proto skutečný aktuální PR, nikoli opakovaný rebase již integrovaných #749/#754.

Pět nových regresních testů nejprve selhalo na původních measurement sources v tomto head. Výsledek realizace a uzavření ledgeru jsou v measurement-pr752-RESULT-2026-11-07.md. Historické protocol 2 fixture jsou pevně převzaté z main 99dc29ae7, mají provenance README a nejsou runtime fallback. Pro matici je důležitá úplně stará trojice s novým SQL: může zachovat staré omezené chování bez nového kontaktového toku, jak specifikuje níže uvedená matice. Aktivní nový protokol je výhradně 3.

## Cílové vlastnictví a invarianty

### 1. Jedna účinná volba na jeden frame record

Embed helper vlastní právě jeden aktivní choice binding. Veřejné setMeasurementConsent, connectKlaro a connectMeasurementConsent zůstávají vstupy, ale jsou adaptéry do téhož interního vlastníka. Binding vlastní svoji identitu, přijatý scope manifestu a disposer. Staré hodnoty nejsou skrytá záložní autorita.

- Nahrazení/odpojení/selhání aktivního zdroje vrátí účinnou volbu na denied. Neobnoví předchozí setter/Klaro grant.
- Starý disposer a opožděný callback nemohou zrušit či přepsat novější binding; disposer je idempotentní.
- Volba patří organizaci, Unit a processing_revision. Změna těchto hodnot resetuje nebo přes skutečný source znovu ověří volbu. Nikdy automaticky nepřenese legacy grant jinému příjemci/zpracování.
- Setter volaný před první measurement-context může být jednorázově připoután k prvnímu přijatému scope; potom již nesmí přežít změnu scope. Toto musí být explicitně testované, bez nekonečného unscoped fallbacku.
- Stav denied, unavailable nebo odpojený CMP nezastavuje samotné oprávněné měření; lease liveness a volba návštěvníka jsou dvě různé věci. Analytics-only nikdy neimplikuje marketing.
- Pojmenování/callback hodnoty musí rozlišit choice a lease. Není potřeba globální store ani další public API.

### 2. Jeden životní cyklus frame recordu

Stejný disposer recordu používají odebrání DOM prvku, změna originu a konečný teardown. Vlastní interval, source/Klaro subscription, lease a load listener. Timer navíc před prací ověří frames.get(frame) === record a odpovídající aktuální origin. Retired record neodesílá ani neobnovuje žádný lease.

Pagehide zastaví heartbeat a revokuje lease; BFCache/pageshow obnoví pouze stále aktuální record a čerstvý handshake/liveness. Pouhé skrytí tabu nezastavuje runtime. Same-origin load zahodí neplatný manifest/lease a scope volbu revaliduje přes tentýž owner; nestaví druhou cleanup cestu. U aktivního recordu existuje nejvýše jeden heartbeat.

### 3. Jeden snapshot souhlasu v runtime

bootstrap.js vlastní projekci stavu do událostí. Při změně pushne stejný nový nested festapp_consent do události festapp_consent_update; zachová publikované top-level analytics/marketing. Inicializace, změnová událost a běžná měřicí událost vycházejí ze stejného normalizovaného snapshotu. Nemutovat objekt již předaný do dataLayer jako náhradu nové zprávy.

Příkaz Consent Mode default/update zůstane před načtením GTM, další změny jdou přes update bez rekonstrukce frame. Test musí číst nested stav v okamžiku změnové události, před následující konverzí.

### 4. Jedna nová sémantika existujícího measurement protokolu

Rozhodnutí: verzovat existující measurement protocol z 2 na 3, nikoli přidat vedle něj další policy engine či trvalou větev obsluhující oba. Layout/scroll/theme envelope festapp-embed zůstává protocol 1. V measurement obálce a v init measurementProtocol helperu bude jediná sdílená JS konstanta 3.

- SQL runtime policy vyjádří measurement_protocol: 3. Konstantní verze vstoupí do processing_revision. Nový measurementManifest ji vyžaduje a přenese ji až do Worker manifestu; klient i runtime porovnávají stejný údaj. Chybějící/nesprávná verze nemá fallback na current.
- Protokol 3 má zde jedinou sémantiku: advanced execution, visitor choice jako stav, bounded buyer contact pouze v úspěšných konverzích. Nezavádět volitelné Basic/Advanced větve nebo více synonymních mode booleanů.
- Nové aktivní send/receive cesty přijímají pouze protocol 3. Protocol 2 ponechat jen v historických migracích a v negativních/kompatibilitních test fixtures; žádný trvalý v2 runtime fallback.
- Registrovaný runtime_profile gtm-v1 je existující deployment profile, nikoli nový/duplicitní consent tok. Zůstává na tomto externím registry rozhraní; jeho přeznačení ani hromadný přepis registrací není pro verzi measurement protocolu potřebný.
- SQL změna processing_revision změní i Klaro storage key při stejných uložených konfiguracích. Původní cookie nečíst jako souhlas pro nové zpracování a není nutné ji hromadně mazat. Opětovné aplikování stejné migrace nesmí hash dál měnit.
- Každá smíšená kombinace, v níž je nový klient/helper/runtime a neslučitelný starý protějšek, musí skončit neaktivním měřením, bez kontaktů a bez dopadu na checkout. Doložit maticí skutečných starých i nových artefaktů, ne jen přepsaným číslem v mocku. Zvlášť otestovat starý runtime bootstrap při novém SQL, aby samotný nový hash nevytvářel falešný důkaz verze vykonávaného kódu.

consent_required: true v existujícím veřejném status/MCP kontraktu výslovně označuje povinnost poskytnout návštěvníkovi notice/ovládání/reporting volby; není predikátem povolení běhu. Toto znění sjednotit v SQL komentáři, MCP popisu, dokumentaci a testech kontraktu. Runtime capability se rozhoduje podle podporovaného protocol 3, eligibility a scope. Shape strict MCP status není třeba měnit jen kvůli tomuto vyjasnění. required_purposes popisují účely reportované volby, nikoli podmínku, že oba musejí být granted.

### 5. Zachovat stávající hluboké moduly a doménovou pravdu

FormMeasurementSession nadále vlastní policy/role freshness, generaci, volbu transportu a platnost capture. SQL nadále vlastní enablement, ceny, stable event IDs a conversion facts. FormDataLayer projektuje pouze povolenou konverzi a zachycený top-level kontakt; neobsahuje nový authorization engine a nemění úspěch objednávky. analyticsPayload dál rekonstruuje allowlist na každé trust hranici. Host-only transport a izolovaný runtime zůstávají výhradní alternativy; host vlastní Consent Mode svých vlastních tagů. Neoznačovat delegovanou host konfiguraci za prokázané chování Googlu.

## Rozhodnutí, předpoklady a blokátory

- Rozhodnutí: opravit všechny nálezy ve stejném PR, zachovat záměr Frantovy změny a oba veřejné consent vstupy/adaptéry; odstranit duplicitní autoritu uvnitř jejich implementace.
- Rozhodnutí: globální změna sémantiky dostane protocol 3 a deterministický nový fingerprint; samotné volitelné bumpnutí deployment revision není dostatečný interface contract.
- Předpoklad: provoz používá původní protocol 2; stav produkčních measurement registrací zde nebyl zkoumán. Dopad: před případným vydáním read-only inventura přesných jednotek/tenantů a artefaktů, potom jen výslovně autorizovaný rollout. Lokální implementaci to neblokuje.
- Předpoklad: pravidla strict MCP status se mezi aktuálním main a realizací nezmění. Při změně prohlédnout aktuální projection/čtenáře, aktualizovat plán; nepřidávat tichý parse fallback.
- Žádný blokátor lokální realizace. Povinné GitHub review, samostatná publikace a produkční gates zůstávají podmínkami pozdějšího vydání.

## Deletion ledger

| Nahrazená cesta | Finální akce | Důkaz |
|---|---|---|
| Nezávislé record.consent jako fallback po ztrátě source | Odstranit jako autoritu; setter jde přes stejný binding jako ostatní adaptéry | Grant -> deny -> disconnect zůstane denied |
| Nechráněné/staré disposery a samostatný Klaro watcher | Idempotentní binding-aware cleanup vlastněný recordem | Starý callback/disposer nepřepíše nový binding |
| Intervaly uklízené jen při !isConnected | Jeden record teardown + membership/origin guard | Navigace A/B/A a removal bez starých timerů/zpráv |
| Mutace již publikovaného context jako update | Nový normalizovaný snapshot ve změnové zprávě | Nested stav správný při samotné update události |
| Aktivní measurement protocol 2 | Jediná aktivní protocol 3 cesta | Scoped rg a reálná old/new compatibility matrix |
| Nezměněný fingerprint pro novou sémantiku | SQL fingerprint obsahuje protocol 3; žádná cookie fallback cesta | Existující řádky mají jiný stabilní hash, stará choice se nepřenese |
| Nejasný popis consent_required/required_purposes | Jeden význam v SQL, klientovi, MCP a dokumentaci | Status shape stále odpovídá strict schématu; žádný reader ho nepoužívá jako execution gate |
| Ručně upravené generated embed/runtime/reference | Pouze generátory ze zdrojů | Všechny --check a docs:check projdou |

## Realizační vlny

### 1. Aktualizace základu a regresní důkazy

Vytvořit vlastní implementační větev/worktree ze skutečného aktuálního PR, zachovat tento review checkout a ostatní sessions. Fetch aktuální main/PR a prohlédnout intervenující commity včetně #749/#754. Integrovat main podle repo politiky bez změny cizích checkoutů. Konflikt source digestů řešit regenerací mcp-reference.json, překlady zachovat z obou větví.

Doplnit skutečně červené regrese do tests/core/embed.test.js a tests/forms/form_measurement_runtime.test.js: oba grant-resurrection přechody, scope změnu, stale disposer, Klaro replacement, retired heartbeat a nested update snapshot. Neztratit původní bezpečnostní ani obchodní testy. Ověřit jejich discovery a red důvod na původním PR.

Výstup: aktuální integrovaný strom, konkrétní selhávající chování. Regrese jsou přes veřejná rozhraní a generovaný helper/runtime, nikoli kontrola názvů interních polí.

### 2. Choice binding a record lifecycle

Upravit web_client/scripts/embed.template.js: jeden binding owner a jeden disposer recordu s výše uvedenými invarianty. Přesunout všechny tři vstupy na tyto vlastníky. Zrušit staré autority a interval cleanup cesty, regenerovat public/embed.js přes build_embed.mjs.

Selhání subscribe/read, výměna source, detach, src change a opožděné callbacks nesmějí obnovit souhlas ani udržovat retired record. Measurement lease zůstává nezávislá na udělení účelů.

Výstup: všechny helper transition regrese procházejí včetně současně aktivních dvou iframe; jejich scope, choice a timers se neovlivňují.

### 3. Jednotná consent projekce

Upravit workers/form-measurement/src/bootstrap.js: společný normalizovaný snapshot pro init, consent update a event. Změna nesmí mutovat již pushnutý objekt. Zachovat top-level pole publikované update události. Regenerovat runtime_source.mjs přes build_measurement_runtime.mjs.

Výstup: eager consumer i opožděné načtení konzumenta dostanou správný nested stav při granted -> denied i denied -> granted; bez nového form eventu, bez rekonstrukce runtime.

### 4. Sémantická revize, SQL forward migration a kompatibilita

Společnou konstantu protocol 3 vlastnit ve form_measurement_contract.js a použít v helperu, EmbedBridge, FormMeasurementRuntime a Worker bootstrapu. Přidat povinný measurement_protocol do runtime policy/manifest; aktualizovat fixture producers a validators. Nepoužívat plošný replace všech protocol čísel: vnější embed/layout protocol 1 je jiný kontrakt a musí zůstat.

Kanonický SQL zdroj database/functions/eshop_forms/form_measurement_policy.sql přidá measurement_protocol a verzi do processing_revision. Nový forward migrační soubor musí být za nejnovější historií; při dnešním head je poslední soubor 20261107130000_form_measurement_gtm_always.sql. Při realizaci zvolit skutečně volný pozdější timestamp. Historické migrace včetně tohoto již publikovaného PR souboru nepřepisovat. Upravovat current assembler target a source parity testy tak, aby četly poslední autoritativní forward, ne dva soupeřící assemblery.

Rozšířit form_measurement_consent_test.sql a form-measurement-migration-postgres.test.mjs o reálné existující řádky: starý snapshot -> forward migrace -> jiný processing hash, stejné enablement/config/scopes a conversion facts; druhá aplikace beze změny hashe. Nové chování nezapíná dosud vypnuté organizace/Unit/formy. Rozšířit chaos/adversarial SQL testy tam, kde kontrolují skutečný Worker manifest.

Kompatibilitní test má načíst zmrazené relevantní protocol 2 artefakty z pevného main base do test fixture bez závislosti na dostupnosti Gitu za běhu CI; fixture označit jako záměrný negativní externí protějšek. Netahat starou implementaci do produkčního bundle. Měřit kontakty, init/ACK, stop a funkčnost checkoutu, ne pouze číslo verze. Matice rozliší vrstvy výslovně:

| SQL policy | Klient/helper/Worker | Povolený výsledek |
|---|---|---|
| stará | všechny staré | Původní známé chování jako baseline |
| nová | všechny nové | Cílový protocol 3, správný consent a bounded kontakty |
| stará | nový klient nebo nový Worker | Off, chybí podporovaná policy verze; checkout funguje |
| nová | nový klient se starým helperem nebo Workerem | Off bez kontaktů, žádný úspěšný protocol 3 ACK |
| nová | starý klient s novým helperem nebo Workerem | Neslučitelný measurement handshake se neaktivuje; checkout funguje |
| nová | kompletně stará trojice | Může zůstat původní omezené chování; nesmí získat nový kontaktový tok ani se vydávat za úspěšný protocol 3 |

Poslední případ je krátké okno starých nasazených/cachovaných artefaktů, nikoli obsluha protocol 2 v novém produkčním zdroji. Samotný nový SQL hash nedokazuje nové JS chování a nelze ho použít jako důkaz dokončeného vydání.

Vyjasnit consent_required a required_purposes ve status docs a MCP tool popisech bez rozbití strict status shape. Runtime gtm-v1 registry ponechat; doménové SQL predicates beze změn. Regenerovat MCP reference.

Výstup: nová choice identita a code capability mají stejný protokol, smíšená instalace neposílá kontakty a neblokuje nákup; nevznikla druhá aktivní verze implementace.

### 5. Dokumentace, CI a kontrakce

Aktualizovat docs/integrations/form-datalayer.md, embedded-checkout.md a workers/form-measurement/README.md: významy policy/notice/choice, protocol 3 versus layout protocol 1, podporované adaptéry, jejich cleanup a cache/mixed-version chování. Jasně uvést záměrné vystavení bounded kontaktu kódu pořadatele i při denied; clearing nemaže historii ani kopie příjemců. Neslibovat live Ads/Meta atribuci.

Nové regrese registrovat do existujících canonical CI kroků. Po integraci main jsou relevantní lanes web-startup (measurement/browser), wix-checkout-compatibility (helper), seat-checkout (SQL/migration) a server-policy (MCP forms/schema/docs, obsahuje #749 auth kontrakt). Neměnit jen místní alternativní seznam testů; authority je automation/ci/checks.json.

Uzavřít deletion ledger scoped rg nad aktivními sources, generátory, docs a test registrací. Zachovat historické SQL i jasně označené staré test protějšky. Žádné skipy maskující neprovedené SQL/browser ověření.

Výstup: finální zdroje a generované artefakty jsou konzistentní, protokol 2 není aktivně obsluhován a všechny dohodnuté přechody mají trvalou CI ochranu.

## Ověření

Validovat po koherentních vlnách; neopakovat passing checks bez změny jejich vstupů. První red batch a finální batch jsou odlišné důkazy. Pnpm 11.24.0, frozen lockfiles. SQL pouze disposable loopback DB s markerem, vypnutým cron a fenced email. Jeden Flutter task na workstation, testy concurrency=1, žádné vypnutí cizích úloh.

Rychlý lokální JS batch (uvnitř web_client, po frozen install):

```sh
pnpm exec node --test --test-concurrency=1 tests/forms/form_measurement*.test.js tests/forms/form_datalayer.test.js tests/forms/order_submission_result_lifecycle.test.js tests/core/embed.test.js tests/core/embed_analytics.test.js
pnpm exec node scripts/build_embed.mjs --check
pnpm exec node scripts/build_measurement_runtime.mjs --check
```

Dále forward assembler --check, tools/festapp docs:check a form tests; finální canonical mirror lanes:

```sh
./automation/test_ci.sh web-startup wix-checkout-compatibility seat-checkout server-policy
```

Browser obsluhu včetně browser mirror lanes delegovat Terra do izolované muted session. Primární agent koordinuje, zdroje jsou po celou dobu běhu zmrazené. Nezakládat druhý mirror ani nepřekračovat Flutter limit.

Browser scénáře: standalone i embed, oba transporty, před/po volbě a odmítnutí, odpojený/broken CMP, změna scope/revize, source replacement, iframe A/B/A a detach, pagehide/BFCache a skrytý tab. Doložit, že checkout funguje při nepodporovaném protokolu; kontakty pouze v purchase/generate_lead a správném scope. Událost změny musí aktualizovat nested stav před následující konverzí. Pro SQL a matrice ověřit počty skutečně vybraných testů a nulu nových skipů. Deterministické tags dokládají náš interface, nikoli skutečnou Google atribuci.

## Pozdější rollout a rollback - samostatně autorizovaná operace

Před vydáním ověřit skutečný deployed protocol, SQL historii, runtime/helper cache a platformou povolené Units/tenanty. Nespouštět registraci ani enablement jako vedlejší efekt upgrade. U více tenantů nejprve výslovně určit schválenou sadu; nešířit web overlays na další prod větve.

Po review/merge a exact-main release gates pořadí: SQL policy protocol 3 a nový fingerprint; Worker protocol 3; host helper protocol 3; vybraný web klient protocol 3. Dočasně staré nebo smíšené protějšky mohou vypnout měření, nikdy checkout nebo souhlas předstírat. Kompletně stará trojice může podle explicitní matice dočasně zůstat na původní omezené sémantice; takový stav není dokončené vydání a nedostane nový kontaktový tok. Při striktních provozních požadavcích tuto measurement-only mezeru dohodnout před vydáním. Ověřit, že /runtime a /runtime.js pocházejí z jednoho immutable Worker buildu; dynamická SQL policy sama nedokazuje verzi JS z cache.

Rollback může bezpečně vypnout měření; nesmí tiše vrátit starou choice identitu ani přijímat dva protokoly jako neomezený fallback. Zachovat konzistentní snapshoty a source/digest receipt; staré policy a staré JS vracet jen jako samostatně posouzený celek. SQL změny aplikovat canonical cestou, ne cloud fallbackem. Změna nevyžaduje plošný restart Supabase ani jiné produkční zásahy.

## Definice hotovo

- Všech pět nálezů je vyřešeno ve zdrojích i všech aktivních vstupech; tři veřejné adaptéry mají jeden choice owner, jeden frame record má jeden cleanup owner.
- Source loss/revize nemohou obnovit grant a retired record neodesílá; nested stav odpovídá volbě už ve změnové události.
- Protocol 3 je jediný aktivní measurement kontrakt, layout zůstává 1; staré choices se nepřenášejí a smíšené verze selhávají do off bez dopadu na objednávky.
- Migrační a kompatibilitní důkazy jsou skutečné, cílené JS/SQL/browser i dotčené canonical lanes prošly, generated checks jsou aktuální.
- Deletion ledger je uzavřen, žádná záměrně ignorovaná regrese ani placeholder. Výsledek výslovně rozlišuje lokálně dokončenou implementaci a dosud neprovedenou publikaci/produkční aplikaci.
- Pokud se při implementaci prokáže nesplnitelný předpoklad či smíšená cesta, nejprve opravit tento plán a všechny jeho důsledky; neobcházet jej tichým fallbackem.
