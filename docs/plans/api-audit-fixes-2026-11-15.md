# Opravy API auditu - 2026-11-15

## Rozsah a postup

Opravit dva nálezy z `docs/security/api-audit-2026-11-15.md` v aktuálním
pracovním stromu. Zachovat původní rozpracované změny. Jde o implementaci
a místní ověření; produkční nasazení není součástí tohoto kroku.
Ověření: standard, protože jde o sdílený API kontrakt a HTTP cestu autentizace.

1. Převést reprodukce do běžně spouštěných regresních testů. Souběh řídit
   explicitními signály přijetí požadavků místo časového čekání. Před opravou
   potvrdit selhání očekávání `retryable=true` a přijetí HTTP 204/205/304.
2. Při vyčerpání limitu souběhu vyhodit explicitně obnovitelnou chybu.
   Zachovat limity dvou požadavků na grant a šestnácti celkem. Nepřidávat
   odhadnutý `Retry-After`: okamžik dokončení přijatých požadavků není známý.
3. Při rekonstrukci upstream Response předávat pro 204/205/304 tělo `null`.
   Zachovat status, hlavičky, timeout, zákaz redirectů a limit 20 MiB.
4. Spustit cílené API a session/HTTP testy. Ověřit návrat 429 s
   `retryable=true`, `outcome=rejected`, zotavení po uvolnění, bezobsahové
   statusy, běžný JSON a odmítnutí nadlimitního těla. Aktualizovat stav auditu
   a odstranit zastaralou samostatnou reprodukci vadného chování.

## Kritéria dokončení a rizika

Oba regresní testy nejprve selžou na původním zdroji a poté projdou;
dotčené stávající testy také projdou. Změna nezasáhne produkční data ani
oprávnění. F2 zůstává preventivní opravou helperu bez prokázaného selhání
konkrétní produkční operace. Výsledek místních testů neprokazuje nasazení.

## Výsledek provedení

Hotovo lokálně: oba nové regresní případy před opravou selhaly a po opravě
prošly. Finální zdroj má ověřených 70 cílených testů bez přeskočení:
58 API/kontrakt/storage/limity/webhook testů a 12 context/session testů.
Kontrola whitespace diffu prošla.

První širší běh měl 69 úspěchů a jedno selhání starého testu s pevným
počtem tří Auth user volání. Stejné selhání `5 !== 3` bylo reprodukováno
s původním HTTP adaptérem z HEAD přes dočasný Node loader bez změny zdrojů.
Test nyní vyžaduje alespoň tři validace uživatele, protože Supabase může
provádět další validace při refreshi. Ověření pořadí uložených refresh tokenů
zůstává zachováno. Po této jediné úpravě prošlo všech 12 context testů;
ostatní úspěšné testy nebyly znovu spouštěny, jejich zdroj se nezměnil.

Zastaralá samostatná reprodukce byla odstraněna. Produkční nasazení nebylo
provedeno. Pro začlenění do main byly pouze soubory této opravy přeneseny
do izolované větve nad ověřeným `origin/main`
`7eb8c04d260356a6d7399f65c017a905d6a1eb15`. Ze 44 novějších commitů
změnil adresář `tools/festapp` pouze nesouvisející test připnuté GoTrue verze.
Před publikací je na tomto aktuálním základu zopakována celá sada 70 testů.
