# Archived decision, superseded 2026-10-25

The user replaced the server-only decision with aggregate public-web-client analytics, separately by exact hostname. Current behavior, rollout scope and the unresolved Velehrad exception are recorded in [public web analytics](../../operations/public-web-analytics.md). The following text is historical evidence and must not be executed as the current instruction.

# Aktuální rozhodnutí: pouze serverové souhrny bez lišty

Uživatel výslovně zvolil „jen serv. bez listy“. Tato část nahrazuje níže
uvedená dřívější zadání RUM, veřejných SPA tras, referrerů a cookie opt-out.
Historické důkazy níže nejsou popisem současného sběru.

## Provedeno na produkci

- Pouze host `vstupenky.online`; ostatní hosty a tenanty beze změny.
- Configuration Rule `a7ded3d36099492287f5c9820fbf8feb` přejmenováno na
  `Disable browser analytics on vstupenky.online`.
- Nová expression: `(http.host eq "vstupenky.online")`.
- Jediná akce zůstává `set_config`, `disable_rum: true`; pravidlo je Active.
  Ověřeno uložené pravidlo i text „The Web Analytics performance beacon is disabled“.
- Web Analytics site/history ponechány, ale automatická injekce je pro tento
  přesný host přebitá Configuration Rule. Žádný manuální beacon ani nový collector.
- Neaktivovala se placená služba, žádný vlastní event/funnel/SQL/Edge Function.
- Ve skutečném Chrome odstraněna pouze již nepotřebná host-only cookie
  `festapp_analytics_optout` s Path=/; přihlášení ani ostatní cookies se neměnily.

## Ověření skutečného účinku

Izolovaný headless Chrome s explicitním DNS mapováním CDN (bez lokálního
DNS blokátoru), bez opt-out cookie: na `/` i `/scan` je beaconScripts=0,
initialized=false, resources=0. Po syntetickém history.pushState na
`/scan/SYNTHETIC_PRIVACY_CHECK` a `/organizationEdit/3` totéž; seznam
síťových požadavků filtrovaný na rum je prázdný. Testovací kód není skutečná
capability a nebyla vyvolána žádná objednávková ani administrační mutace.
Také skutečný uživatelův Chrome po načtení nové karty: žádný beacon ani
inicializace. Již otevřené starší stránky je nutné jednou obnovit.

## Přehled serverového provozu

Ověřen živý přehled Requests se skutečnými daty a zeměmi Czech Republic
+ další EU. Přehled omezen filtrem Host equals vstupenky.online:

https://dash.cloudflare.com/84b32318ac235bf6738bdf1c8caa0795/vstupenky.online/analytics/requests?filters=%5B%5B%7B%22key%22%3A%22clientRequestHTTPHost%22%2C%22operator%22%3A%22eq%22%2C%22value%22%3A%22vstupenky.online%22%7D%5D%5D

Jde o požadavky včetně souborů, botů, scanneru a administrace, nikoliv
čisté počty veřejných návštěvníků. Nevykazuje pohyb uvnitř Flutteru bez
HTTP požadavku ani browserové Core Web Vitals. Dřívější cookie opt-out
serverové požadavky nevylučuje. Zdroje návštěv nejsou slibovanou funkcí
aktuálního základního přehledu. Jemnější členění závisí na tarifu; žádný
upgrade nebyl objednán.

## Rozsah soukromí a oprávněného zájmu

Nové čtení browserových API, analytické cookies ani přenos SPA tras do RUM
jsou vypnuté. Serverový provoz nelze označit za zcela anonymní: Cloudflare
při obsluze nutně přijímá IP, HTTP cestu a technické údaje požadavku a
jeho dashboard může obsahovat i IP a cesty. Nevytváříme k nim nové kopie,
identifikátory ani propojení s účty/objednávkami. Účel souhrnů je provoz,
kapacita, dostupnost a bezpečnost, nikoliv marketing/profilování uživatelů.
Volba méně invazivního serverového přehledu odstranila pro tento úkol
potřebu browserového měření; zůstává povinnost transparentně informovat
o serverovém zpracování a řešit případné námitky. Nejde o audit veškerého
ostatního zpracování aplikace, např. dříve existujícího měření e-mailů.

Lokálně upraven odkaz v Organization Edit a popisky v šesti jazycích na
serverový provoz. Zásady soukromí a volby nyní popisují skutečný režim,
neobsahují slib účinného cookie opt-out. Změny aplikace a dokumentů
jsou určené pro příští release; živé vypnutí RUM proběhlo bez deploye aplikace.

Validace lokálních změn: renderer právních stránek a jeho --check prošly.
Cílený `fvm dart analyze lib/components/organization/views/organization_edit_page.dart`
skončil kódem 0, pouze již existující info o názvu konstanty ROUTE (řádek 20).
Obě prohlížečové session byly po ověření uzavřeny. Vydání aplikace
není součástí této změny; uživatel následně autorizoval začlenění do main.

Podklady:
https://developers.cloudflare.com/rules/configuration-rules/settings/
https://developers.cloudflare.com/analytics/account-and-zone-analytics/zone-analytics/

## Příprava do main pro příští release

Změna izolovaná nad aktuálním origin/main; původní rozpracovaný checkout
nebyl změněn. Přeneseny pouze odkazy, oprava viditelnosti organizačního
menu, příslušné překlady, právní informace a cílený regresní test.

Validace izolované změny: apply_config.sh, synchronizace překladů,
13 Node testů menu/bootstrapu a 12 testů veřejných překladů, Vite build,
renderer právních stránek --check a cílený Dart analyzer tří změněných
souborů. Vše dokončeno úspěšně; analyzer hlásí pouze již existující info
o názvu konstanty ROUTE v organization_edit_page.dart. Žádné produkční
vydání aplikace ani změna jiné tenant větve nejsou součástí tohoto merge.
