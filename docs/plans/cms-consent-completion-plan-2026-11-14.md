# Dokončení přenosu cookie voleb pro WordPress, Joomlu, Wix a HTML

Datum: 2026-11-14
Stav: implementace a lokální ověření probíhá; uživatel následně autorizoval rollout pouze vstupenky.online
Verification: standard - oprávnění, veřejný kontrakt a databázová migrace

## Výsledek a rozsah

Pořadatel nastaví přenos v **Nastavení pořadatele > Měření > Moje weby** ve
Festappu. Vybere svůj web, CMS a podporovanou cookie lištu, vyplní její nezbytné
údaje a potvrdí pokrytí zásad. Festapp vytvoří konfiguraci k přenosu do doplňku.
Doplněk pouze importuje konfiguraci, umožní její vypnutí a zobrazí stav importu.
Nikdo ručně nepřepisuje Organization ID, Unit ID ani revizi souhlasu.

Dokončení zahrnuje backend, Flutter administraci, společný embed runtime, oba
CMS adaptéry, Wix a existující HTML/Webnode generátory, dokumentaci, zapojení
testů a odstranění nahrazených cest. Wix a HTML doplnil uživatel během implementace. PR #856
a #857 jsou zdrojem použitelného kódu, nikoli hotovou cílovou implementací.
Issue #858 popisuje problém správně, ale návrh zobrazit tři hodnoty a získávat je
novým veřejným endpointem nahrazuje tento plán.

Bez samostatné autorizace se neprovádí produkční SQL migrace, publikace CMS
balíčků ani nasazení tenantů. Původní plán autorizaci k publikaci nevydával. Následná implementační session
2026-11-14 výslovně autorizovala squash sloučení, Dependabot #859-#863 a nasazení
na vstupenky.online (tenant `festapptickets`); další tenanty ani veřejné CMS
balíčky tato autorizace nezahrnuje.

## Ověřený výchozí stav

| Fakt | Zdroj a důsledek |
|---|---|
| Bridge, weby a jejich schválení už mají společnou administraci. | `lib/components/unit/views/unit_measurement_settings.dart`, `unit_settings_screen.dart`, `unit_measurement_approval.dart`, `db_units.dart`. Rozšířit tento tok, nezaložit druhou obrazovku nastavení. |
| SQL vlastní sémantickou revizi a veřejnou policy formuláře. | `database/functions/eshop_forms/form_measurement_policy.sql`: `form_measurement_runtime_internal`; `form_measurement_runtime.sql`: `get_form_measurement_policy`. MD5 se nesmí přepsat do Dart/PHP. |
| Revize dnes závisí na Unit a jejím runtime, nikoli na ID formuláře. | Stejná Unit má stejnou sémantickou revizi; způsobilost měření zůstává samostatně vyhodnocená pro každý formulář. |
| Přenos, odvolání a časově omezené leases již existují. | `web_client/src/embed/host_consent_link.js`, `host_complianz.js`, `host_cookiebot.js`, `host_cookieconsent.js`; `components/forms/form_consent_link.js`, `form_measurement_session.js`. Zachovat jejich vlastnictví. |
| Oba produkty každého CMS vznikají ze společných šablon. | `integrations/{wordpress,joomla}/shared/`. Generované produktové kopie nejsou samostatní vlastníci. |
| WP validace kategorií je užší než runtime. | PR #857 `shared/consent.php.in`: `consent_validate`, ASCII regex. Reprodukce s `statistika návštěv` skončila odmítnutím. Nový tok musí mít parity test, nikoli tento regex znovu použít. |
| Nové WP integrační testy nejsou doloženy zeleným CI. | `tests/consent-contract.php` vyžaduje reálný WP; není v běžném `pnpm test`. Výsledky autorových fixture testů nejsou úplný backend E2E. |

Review proběhlo nad #856 `ed05cb320cce2e8e8b2a9d9e6c842836724917b6` a #857
`633a2df85631b5ae99d7e9421bc7f0f2a00d1535`; sledovaný main byl
`d56b9df3d265bd0bde798a1c09748ec27770b1c6`. V izolované větvi
`review/cms-consent-20261114` je zkušební spojení obou PR. Konflikt v
`automation/test_embed_adapters.sh` byl vyřešen zachováním obou sad vstupů.
Tato větev nebyla publikována a nenahrazuje aktuální main.

Na spojeném kódu prošlo 258 JS testů adaptérů/přenosu, 120 případů rendererů,
242 kontrol Joomla konfigurace, 8 kontrol výchozího režimu Joomly a 14 JS
kontrol GTM/WP defaults. To je výchozí regresní důkaz, nikoli důkaz nové cílové
architektury. Běžel offline PHP kontejner se stuby CMS API, nikoli celý WordPress.

## Cílová architektura a rozhodnutí

### Jeden serverový vlastník konfigurace

- Uložit propojení pod Unit a přesný origin webu do jediné tabulky, pracovně
  `analytics.website_consent_bindings`. Nepřidávat paralelní konfigurační pole
  do Unit JSON. Řádek obsahuje provider, normalizované provider-specific údaje,
  verzi konfigurace, potvrzenou sémantickou revizi, stav zapnutí a údaje kdo/kdy
  potvrdil pokrytí. Organizaci odvodit ze skutečné Unit.
- CMS/platforma je volba způsobu integrace a návodu. Nesmí vytvořit odlišná
  pravidla souhlasu nebo duplikovat propojení stejné Unit a originu.
- Použít explicitní veřejné RPC pro administrativní čtení, potvrzení/zápis,
  vypnutí a export. Všechna kontrolují `can_manage_unit_configuration` nad
  uloženým scope; přímé tabulkové zápisy nejsou povolené. `SECURITY DEFINER`
  funkce mají `search_path=public,extensions`. Žádné aplikační triggery.
- Provider údaje validovat při zápisu. Zachovat přesné originy, podporované
  revize CMP, Cookiebot cutoff/expiry a rozdílné kategorie. Kopie v PHP nesmí
  rozhodovat o aktuálním serverovém schválení či sémantické revizi.
- Oddělit koncept uložené konfigurace od její účinnosti: draft, vyžaduje
  schválení webu, vyžaduje nové potvrzení, připraveno, vypnuto. Účinný stav
  odvozuje SQL z bridge, schválení originu, eligibility a shody revizí.

### Revize, souběh a zneplatnění

- Vyčlenit potřebný Unit scope ze stávajícího SQL vlastníka do jedné interní
  projekce a delegovat na ni z `form_measurement_runtime_internal`. Zachovat
  dosavadní výpočet sémantické revize byte-for-byte pro nezměněné vstupy.
- Potvrzení přijímá očekávanou aktuální sémantickou revizi a očekávanou verzi
  uložené konfigurace. Zápis potvrzení je atomický a při stale hodnotě skončí
  konfliktem; žádné tiché přepsání nebo automatické potvrzení na read/export.
- Export obsahuje pevnou potvrzenou revizi. Změna zásad, CMP mapování nebo
  odvolání potvrzení vyžaduje nové vědomé potvrzení a nový export. Runtime-only
  změna nesmí předstírat změnu zásad. Žádný endpoint nesmí jen vracet nejnovější
  revizi pro automatické dosazení ke staré návštěvnické volbě.
- Pro spravované propojení nestačí samotný starý export. Přidat stabilní ID a
  verzi propojení do exportu i existujícího přenosu a porovnávat je s aktuální
  serverovou policy pro přesný origin. Jde o identifikaci konfigurace, ne heslo,
  návštěvnický souhlas, bearer token či novou autentizaci.
- Policy vrací pouze nezbytné veřejné identifikátory a účinný stav propojení,
  nikoli administrativní audit či kompletní CMP konfiguraci. Výpočet technické
  `processing_revision` zahrne změny účinných propojení, aby existující refresh
  a lease lifecycle zachytil i vypnutí bez změny sémantiky zásad.
- Vypnutí nebo odebrání propojení zanechá neaktivní řádek/verzi: starý export
  nesmí spadnout do původního nespravovaného režimu. Po zjištění změny se
  import okamžitě odpojí, nejpozději vyprší při současné maximální lease 60 s.
  Při nedostupné policy se grant neprodlužuje. Checkout funguje dál a formulář
  nabídne vlastní lištu. Odvolání schválení originu i bridge zůstává účinné.

### Jeden formát pro oba doplňky

- Jeden verzovaný JSON export: `schemaVersion`, cílový service origin,
  `websiteOrigin`, reference/verze propojení a provider konfigurace pro stávající
  adaptéry včetně serverem odvozeného scope a potvrzené revize. Není to tajemství.
  Service origin určit z kanonické tenant/produktové konfigurace.
- Oba doplňky dostanou jediné pole/import souboru s exportem, vypnutí a lokální
  stav. Kontrolují velikost, strukturu, podporovanou verzi a povolené originy;
  obsah escapují. Nepřepočítávají revizi ani nepředstírají vzdálené schválení.
- Sdílený JS helper rozbalí tentýž export a použije existující provider adaptéry.
  Rozšířit stávající kontrakt/protokol jen o identifikaci spravovaného propojení;
  nezakládat nový consent engine, transport ani veřejný HTTP endpoint z #858.
  Starší peer bez potřebných polí pro tento export bezpečně ukáže vlastní lištu.
- Zachovat podporované ruční externí adaptéry jako výslovnou externí hranici
  existujícího kontraktu. Na originu se spravovaným propojením nebo jeho
  neaktivním záznamem nesmí chybějící reference obejít centrální zneplatnění.
  Stávající neřízené integrace mimo tuto hranici mají regresní testy.
- Automatické přepisování celého obsahu/menu WordPressu z PR odstranit. Přenos
  aktivovat pouze na vlastním bloku/shortcodu/link modulu a vlastním fallback
  odkazu. Cizí ručně vložené `noopener/noreferrer` se zachovají. Vysvětlit rozdíl
  mezi přenosem cookies a kontinuitou měřicí identity; tu tento projekt neslibuje.
- Výchozí stav zůstává vypnutý. CMS nikdy nemění globální bezpečnostní hlavičky.
  Joomla viditelně upozorní na blokující COOP; lokální stav importu nesmí tvrdit,
  že vzdálené propojení skutečně funguje, pokud to neověřil celý tok.

## Pořadí implementace

### 1. Kontrakt a backend

**Změny:** nový kanonický SQL soubor pod `database/functions/eshop_forms/` pro
propojení/RPC, rozšíření projekce v `form_measurement_policy.sql` a
`form_measurement_runtime.sql`. Nejprve určit přesná RPC jména a JSON kontrakt
v `docs/integrations/form-datalayer.md`; použít je ve všech dalších vlnách.
Přidat forward migraci s vlastním reprodukovatelným assemblerem; nepřegenerovat
již publikovanou `20261111120000_form_consent_scope.sql` změnou starého assembleru.

**Validace:** skutečné rollback SQL testy v disposable DB: manager/cizí Unit,
anon odmítnutí admin RPC, scope z uložených řádků, draft/schválení, export,
souběžná a stale potvrzení, změna revize, vypnutí, neaktivní záznam, žádný únik
soukromých údajů. Prokázat shodu starého scope pro nezměněnou konfiguraci,
upgrade ze současného schématu i opakovatelnou aplikaci podle migračních pravidel.

**Hotovo:** autoritativní zápis, stav a export existují a nelze potvrdit stale
scope ani obejít oprávnění; žádné ruční ID/revize nejsou autoritou klienta.

### 2. Runtime a odvolání

**Změny:** parsování exportu u společného embed helperu, delegace na současné
CMP adaptéry; binding reference ve `measurement_consent_source.js`,
`host_consent_link.js`, `form_consent_link.js` a související policy/session
normalizaci. Jedna kontrola účinného propojení pro import do iframe i nové karty;
nezměnit vlastnictví běžného lokálního souhlasu ani website dataLayer režimu.

**Validace:** parity JSON -> reálný adaptér pro všechny podporované CMP,
Unicode/mezery/UTF-16 hranice kategorií, grant i refusal, odvolání, replay,
source/scope/origin mismatch, starý export po vypnutí/změně konfigurace,
starší peer, runtime-only deploy a ztráta policy. Explicitně otestovat, že
odstranění binding polí na spravovaném originu nepovolí legacy fallback.

**Hotovo:** starý export po zneplatnění nemůže obnovit grant a bez platného
přenosu zůstává nákup i lokální lišta dostupná.

### 3. Nastavení ve Festappu

**Změny:** rozšířit `UnitMeasurementSettings`/`unit_settings_screen.dart`,
`DbUnits`, model propojení a lokalizace. Vykreslit konkrétní web, CMS/provider,
jen příslušná CMP pole, stav z RPC, potvrzení pokrytí a kopírování/stažení exportu.
Změny v rozepsaném Unit formuláři nejsou potvrzená serverová konfigurace: před
potvrzením/exportem dokončit canonical save a načíst aktuální scope, nebo export
blokovat do uložení. Výběr platformy nesmí rozmnožit pravidla ani backend entity.

**Validace:** widget testy v existujícím `unit_measurement_settings_cases.dart`
a jeho skutečně sbíraném test rootu; oprávnění, draft vs saved, pole podle
provideru, stale konflikt, potvrzení, export a explicitní stav nedostupnosti.
Dart formát a cílený analyzer; Flutter slot ověřit před spuštěním, testy vždy
`--concurrency=1`.

**Hotovo:** celý postup je proveditelný bez podpory a bez vyhledávání interních
ID; změněný rozsah zásad se nedá potvrdit omylem tichým uložením jiného pole.

### 4. Zjednodušení CMS a odstranění duplicit

**Změny:** převzít použitelné renderery, link block/shortcode a balení z #856/#857.
V `integrations/wordpress/shared/` a `integrations/joomla/shared/` nahradit
provider formuláře importem společného exportu. Odstranit detekci CMP policy ID,
adopt tlačítka, vlastní zadávání revizí, globální filtry odkazů a jejich testy.
Ponechat escaping, Settings API nonce/capability, Joomla form ochrany, URL
allowlist, limity vstupu, uninstall a původní výchozí chování bez importu.
Přegenerovat oba produkty jen kanonickými skripty, ne upravovat produktové kopie.

**Migrace:** PR jsou nepublikované; jejich novou konfigurační option není potřeba
podporovat jako zákaznickou legacy cestu. Před odstraněním to ověřit vůči
publikovaným verzím. Pokud mezitím vyšly, žádné automatické převzetí starého
potvrzení: vypnutí staré varianty a vědomý import nového exportu. Lokální fixture
připravit znovu, ne přenášet její testovací nastavení jako produkční data.

**Validace:** oba produktové generátory a metadata, offline adapter suite,
reálný WordPress na deklarovaném minimu i aktuální podporované verzi, Joomla 5/6:
validní/poškozený/cizí export, off/on, escaping, permissions/uninstall, jedno
načtení helperu, vlastní linky, nedotčené ruční linky a COOP upozornění.

**Hotovo:** CMS neobsahuje konkurenční konfigurátor; původní byte-compatible
výstup při vypnutí a kanonické sdílené generování zůstávají doložené.

### 5. Trvalé testovací gates a úplný průchod

Zapojit nové testy do skutečných příkazů, `automation/ci/checks.json` a jeho
source/test ownership inventáře. WP test nesmí být pouze souborem, který CI
nikdy nespouští. Zachovat obě části konfliktu adapter skriptu. Nahradit testy
ručního nastavování ID/revizí testy nového importu; stabilní bezpečnostní regresní
případy nezahazovat jen kvůli změně UI.

V izolovaném prostředí provést **Festapp nastavení -> potvrzení -> export ->
import do skutečného CMS -> skutečný veřejný formulář proti disposable backendu**.
Simulovat lze poskytovatelovo API/transport pouze se zřetelně označenou hranicí;
nejde pak o live CMP důkaz. Nezaměňovat fixture formulář s kompletním backend E2E.
Běžná CI nesmí záviset na placeném CMP nebo produkčním účtu.

Povinná matice: bez volby, přijetí, odmítnutí, pouze analytika, odvolání při
otevřeném formuláři, zavření/reload zdrojové karty, změna zásad, změna mapování,
vypnutí propojení/bridge, odebrání schválení, nepovolený web, starý export,
přerušený přístup k policy a blokující COOP. Pro link runtime Chromium/Firefox/
WebKit, pro CMS průchod každá podporovaná kombinace alespoň jednou; společné
runtime scénáře neduplikovat násobením celé matice všemi CMS verzemi.

Použít existující CMS environment wrappery a repository browser příkazy.
Agent-owned browser je izolovaný, na pozadí a muted; browser práci dle osobních
pravidel delegovat Terra agentovi. Nikdy nepoužívat běžící DB jiné úlohy.

**Hotovo:** normální CI skutečně sbírá nové testy a kompletní průchod dokládá
platný i neplatný přenos se skutečným serverovým schválením.

### 6. Kontrakce, dokumentace a připravenost ke sloučení

| Nahrazovaný artefakt | Finální stav a důkaz |
|---|---|
| CMS pole Organization/Unit/consent revision | Odstraněna z formulářů i návodů; scope je pouze v importovaném serverovém exportu. |
| PHP provider validátory/detekce/adopt UI | Odstraněny; zůstane parsování obálky a bezpečnost výstupu, s parity testem delegace do společného JS. |
| WP `mark_consent_links`, `mark_menu_link` a globální hooks | Odstraněny včetně registrací; test prokáže zachování cizích rel atributů. |
| Nový veřejný endpoint navržený #858 | Neimplementovat; administrativní export řeší potřebu bez další veřejné API cesty. |
| Testy starého CMS konfigurátoru | Nahrazeny import/persistence/escaping testy; bezpečnostní chování zůstává testované na správném vlastníkovi. |
| Generované produktové kopie a jazyky | Obnoveny ze shared; generation check a kontrola balíčků potvrdí shodu. |
| Staré provozní návody a readiness evidence | README, veřejná cs/en nápověda a metadata popisují skutečně vydávanou verzi; starý test receipt se nevydává za nový. |

Aktualizovat #858 a PR popisy až při samostatně autorizované implementaci a
GitHub publikaci. Propojit je s tímto plánem, uvést skutečný finální scope a
opravit tvrzení o testech. PR lze přepracovat v jejich větvích nebo nahradit
jednou integrační změnou; rozhoduje aktuální overlap, ne potřeba zachovat počet PR.
Neslučovat dvě neúplné varianty jen pro uzavření čísel.

**Výstup:** čistý integrační diff, splněný deletion ledger, cílené checks na
finálních vstupech a přehled skutečných testů/omezení. Před autorizovaným
publikováním znovu fetchnout main, zahrnout intervenující commity a ověřit
zasažené testy. Původní review merge ani staré zelené CI nejsou aktuální důkaz.

## Ověřovací příkazy a úsporné pořadí

Během implementace dokončit ucelenou vlnu a pak provést její cílenou kontrolu;
neopakovat celé sady po každém souboru. Zelený výsledek platí jen pro nezměněné
vstupy. Nepsat testy překladových vět nebo trivialit místo behaviorálního pokrytí.

Existující základní příkazy:

```sh
bash automation/test_embed_adapters.sh
pnpm --dir web_client exec node --test \
  tests/core/host_complianz.test.js tests/core/host_cookiebot.test.js \
  tests/core/host_cookieconsent.test.js \
  tests/forms/form_consent_link.test.js tests/forms/form_consent_link_cmp.test.js \
  tests/forms/form_consent_link_cookiebot.test.js \
  tests/forms/form_consent_link_cookieconsent.test.js
pnpm --dir web_client exec node scripts/build_embed.mjs --check
pnpm --dir web_client exec node scripts/build_runtime.mjs --check
```

Nové SQL/CMS/E2E testy připojit do skutečných owner commands, zaznamenat přesný
příkaz a počty do implementačního výsledku. Zjistit existující sbíraný Flutter
root pomocí scoped `rg` na název cases souboru; samotný cases soubor není test root.
Použít pnpm 11.24.0 a frozen instalaci. Plánování samo další testy nevyžaduje.

## Provozní pořadí a rollback

Implementace a lokální důkaz mohou být dokončené bez produkční aktivace; tyto
stavy se musí ve výsledku odlišit. Při později autorizovaném rollout: nejprve
forward schema/RPC a kompatibilní policy, pak nový runtime/formulář a Festapp
administrace, nakonec CMS balíčky. Nový export nezpřístupnit před kompatibilním
runtime. Na starém peeru musí být výsledkem lokální lišta, nikdy implicitní grant.

Migrace a nasazení běží výhradně kanonickými cestami na vybraném tenantovi.
Exact-main GitHub release gate zůstává povinný. Žádné další prod větve ani
zveřejnění všech značek bez konkrétního autorizovaného scope.

Rollback vypne spravované přenosy a zachová neaktivní záznamy; checkout a vlastní
lišta fungují dál. Nevracet odstraněné CMS konfigurátory, nemažte audit/tombstones
ani neobnovovat použití starých exportů.

## Definice dokončení

- Pořadatel provede celý tok ve Festappu a CMS bez pomoci podpory.
- Server odvozuje scope, autorizuje zápis a vlastní aktuální stav propojení.
- Změny a vypnutí zneplatní i již vydané exporty a otevřené přenosy.
- Oba CMS používají stejný formát a stávající společné adaptéry; žádné paralelní
  formuláře, výpočty revize ani nechtěné úpravy cizích odkazů nezůstaly.
- Nové testy jsou skutečně sbírané a kompletní backend/CMS průchod prošel.
- Zdroj je připraven ke sloučení; provozní aplikace má vlastní přesný stav.

## Předpoklady a zbytková rizika

Ověřeno 2026-11-14: veřejný WordPress.org ZIP vstupenky-online 1.0.8
(SHA-256 `6ba77dac0f7b297a5632fa5cdeb051d6622299e8c56e352373612ea64b668d79`)
a veřejný Joomla ZIP 1.0.5 (`104d98e8c83cea25b5e3fbf343dc7fd5969dcee89d83f3b986526bed25b8d31c`)
neobsahují navrhované provider konfigurátory ani jejich option/parametry. Nový
import proto nemusí podporovat nevydané nastavení z #856/#857. Veřejné CMS balíčky
se v tomto rolloutu nepublikují; nové zdrojové verze jsou připravené k samostatnému vydání.
Žádná aktuálně chybějící externí služba neblokuje zahájení implementace.

CMS cache, optimalizátory a COOP mohou přenos znemožnit i s platným exportem.
Fallback musí zůstat použitelný; bez ověření nelze zobrazit tvrzení „funguje“.
Reálné změny vzdáleného GTM/notice obsahu pod stejným ID vyžadují stávající
vědomé zvýšení `measurement_consent_version`; export tuto povinnost neobchází.

## Implementační aktualizace 2026-11-14

Práce běží na `feat/cms-consent-completion-20261114` v samostatném worktree z
main `355ceae08`. Rozpracované globální balení WordPressu v původním worktree
není součástí této změny. Z #856/#857 jsou převzaty jen použitelné renderery,
vlastní link block/shortcode a jejich balení; review větev nebyla zdrojově sloučena.

Kanonická jména RPC a schema 1 jsou v `docs/integrations/form-datalayer.md`.
Nový vlastník `website_consent_bindings.sql` a samostatný assembler vytvářejí
forward migraci `20261114170000_website_consent_bindings.sql`. Historická scope
migrace zůstává beze změny; její starý assembler kontroluje zmrazený hash.
`unit_measurement_consent_scope_internal` zachovává původní MD5 vstupy.

CMS sdílí pouze bezpečnostní parser obálky `integrations/measurement/consent-export.php`;
provider sémantiku dál vlastní společné JS adaptéry. `host_consent_export.js`
rozbaluje export. `form_measurement_embed_consent.js` propojuje spravovaný iframe
s existující lokální lištou a zachovává transport lease i po vlastní lokální volbě.

Nové instalované CMS testy nelze zaměnit za backend E2E. První ověření WP 6.6/7.1.3
a Joomla 5.4.10/6.1.4 používá syntetický export; další WP kontrola používá skutečný
export z disposable SQL RPC. Souvislý průchod se skutečným exportem z Flutter UI
do WordPressu a veřejného formuláře prošel. Normální fixture owner ověřil devět
CMS/backend/browser kombinací včetně odvolání, starého exportu a COOP fallbacku;
je zapojen do kanonického Wix CI jobu. Hranice modelovaných CMP/Wix host API,
samostatné nativní Wix ověření a cílené testy jsou popsány ve
[finálním implementačním výsledku](cms-consent-completion-RESULT-2026-11-15.md).

## Uživatelem rozšířený rozsah 2026-11-14

Během implementace uživatel výslovně požádal zahrnout Wix a ostatní existující
webové integrace ještě před nasazením. Inventář `integrations/README.md` obsahuje
WordPress, Joomla a Wix; obecné HTML/Webnode má existující generátory v aplikaci
a veřejné nápovědě. Tyto čtyři cesty proto používají stejný export a vazbu.
Make a ostatní API konektory nemají návštěvnický browser consent a nejsou tímto
rozšířením dotčeny. Nevzniká nový Shopify/Shoptet doplněk.

Platforma vazby připouští `wordpress`, `joomla`, `wix`, `html`; stejný Unit/origin
má stále jeden řádek. Native Wix provider používá výslovně uloženou policy
(`defaultPolicy=false`) a povinný `createdDate` v archivovaném cutoff/age mapování.
Každé čtení znovu volá živé API; chybějící datum, default, expiry nebo API znamená
vlastní lištu. Živý izolovaný visitor test na existujícím vývojovém webu ověřil
odstranění consent-policy cookie i reset z druhé karty bez reloadu. Události
nejsou jediným zdrojem: adaptér má polling a focus/visibility kontrolu.

Wix nemá vlastní konfigurátor provider scope/revize. Jeho panel importuje JSON;
HTML generátory v aplikaci i cs/en nápovědě přidávají volitelný stejný import,
escapují atribut a označují jen svůj vlastní fallback odkaz. Podepsaný Wix
checkout_origin a existující billing/marketplace hranice zůstávají samostatné.
Nasazení existujících hosted Wix assetů musí dodržet své release gates; nové
marketplace listování ani změna publisher poplatků tímto rozšířením nevzniká.
