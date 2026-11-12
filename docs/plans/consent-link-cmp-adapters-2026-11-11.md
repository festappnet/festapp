# Převzetí souhlasu CookieConsent v3 — 2026-11-11

Rozsah této etapy: pouze CookieConsent v3 (orestbida). Cookiebot a CookieYes
jsou odloženy. Bez commitu, publikace a změn Complianzu nebo GCM mostu.

## Rešerše před implementací

| Oblast | Ověření a zvolená hranice |
| --- | --- |
| Uložená volba | `validConsent()` a `getCookie()` jsou veřejné API; před volbou není platný záznam. `acceptCategory` ukládá kategorie, `consentId`, čas první a poslední volby. API nedokládá fyzické kliknutí: stejně může rozhodnutí uložit kód webu. Vyžadujeme platné API, neprázdný identifikátor, platné časy a uložené kategorie. [API](https://cookieconsent.orestbida.com/reference/api-reference.html), [ukládání v3.2.0](https://github.com/orestbida/cookieconsent/blob/v3.2.0/src/utils/cookies.js). |
| Opt-in / implied | `mode` má hodnoty `opt-in` a `opt-out`; druhý umožňuje spuštění výchozích kategorií před volbou. Kategorie mohou být `enabled` nebo `readOnly`. Podporujeme pouze `opt-in` a obě mapované kategorie bez těchto příznaků; API nemá příznak explicit/implied. Chybějící doklad volby vrací `null`. [Konfigurace](https://cookieconsent.orestbida.com/reference/configuration-reference.html). |
| Verze zásad | Vlastní `revision` je přímý ekvivalent policyId. Výchozí nula vypíná správu revizí podle dokumentace. Vyžadujeme kladné bezpečné celé číslo `revision` v JSON helperu, konfiguraci CMP i cookie, všechny shodné. Správce archivuje obsah a mapování na Festapp `consentRevision`; číslo samo obsah zásad neověřuje. [Revize](https://cookieconsent.orestbida.com/advanced/revision-management.html). |
| Expirace a jiná karta | `getCookie()` čte skutečné úložiště, zatímco `validConsent()` a `acceptedCategory()` používají stav instance, který se nemusí změnit při expiraci nebo změně v jiné kartě. `expirationTime` se ukládá jako epoch ms; je ve zdrojáku, ale chybí ve výčtu polí API dokumentace. Vyžadujeme budoucí konečný čas, čteme čerstvou cookie a porovnáváme s kategoriemi API každou sekundu. Neshoda vrací `null`, nová kladná volba z jiné karty vyžaduje sladění instance (například reload). Podporováno i `cookie.useLocalStorage`. [Zdroj cookie](https://github.com/orestbida/cookieconsent/blob/v3.2.0/src/utils/cookies.js), [stav API](https://github.com/orestbida/cookieconsent/blob/v3.2.0/src/core/api.js), [localStorage](https://github.com/orestbida/cookieconsent/blob/v3.2.0/src/utils/localstorage.js). |
| Události | `cc:onFirstConsent`, `cc:onConsent`, `cc:onChange` na `window`. Obsah události není autoritou; po microtasku se čte API. Oznámení pouze při změně výsledku, interval zachytí i změny bez události. [Události](https://cookieconsent.orestbida.com/advanced/callbacks-events.html). |
| Služby | `acceptService` / `acceptedService` a `getCookie().services` umožňují oddělené volby uvnitř kategorie. Takové mapované kategorie automaticky nepřevádíme: neprázdné definice či uložené seznamy služeb pro analytics/marketing vrátí `null`. [API](https://cookieconsent.orestbida.com/reference/api-reference.html), [kategorie](https://cookieconsent.orestbida.com/reference/configuration-reference.html#categories). |
| TCF | Ve veřejném API a konfiguraci není doložen převod TCF účelů a vendorů na tyto kategorie. Žádný takový převod neděláme; při přítomném `window.__tcfapi` marketing zůstává false. Jde o konzervativní pravidlo integrace, nikoli tvrzení knihovny. [API](https://cookieconsent.orestbida.com/reference/api-reference.html), [konfigurace](https://cookieconsent.orestbida.com/reference/configuration-reference.html). |
| Globální API | Npm používá modulový import; web musí pro helper nastavit `window.CookieConsent = CookieConsent`. [Instalace](https://cookieconsent.orestbida.com/essential/getting-started.html). |

## Implementace a ověření

Samostatný adaptér zachová kontrakt `read(scope)` / `subscribe`. Neplatný JSON,
neznámý provider a neplatná konfigurace zůstávají configured a denied, bez GCM
fallbacku. Názvy kategorií lze určit přes `categories.analytics` a
`categories.marketing`, výchozí jsou `analytics` a `marketing`; musí být odlišné.

Testy použijí přesně připnutou `vanilla-cookieconsent@3.2.0` v oddělených JSDOM
oknech, skutečný vygenerovaný helper, Klaro a FormMeasurementSession. Stav
expirace a jiných karet se ověří změnou úložiště bez změny stavu instance.

## Stav provedení

Hotovo pro CookieConsent v3: adaptér `web_client/src/embed/host_cookieconsent.js`,
výběr provideru v `host.js`, generovaný `embed.js`, unit a integrační testy se
skutečným helperem, Klaro a `FormMeasurementSession`, registrace v CI, dokumentace,
CS/EN nápověda a changelog. Complianz ani GCM implementace se neměnily.
Testovací závislost `vanilla-cookieconsent` 3.3.0 (aktuální stabilní verze).

Ověřeno:

- `host_cookieconsent.test.js` a `form_consent_link_cookieconsent.test.js` proti
  skutečné knihovně: 64/64.
- Regrese Complianz, odkazu, GCM, embedu, CMP a session: 255/255.
- `build_embed.mjs --check`, testy nápovědy.
- E2E na živém webu s CookieConsent 3.1.0 (opt-in, `revision` 3, HTML webu bez
  úprav, vložen jen helper s konfigurací a odkaz; měřicí požadavky blokované)
  v Chromiu, Firefoxu a WebKitu: bez volby → lišta formuláře; přijetí → převzato,
  ve formuláři žádná cookie ani localStorage; odmítnutí → převzato; jen analytika;
  změna volby při otevřeném formuláři; nesoulad revize → lišta; zavření karty
  webu (i bez `pagehide`, zachytí `peer.closed` do ~1 s); reload webu → konec.
- Omezení: po pádu renderu karty webu (`peer.closed` zůstává false) platí převzatá
  volba do vypršení lease, nejdéle 60 s. Web s `<meta name="referrer">` převzetí
  nespustí (stávající pravidlo odkazu, beze změny).

Cookiebot a CookieYes jsou další etapy.

## Etapa Cookiebot — rešerše před implementací

Rozsah: pouze Cookiebot, bez změny hotového CookieConsent v3, Complianzu a GCM.
Živou lištu v automatickém i ručním blokování ověří správce na svém webu;
jednotkové testy modelují dokumentovanou hranici, nestahují Cookiebot runtime.

| Oblast | Oficiální doklad a konzervativní rozhodnutí |
| --- | --- |
| Výslovná volba | SDK dokumentuje `consent.{necessary,preferences,statistics,marketing,method}`, `hasResponse`, `consented`, `declined`. `method` je explicit/implied/null; staré neznámé volby jsou implied. Vyžadujeme explicit, booleany (včetně hasResponse) a konzistentní consented/declined. hasResponse je při otevřeném renew false, i když uložená volba dál platí (změřeno), proto převzetí nepodmiňuje; váže ho uložené ID souhlasu. Pouhá událost ani otevření/zavření dialogu nejsou volbou. [SDK](https://www.cookiebot.com/en/developer/). |
| Opt-in a regulace | SDK zveřejňuje gdprApplies/ccpaApplies/lgpdApplies; to je geolokace, nikoli nastavení lišty. Běžný loader nemá data-type ani data-level (změřeno), režim pochází z nastavení účtu. Opt-in proto odvozujeme z runtime: method explicit, gdprApplies true, ccpaApplies false. Nedokumentované `responseMode` (naměřeno `leveloptin`) je-li přítomno, musí být optin/leveloptin/inlineoptin. Přechodný inlineoptin byl ověřen při obnově volby na živém Cookiebotu; stále vyžaduje všechny kontroly výslovné uložené volby. Implied, jiný či neznámý režim vrátí null. Automatické versus ruční blokování není režim souhlasu a není podmínkou převzetí. [SDK](https://www.cookiebot.com/en/developer/), [automatické blokování](https://support.cookiebot.com/hc/en-us/articles/360009074960-Automatic-cookie-blocking). |
| CBID / doména | data-cbid nebo parametr cbid na `https://consent.cookiebot.com/uc.js` označuje skupinu domén, ne verzi zásad. Vyžadujeme právě jeden takový script, shodné povinné `cbid` konfigurace a povinný `origin` shodný s aktuálním webem. Při změně CBID nebo originu vracíme null; kopie staré cookie sama CBID nedokládá. [SDK](https://www.cookiebot.com/en/developer/), [skupiny a sdílení](https://support.cookiebot.com/hc/en-us/articles/360003792573-Cross-domain-Consent-Sharing-in-the-Cookiebot-Admin). |
| Revize / obnova | Ve zveřejněném seznamu SDK není aktuální a uložená revize zásad k porovnání. Support doporučuje obnovovat podle `Cookiebot.consentUTC`. Povinné `consentValidFrom` (UTC ISO datum s časem) mapuje archivované znění na consentRevision; starší záznamy se odmítnou. Při změně zásad správce nastaví nový cutoff, obnoví souhlasy v Cookiebotu a aktualizuje mapování. To není automatické ověření obsahu zásad ani kryptografické přiřazení CBID; správce nesmí přiřadit nový rozsah starému cutoffu. [Cutoff](https://support.cookiebot.com/hc/en-us/articles/12875664186268-Renewing-consents-after-a-specific-cutoff-date), [obnova](https://support.cookiebot.com/hc/en-us/articles/26380933353372-Renew-existing-user-consents-in-the-Cookiebot-Manager). |
| stamp / consentID / ver | Seznam veřejných SDK vlastností nepopisuje `consent.stamp` ani `consentID`. Support popisuje náhodný klíč pro vyhledání záznamu a ukazuje cookie s `stamp`, `utc`, `ver`. Není doložen význam `ver` jako verze zásad ani stabilní vztah consentID/stamp: `ver` proto nepoužíváme jako revizi. Naměřeno: `consentID` a `consent.stamp` jsou vždy přítomné a shodné (bez volby `'0'`, po volbě nový base64 klíč). Vyžadujeme je shodné a platné (ne 0/-1). Z cookie čteme jen pole `stamp`, které musí být právě jedno a shodné s consentID; ostatní pole (kategorie, ver, utc, region) neinterpretujeme. Jiný formát vrací null. [Log souhlasů](https://support.cookiebot.com/hc/en-us/articles/360003782654-Logging-and-demonstration-of-user-consents), [oficiální příklad cookie](https://support.cookiebot.com/hc/en-us/articles/360006346473-Extracting-cookie-information-via-API), [SDK](https://www.cookiebot.com/en/developer/). |
| Expirace / jiná karta | Support uvádí nastavitelnou dobu platnosti, výchozích 12 měsíců a zkrácení prohlížečem. Veřejné SDK nedává getter skutečné expirace cookie. Povinné maxAgeSeconds (nejvýše 365 dní) musí být nejvýše dobou nastavenou správcem; kontrolujeme consentUTC (tolerance 60 s do budoucnosti, změřený předstih je jednotky ms) a uložený stamp. Odstranění/neshoda vrací null i při starém API v paměti; každá neshoda okamžitě vrátí null. Cookiebot zapíše cookie o pár ms dřív než consentID/consentUTC, ale přechodný zápis nelze bezpečně odlišit od odvolání v jiné kartě nebo smazaného záznamu. Již otevřený formulář neshodu odhalí nejpozději při následující sekundové kontrole. Interval 1 s doplňuje události. Neměníme cookies ani neprodlužujeme expiraci. [Expirace](https://support.cookiebot.com/hc/en-us/articles/360023003294-Cookie-consent-expiration-in-Safari-12-1-and-newer), [čtení cookie](https://www.cookiebot.com/en/developer/). |
| Události | CookiebotOnConsentReady, CookiebotOnLoad, CookiebotOnAccept, CookiebotOnDecline, CookiebotOnDialogDisplay na window. Accept/Decline mohou nastat i při obnovení uložené volby, nikoli pouze při kliknutí. Čteme po microtasku a oznamujeme jen změnu výsledku. [SDK](https://www.cookiebot.com/en/developer/). |
| Služby / TCF | Základní SDK dokumentuje kategorie, nikoli obecné per-service API. Neinterpretujeme nezdokumentované per-service struktury (null). TCF dovoluje samostatné volby vendorů a účelů: marketing proto zůstává false při __tcfapi nebo data-framework IAB/TCF (také query data-framework). Neprovádíme projekci vendorů do celé kategorie. [TCF](https://support.cookiebot.com/hc/en-us/articles/360007652694-Cookiebot-CMP-and-the-Transparency-and-Consent-Framework-TCF), [SDK](https://www.cookiebot.com/en/developer/). |

### Cookiebot — měření skutečné lišty (2026-11-11)

Testovací web s CBID účtu, `/` (data-blockingmode auto) a `/manual/` (bez
blokování), headless Chromium, Firefox a WebKit, čistý profil, česká IP.
Výsledky jsou ve všech třech enginech a na obou stránkách stejné.

- Loader: jen `id`, `src`, `data-cbid`, `type` (a `data-blockingmode` u auto).
  Bez `data-type`/`data-level`. Lišta se zobrazí i při `navigator.webdriver`.
- Bez volby: hasResponse false, consented/declined false, consentID a
  consent.stamp `'0'`, method null, consentUTC null, cookie chybí,
  regulations `{gdprApplies:true,ccpaApplies:false,lgpdApplies:false}`.
  Nedokumentované: responseMode `leveloptin`, consentLevel `strict`.
- Přijetí / odmítnutí / jen statistiky: hasResponse true, method explicit,
  nový consentID = consent.stamp, consentUTC je Date (o 10 až 350 ms po kliknutí,
  při CookiebotOnConsentReady až o 14 ms před Date.now()). consented/declined
  odpovídají kategoriím. `consent.services` neexistuje, `__tcfapi` neexistuje.
- Cookie `CookieConsent` (Secure, SameSite Lax, platnost 12 měsíců):
  `{stamp:'…',necessary:true,preferences:…,statistics:…,marketing:…,method:'explicit',ver:1,utc:…,region:'cz'}`,
  v document.cookie s `%27` a `%2C`. localStorage nepoužívá.
- Reload: stejné ID, utc i kategorie; consentLifetime je null.
- Renew (otevřený dialog): hasResponse false, isRenewal true, ostatní (consented,
  ID, kategorie, cookie) zůstává. Nová volba: nejdřív se změní kategorie, pak se
  zapíše cookie s novým stamp a až v dalším tasku consentID/consentUTC.
- Jiná karta a smazaná cookie: API původní karty se nezmění (ani po 12 s),
  takže samotné API nestačí; uložený stamp je nutný k odhalení jiné volby a
  expirace. Veřejný getter cookie SDK nedokumentuje (`getCookie` existuje, ale
  není v seznamu API), proto adaptér čte jen pole stamp.

Konfigurace provider:'cookiebot', organization, unit, consentRevision a povinné
cbid, origin, consentValidFrom, maxAgeSeconds. Mapování statistics → analytics,
marketing → marketing. Neplatná konfigurace zůstává configured a denied bez GCM.
Fixture modeluje naměřený tvar (loader bez data-type/level, consentID '0',
renew, kódování cookie). Autoritou kategorií a metody je SDK; z cookie se bere
jen stamp.

### Cookiebot — výsledek implementace

- Nový `host_cookiebot.js` a výběr provideru ve standardním host.js; regenerovaný
  embed.js. Ostatní adaptéry, GCM, transport odkazů, manifest a registry beze změny.
- Jednotkové testy v `host_cookiebot.test.js`, vlastní dokumentovaná fixture a
  integrační `form_consent_link_cookiebot.test.js` se skutečným generovaným
  helperem, Klaro a FormMeasurementSession. Žádné stažení Cookiebot runtime,
  simulace síťového blokování ani tvrzení o živé kompatibilitě.
- Zahrnuto přijetí/odmítnutí/obě částečné volby, preferences-only, implied,
  neznámé regulace/opt-out, CBID/origin/cutoff, expirace, chybějící a rozbité API,
  neplatná konfigurace bez GCM fallbacku, TCF, neplatné/duplicitní cookie,
  coalescing/duplicitní události, jiná karta, retirement listenerů a intervalů,
  local-choice precedence, replay, lease, změna scope, zavření/reload webu.
- Doplněn stávající CI vlastník web-measurement a inventář, integrační dokumentace,
  CS/EN nápověda s ukázkou konfigurace a CHANGELOG. Žádné nové závislosti.

Historické ověření původní větve autorem: 113/113 Cookiebot testů prošlo; 160/160
regresních testů Complianz/CookieConsent/GCM/odkazů prošlo; 3/3 help_pages prošly.
`build_embed.mjs --check`, `build_runtime.mjs --check`,
`build_measurement_runtime.mjs --check`, CI inventory a `git diff --check` prošly.

Praktické hranice: oficiální loader `.com/uc.js` ponechaný v DOM, opt-in režim
účtu, známá GDPR regulace bez CCPA, cookie s polem stamp shodným s consentID,
správně nastavená skutečná platnost a archivovaný cutoff. Původní požadavek
data-type/data-level byl po měření odstraněn: běžné nasazení ho nemá a adaptér
by nic nepřevzal. Automatické
ani ruční blokování se zde nepředstírá. Případné nové/odlišné formáty skončí null;
není zde univerzální parser všech verzí Cookiebotu. CBID na scriptu a cutoff
neověřují kryptograficky, ke kterému CBID patřila zkopírovaná cookie.

CookieConsent v3, Complianz a GCM zdrojové soubory i jejich testy jsou proti
výchozímu stavu této větve beze změny. V okamžiku původního ověření nebylo nic
commitováno ani publikováno; následoval commit d01c86d59 a dokončení issue #824.

Finální celý `test` skript přes pnpm 11.24.0 (`verify-deps-before-run=false`,
bez automatické reinstalace v sandboxu): běžná sada 1573 testů, 1553 prošlo,
9 selhalo a 11 přeskočeno. Devět selhání tvoří známý Ghost Listener Logic (1)
a native_browser při zakázaném loopback listen EPERM (8). DB sada: 31 testů,
3 prošly, 7 selhalo, 21 přeskočeno; chybí lokální DATABASE_URL / DB prostředí.
Žádný nový Cookiebot test neselhal. Celkový skript skončil nenulovým kódem;
nejde o úspěšnou plnou validaci. Dočasné logy byly po zapsání výsledků odstraněny.

### Dokončení issue #824 - 2026-11-12

Větev byla převzata na aktuální `main`; konflikt anglické nápovědy zachovává
kanonický `{{FORM_ORIGIN}}` i novou dokumentaci Cookiebotu. Odstraněna tolerance
1,5 s pro chybějící nebo změněný stamp: nové čtení vrací okamžitě `null`, existující
vazba se zruší při následující sekundové kontrole. Regrese pokrývají také nový
formulář otevřený bezprostředně po smazání cookie nebo odmítnutí v jiné kartě.
Živé ověření navíc odhalilo dočasný opt-in režim `inlineoptin` při obnově volby;
adaptér jej přijímá při zachování všech kontrol explicitní uložené volby.

[Živý průchod a jeho hranice](consent-link-cookiebot-824-validation-2026-11-12.md)
popisuje skutečný Cookiebot, formulářový modul a přenos změn na stejné vazbě.
TCF je v tomto průchodu simulované; živá TCF lišta ani živé Firefox/WebKit nejsou
tímto dokladem pokryty. Kanonické fixture testy zůstávají součástí
`web-measurement`; závěrečné lokální ověření používá `automation/test_ci.sh`
pro všechny kanonické joby. Schválení PR a produkční nasazení jsou oddělené kroky.
