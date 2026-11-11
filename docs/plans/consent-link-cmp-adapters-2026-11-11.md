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
