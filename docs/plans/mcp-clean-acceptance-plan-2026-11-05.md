# MCP: opakovatelné ověření a čistá dokumentace

Datum: 2026-11-05
Stav: provedeno a ověřeno lokálně; publikace a produkční release neprovedeny
Ověření: standard

## Výsledek a rozsah

Dokončit předchozí audit: funkční sada MCP musí projít bez skipped testů,
ověřit skutečné lokální Auth -> Edge -> OAuth -> MCP -> SQL a zachovat jediný
generovaný katalog i pravdivé příklady. Opravit příčiny selhání, nikoli očekávání
jen proto, aby testy prošly. Zákaznická data, produkční zápisy, deploy a publikace
nejsou součástí tohoto zadání. Rozdíly produkce se vyhodnotí čtením a jejich
dispozice bude doložená; nebudou skrytě přepsány.

## Podklady

- `docs/development/mcp-help-claim-audit-2026-11-05.json`: 346 testů,
  316 prošlo, 30 selhalo, 0 skipped. První běh měl 65 selhání; částečné doplnění
  lokálních závislostí pomohlo, ale není opakovatelnou přípravou prostředí.
- `tools/festapp/test/seat-fixtures.mjs` a `form-fixtures.mjs` instalují historické
  migrace a neúplný výběr současných SQL ownerů. Chybí například
  `ensure_order_payment_instructions_internal`; některé následné chyby jsou důsledky.
- Samostatná selhání se týkají přesného ACL soukromé tabulky,
  ticket-layout readiness, shody email/form ownerů a verzí setup/inventory fixtures.
- `test/local/pilot.e2e.mjs` již nabízí skutečné přihlášení a omezené delegované
  čtení. Je nutné jej skutečně spustit, ne odvodit úspěch z unit testů.
- Produkční audit nenašel chybějící funkci v 828 porovnávaných definicích;
  9 těl se lišilo od pracovního stromu. Přítomnost funkce není důkaz oprávnění
  konkrétního OAuth klienta ani úspěchu celé operace.
- Čas uživatele není ISO vstup API. Nastavení akce se musí načíst a neurčitelné
  pásmo upřesnit; není dovoleno hádat je z češtiny nebo zařízení.

## Invarianty

1. SQL a existující aplikační/Edge ownery zůstávají autoritou obchodního chování.
2. Testy používají jen markerem ověřenou loopback DB, cron off, email paused
   a bez externího worker URL. Žádná produkční session ani provider dispatch.
3. Současné závislosti se instalují opakovatelně z kanonických SQL souborů.
   Historické migrace a existující receipty se nepřepisují.
4. Zachovat skutečné role, přesné ACL, source hashes, konflikty, souběh,
   stejný commandId při nejistotě a kontrolu trvalého výsledku.
5. Katalog a schémata zůstávají generované z registru, scope kontraktu a policy.
   Test existence názvu nástroje není vydáván za funkční akceptaci.
6. Nesouvisející rozpracované soubory jiných úkolů se nemění ani nepublikují.

## Provedení

### 1. Opakovatelná příprava databázových fixtures

Zavést sdílenou testovací instalaci současných kanonických závislostí pro
formuláře, checkout, místa a readiness. Umístit ji do `tools/festapp/test/` a
volat ji v existujících setup transakcích v potřebném pořadí vůči historickým
migracím. Využít existující parser/kontrakty SQL, bude-li nutný výběr definic;
nekopírovat těla funkcí. Zahrnout payment instructions a jejich skutečné
závislosti, seating guards/schema a aktuální email/form ownery.

Výstup: vybrané dříve padající scénáře běží bez chyb chybějících funkcí a bez
závislosti na ručním doplnění DB z předchozího auditu.

### 2. Skutečné zbývající regrese

U přesné ACL kontroly ověřit kanonické role nové soukromé tabulky a přidat jen
odůvodněnou konkrétní položku, nikdy obecnou výjimku. Readiness obnovit instalací
skutečných odpovídajících ownerů/kontraktu. U email/form parity načíst současný
kanonický SQL owner po historické migraci. U setup a inventory dohledat přesný
konflikt původní verze nebo fixture a opravit producenta či scénář podle skutečného
kontraktu. Funkční chybu opravit u jejího vlastníka a přidat cílenou regresi.

Výstup: všechny původní neúspěšné scénáře projdou, bez oslabení assertionů nebo
obcházení nových guardů.

### 3. Úplná sada a skutečný autorizovaný průchod

Po sjednocení vstupů spustit `pnpm --dir tools/festapp test` s Node 24 a oběma
DB proměnnými na chráněné lokální prostředí. Pak spustit existující
`test/local/pilot.e2e.mjs` s explicitní lokální service-template instancí.
Chybějící bootstrap vyřešit v lokální přípravě; žádné produkční fallbacky.
Zachovat kontrolu identity, rozsahu, revokace a úklid vlastních fixtures/služeb.

Výstup: plná sada 0 fail / 0 skipped a receipt skutečné Auth/Edge/OAuth/MCP/SQL
akceptace, se zřetelnými hranicemi ověření.

### 4. Produkční rozdíly a dokumentace

Devět rozdílů porovnat se zdroji v HEAD a pracovním stromu, zjistit jejich původ
a dopad na MCP kontrakt. Úpravy patřící jinému rozpracovanému úkolu zachovat a
označit jako nenasazený zdroj, nikoli jako chybu produkce nebo nové oprávnění.
Pokud vznikne nutná produkční oprava, připravit ji reviewovatelně jako samostatný
release krok; neprovádět ji v tomto zadání.

Regenerovat MCP katalog, zkontrolovat jazyk a skutečné dependencies všech promptů,
aktualizovat audit/receipt podle nových výsledků a vytvořit CS/EN statické náhledy.
Zachovat omezení veřejného ChatGPT klienta a neprohlašovat nasazení či provedení
funkcí pouze na základě seznamu nástrojů.

Výstup: `docs:check`, testy dokumentace/nápovědy/vyhledávání prošly; všechny
dřívější auditní položky mají doložené řešení nebo konkrétně vymezený release stav.

## Odstranění a kompatibilita

| Položka | Dispozice | Důkaz |
|---|---|---|
| Ruční doplňování jednotlivých chybějících lokálních funkcí | Nahradit opakovatelnou přípravou fixtures | Scénáře projdou z podporovaného základu |
| Neúplné současné SQL overlaye ve fixtures | Sjednotit potřebné závislosti | Celá sada, přesná source parity a readiness |
| Historické migrace / receipty | Zachovat jako externí kompatibilní hranici | Existující replay/upgrade testy |
| Staré tvrzení o 30 nevyřešených selháních | Zachovat jako historický audit, doplnit konečné řešení | Nový výsledkový receipt |
| Ručně vedený alternativní katalog nebo timezone default | Nezavádět | Generátor a kontrola promptů |

## Dokončení

- [x] Plná funkční sada bez fail/skipped na ověřené lokální DB.
- [x] Opakovatelná příprava namísto ručních zásahů do prostředí.
- [x] Skutečný lokální autentizovaný pilot a negativní scope/revocation scénáře.
- [x] Všech devět produkčních rozdílů klasifikovaných a žádný skrytý produkční zápis.
- [x] Katalog, prompty, audit a statické náhledy odpovídají výsledkům.
- [x] Žádné oslabené testy, tajné fallbacky nebo změny nesouvisející rozpracované práce.

Lokální rollback tvoří transakční rollback fixtures a úklid pouze vlastních
syntetických dat a služeb. Produkční rollback zde není potřebný, protože se
produkce nemění. Pokud důkaz vyvrátí předpoklad plánu, upravit tento plán a
pokračovat k témuž výsledku; neoznačit neprovedené ověření za úspěch.

## Upřesnění podle provedení

- Devět produkčních rozdílů nebylo shodných s HEAD ani s dohledanou historií.
  Read-only porovnání těl prokázalo nasazené filtry skrytých členů a zachování
  jejich členství při zápisu skupiny. Kanonické zdroje tyto ochrany postrádají.
  Vlna 4 je proto zahrnuje jako převzetí existujícího bezpečnějšího chování:
  soukromé visibility predicates, devět spotřebitelů, dopředná migrace a reálné
  regresní testy neodhalení i zachování členství. Produkce se nepřepisuje.
- U setup finalizace byl nalezen druhý revision guard s odlišným SQLSTATE.
  Odstranit jej a ponechat konflikt/replay kanonickému finalizeru; adaptér musí
  rozlišit nutnost nového načtení od skutečného dočasného souběhu.

## Výsledek provedení

- Celá funkční sada: 349/349 prošlo, 0 selhání, 0 skipped. Příprava SQL je součástí test příkazu.
- Skutečný lokální Auth/Edge/OAuth/MCP/SQL pilot prošel včetně uložení formuláře,
  idempotentního replay, trvalého readbacku, načtení časového nastavení akce mimo Europe/Prague,
  omezených scopes, nezávislé revokace klientů a úklidu vlastních dat/služeb.
- Původních devět rozdílů odpovídá kanonickým zdrojům. Z 831 současných definic
  odpovídá 830 uloženému read-only produkčnímu auditu; jediným rozdílem je nová
  oprava setup konfliktu čekající na release. Žádná definice nechybí.
- Obě dopředné migrace prošly aplikací a rollbackem v chráněné lokální transakci.
- Generovaný katalog je aktuální (193 nástrojů, 83 oprávnění); 7/7 kontrol
  dokumentace a nápovědy prošlo. CS/EN statické náhledy byly obnoveny.
- Výsledkový doklad: `docs/development/mcp-clean-acceptance-2026-11-05.json`.
  Historické auditní běhy zůstávají zachované. Produkční přijetí všech nástrojů
  ani dostupnost veřejného ChatGPT konektoru tento lokální výsledek nedokazuje.

## Začlenění do aktuálního mainu a vydání

Uživatel následně výslovně zadal sloučení a nasazení pro vstupenky.online.
Přenesení do čisté kopie mainu `2ed9752cfbfb745efb8cc2026f6d63ff44dfd011`
zachovává novější kanonické řešení: skutečnou migraci lokální databáze a
`assertSchema` namísto historických SQL overlayů ve fixtures. Tyto dočasné
installery ani duplicitní migrace `20261105034000` se nepublikují. Ochrany skrytých
členů již main obsahuje v migraci `20261101180000` a canonical users owneru.

Čerstvý lokální bootstrap prošel až po novou migraci setup konfliktu. Úplná sada
349 scénářů měla jediný nesoulad přesného seznamu soukromých tabulek po přidaných
sale-opening tabulkách. Doplněny byly pouze tři konkrétní owner-only vztahy;
stejný ACL scénář poté prošel. Ostatních 348 scénářů, 7 kontrol nápovědy a skutečný
lokální Auth/Edge/OAuth/MCP/SQL pilot prošly na těchto zdrojích. Výsledkový receipt
rozlišuje původní ověření a tuto integraci.

Main je chráněný požadavkem na jedno schválení PR. Změny jsou připravené jako
jeden commit pro squash; publikace na main a produkční nasazení se neprohlašují
za hotové před splněním této podmínky a releasových kontrol.
