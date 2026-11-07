# PR #752 - výsledek canonical cutoveru

Datum: 2026-11-07. Stav: lokální implementace a požadované ověření dokončeny. Publikace, merge, produkční migrace, enablement ani deployment neprovedeny.

Worktree `/Users/miakh/source/festapp-pr752-cutover`, větev `fix/pr752-canonical-measurement`, base `8af7d6435a9d763db1d1e55e2fb06d83b3f70dde` ze skutečného PR #752. Tento head již zahrnuje main `99dc29ae7f664796f6d1a9916d360ca28535411e`, #749/#754 a kapacitní wording. Cizí review/release worktrees a jejich rozpracované změny zůstaly zachované. Nová implementace je necommitnutý lokální diff.

## Výsledek

Všechny tři veřejné consent vstupy vedou do jediného scope-bound choice bindingu. Výměna nebo ztráta zdroje neobnoví starší grant; starý disposer/callback je neúčinný. Klaro watcher patří témuž owneru a jeho registrace/disposal má cleanup i při chybě. Setter před prvním kontextem se připoutá jednou; mezi organizacemi, Unit a processing revision se stará volba nepřenáší.

Frame record vlastní jeden heartbeat, lease, subscription a load listener. Výměna originu/detach uklidí záznam a časovače, pagehide zastaví liveness, BFCache resume obnoví aktuální record. Změna souhlasu předává čerstvý nested festapp_consent už v samotné update události a nemutuje publikovaný objekt.

Jediná aktivní measurement cesta používá protocol 3, nezávisle na layout protocol 1. SQL policy i manifest nesou povinný measurement_protocol; stejná verze vstupuje do processing fingerprintu a mění identity uložených voleb. Nová forward migrace `20261107170000_form_measurement_protocol.sql` nevynucuje enablement, nepřepisuje historii ani nemění konverzní fakta/uloženou konfiguraci. Druhá aplikace má stejný hash. Registrovaný externí deployment profile gtm-v1 zůstává úmyslně zachován.

consent_required dále označuje požadované notice/ovládání volby, nikoli execution gate. SQL komentář, MCP popis a dokumentace nyní používají stejný význam. Frantův deklarovaný advanced/contact záměr zůstává zachován: bounded buyer contact pouze v úspěšných konverzích také pod denied state. Tento záměr není zárukou správného nastavení libovolných tagů pořadatele.

Browser navíc odhalil duplicitní ruční konstrukci manifestu v EmbedBridge. Byla odstraněna; bridge nyní používá stejný measurementManifest owner jako ostatní producenti a má regresi přes skutečně odesílaný kontext.

## Provedené ověření

Pnpm 11.24.0, frozen install v web_client a tools/festapp. Pět nových cutover testů na původním stavu selhalo, žádné skipy. Zachované red evidence: `/tmp/pr752-cutover-red.log`.

Finální canonical batch:

```sh
./automation/test_ci.sh web-startup wix-checkout-compatibility seat-checkout server-policy
```

Všechny čtyři lanes prošly (44,3 / 11,1 / 95,1 / 9,9 s). Po doplnění výhradně browser regresí a přejmenování zastaralého názvu testu byl na konečných vstupech znovu spuštěn pouze dotčený kontrakt:

```sh
./automation/test_ci.sh web-startup
```

Prošel za 42,5 s. Runtime/SQL a vstupy ostatních tří passing lanes se poté nezměnily. Oba vývojové receipts jsou uchovány v [CI záznamu](measurement-pr752-ci-2026-11-07.json).

Doložené výsledky uvnitř lanes:

- 161/161 cílených measurement/checkout/embed JavaScript testů, bez skipů.
- Pět measurement browser runnerů: host, Klaro, isolated runtime, nested a adversarial prošlo. Další reálné browser případy ověřily chyby read/subscribe, zastaralý disposer/callback, stejný iframe přes dva task-owned originy A/B/A s jediným heartbeat a detach bez timeru. Událost hidden byla řízeně simulována přes document.hidden a visibilitychange, s ověřeným skutečným doručením události; nejde o tvrzení o fyzickém přepnutí tabu/OS.
- 7/7 SQL souborů: šest measurement test souborů a canonical source parity; skutečná disposable PostgreSQL databáze.
- 27/27 PostgreSQL Node testů, bez skipů; zahrnují skutečný starý SQL snapshot -> forward -> nový stabilní fingerprint, zachování enablement/config/facts a opakování migrace.
- Forward migration assembler/parity, deterministic embed/runtime builds, docs:check, MCP forms/auth a ostatní předepsané kontroly v lanes prošly.
- Čtyři již existující nesouvisející Wix PostgreSQL integration testy zůstaly v příslušné Wix lane skipnuté. Nejde o skip nového measurement SQL/browser ověření ani o tvrzení, že všechny volitelné integrace byly vykonány.
- Samostatné targeted bridge/helper/frozen-peer testy po odstranění ručního manifestu: 54/54; tyto případy jsou i v konečném 161-test batchi.
- git diff --check prošel; scoped reachability/absence průchod neukázal aktivní protocol 2 handler ani starou record.source/record.consent fallback autoritu.

Původní browser selhání odhalilo skutečnou chybu manifestu a vedlo k opravě owneru. Jedno transientní CDP launch selhání se vyřešilo opakováním bez změny zdrojů. Testovací spy byl opraven tak, aby nepředával neklonovatelný gtag Arguments objekt přes postMessage. Výsledná evidence pochází až z passing běhů po těchto opravách. Task-owned sessions a fixture servery byly uklizeny.

## Deletion ledger - uzavřeno

| Nahrazený artefakt | Výsledek a důkaz |
|---|---|
| Nezávislé record.consent a record.source fallbacky | Odstraněny; jediný binding. Reprodukce source loss/revision nyní denied. |
| Nechráněné/stale disposery a samostatný Klaro watcher | Jeden idempotentní binding disposer; source replacement, stale callbacks a chybná registrace mají testy. |
| Interval cleanup jen přes !isConnected | Jeden disposer recordu + membership/origin guard; unit i skutečný A/B/A browser a detach. |
| Mutace publikovaného context jako náhrada update | Čerstvý canonical snapshot pro init/update/event; eager consumer i browser vidí nested změnu před konverzí. |
| Aktivní measurement protocol 2 | Ve všech nových send/receive cestách pouze shared protocol 3. Protocol 2 zůstává výhradně v jasně označených historických test peers a historii. |
| Stejný fingerprint přes změnu chování | Measurement protocol je povinný a hashovaný; skutečný SQL before/after/idempotence test. |
| Nejasný consent_required/required_purposes | Vyjasněn veřejný význam, strict MCP status shape zachován; žádné nové konkurenční mode flags. |
| Ruční manifest projection v EmbedBridge | Odstraněna, používá shared measurementManifest; skutečný browser průchod a sent-context regrese. |
| Ručně sloučené generated artefakty | Embed, runtime, canonical SQL parity i MCP reference jsou generované z vlastních zdrojů a checks prošly. |

Úmyslně zachované hranice: setMeasurementConsent/connectKlaro/connectMeasurementConsent jsou podporované veřejné adaptéry do jednoho owneru. Layout protocol 1 včetně jeho guardu zůstává samostatný kontrakt. Registry gtm-v1 není measurement protocol fallback. `web_client/tests/fixtures/measurement_protocol_2` jsou skutečné zmrazené artefakty z main 99dc29ae7 s provenance README, nikoli druhá implementace v produkci; nejsou importovány produkčními zdroji/generátory. Matice testuje old/new skutečný handshake, odmítnutí kontaktů a zachovaný submit, nejen pozměněné číslo v mocku.

## Neprovedené produkční kroky a hranice důkazu

Požadované místní ověření není otevřené. Kontrolované browser fixtures a konzumenti dokazují náš kontrakt, nikoli živou Google Ads/Meta atribuci či chování libovolného externího kontejneru.

Publikace a produkce nebyly autorizované tímto execution promptem a nebyly provedeny. Před pozdější publikací znovu fetch aktuální main a PR, prohlédnout postup ostatních sessions, zachovat nové změny a opakovat zneplatněné gates. Před produkcí inventura přesně schválených Units/tenantů a starých artefaktů, povinné review/merge/exact-main CI gate, potom SQL -> Worker -> helper -> vybraný web podle plánu. Produkční migrace zůstává unapplied; neaktivovat měření ani jiné tenanty jako vedlejší efekt. Vývojové dirty receipts nejsou release attestací.
