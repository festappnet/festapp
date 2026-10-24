# Vstupenky SEO release - 2026-10-15

> Historical plan or dated evidence. Statuses, versions, authorization and pending steps below apply to the recorded phase, not automatically to today. Use [current documentation](../../README.md) for operating procedures; archiving does not close unverified gates.


## První ověřené nasazení

- Sdílený main: `fc82858c3c6ed33190c0cfd28c7aa5fb45934daf`.
- Tenant `prod/festapptickets`: `4ddf2441db139cc0f982ff24bfea2fa8a8d85b35`, verze `0.20.214+698`.
- Lokální Flutter + Vite build a přímé Cloudflare nasazení: `https://05fb2d7d.vstupenkyonline.pages.dev`.
- `automation/test_all.sh` po opravách prošel: web 348, SQL 185, Flutter 1468 a Deno 336 testů; automation zelená. Lokální image-worker remote integrační testy přeskočeny dle existujícího kontraktu. Log `/tmp/festapp-tests-all-final.log`.
- Coherent live verifier prošel třikrát; HTTP/HTTPS apex/www matice zachovává cestu/query a končí na HTTPS apexu. Sitemap, canonical, HSTS a přímé načtení stránky pořadatele ověřeny.
- HTTP www zůstává se dvěma přesměrováními kvůli existujícímu vnějšímu HTTPS pravidlu. OAuth přístup ke konfiguraci této hrany vrátil 403, pravidlo nebylo změněno.

## Navazující opravy podle uživatelského ověření

- Odkaz z katalogu při aktivní PWA načítal Flutter shell. Oprava registruje stránku pořadatele jako samostatný veřejný dokument v precache a směrování navigace.
- Minulé události jsou viditelná sekce bez sbalování, včetně SSR.
- Od 9 minulých událostí ve více letech se zobrazují sestupné roční skupiny ve Flutter administračním seznamu, Flutter veřejném seznamu a JS/SSR katalogu. Krátký archiv nebo jediný rok zůstává plochý. Neznámá data se neztrácejí.
- Původní roční členění bylo pouze v nepublikovaném lokálním diffu; přenesena jen související úprava, ostatní rozpracovaný obsah zachován.
- Cílené kontroly: web katalog 7/7, Flutter helper 2/2, edge/organizer 14/14, generated PWA offline navigation PASS. Dart analýza bez chyb, 5 předchozích info upozornění ve dvou existujících obrazovkách.
- GitHub PR `https://github.com/festappnet/festapp/pull/424` řeší poslední precache mapování. Uživatel výslovně schválil administrátorské sloučení a nasazení po kontrolách.
- Finální main: `acb70361f2a724e6a811ee6d0dfeb75a6d206a19`. PR #424 sloučeno po 4 úspěšných GitHub kontrolách s explicitně schválenou výjimkou review.
- Finální tenant: `b3af34f6598da0fc913208b237d7e9c465781d19`, verze `0.20.215+699`, se zachovanými předky main i předchozí produkce. Main-owned drift check PASS.
- Lokální build `/tmp/festapp-seo-followup-build-final.log` a `verify_web_build` PASS. Ověřena přesná shoda všech build vstupů kandidáta s finálním tenantem kromě metadat ancestry; Flutter ani Vite nebyly znovu sestavovány pro pouhou změnu ancestry metadat.
- Přímé nasazení: `https://f5c52cb0.vstupenkyonline.pages.dev`. Log `/tmp/festapp-seo-followup-deploy.log`; live verifier PASS pro `0.20.215+699` třikrát po sobě.
- Skutečný izolovaný headless prohlížeč přešel ze staré PWA přes vlastní UI Reload. Cache obsahovala aktivní shell `festapp-app-shell-0.20.215+699`. Katalog ukázal všech 47 minulých akcí, roky 2026 a 2025 a žádné details/sbalování. Kliknutí na skutečný odkaz Pro pořadatele zachovalo `/pro-poradatele` a vykreslilo správný H1 pod aktivním service workerem. Prohlížeč uzavřen.
- Nasazen pouze tenant festapptickets; žádné jiné produkční varianty nebyly publikovány. Originální rozpracovaný pracovní strom zachován.
