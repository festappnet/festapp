# PR #750: měření reklam s vynuceným souhlasem

Datum: 2026-11-06

Stav: Doporučený návrh po zapracování architektonické oponentury, bez autorizace publikace nebo produkčních změn

Verification: standard - veřejný kontrakt, oprávnění, souběh a předávání kontaktů

Oponentura: 2026-11-07, nezávislý subagent `gpt-6-astra`, reasoning `medium`, výslovně vyžádaný uživatelem. První verdikt byl changes required; níže jsou zapracované opravy interface, vazby runtime revize, host protokolu a mezí rollout záruk. Nejde o provedené integrační ověření.

Následná kontrola Astry označila upravený plán za ready for implementation bez zbývajícího architektonického blokátoru. Uživatel následně zadal přípravu finálního exekučního promptu k dosažení tohoto cíle. Produktová matice v přiloženém promptu je proto součástí připraveného zadání; při jeho výslovném spuštění ji není třeba znovu potvrzovat. Příprava promptu sama nespouští implementaci ani publikaci.

## Výsledek a rozsah

Zachovat reklamní atribuci, produktové štítky, zásady pořadatele a vzhled souhlasového dialogu z PR #750. Souhlas však musí skutečně řídit spuštění cizího kódu a předávání dat. Odmítnutí nesmí znamenat pouze další příznak v již běžícím skriptu.

Tento dokument je návrh úprav PR, nikoli potvrzení právní shody nebo pokyn k okamžité implementaci. Autoritou je pro tento návrh aktuální zadání uživatele, které přijalo doporučení nepředávat kontakty po odmítnutí. Záměr always-on z popisu PR není požadavkem cílového řešení.

V rozsahu: SQL projekce způsobilosti, lokální souhlas, FormDataLayer, runtime, oba embed transporty, dokončení objednávky, UI/MCP, migrace a relevantní CI. Mimo rozsah: změna významu purchase na zaplaceno, obecná marketingová platforma, server-side Ads, samostatný analytický produkt, produkční zapnutí, právní posudek a plošné změny tenantů.

## Pevný bod a ověřené skutečnosti

- PR: https://github.com/festappnet/festapp/pull/750
- Kontrolovaný head: `65705b455ace4818d063aa122352cf48b6fe86f8`.
- Merge-base: `9f97554a168b1f28217842357852796082f053f9`.
- Zjištěný aktuální main: `b3c20983b13120d8a4c0238b4358fa77b9e292ce`.
- PR má konflikt v `automation/release/help/mcp-reference.json`. Před implementací znovu určit refs; před publikací aktualizovat vůči autoritativnímu main podle pravidel repozitáře.

| Fakt | Důkaz na kontrolovaném headu | Důsledek |
|---|---|---|
| Konstruktor začne načítat roli; souběžný waiter na ni nepočká | `form_datalayer.js:61-69,107-109`, `form_page.js:611-617` | Potvrzená P1: přihlášený běžný návštěvník samostatného formuláře nenastartuje měření ani CMP. Pozdější odpověď start neopraví. |
| Běžný test přiřazuje refreshPolicy až po konstrukci | `web_client/tests/forms/form_datalayer.test.js:224-235` | Dosavadní test přihlášených nepokrývá skutečné pořadí volání. |
| GTM i Unit skripty se načtou při init bez ohledu na souhlas | `workers/form-measurement/src/bootstrap.js:28-67` | Záměr PR, který je potřeba změnit; nejde o náhodný bug. |
| Chyba CMP může vést ke spuštění runtime | `form_measurement_cmp.js:121-127`, `form_page.js:617` | Souhlasová vrstva dnes nemá bezpečný chybový stav. |
| purchase/lead přebírá čitelný kontakt a pak přidá nulovací záznam | `form_datalayer.js:146-158,243-251`, `bootstrap.js:16-19`, `embed.template.js:269-278` | `push({user_data:null})` resetuje další stav, ale neodstraní starší objekt z historie pole. Dosavadní test na řádcích 184-189 to přímo ukazuje. Nelze tvrdit smazání kontaktu po události. |
| Host transport považuje handshake za dostatečnou připravenost | `embed_bridge.js:96-119` | Samotná implementace transportu nesmí rozhodovat, zda je dovoleno měřit. |
| Expirace policy v hidden dokumentu iframe neodpojí | `form_measurement_runtime.js:77-82`, zatímco `workers/form-measurement/README.md:31-34` slibuje odpojení | Nové aplikační sendy blokuje TTL, ale již načtený Unit skript může dál samostatně komunikovat. Záměr zachovat hidden frame nepokrývá slibovanou revokaci cizího kódu. |
| Nápověda stále slibuje čekání na souhlas | `assets/translations/cs.json:480` a ostatní lokalizace, `tools/festapp/src/operations/configuration.mjs:41` | Potvrzená P2: nový kód a veřejně viditelný popis se rozcházejí. |
| Izolovaný runtime má vlastní Unit origin, CSP a nezískává aplikační token | `workers/form-measurement/src/worker.mjs`, `database/functions/eshop_forms/form_measurement_runtime.sql` | Zachovat tento bezpečnostní základ. Cizí kód se nevrací do dokumentu formuláře. |
| Worker načítá konfiguraci nezávisle na policy parentu, ale bootstrap nezná její revize | `worker.mjs:28-47`, `bootstrap.js:21-32`, `form_measurement_runtime.js:14-22` | Původní návrh revision-bound souhlasu měl mezeru: nová konfigurace by mohla běžet pod starou volbou. Handshake musí porovnat skutečný konfigurující snapshot před jakýmkoli spuštěním Unit kódu. |
| SQL vlastní způsobilost a conversion facts bez kontaktních polí, nikoli souhlas návštěvníka | `form_measurement_policy.sql`, `form_datalayer.sql`, `user_permissions/form_measurement.sql` | SQL nepřesouvat do JS. Obchodní fakta oddělit od svolení odeslat je třetí straně. |
| Změna platného privacy URL není v configuration_revision | `form_measurement_policy.sql:82-89` | Nový zpracovatelský kontext potřebuje vlastní konzistentní revizi, kterou používá uložený souhlas. |

Cesty bez prefixu v tabulce patří pod `web_client/src/components/forms/`; `embed_bridge.js` pod `web_client/src/services/` a `embed.template.js` pod `web_client/scripts/`.

Při první kontrole prošlo 159 cílených JS testů na uvedeném PR headu. Všech šest spuštěných GitHub kontrol prošlo; log jobu seat-checkout potvrzuje aplikaci všech tří nových migrací. To nedokládá spuštění nových measurement SQL assertions nebo doručení do skutečného Google Ads/Meta. V této plánovací fázi se testy neopakují.

Prověřená, ale nepotvrzená zranitelnost: pozdní callback používá `this.analytics`, ale běžná navigace přes RouterService starou FormPage zahodí a vytvoří novou. Reprodukce ruční výměnou property neprokazuje dosažitelný únik mezi pořadateli. Vazbu výsledku na původní session přesto zavést jako invariant; nevykazovat ji jako potvrzenou P1.

## Co skutečně zaručuje Consent Mode

Google rozlišuje basic režim, který před souhlasem Google tagy nenačítá, a advanced režim, který i s denied posílá cookieless pingy. Samotný default denied neznamená nulové požadavky. Vlastní HTML a ne-Google skripty se automaticky neřídí všemi pravidly Google tagů. Zvolit basic režim jako výchozí kontrakt Festapp. Advanced měření vyžaduje samostatný konkrétní návrh, konfiguraci a ověření; nepřidávat skrytý fallback.

Zdroje: [Consent mode overview](https://developers.google.com/tag-platform/security/concepts/consent-mode), [Consent implementation](https://developers.google.com/tag-platform/security/guides/consent), [GTM consent settings](https://support.google.com/analytics/answer/10718549?hl=en).

Enhanced conversions používají normalizované a SHA-256 hashované identifikátory. Hashování z nich nedělá anonymní data a nenahrazuje svolení je použít. `ad_user_data`, `ad_storage` a `ad_personalization` jsou odlišné technické signály; marketingová volba je může v první omezené implementaci ovládat společně, ale jejich význam nezaměňovat.

Zdroje: [Enhanced conversions](https://support.google.com/google-ads/answer/9888656?hl=en), [Server-side consent](https://developers.google.com/tag-platform/tag-manager/server-side/consent-mode).

Izolovaný iframe negarantuje stejné cookies, identitu a atribuci jako tag v hostitelském dokumentu. Click ID v URL samotné není důkaz fungující konverze. Zachovat CSP; nepovolovat same-origin skripty, další frames nebo service workers jen proto, aby integrační test zezelenal. Kompatibilitu případně vyřešit jiným explicitním provider adaptérem.

Zdroje: [Conversion linker](https://support.google.com/tagmanager/answer/7549390?hl=en), [Conversion troubleshooting](https://support.google.com/google-ads/answer/15299266?hl=en).

## Doporučená architektura

### Jeden hluboký modul místo vzájemných podmínek

Zavést `FormMeasurementSession` v `web_client/src/components/forms/form_measurement_session.js`. Je jediným vlastníkem aktuální způsobilosti, identity, uložené volby, generace a zvoleného transportu. Konstruktor pouze sestaví objekt; žádné síťové požadavky ani časovače před explicitním startem.

Malé veřejné interface:

```js
const measurement = new FormMeasurementSession({
  scope, policySource, consentSource, transport, clock,
  onActive: () => analytics.activate(currentSession),
});
measurement.start(); // přihlásí zdroje a zahájí reconcile, nečeká na volbu uživatele
measurement.record(event); // allowlistem omezená událost bez kontaktních polí; accepted/dropped
const sendObserved = measurement.capture(); // zachytit PŘED asynchronní prací
pendingWork.then(event => sendObserved(event));
measurement.dispose();
```

Změny identity/policy/consent/visibility jsou vstupy předaných zdrojů, které modul přihlásí a odhlásí. Nevystavovat stránce pořadí `setConsent -> renewPolicy -> updatePolicy -> start` nebo konkrétní epochy. `start()` je idempotentní spuštění sledování, vrací void a všechny asynchronní chyby modulu bezpečně zpracuje; disposed nelze znovu spustit. Vnitřní grant je obyčejný neměnný objekt; není to JWT ani nový backend autorizační systém.

`capture()` vrátí odesílací closure svázanou s aktuální session a generací. Není-li při zachycení stav active, closure zůstává trvale no-op. Po zneplatnění zachyceného grantu zůstává trvale no-op i po novém udělení souhlasu. Nejde o frontu a closure sama nedrží event/payload. `FormDataLayer.observe()` ji zachytí před čekáním na rezervace; doménová metoda `captureSubmission()` ji zachytí před submit a vrátí callback pro výsledek objednávky. FormPage tak nevidí epochu ani nevytváří analytics payloady.

- `FormDataLayer` ponechat jako vlastníka katalogu, změn košíku, významu událostí a deduplikace v rámci jedné návštěvy formuláře. Nemá číst Auth storage, obnovovat policy nebo rušit iframe. Při `onActive` nastaví baseline podle aktuálního košíku a publikuje aktuální page/catalog kontext; nepřehrává staré interakce. Již přijaté page_view/form_start/purchase zůstávají deduplikované i přes skrytí a další aktivaci.
- `FormMeasurementRuntime` je adaptér izolovaného transportu. Umí připojit, poslat a odpojit; neodvozuje souhlas.
- Host část `EmbedBridge` je druhý skutečný adaptér. Viewport, scrolling a theme zůstávají nezávislé na měření. Host handshake dodá vstup; sám nic neaktivuje.
- CMP adaptér dodá pouze uložené potvrzené účely, revizi a zánik zdroje. Nevolá `runtime.start()` ani `stop()`.
- SQL zachová jednu autoritu `form_measurement_status_internal` a typed operation predicates. Veřejná projekce doplní `processing_revision` a `required_purposes`; surové skripty zůstávají pouze v runtime konfiguraci.

Nevytvářet provider registry, obecný event bus, nový persistentní frontovací systém ani dvojí MeasurementService/Coordinator. Dva existující transporty opravňují transport seam; další abstrakce vzniknou pouze pro skutečnou druhou implementaci.

### Účely mají odpovídat tomu, co lze opravdu vynutit

Současný GTM/custom-script runtime obsahuje libovolný kód pořadatele a může kombinovat analytiku i reklamu. Festapp uvnitř takového kontejneru nedokáže zkontrolovat účel jednotlivého tagu. Proto pro tento smíšený profil doporučuji konzervativně vyžadovat **oba souhlasy** před jeho načtením. Je to vědomé produktové omezení doporučeného návrhu, nikoli již schválená vlastnost implementace.

| Uložená volba | Současný smíšený GTM/custom runtime | Kontakty v obecném dataLayer |
|---|---|---|
| Chybí / odmítnuto / neplatná | Nenačíst | Nikdy |
| Jen analytika | Nenačíst | Nikdy |
| Jen marketing | Nenačíst | Nikdy |
| Analytika i marketing | Lze načíst při platné policy a kontextu | Nikdy |

Čistě analytické měření po samotném analytickém souhlasu je možné nabídnout samostatným omezeným adaptérem se známým kódem a známými daty. Není součástí dokončení tohoto PR. Neoznačit libovolný GTM kontejner za analytický pouze přepínačem; tím by se neobejitelná pravidla znovu přenesla na pořadatele. Samostatný `required_purposes` konfigurační formulář nyní nepřidávat, hodnotu odvozovat z podporovaného profilu.

Pro host-owned transport platí stejná pravidla na výstupu Festapp. Nelze přikázat cizímu hostiteli, aby nenačetl vlastní tagy; lze mu neposlat žádnou měřicí událost bez příslušné volby. Schválený origin je podmínka příjemce, nikoli náhrada souhlasu. Nedůvěryhodný nebo neschválený host měřicí data nedostane. Načítání formuláře, nákup a layout embed tím neblokovat.

### Stav a generace

Odvozené stavy: blocked, awaiting-consent, starting, active, disposed. Chyba síťové policy znamená blocked; chyba nebo chybějící CMP znamená awaiting-consent. Oba chybové stavy jsou obnovitelné novým úspěšným vstupem. Jediný terminální stav je disposed. Není potřeba zvláštní třída pro každý stav.

Aktivní grant váže organization, Unit, canonical form link, identitu návštěvníka, účely, processing_revision, runtime/policy revision, transport origin+instance, generaci a lokální expiraci. Grant je pouze interní rozhodnutí browser modulu. SQL autorizaci nenahrazuje a hostovo tvrzení o souhlasu kryptograficky neověřuje.

1. Všichni čekající na stejnou policy/roli dostanou tentýž in-flight Promise. Odpověď se přijme pouze pro zachycenou generaci a identitu. Stará `finally` nesmí přepsat stav novějšího requestu.
2. Start se po obnově zdrojů znovu odvodí ze stavu; nesmí záviset na jednorázovém `.then(allowed)` ve FormPage. Unknown role u přihlášeného návštěvníka blokuje, staff se neměří.
3. Odmítnutí, zánik zdroje souhlasu, změna identity, expirace, odchod ze stránky a změna účelů nejprve synchronně zneplatní grant. Potom se odpojí iframe, zruší handshaky a zahodí rozpracované měřicí sendy. Již odeslaná data nelze vzít zpět.
4. Žádné `enabled()` nebo getter nesmí mít vedlejší efekt odpojení transportu. Rozhodnutí se mění jen při zpracování vstupu; kontrola před send je čistá.
5. Obnova stále stejné platné policy neobnovuje iframe. Změna processing/runtime/policy identity starý iframe zneplatní. Po nové aktivaci nereplayovat košík, kontakt nebo purchase z předchozího grantu.
6. Při skrytí/pagehide runtime odpojit. Také callback expirace odpojuje bez výjimky pro hidden dokument. Po návratu/BFCache ověřit zdroje a vytvořit novou generaci. Nezavádět neomezené běžení custom skriptu na pozadí kvůli obavě ze druhého GTM startupu. Deduplikace aplikačních událostí zůstává v ownerovi událostí.
7. Host consent má konečnou životnost, nejvýše stávajících 60 s; přihlášený zdroj ho může pravidelně potvrzovat. Detach, skrytí, změna instance/originu nebo ticho jej zneplatní. Bez helperu se měření nespustí po 5 s automaticky.

`onActive` se volá jednou při přechodu do active po úspěšném handshake; ekvivalentní policy renewal ho znovu nevolá. Callback neobnovuje data z minulých generací. Po suspend/resume přežívá aplikační deduplikace v témže FormDataLayer; staré captured sendery se nikdy neobnoví. Nové spuštění GTM může opakovat jeho vlastní automatické page views. Ty jsou mimo deduplikaci Festapp; netvrdit exactly-once pro celý kontejner.

Browser časovače nedávají pevnou real-time záruku backend revokace v uspáném procesu. TTL blokuje nové aplikační odeslání a odpojení při hide omezuje cizí běžící kód. Tuto provozní mez nepopsat jako okamžitý globální kill switch.

### Revize souhlasu

`processing_revision` odvozuje SQL z organization/Unit, uloženého GTM ID/script, privacy URL, runtime profilu, schválených příjemců, collector konfigurace a explicitní `measurement_consent_version`. Použít jeden deterministický opaque fingerprint, ne nový podpisový nebo revizní framework. Kosmetické změny barvy a rozložení ho nemění.

`measurement_consent_version` je kladný integer v kanonickém Unit settings kontraktu; chybějící historická hodnota znamená 1. Pořadatel ji přes tutéž autorizovanou aggregate mutaci může změnit pouze zvýšením, SQL odmítne pokles/null a aggregateVersion zabrání přepsání souběžné změny. UI může nabídnout akci „Vyžádat nový souhlas“, která uloží další verzi; nezobrazovat technický fingerprint. Stejnou možnost a pravidla dokumentovat v MCP. Text slibující jiný účel vyžaduje zvýšení této verze; kosmetická editace nikoli.

Fingerprint nevidí změnu obsahu vzdáleného GTM kontejneru se stejným ID, externího skriptu se stejnou URL ani obsahu zásad na stejné adrese. Za takovou změnu a zvýšení consent verze odpovídá pořadatel. Nelze tvrdit, že Festapp technicky rozpoznává všechny změny účelu nebo skutečné bytes vzdáleného kódu.

Uložená volba patří organization+Unit+processing_revision. Nová konfigurace nenabude souhlas automaticky ze starého cookie. grant pro send navíc patří konkrétnímu formuláři a instanci. Dlouhodobý záznam volby CMP a krátkodobá čerstvost host zdroje jsou různé věci; neopakovat návštěvníkovi dialog každých 60 s.

### Handshake potvrzuje konkrétní konfiguraci před spuštěním kódu

Měřicí protokol změnit na `protocol: 2` v namespace `festapp-measurement`. Layout/scroll/theme protokol `festapp-embed` zůstane 1. V jeho existující init může být samostatný měřicí envelope verze 2; layout pole žádné měřicí oprávnění nepřiznávají. Staré měřicí zprávy se odmítnou, nesmí se tiše převést na nový grant.

1. RPC runtime config vrátí stejnou veřejnou revizní projekci jako policy a konfiguraci z téhož SQL snapshotu. Worker do explicitního bootstrap configu vloží organization, Unit, canonical form link, processing/runtime/policy revision, profil a required_purposes. Do public parentu neposílá skripty ani backend credentials.
2. Bootstrap před Unit kódem odešle ready s tímto manifestem. Parent/session ověří origin a source window a porovná manifest se snapshotem, ke kterému má současný souhlas. Nesoulad zruší frame a obnoví policy; pro nový processing_revision bude potřeba odpovídající uložená volba.
3. Teprve při shodě parent pošle init s manifest identity, instancí, generací a grantem. Bootstrap sám ověří shodu s vlastním configem a required_purposes; potom nastaví Consent Mode a může vložit GTM/Unit skripty. ACK vrátí tutéž manifest identity. Parent se stane active jen po shodném ACK a stále platném grantu.
4. Timeout, zánik grantu a pozdní ready/ACK bezpečně odpojí frame. Před handshakem lze spustit pouze vlastní statický bootstrap, nikoli kód pořadatele. Manifest garantuje shodu uložené konfigurace Festapp, ne neměnnost vzdáleného GTM obsahu.

Host-owned transport má obdobnou výměnu bez načtení Unit kódu: child předá scope, processing_revision a required_purposes; helper může potvrdit jen uloženou volbu bound na tuto revizi. Novou revizi nelze automaticky označit za schválenou podle starého globálního `true`. Integrátor buď používá revision-bound CMP adaptér, nebo explicitně znovu potvrdí po vyvolání souhlasu pro daný kontext; bez takového zdroje zůstane měření vypnuté.

Helper po novém potvrzení vytvoří náhodné lease ID pro scope+revision+instance. Child si lokálně od přijetí měří krátkou platnost; nepřebírá cizí absolutní timestamp. Heartbeat stejnou volbu znovu čte ze živého CMP zdroje a prodlužuje tutéž lease; nesmí jen přeposílat kdysi uložený boolean. Zánik zdroje, změna volby/revize/instance vyžaduje invalidaci a nový lease. Každá měřicí událost nese lease ID a generaci; helper před push ověří aktuální vlastní zdroj, lease, instance, scope/revision a vlastní lokální expiraci. Legacy ruční boolean setter není obnovitelným zdrojem nového protokolu. Starý helper zachová nákup/layout, ale nové měření neaktivuje.

Konkrétní nový veřejný host vstup je `FestappEmbed.connectMeasurementConsent(frame, source) -> disconnect`. Zdroj má `read(context) -> {processingRevision, analytics, marketing} | null` a `subscribe(notify) -> unsubscribe`. Read je synchronní čtení skutečně uložené a potvrzené volby; vrácená processingRevision pochází z tohoto uloženého záznamu, nesmí se jen opsat z argumentu. Context obsahuje organization, Unit, processingRevision a requiredPurposes. Přesun na nový kontext vyžaduje nový revision-bound záznam, nikoli přejmenování starého consentu. Přizpůsobení konkrétní host CMP je integrátorská povinnost a testuje se na deterministickém zdroji; helper sám nesmí změnit globální host CMP nebo zobrazovat nevyžádané druhé dialogy.

### Kontakty nepatří do obecné události

Z obecného `analyticsPayload`, runtime i host dataLayer úplně odstranit `user_data`. Historické pole dataLayer není důvěrný kanál a nulovací událost historii nemaže. Prosté nahrazení e-mailu hashem v tomtéž obecném poli neřeší tuto vlastnost.

Reklamní atribuce a konverze s částkou, produkty a stabilním náhodným event ID bez kontaktu zůstávají užitečné i bez enhanced conversions. Stabilní identifikátor přitom není automaticky anonymní údaj. Dokončení tohoto PR proto nevyžaduje export kontaktů. Nevracet aktivní enhanced přepínač jen kvůli příslibu funkce.

Pokud produkt později vyžaduje enhanced conversions, vznikne oddělený konkrétní Google adaptér. Dostane normalizované identifikátory pouze pro právě platný marketingový grant, po explicitním zapnutí pořadatelem a s prokázanou funkčností izolace. Kontakty nesmějí do host zpráv, obecného dataLayer, conversion_facts, URL, persistence ani logů. Případné normalizování/hashování se řídí dokumentovaným provider kontraktem, nikoli vlastní ad-hoc regex implementací. Tato cesta je nyní mimo implementační scope; žádný placeholder s funkčním exportem.

### Objednávka a doručení

`form_page.js` zachytí submittedSession a callback z `analytics.captureSubmission()` před asynchronním submit. Callback uvnitř používá captured sender, nikoli pozdější `this.analytics` ani pouze odkaz na stejný stále existující owner. Výsledek patří jen původní session a grantu. Disposed, jiné scope, jiná generace nebo pozdější souhlas znamenají drop měřicího výsledku; business výsledek se zpracuje normálně. Stejně zachytit sender u rezervací v observe. Pro tuto verzi žádný kontakt ani nezachycovat.

Ponechat SQL obchodní facts a autorizovaný receipt replay bez osobních údajů. Jejich současné podmínky jsou trvalé enablement přepínače a platné zásady; dočasná dostupnost runtime není podmínkou záznamu. Nenahradit je plošně `eligible`, což by při provisioning nebo runtime výpadku zahazovalo obchodní fakta. Browser výstup naopak potřebuje celou aktuální způsobilost a souhlas. `purchase` nadále znamená přijatou objednávku, nikoli potvrzené zaplacení. Stabilní event_id/transaction_id se nemění při replay. V browseru jde o omezené best-effort doručení, nikoli exactly-once: postMessage úspěch není potvrzená konverze u poskytovatele. Nezavádět kvůli tomu frontu, která po pozdějším souhlasu přehraje staré nákupy.

## Implementační vlny

### 1. Sjednotit kontrakt a bezpečné výchozí chování

- Aktualizovat PR vůči main a přegenerovat konfliktní MCP referenci ze zdroje. Needitovat generovaný JSON ručně.
- V `form_measurement_contract.js` odstranit contactUserData a user_data z povolených payloadů. Zachovat attribution allowlist a item_category/item_brand.
- Do `packages/festapp_contracts/configuration-settings.json` doplnit `unit.measurement_consent_version` jako kladný integer a zachovat jeden zdroj SQL/MCP kontraktu. Kanonická autorizovaná Unit aggregate mutace odmítne pokles/null a veřejná projekce doplní výchozí 1. V `form_measurement_policy.sql` doplnit processing_revision a required_purposes pro aktuální smíšený profil; `enhanced_conversions_unavailable` vrátit na true.
- Vrátit UI/MCP popisy do souladu se skutečným basic kontraktem a omezením obou účelů. Zobrazit, že analytika-only tento smíšený kontejner nespustí. Privacy URL i všechny existující organization/Unit/form přepínače zachovat.
- Canonical SQL a migrační kopie musí zůstat shodné. Pokud tři migrace PR nejsou nikde aplikované, lze je před publikací zregenerovat jako součást nepublikované změny. Pokud již aplikované jsou, ponechat jejich historii a vytvořit novou forward migraci. Stav zjistit přes approved postup; neodhadovat jej z pořadí SHA.

Výstup: explicitní technický kontrakt bez PII exportu a bez nepravdivé dostupnosti enhanced conversions. Během rozpracovaného refaktoru žádný deploy.

### 2. Přesunout rozhodování do FormMeasurementSession

- Přesunout policy/role renewal, lifecycle, generace a subscriptions z FormDataLayer do nového modulu.
- Implementovat sdílený in-flight Promise, čisté rozhodnutí, onActive a captured sender pro všechny asynchronní události. CMP připojit i během unknown role tak, aby nenastartovalo runtime; staff kontext nemusí notice zobrazovat. Stránka sama nesmí čekáním na roli navždy přeskočit vytvoření session. Ekvivalentní renewal zachová generaci a disposed je jediný neobnovitelný stav.
- FormDataLayer přijme jen event sink. FormPage vytvoří ownera, připojí UI a při clear/init ho zlikviduje. Submit outcome zachytí ownera před requestem.
- Odstranit původní konstruktorový renewal, visitorReady, transport-revoking enabled() a veřejné sekvence volání, které nový modul nahrazuje. Nemít druhý paralelní policy timer.

Výstup: jediný vlastník start/stop, bez závodu přihlášených; pozdní odpovědi a odhlášení nemění novější generaci.

### 3. Vynutit pravidla v obou transportech

- Runtime připojit pouze s platným rozhodnutím session. RPC/Worker/bootstrap zachovají skutečný revizní manifest a measurement protocol 2 ověří jeho shodu před vložením Unit kódu. Před načtením GTM deklarovat Consent Mode stav; každý update případně publikovat atomicky i jako `festapp_consent` pro dokumentované čtenáře. Consent Mode je doplňková informace, nikoli bezpečnostní gate.
- Odmítnutí a změna účelů odstraní dokument s cizím kódem. Zrušit bezpodmínečné starty, start v catch, timeout fallback a podporu kontaktů v bootstrapu.
- Host helper/bridge implementují výše uvedený measurement envelope a connectMeasurementConsent se skutečně revision-bound zdrojem. Handshake váže origin, source window, scope/revision, instance, účely, lease ID a generaci. TTL se měří lokálně a heartbeat znovu čte zdroj; viewport ani jednorázový setter jej nesmějí prodlužovat. Zprávy pro starou generaci/lease receiver zahodí. Po vypršení zdroj přestane posílat; receiver před push ověří vlastní dosud platnou volbu.
- Boolean starého `setMeasurementConsent(true)` stále znamená jen analytiku a smíšený profil tím neaktivuje. Starší helper může zobrazovat/nakupovat, ale chybějící marketing nebo chybějící čerstvost nesmí obejít gate. Zachovat jen tuto explicitní externí kompatibilitu, ne always-on aliasy.
- Host a Unit runtime současně nikdy neposílají stejnou událost. Výběr transportu uzavřít před aktivací; pozdní změna vytvoří novou generaci.

Výstup: stejná pravidla pro standalone, běžný embed i host-owned dataLayer, bez PII v kterékoli zprávě.

### 4. Kontraktní testy, generované výstupy a dokončení

- Přepsat testy always-on jako testy zákazu načtení i zákazu událostí. Obnovit odebrané no-consent/no-replay/revoke/expiry assertions; netestovat jen volání setConsent(false).
- Doplnit integrační regresi skutečného pořadí `new FormDataLayer/session -> start -> delayed policy`, včetně role visitor, staff, error a stale identity odpovědi. Test, který dodá refreshPolicy až po konstrukci, jej nenahrazuje.
- Doplnit opožděný submit i awaitPendingReservations přes revoke/regrant stejného ownera, opakovaný stejný receipt, BFCache, CMP error/recovery, chybějící helper, neschválený host, opožděný ACK a změnu runtime revize. Mezi parent policy a Worker fetch vložit změnu script/GTM konfigurace a dokázat, že se Unit kód nespustí. Host heartbeat nesmí obnovit lease z odpojeného zdroje ani převést souhlas na novou revizi. Zvýšení consent version musí zneplatnit starou uloženou volbu. Generování kryptografických credentials ani produkčních objednávek není potřeba.
- V browseru kontrolovat skutečné síťové požadavky a script elements před volbou, po odmítnutí, po povolení a po odvolání. Pro tagy použít deterministické skripty s pozorovatelným efektem; reálného poskytovatele ověřovat odděleně.
- Measurement SQL testy zařadit do kanonického `automation/ci/checks.json` v existující seat-checkout lane po bootstrapu. Measurement browser suite zařadit do existující web-startup lane; nekopírovat test seznam do další workflow. Db assertions musí běžet nad izolovaným DB, nejen úspěšně aplikovat migrace.
- Přegenerovat embed/runtime/MCP ze zdrojů a ověřit check režimy. Opravit všechny lokalizace a integrační dokumentaci. Nový test nápovědového překladu nepsat; testovat strojové payloady a chování.

Výstup: cílená sada dokazuje doručení i absenci před souhlasem a odstranění starých cest. Publikace zdrojů až po relevantních canonical CI mirror lanes.

## Ověření a ukončovací podmínky

| Riziko | Nejmenší průkazné ověření při implementaci |
|---|---|
| Startup race / stale odpověď | Node kontraktní test s odloženým Promise a skutečným startup pořadím |
| Neoprávněné tagy nebo odchozí události | `pnpm --dir web_client run test:measurement-browser` a runtime/nested/adversarial varianty; síťová absence před souhlasem a po odmítnutí |
| Chybný CMP/host nebo replay | Cílené measurement, embed a submission lifecycle Node testy; generace a expirace |
| Jiná konfigurace při skutečném načtení | RPC/Worker/bootstrap handshake test s policy A a runtime config B; žádný Unit script side effect |
| SQL drift, grants a revize | Measurement SQL adresář plus canonical mutation parity nad disposable DB přes repozitářový runner; ověřit počet vybraných testů |
| Nastavení UI/MCP | Relevantní Unit/form Flutter případy a konfigurace MCP; pouze jeden Flutter task a `--concurrency=1` |
| Generované artefakty | `build_embed.mjs --check`, `build_measurement_runtime.mjs --check`, existující MCP docs:check |
| Publikace | Affected lanes `automation/test_ci.sh`; po integraci všech osm required GitHub jobs na přesném baseMainSha před tenant overlay/release |

Browser ověření delegovat na Terra; izolované background sessions, muted, light mode. Nepoužívat přihlášené uživatelské okno. Neprovádět browser práci jen kvůli tomuto plánu.

## Odstranění nahrazených cest

| Artefakt | Konečný stav | Důkaz |
|---|---|---|
| PII v obecném analyticsPayload, contact extraction v submit, host/runtime user_data | Odstranit | Seeded e-mail/telefon/secret se nenachází v žádném měřicím payloadu, dataLayer historii ani DB facts |
| Bezpodmínečný start, catch-start, 5s auto-start | Odstranit | Broken/no CMP a absent host nenačtou žádný cizí tag |
| Policy/Auth/visibility vlastníci ve FormDataLayer a zrcadlené gates v bridge | Přesunout do session, odstranit původní | Jeden owner a jedna obnova; transport nemá právo sám přiznat oprávnění |
| Always-on testy a nepravdivé návody | Nahradit | Testy dokazují gate a nové UI/MCP/docs popisují stejnou matici |
| Measurement protocol 1 a lease bez revize | Odmítnout v nové implementaci | Staré/cached měřicí zprávy nespustí kód ani push, layout protocol 1 dál funguje |
| Původní GTM consent template | Nepotřebné nevracet automaticky | Zvolený basic gate funguje mimo GTM; doplňkový provider consent má explicitně ověřené pořadí |
| Starší veřejný boolean embed setter | Ponechat jen jako analytics-only vstup | Nemůže vytvořit marketingový grant ani obejít expiraci |
| Unit Pages izolace, SQL facts a receipt replay | Zachovat | Žádný same-origin fallback a žádné nové PII sloupce |

## Rollout, meze a rozhodnutí

Implementace a plánování neautorizují commit/push, komentář do PR, migraci produkce, změnu collectorů, zapnutí měření ani tenant deployment. Žádný nový provozní projekt nevytvářet. Historické zjištění v plánu PR747, že nebyl zapnut žádný Unit runtime, není aktuální provozní důkaz.

Po zvláštním schválení rollout dodrží main/tenant ancestry, affected canonical CI mirror, všech osm required GitHub checks na přesném baseMainSha, backend access skill pro SQL a lokální direct deployment pro jediný vybraný tenant. Předem zkontrolovat aktuálně zapnuté Unit/formy, chybějící privacy URL a existující GTM consent konfiguraci; změnu cizího kontejneru nepovažovat za automatickou součást deploymentu aplikace. Pro nekompatibilní runtime protokol dočasně vypnout scoped measurement, aplikovat databázový kontrakt a nasadit runtime/helper/aplikaci; zapnout až po kompatibilních probes. Nesmí existovat mezikrok s povoleným always-on fallbackem. Checkout musí po celou dobu zůstat funkční.

Otevřený starý always-on klient není smazán novým deployem ani DB přepínačem. Před tvrzením úplného provozního cutover doložit, že v daném scope nebyl starý runtime nikdy aktivní, nebo zánik/reload dříve běžících klientů či jiný konkrétně prokázaný způsob ukončení. Bez takového důkazu zůstane měření vypnuté a legacy runtime se vykáže jako provozní zbytkové riziko; nový kontrakt se smí vykázat jako ověřený pro nové klienty. Žádný limit starých skrytých sessions nevymýšlet z TTL, které původní kód nevynucoval. Nová aplikace zachová nákup/layout i se starým helperem, ale měření bude bezpečně zablokované do upgradu.

Rollback může ponechat měření vypnuté a vrátit kompatibilní bezpečný build. Nesmí znovu zapnout cestu exportující kontakty po odmítnutí. Measurement protocol 2 je jediná nová měřicí cesta; zachování layout protocol 1 ani starého analytics-only veřejného setteru neznamená podporu starých měřicích grantů.

Rozhodnutí návrhu: basic režim, jeden owner, existující dva transporty, současný smíšený profil vyžaduje oba účely, žádné kontakty v obecném dataLayer, bez enhanced conversions v tomto scope. Tato přísnější matice je doporučení k produktovému přijetí, ne tvrzení o nutnosti předepsané Googlem nebo zákonem.

Předpoklad: hlavní cíl nyní je spolehlivá a kontrolovatelná reklamní atribuce; enhanced matching není podmínka přijetí PR. Pokud je enhanced matching nebo analytics-only libovolný GTM nutný, návrh se musí znovu produktově rozhodnout před implementací dané části, ne obejít fallbackem.

Meze: schválený host může lhát o své CMP a po přijetí může data zpracovat mimo kontrolu Festapp. Již doručená data nelze odvolat. Arbitrární skript po oprávněném spuštění může mít vlastní efekty na povolených collectorech. Allowlist kampaní a veřejných produktových názvů nezaručuje anonymitu jejich řetězců; garantujeme odstranění kontaktních polí a nepřebírání soukromých odpovědí formuláře, nikoli globální PII-free klasifikaci všeho, co pořadatel vložil do veřejných názvů/URL. Iframe může omezovat skutečnou reklamní atribuci; doručení a deduplikaci u Google/Meta lze potvrdit až na schválené testovací konfiguraci. Žádný nový plánovaný test nebo provider adaptér se v této fázi nevydává za vykonaný.

Hotovo znamená: jedna session rozhoduje pro všechny vstupy a oba transporty, žádný cizí měřicí kód před příslušnou volbou, žádné kontakty v obecném exportu, přihlášený visitor se spolehlivě inicializuje, staré generace a zakázané replaye jsou zahazovány, SQL zůstává autoritou způsobilosti a CI skutečně vykonává relevantní assertions. Produkční nasazení se vykazuje samostatně jako neprovedené, dokud neproběhne jeho schválený postup.


## Implementační aktualizace 2026-11-07

Fetched main je `44a46d6a8` (nová oprava RPC editoru z #751), PR head zůstává
`65705b455`. Main byl lokálně začleněn bez vytvoření merge commitu. Konfliktní MCP
reference byla přegenerována. Merge odhalil kolizi timestampu `20261106220000`:
autoritativní main jej používá pro cash_reservations, PR pro Unit privacy URL.
Privacy migrace byla pouze přejmenována na `20261106221000`, její obsah je
byte-for-byte zachován. Žádná historická SQL definice nebyla přepsána; nový kontrakt
je samostatná forward migrace `20261107110000_form_measurement_consent.sql`.
Před případnou budoucí produkční aplikací je nutné ověřit ledger a vyřešit identitu
případně aplikovaného PR timestampu, nikoli předpokládat, která z kolidujících
migrací už běžela. Lokální disposable bootstrap používá jednoznačné timestampy.
Produkční ledger nebyl čten ani měněn.


Implementační výsledek a skutečně provedené kontroly jsou zaznamenány v
[RESULT-2026-11-07](form-measurement-pr750-RESULT-2026-11-07.md). Izolovaná větev
je proti fetched mainu, změny zůstaly necommitnuté a žádný provozní krok neproběhl.
