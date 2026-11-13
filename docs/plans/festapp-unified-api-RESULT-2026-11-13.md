# Společné API Festapp - produkční výsledek

Oba API vstupy jsou nasazené ze zdroje
`97a579e218c1793769a195a88861382de47769ee` a veřejně vracejí metadata,
OpenAPI, manifest i úplnou statickou dokumentaci přes ověřené HTTPS.
`vstupenky.online` a `tickets.festapp.net` běží na shodné verzi
`0.20.600+1125`. Oba živé OAuth průchody prošly na izolované fixture org3:
čtení a okamžitý DPoP-bound refresh HTTP 200, chybná audience a Bearer downgrade
HTTP 401, po revokaci další přístup HTTP 401. Testovací granty byly odvolány a
izolované browser relace uzavřeny. Business data se živým ověřením neměnila.

[Produkční receipt](festapp-unified-api-evidence-2026-11-13/production-rollout-97.json)
obsahuje přesné image/config/projection digests, tenant revisions a výsledky.
Navazující zdroj `e4fa4a359a0d3424a85e7cc451ee000f63ec4850` je na mainu;
[všech osm GitHub jobs prošlo](festapp-unified-api-evidence-2026-11-13/github-final-source.json).
Neprováděl se další produkční release pouze kvůli této navazující zdrojové pojistce.

Uživatel výslovně odložil **Make cutover až po přijetí stávající aplikace
v review**. Původní `/make/v1`, publikovaný konektor, native README, připojení,
granty a dva scénáře zůstávají beze změny. Deletion ledger je záměrně otevřený.
Navazující zdroj odstraňuje automatický kalendářní cutoff; test potvrdil
HTTP 200 původní dokumentace i po původním datu. Veřejné `integrations/make/API.md`
znovu popisuje původní review kontrakt; připravená migrace je odděleně v
[API-AFTER-REVIEW.md](../../integrations/make/API-AFTER-REVIEW.md).

## Nasazený rozsah

- Oba API hosty obsluhuje stávající globální MCP runtime na jednom listeneru.
  Regionální MCP a původní Make runtime zůstaly zachované. API audience jsou
  oddělené od MCP i navzájem; regionální profil je pevný, globální explicitně vybraný.
- Z 196 katalogových operací je kvalifikováno 96 operator API operací, včetně
  `products.save` a syntetického `ticket_layouts.preview`; summary profil má pět
  čtecích operací. Ostatní rodiny mají konkrétní readiness mezeru, citlivé zápisy
  bez důvěryhodného step-up zůstávají blokované. Service identities ani
  `client_credentials` nebyly aktivovány.
- Osm verzovaných OpenAPI projekcí a offline reference vychází ze stejných
  runtime schémat. První vydané snapshoty 97 jsou immutable baseline; `api:check`
  nyní automaticky obsahuje směrový breaking-change gate.
- Globální auth store byl zálohován a upgradován při zachování klíčů a stavu.
  Oba nové ingressy mají ověřené DNS/TLS. Cloudflare BIC výjimky se týkají jen
  přesných API hostname a integračních cest; Auth/REST ani ostatní pravidla se nemění.
- Pro globální souhlas byl chráněným one-key postupem doplněn broker binding org25.
  Ostatní tři záznamy zůstaly shodné. Worker probe a email health prošly,
  fronta se vrátila do původního nepozastaveného stavu. Business SQL ani kód
  Edge Functions se neměnily. Autentizovaná produkční evidence používá pouze org3;
  org25 má ověřený registry binding a nasazené UI, nikoli úspěšný grant v této evidenci.

## Ověření

Všech osm GitHub CI jobs prošlo na nasazeném 97. Lokální mirror a opravená
seat-checkout lane zahrnují 2 skutečné API SQL testy bez skipů: COMMIT, ztracená
odpověď, nový grant, původní commandId a bezpečný replay bez duplicity.
[Publikační CI evidence](festapp-unified-api-evidence-2026-11-13/ci-publication.json).
Navazující review podmínka a automatický compatibility gate prošly znovu celou
[server-policy lane](festapp-unified-api-evidence-2026-11-13/ci-final-review-condition.json).
Finální 97 image prošel 23 disposable Caddy kontrolami včetně odmítnutí API přes
vedlejší Supabase alias; produkční veřejné endpointy mají HTTP 200 i bez User-Agent.

Dřívější stejné workloady daly MCP p95 +6,05 %, idle RSS +7,53 MiB a peak 183,79 MiB,
bez OOM. Uživatel přijal dřívější výjimku 17,34 MiB; limity 384 MiB/0,5 CPU a
heap 192 MiB se nezvýšily. [Benchmark evidence](festapp-unified-api-evidence-2026-11-13/mixed-benchmark-final.json)
patří k doloženému předchozímu image, nikoli k novému produkčnímu měření.
105 119 skutečných HTTP refresh výměn simulovalo téměř rok souhlasu;
[refresh evidence](festapp-unified-api-evidence-2026-11-13/refresh-year.json) a
[rekey evidence](festapp-unified-api-evidence-2026-11-13/storage-rekey-cli.json) zůstávají zachované.

[Globální reference](https://api.festapp.net/integrations/v1/docs/) -
[Regionální reference](https://api.vstupenky.online/integrations/v1/docs/) -
[Make deletion ledger](festapp-unified-api-DELETION-LEDGER-2026-11-13.md).
