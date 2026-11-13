# Společné API Festapp - lokální výsledek

Lokální implementace a kvalifikace připraveného rozsahu je dokončená. Produkční
přechod, publikace a uzavření deletion ledgeru dosud neproběhly. Verification:
standard. Lokální commit vznikl se schválením uživatele; push ani produkční
migrace/deploy dosud nebyly provedeny.

## Autoritativní review zdroj

Výsledný checkout je `/Users/miakh/source/festapp-unified-api-review-20261113`,
nad `origin/main` `c02cdad38` (včetně nové volby zúžení souhlasu z `6afb748aa`). Původní sdílený
worktree s cizí rozpracovanou prací zůstal zachován; jeho prototyp není zdrojem
pro publikaci. Přenos zachovává novější MCP capability search, inventory operace,
opravu OAuth CSP a MIT/runtime licence/notices.

Poslední kvalifikovaný image před integrací novějšího mainu:
`sha256:350aced2ee377f6a1a6f01b8e5963807a7af84024c60f46fb00aabadddf52a9b`.
Přesný runtime digest a osm manifestů jsou v
[source-final.json](festapp-unified-api-evidence-2026-11-13/source-final.json).
Před produkčním sestavením se release manifesty zapečetí z přesného
publikovaného checkoutu. Tento receipt není potvrzení nasazení.

## Připravený rozsah

- Dvě API fasády nad jedním stávajícím MCP procesem, společnými Operations,
  auth store, granty, limity a artifact ownerem. Samostatný API/docs proces,
  Redis, privilegovaný API klíč ani nový SQL receipt store nevznikly.
- Oddělené MCP/global/regional audience, pevný regionální profil a explicitní
  globální kontext. PKCE, DPoP bez Bearer downgrade, PAR, private_key_jwt,
  refresh reuse/race, revokace, restore a offline transakční storage rekey.
- Z 196 katalogových operací je pro operator API kvalifikováno 96, včetně
  `products.save` a syntetického `ticket_layouts.preview`. Make summary má pět
  čtecích operací. Ostatní rodiny mají konkrétní readiness mezeru v generované
  specifikaci. Celý katalog se nevykazuje jako připravený; citlivé zápisy bez
  důvěryhodného čerstvého step-up zůstávají blokované.
- Osm OpenAPI 3.2.1 projekcí a úplné offline reference ze stejných runtime
  schémat. Validované request/response příklady, parity, lint, směrový diff,
  immutable snapshots a shodný manifest pro docs/API. DPoP vyžaduje OAuth AND
  podepsaný proof. Úspěšné příklady mají `ok: true`.
- Make generátor čte veřejný regionální summary kontrakt. Serverové DTO/importy
  a vlastní pagination headers byly odstraněny. Stejný clientId může během
  omezeného přechodu držet původní MCP grant a nový API grant; nepromují se mezi
  audience. Nové připojení se aktivuje a ověří před odvoláním starého.
- Souhlas ukazuje API resource a datový profil v samostatném i prvním
  přihlašovacím rozhraní. First-party API vyžaduje potvrzení těchto přesných
  hodnot; stará UI se pro API odmítne. Aktualizace stránek souhlasu proto patří
  do koordinovaného rolloutu před aktivací API klientů. MCP funguje dál. Nabídka nahrazovaných
  připojení je omezená na stejnou audience.

## Ověření

Oba dotčené kanonické lanes `server-policy` a `seat-checkout` prošly na finálních
vstupech. API PostgreSQL testy: 2 úspěšné, 0 selhání, 0 skipů. Zahrnují skutečný
COMMIT, ztracenou odpověď, nové SQL spojení, nový OAuth grant, původní commandId,
revokaci po commitu a odebrání práv před replayem. Nevznikl duplicitní produkt
ani email. Flutter MCP skupina: 10 úspěšných testů. First-party API a web consent
mají cílené HTTP/DOM testy. Kanonický browser gate prošel v izolované relaci.
Viz [ci-final.json](festapp-unified-api-evidence-2026-11-13/ci-final.json).

Skutečný pinned provider absolvoval 105 119 HTTP refresh výměn s virtuálním
pětiminutovým posunem přes téměř rok souhlasu: nejvýše 266 živých záznamů,
přibližně 1 MiB replay evidence a správná revokace rodiny po reuse. Jde o
simulovaný čas, nikoli roční produkční pozorování. Původní replay důkazy se
nevyhazují; packing overflow odmítne consume atomicky. Dlouhé souhlasy jsou
explicitní politikou klienta. Viz [refresh-year.json](festapp-unified-api-evidence-2026-11-13/refresh-year.json).
Rekey CLI ověřil process lock, chráněné soubory, nový klíč/readback a odmítnutí
starého klíče; test vadného záznamu ověřil rollback celé re-encryption transakce.

Uvedený image prošel 22 kontrolami skutečného Caddy ingressu, včetně veřejného
DPoP htu, podvržených hlaviček, oddělených audience, 413, backend-down 502 a
zachování Auth/REST/Functions cest. Viz [ingress-final.json](festapp-unified-api-evidence-2026-11-13/ingress-final.json).

Kontrolované srovnání s aktuální produkční MCP generací použilo 100 stejných MCP
probes + 100 background operací, exporty, 32prvkové preview, artefakty a refresh.
Limity zůstaly 384 MiB / 0,5 CPU / heap 192 MiB. MCP p95: 18,37 -> 19,48 ms
(+6,05 %); warmed-idle RSS +7,53 MiB; container peak 183,79 MiB, bez OOM.
Dřívější nárůst 17,34 MiB uživatel výslovně přijal. Starší burst a souběžná
měření včetně regresí zůstávají uložená; finální běh proběhl po dokončení CI.
Backend/renderer jsou fixture, externí síť/R2 náklady nejsou měřením pokryté.
Viz [mixed-benchmark-final.json](festapp-unified-api-evidence-2026-11-13/mixed-benchmark-final.json).

## Publikační kontrola po spojení s mainem

Úplný lokální mirror provedl všech osm lanes. Jediný neúspěch byl test, který
předpokládal dokončení všech emailových projekcí v jedné dávce s limitem 250 ms.
Test nyní omezeně dokončí vlastní fixture ve více dávkách; produkční SQL se
nemění. Celá opravená seat-checkout lane prošla, včetně 2 API SQL testů bez skipů.
Po omezení Caddy na přesný API hostname a regenerování všech osmi projekcí
prošla znovu celá server-policy lane. Ostatní passing vstupy zůstaly beze změny.
Viz [ci-publication.json](festapp-unified-api-evidence-2026-11-13/ci-publication.json).

Aktuální zdroj prošel 23 disposable Caddy kontrolami, nově včetně odmítnutí API
přes sdílený `supabase.festapp.net` alias. Viz
[ingress-host-bound.json](festapp-unified-api-evidence-2026-11-13/ingress-host-bound.json).

## Schválené provozní dokončení

Uživatel dne 2026-11-13 výslovně schválil celý uvedený rozsah: commit/push main,
auth store, oba API ingressy, souhlasové stránky prod/festapptickets a
prod/festappticketsglobal a publikaci/přepojení Make. Před publikací je třeba čerstvé porovnání upstream, celý
publikační CI gate dle aktuální policy a zapečetění přesného commit/image.
Změna CI metadata konzervativně vybírá všechny lanes; cílené dva passing lanes
ani Flutter skupina tyto budoucí publikační požadavky nenahrazují.

Rollout musí koordinovat kanonický runtime, oba API ingressy, aktualizované
stránky souhlasu a Make reconsent. Vyžaduje live ověření issuer/resource/profile,
DNS/TLS, callbacku, čtení, bezpečného syntetického zápisu a revokace. Před
aktivací API klientů musí být dostupné odpovídající first-party UI. Skutečný
Make scénář musí kvalifikovat pagination ceiling a instalované konzumenty.
Dřívější read-only průzkum potvrdil legacy definici, reviewer connection a dva
známé scénáře; živou inventuru je před přechodem nutné obnovit.

Starý `/make/v1` proto zůstává jen jako tenký registrovaný adaptér s vlastníkem
a sunset 2026-12-13. Odstraní se po prokázaném přechodu podle
[deletion ledgeru](festapp-unified-api-DELETION-LEDGER-2026-11-13.md).
`api:compatibility` nyní ověřuje přesnou shodu osmi explicitně schválených
počátečních snapshotů; po živé publikaci přejde baseline do stavu released. Service identities zůstávají oddělenou navazující vlnou S s návrhem
ADR; `client_credentials` nejsou aktivní. Recovery/rollback postup je v
[provozním dokumentu](../operations/festapp-api-auth-recovery.md).

[Offline globální reference](../../tools/festapp/contracts/api-v1/global-api/docs/index.html)
funguje přímo z disku bez loginu nebo serveru.
