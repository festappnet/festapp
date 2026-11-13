# Výsledek lokální realizace společného API

Stav: implementovaný a cíleně ověřený základ, celý autoritativní plán zůstává
otevřený. Verification: standard. Bez commitu, push, produkčních migrací,
nasazení nebo publikace Make konektoru. Cizí rozpracované změny byly zachovány.

## Implementováno

- Dvě veřejné fasády `/integrations/v1` nad jedním stávajícím MCP runtime,
  společným Operations, auth store, admission rozpočtem a artifact ownerem.
  Samostatný API proces ani další úložiště nevznikly. Regionální profil je pevný;
  globální kontext se vybírá explicitně. Obě API audience jsou oddělené od MCP.
- Explicitní OAuth klienti, resource/profile/operation binding, PKCE, refresh
  rotation/reuse/race, DPoP bez Bearer downgrade, PAR a private_key_jwt.
  DPoP replay evidence přežívá restart verifieru. Obnova starší auth zálohy má
  příkaz pro zneplatnění obnovených grantů; signing/cookie/storage/broker klíče
  mají rozlišené recovery postupy.
- HTTP Problem Details, limity vstupu, scope/readiness kontrola, autorizované
  artefakty, sdílené limity i při odpojení MCP během exportu. Aktuální katalog
  obsahuje 193 descriptorů; operator API zpřístupňuje 93 operací, včetně
  `products.save`. Summary profil má pět čtecích operací. Ostatní zápisové rodiny
  vracejí explicitní readiness blokaci.
- Osm OpenAPI 3.2.1 projekcí: dvě fasády, dva datové a dva proof profily.
  Schémata pocházejí ze společné čisté projekce runtime descriptorů pro MCP/API.
  Build vytváří validované příklady, immutable snapshots, manifesty a úplnou
  offline Redoc referenci. DPoP security vyžaduje OAuth a podepsaný proof současně.
  Runtime streamuje statické specifikace a HTML ze souborů.
- Make generátor čte veřejný regionální summary kontrakt a vlastní UI policy.
  Přímé importy serverových Operations/DTO/policy a vlastní pagination headers
  byly odstraněny. Generovaný klient zachovává clientId, callback a scope ceiling;
  potřebuje nové připojení s API audience u canonical issueru.
- Review artefakt Caddy ingressu zachovává existující Supabase cesty, přepisuje
  nedůvěryhodné forwarding hlavičky a mapuje proxy chyby na Problem Details.
  Do aktivní produkční konfigurace nebyl zapojen.

## Ověření

Přenosná evidence a přesné příkazy jsou ve
[verification.json](festapp-unified-api-evidence-2026-11-13/verification.json).
Auth/API/shared-runner sada: 122 úspěšných testů bez skipů. Finální surface sada
včetně osmi statických rout a cache: 28 úspěšných bez skipů; sady se překrývají.
Dřívější passing evidence pro skutečný 20 000-row auth store, lokální PostgreSQL
produkt/retry a Make summary, i CI contract byla zachována; nejde o plné CI lanes.
SQL fixture používá vnější rollback, takže neprokazuje samostatný durable
COMMIT/reconnect scénář.

`api:check`, `docs:check` a Make generated check prošly. `api:compatibility`
záměrně odmítá schválit první release bez vydané baseline. Nemá se obcházet
vytvořením baseline z pracovního stromu. Browser ověřil reference přes `file://`
v izolované headless relaci: hledání, detaily, schémata, lokální odkazy a žádné
externí požadavky. Relace byla zavřena.

Finální lokální image:
`sha256:fdaa8f2685dc3bbd025ff663f45cb93fd1ba69270d52aea54d7050e780e7c495`.
[Caddy evidence](festapp-unified-api-evidence-2026-11-13/ingress.json) dokládá
22 kontrol na tomto image, včetně obou fasád, DPoP veřejné URL, podvrženého
forwardingu, audience substitution, 413 a nedostupného backendu.

[Finální krátký benchmark](festapp-unified-api-evidence-2026-11-13/container-read-benchmark-final.json)
srovnává postupně spuštěné baseline `09cdd991f` a finální image při
384 MiB / 0,5 CPU / heap 192 MiB: warmed-idle RSS +0,098 MiB, MCP p95
50,66 -> 54,74 ms (+8,05 %), container peak kandidáta 92,56 MiB, bez OOM.
Jde o malý vzorek čtení s fixture backendem. Starší důkaz regrese mezikandidáta
(+45,9 %) zůstává uložený; nebyl přepsán. Celý provozní benchmark není uzavřený.

## Zbývající práce a provozní kroky

1. Kvalifikovat každou další zápisovou rodinu podle jejích scope, proof/step-up,
   preview, retry a recovery podmínek. Prokázat nejistý výsledek přes skutečný
   samostatně commitnutý zápis a reconnect. Blokované rodiny nevykazovat hotové.
2. Dokončit dlouhé refresh families a adversariální kapacitu. Současná API
   politika připouští nejvýše sedm dní a modelovanou rezervaci růstu; nejde
   o důkaz provozní kapacity při libovolné frekvenci obnovy.
3. Provést plný srovnatelný benchmark exportu, nejtěžší preview, refresh,
   vyčerpání kapacity a disconnect/expiration recovery. Krátký read slice
   ani cílený disconnect test tento release gate nenahrazují.
4. Po autorizovaném rollout API/ingressu ověřit skutečné DNS/TLS/public metadata,
   globální first-party consent origin, provést Make reconsent, skutečnou Make
   kvalifikaci včetně pagination ceiling a ověřit distribuci konzumentů.
   Read-only průzkum potvrzuje legacy definici, existující reviewer connection
   a dva známé scénáře. Starý `/make/v1` adaptér proto dosud nelze odstranit.
   Má vlastníka, sunset 2026-12-13 a
   [otevřený deletion ledger](festapp-unified-api-DELETION-LEDGER-2026-11-13.md).
5. Před publikací zdroje zapracovat aktuální upstream do izolovaného review
   výsledku, spustit dotčené canonical CI mirror lanes a zapečetit manifesty
   z přesného release checkoutu. Pracovní HEAD `742d614b7` není release source;
   pro globální binding byl porovnán a převzat owner z `origin/main` `09cdd991f`.
   První publikace vyžaduje schválenou immutable compatibility baseline.

Service identities zůstávají samostatnou vlnou S. Byl sepsán návrh principal/SQL
ADR; `client_credentials` nejsou aktivní. Online storage rekey není implementován.

[Globální offline reference](../../tools/festapp/contracts/api-v1/global-api/docs/index.html)
a [regionální summary DPoP reference](../../tools/festapp/contracts/api-v1/regional-api/profiles/order-summary/proofs/dpop/docs/index.html)
fungují přímo z disku. Recovery postup je v
[provozním dokumentu](../operations/festapp-api-auth-recovery.md).
