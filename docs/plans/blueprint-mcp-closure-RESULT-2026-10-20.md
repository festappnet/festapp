# Blueprint + MCP closure: lokální výsledek

Stav: původní plán dokončen v autorizovaném lokálním rozsahu. Níže je původní lokální kvalifikace před publikací; navazující uživatelem autorizované začlenění do main a jeho dodatečné kontroly popisuje [integrační záznam](../archive/repository-artifact-followup-2026-10-21.md#blueprint). Produkční migrace, deploy a publikace package neproběhly.

Kandidát: `/Users/miakh/source/festapp-blueprint-mcp-closure-20261020`, detached base `48d8b6db0479818b556e3852c7ea50ead4035d11`. Sdílený package: `/Users/miakh/source/venue-seat-picker-blueprint-mcp-closure-20261020`, runtime sjednocený s předaným r37 a integritní deltou. Původní rozpracovaný strom a souběžné sessions nejsou přepsané. Pozdější samostatné změny r38, importu skutečných akcí a implicitních blueprint nabídek nejsou součástí této zmrazené closure.

## Výsledek

- Osm přesných Flutter owners je uzavřených. Tři reprodukovaná selhání opravují regular Roboto fixture, platný dirty-dialog kontrakt a zpracování Escape v dialogovém shellu. Pět ostatních owners už fungovalo na aktuálním základu. Další zastaralé transportní fixture nyní vracejí platné command/receipt identity. Runtime integrita fontů a assertions zůstávají.
- Public formulář používá vlastní veřejnou projekci bez nepotřebného offline editor syncu. Anonymous, skutečně přihlášený buyer bez editor práv a unit administrator otevřeli stejný formulář i plánek. Přímé editor RPC nadále odmítá neoprávněné identity.
- Webové MCP propojení používá JS shell, schema-2 `access`, skupiny pořadatelů, explicitní all/partial/clear a limit 100 konkrétních akcí. Celý pořadatel a create jsou oddělené souhlasy. Router i komponent ignorují opožděné async výsledky po přechodu nebo zániku. Publikované cs/en slovníky obsahují kanonické MCP překlady. Nativní Flutter consent zůstává zachovaný.
- Skutečný lokální LoginModal, GoTrue, broker, Edge exchange a syntetický native SDK klient vytvořily jeden omezený grant. Repeated approve druhý grant nevytvořil. Expiry, cancel, cizí event/origin a odebrání práv jsou ověřené; existující native session po revokaci vidí prázdný rozsah.
- Blueprint SQL zachovává canonical schema/resource 2, ceny, identity, receipts a atomické jednotky. Novější main command ownery a původní integrity delta jsou sjednocené; odstraněné legacy writer overloady se nevracejí přes foundation/source manifest.

## Provedené gates

| Oblast | Skutečný výsledek a evidence |
|---|---|
| Flutter | Obě registrované roots + native MCP v jedné sériové batch: **711 viditelných testů prošlo**, dalších 49 hidden lifecycle/setup výsledků, žádný fail/skip. [Běh](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [osm přesných owners](../archive/repository-artifact-followup-2026-10-21.md#blueprint). |
| JS | Celá sada **512 pass, 0 fail, 25 již existujících skip**. Poslední změna zpracování superseded MCP importu má navíc finální affected startup/MCP/translation batch **31 pass**. [Celá sada](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [affected freeze](../archive/repository-artifact-followup-2026-10-21.md#blueprint). Žádný nový skip. |
| MCP a hosting | Remote Node **10 pass**, Edge **8 pass**, hosting/CSP/PWA **7 pass**, skutečné browser controls pass. [Reálný lokální grant](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [production shell](../archive/repository-artifact-followup-2026-10-21.md#blueprint). |
| Package | Core **263 pass**, JS package **28 pass**, Escape regression **1 pass**. Celý nový pub/npm archive gate prošel, včetně čistého consumeru a skutečného archived Flutter example v browseru. [Receipt](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [archive log](../archive/repository-artifact-followup-2026-10-21.md#blueprint). |
| SQL | Canonical source parity, integrity source parity a reservation integrity: **3/3 pass**. Skutečné PG races: **19 + 2 + 1 = 22 scénářů**, všechny prošly. Fresh katalog s **252 forward migracemi** zachoval skutečný předem sold/held aggregate a replay. [SQL](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [races](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [fresh](../archive/repository-artifact-followup-2026-10-21.md#blueprint). |
| Zdrojové kontrakty | Integrity assembler: **22 canonical sources**, canonical mutation source generator i immutable foundation check prošly. Nulový drift skutečné lokální DB proti source ownerům; původní main migrace beze změny. [Gates](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [drift](../archive/repository-artifact-followup-2026-10-21.md#blueprint). |
| Skutečné UI | Release Flutter a production JS: chairs1000, tables100x10 a mixed950+standing50 mají nové přijaté objednávky, správnou cenu, spot identity, clear holdu a reload sold stavu. Admin UI uložilo a znovu otevřelo 1000 nezměněných bindings; revision 3 -> 4, canvas width 2810 -> 2964. [Nákupy](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [admin](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [identity](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [atomická pohovka](../archive/repository-artifact-followup-2026-10-21.md#blueprint). |
| Výkon | Každá fixture: 100 anonymních read sessions, 20 nezávislých holds a 20 soupeřů s právě jedním vítězem. Hold p95 přibližně **158/141/158 ms**, žádný deadlock/timeout/internal error. Desktop modaly **454/634/329 ms**, 30 native CDP touch zoomů s p95 **20/32/24 ms**. [HTTP](../archive/repository-artifact-followup-2026-10-21.md#blueprint), [UI](../archive/repository-artifact-followup-2026-10-21.md#blueprint). |

Package core měl tři testy se starými `attachment.edge/x/y/rotation` a implicitním wall reflow. Canonical physical kontrakt používá typed placement a rigidní posun celého stolu. Fixture a assertions nyní ověřují skutečný kanonický kontrakt: clamp celého inventáře, stejné IDs/poses/placements, žádné kolize a přesné zachování free chair/manual rotation. Runtime se kvůli nim neměnil. [Reseal důkaz](../archive/repository-artifact-followup-2026-10-21.md#blueprint) potvrzuje stejné kompilované package vstupy; nový archiv byl přesto celý sestaven a ověřen.

## Uzavřený deletion ledger

| Nahrazená cesta | Konečný stav |
|---|---|
| Staged/legacy Blueprint readers a chybějící layout fallback | Legacy rollout routines nejsou v DB, public/admin readers při chybějícím layoutu fail closed. Fresh/cutover poison gate prošel. |
| Legacy Blueprint writer a duplicitní source ownery | `update_blueprint(jsonb)`, jeho interní legacy owner a starý jednoparametrový storno overload odstraněny guardovaným forward SQL. Manifest ukazuje na canonical Blueprint update/swap ownery; staré eshop kopie jsou odstraněné. |
| Interní renderer/style/geometry kopie | Host používá společný package; žádný load-error renderer fallback. Archived consumer a oba skutečné hosty kvalifikované. |
| Sibling runtime dependency / druhý aktivní npm package | Pub používá repository-relative vendor; npm má jeden aktivní immutable tarball `festapp-venue-layout-0.3.0-closure-062c9d302de0.tgz`, SHA-256 `062c9d302de0787d122160f38de7d6e37441382e005e8ffcedd916140312b4cc`. Tento i ostatní starší host archivy se obnovují z Git revize `a4296c57687294b34826e59c7b232eef582c9748`; aktuální výběr určuje `web_client/package.json`. |
| Web MCP -> Flutter handoff/cache fallback | Hosting i service worker mají JS/online-only hranici pro `/settings/mcp-connect`. Nativní Flutter route je úmyslně zachovaná. |
| Public form -> nepotřebný editor sync | Odstraněno ve FormPage bootstrapu, bez rozšíření RLS/grantů. Tři identity a přímý deny jsou doložené. |
| Dirty sibling checkout jako runtime source | Izolovaný host má vlastní vendor a archive receipts. Sibling stromy slouží jen jako importní/historická evidence. |
| Legacy DB archivy/offline importer | Zachovaná explicitní offline/archivní hranice; normální read/save nejsou fallback. Fyzická kontrakce dat není autorizovaná. Cenové snapshoty, objednávky a receipts zachované. |

## Reprodukovatelnost a provozní hranice

[Finální manifest](../archive/repository-artifact-followup-2026-10-21.md#blueprint) spojuje source, package, SQL a build hashe. [Úklid](../archive/repository-artifact-followup-2026-10-21.md#blueprint) určuje stav task-owned služeb; data se nemažou.

E-mail byl po celou dobu paused, worker_url NULL a bez aktivního odesílacího cronu. Nepoužil se skutečný Google OAuth ani uživatelský native klient: native SDK klient/callback, přesný loopback issuer transport a vnější notification SDK hranice jsou explicitně syntetické. Ztracené potvrzení má component regression a skutečné broker duplicate-approve odmítnutí; nebyl proveden live provider výpadek. Image Worker čte skutečné lokální R2 bytes přes úzký testovací hostname adaptér; hash background bytes odpovídá manifestu. CDP touch emulace není fyzický telefon.

Výsledek je připravený společný lokální kandidát. Začlenění do main, produkční migrace a klientský rollout vyžadují samostatnou autorizaci a aktuální release gates. [Follow-up kanonických oprávnění](canonical-authorization-plan-2026-10-20.md) zůstává oddělenou budoucí prací.
