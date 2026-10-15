# Vypnutí veřejné aplikace pomocí IS_APP_SUPPORTED

Historický záznam prvního kroku. Aktuální rozšíření odstraňuje také obsahovou administraci: [ticketing scope](tenant-ticketing-scope-2026-10-15.md).

Implementace připravená na kanonickém main `488988612` v samostatné pracovní kopii, větev `fix/tenant-public-app-scope-20261015`. Změna nebyla publikována ani nasazena. Vybraný tenant vstupenky.online již má v `prod/festapptickets` nastavené `IS_APP_SUPPORTED=false`; konfigurace jiných tenantů se nemění.

## Výsledek

`AppConfig.isAppSupported` je existující generovaná compile-time konstanta. Pokud je `false`, Flutter už neregistruje veřejnou obálku akce s programem, událostmi, novinkami, mapou, informacemi, uživatelským profilem a přehledem jednotky. Vypínají se také veřejné odkazy na vlastní program, poradenství, časový přehled, hru, zpěvník, pobyt a editor novinek. Neznámé veřejné URL končí na kořenovém katalogu.

Přímé veřejné odkazy přesměrovává Cloudflare worker HTTP 302 na `/` ještě před načtením Flutteru. Stejná klasifikace URL se používá ve web klientu i v generovaném PWA workeru. PWA přesměruje také offline navigaci místo otevření uloženého Flutter shellu. Manifest nenastaví zakázanou veřejnou startovací URL ani při současném `FORCE_OCCASION_LINK`. Serverový katalog a sitemap veřejné programové URL neinzerují.

Přihlášení, obnovy hesla, OAuth callbacky, formuláře a nákup, jednotková a příležitostní administrace, rezervace, kontrola vstupenek, recepce a úklidové provozní obrazovky zůstávají dostupné podle dosavadních práv. Mapový a událostní editor pro administraci zůstávají zachovány. Flag omezuje veřejný aplikační produkt, nemění backendová oprávnění.

Nový build verifier kontroluje shodu flagu v generované Dart konfiguraci, PWA workeru a Cloudflare workeru s project.conf. Změna tedy používá stávající tenant konfiguraci, nikoli novou doménovou výjimku.

## Změřená velikost

Dva skutečné web release buildy stejných zdrojů a konfigurace, oba s `isAppSupported=false`. První má původní routy, druhý novou podmíněnou registraci. Flutter 3.47.2, Dart 3.13.2, `--release --no-pub --base-href / --no-web-resources-cdn --no-wasm-dry-run --dump-info`.

| Hlavní JS | Před | Po | Rozdíl |
| --- | ---: | ---: | ---: |
| Před kompresí | 10 960 139 B | 10 534 373 B | -425 766 B (-3,88 %) |
| Stejná lokální Brotli Q9 | 2 477 147 B | 2 383 532 B | -93 615 B (-3,78 %) |

Z dump-info zcela zmizely knihovny veřejné stránky události, profilu uživatele, obálky akce, novinek a některých programových obrazovek. Mapová implementace se jen zmenšila, protože ji stále potřebuje administrativní editor. Sdílený administrační kód a automaticky registrované pluginy zůstávají; nejde o odstranění celého mapového enginu nebo veškerého kódu programu.

Tato úspora není kombinována s předchozími experimenty odloženého textového editoru a dalších modulů. Nelze je bez dalšího společného buildu sčítat. Nejde o měření úspory sekund ani přesnou reprodukci produkčního tenant releasu. Cloudflare redirect navíc pro zakázaná URL eliminuje samotné načítání Flutteru, ale jeho časový dopad nebyl měřen.

## Ověření

- Oba srovnávací Flutter web release buildy prošly.
- Dva nové routerové testy prošly při vypnutém flagu. Celkem 73 Flutter testů prošlo v běžné konfiguraci s flagem zapnutým, včetně přímých odkazů, post-login navigace a mapových rout.
- Cílená Node sada: 53/53 kontrol prošlo; po doplnění testu SEO pro vypnutý režim prošla celá nová související sada 5/5. Testuje skutečné generování hosting workeru, přímé URL, offline PWA, webový handoff a katalog/sitemap.
- `automation/tests/apply_config.test.sh` prošel včetně nového případu vypnuté aplikace s vynucenou akcí. PWA manifest, kořenový vstup a offline sada prošly.
- Web klient prošel `npm run build`.
- Cílená Dart analýza nemá chyby; hlásí tři již existující nálezy v app_router.dart/main.dart (názvosloví LINK, mutovatelná položka MyApp a soukromý typ ve veřejné signatuře).
- Volitelně spuštěná starší sada `cloudflare_security_headers.test.mjs` má existující nesoulad: očekává HTTP 200 pro prázdnou cestu `/form/`, původní i upravený worker vracejí 404. Shodné selhání bylo ověřeno na nezměněném HEAD; tento nesouvisející test se neupravoval. Nový test explicitně kontroluje zachování bezpečnostní hlavičky na redirectu.

Nebyl proveden skutečný browser E2E ani produkční rollout. Full release gates nebyly spouštěny. Při budoucím releasu je potřeba ověřit aktualizaci již nainstalované PWA; stará běžící verze získá nová pravidla až aktualizací.

[Velikosti](tenant-public-app-scope-2026-10-15/sizes.json), [největší změny knihoven](tenant-public-app-scope-2026-10-15/largest-library-reductions.json). Kompletní buildy a logy: `/tmp/festapp-public-app-scope-20261015`.
