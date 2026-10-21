# Vstupenky.online: serverové souhrny bez lišty

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md,
`docs/architecture/ai_context.md` a aktuální část plánu
`docs/plans/vstupenky-analytics-plan-2026-10-20.md`.

Poslední výslovná volba uživatele: „jen serv. bez listy“. Nahrazuje původní
zadání browserového RUM, SPA tras a cookie opt-out. Browserový beacon se
na vstupenky.online nenačítá: aktivní Configuration Rule
`a7ded3d36099492287f5c9820fbf8feb` pro `(http.host eq "vstupenky.online")`
má `disable_rum: true`. Ověřeno v dashboardu a v čistém prohlížeči bez
opt-out cookie, s neblokovanou CDN. Žádný jiný host či tenant se neměnil.

Používej existující Cloudflare serverový přehled Requests s filtrem Host
equals vstupenky.online. Nezapínej RUM, Pages beacon, consent lištu, nový
collector, placený upgrade, API/SQL/Edge Function nebo vlastní dashboard.
Nepropojuj statistiky s účty či objednávkami. Bez dalšího výslovného
rozhodnutí nevracej původní sledování veřejných cest uvnitř SPA.

Serverové požadavky zahrnují soubory, boty i administraci a nejsou počtem
osob ani pohybem uvnitř Flutteru. Cookie neměření je neovlivňuje. Údaje
HTTP požadavků včetně IP a cesty nejsou zaručeně anonymní; transparentní
informace zachovej v zásadách soukromí. Odkaz v Organization Edit i
právní zdroje jsou připravené pro příští release.

Veškerou cizí rozpracovanou práci zachovej. Verification: standard pro
produkční změny, jinak přiměřená změněné vrstvě. Uživatel autorizoval začlenění změn do main pro příští release.
Neprováděj deploy jen kvůli opakování již prokázaného vypnutí RUM. Případné
vydání lokálních UI/dokumentů proveď kanonickým tenant release postupem.
Existující chráněný read token nevytvářej znovu a nevypisuj ho do výstupů.
