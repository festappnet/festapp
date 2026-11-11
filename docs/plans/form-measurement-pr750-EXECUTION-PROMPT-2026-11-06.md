# Oprav PR #750 podle prověřené cílové architektury

Aktualizováno: 2026-11-07. Verification: standard.

Implementuj celé přepracování PR https://github.com/festappnet/festapp/pull/750 v `/Users/miakh/source/festapp`. Cílem je funkční reklamní atribuce a konverzní měření, jejichž spuštění skutečně řídí souhlas návštěvníka. Dokonči implementaci a potřebné ověření; samotná analýza, oprava startup race nebo další návrh nejsou splněním zadání.

Použij izolovaný worktree a zachovej cizí změny i checkouty. Oba plánovací dokumenty mohou být zatím pouze lokální/untracked; přenes je do pracovního checkoutu jako dokumenty tohoto zadání. Jejich nepřítomnost na PR větvi není důvod rekonstruovat schválený návrh od začátku.

Nejprve přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`, `CONTRIBUTING.md` a celý autoritativní plán:

`docs/plans/form-measurement-pr750-plan-2026-11-06.md`

Plán prošel nezávislou oponenturou `gpt-6-astra`, reasoning `medium`. Pět připomínek bylo zapracováno a následný verdikt byl ready for implementation bez zbývajícího architektonického blokátoru. To není důkaz hotové implementace ani náhrada testů.

Zjisti aktuální pracovní stav, fetchni autoritativní main a PR refs a prohlédni nové commity. Kontrolovaný PR head byl `65705b455ace4818d063aa122352cf48b6fe86f8`, tehdejší main `b3c20983b13120d8a4c0238b4358fa77b9e292ce`. Tyto SHA jsou výchozí důkazy, nikoli pokyn zahodit novější práci. Aktualizuj větev podle pravidel repozitáře; konfliktní MCP referenci přegeneruj ze zdroje. Pokud nové důkazy mění skutkový předpoklad plánu, aktualizuj plán a dotčenou vlnu s vysvětlením; zachovej cílové chování a odstraňovací seznam.

## Přijaté cílové chování

Produktové volby níže jsou součástí tohoto exekučního zadání. Nežádej znovu jejich potvrzení. Soubor se stává instrukcí k implementaci jeho výslovným spuštěním uživatelem; samotná přítomnost v repozitáři práci nespouští.

- Zachovej attribution allowlist a reklamní click ID, produktové štítky, zásady pořadatele, lokalizovaný vzhled souhlasové vrstvy a organization/Unit/form přepínače. Zachovej checkout, SQL oprávnění a izolaci cizího kódu.
- Použij basic režim: před příslušným souhlasem žádné načtení GTM/Unit skriptů ani měřicí události hostiteli. Chybějící nebo rozbitá CMP/helper ponechá měření vypnuté; nákup funguje dál.
- Současný smíšený GTM/custom profil vyžaduje analytický i marketingový souhlas současně. Samotný jeden účel jej nespustí. Toto omezení jasně popiš v UI/MCP/docs; nový analytics-only profil neimplementuj.
- Odstraň extrakci a export kontaktních polí z obecného dataLayer a obou transportů. Enhanced conversions nejsou součástí této úlohy; příznak enhanced_conversions_unavailable musí být true. Zachovej konverzní fakta bez kontaktních polí a stabilní event ID.
- Odvolání, změna identity, expirace, zánik consent zdroje, skrytí/pagehide a relevantní změna konfigurace zneplatní grant i rozpracované odesílání. Nové udělení souhlasu staré sendery neobnoví. Již doručená data neslibuj odvolat.

## Implementace

Proveď čtyři vlny autoritativního plánu v pořadí závislostí: kontrakt/SQL, jeden lifecycle owner, oba transporty, testy/generované výstupy/dokumentace. Rozpracované stavy nenasazuj. Rutinní implementační volby řeš samostatně.

- Jeden FormMeasurementSession vlastní eligibility, roli, souhlas, freshness, generaci a volbu transportu. Konstruktor nemá síťové efekty; start je synchronní zahájení sledování. In-flight policy Promise sdílejí všichni čekající a stale odpověď/finally nesmí měnit novější generaci. Dispose je terminální, ostatní chyby jsou obnovitelné.
- FormDataLayer vlastní význam událostí, katalog, baseline košíku a deduplikaci návštěvy. Nemá vlastní policy timer ani Auth/consent rozhodování. OnActive oznamuje použitelnou aktivaci bez přehrání starých interakcí.
- Capture vrací sender bound na původní grant. Inactive capture je trvalý no-op; revoke/regrant starý sender neobnoví. Zachyť jej před čekáním na rezervace i před submit. Doménová captureSubmission vrací callback pro výsledek objednávky; pouhý odkaz na stejný owner nestačí. Business dokončení objednávky na measurement callbacku nezávisí.
- Measurement protocol 2 porovná skutečný RPC/Worker bootstrap manifest s přijatou processing/runtime/policy revizí před vložením Unit kódu. Ready/init/ACK vážou scope, revizi, instanci a generaci. Při neshodě nic nespouštěj. Layout/scroll/theme embed protocol 1 zachovej; staré measurement granty odmítej.
- Host connectMeasurementConsent(frame, source) používá revision-bound uloženou volbu, živé čtení/subscription a lease ID. Expirace je lokální, heartbeat znovu čte zdroj. Viewport ani starý boolean nesmějí prodlužovat oprávnění nebo převést volbu na novou revizi. Receiver před push ověří aktuální volbu i lease. Starší helper zachová nákup/layout, nové měření neaktivuje.
- Jedna SQL processing revision zahrnuje známou Festapp konfiguraci a explicitní kladnou, nesnižovatelnou Unit measurement_consent_version přes existující autorizovanou aggregate mutaci. Neslibuj rozpoznání změny vzdáleného GTM obsahu se stejným ID nebo zásad na stejné URL.
- Zachovej SQL autoritu a podmínky persistence/replay konverzních faktů. Dočasná nedostupnost runtime nesmí nově zahazovat obchodní fakta. Purchase dál znamená přijatou objednávku; nepřidávej replay starých nákupů po dodatečném souhlasu.
- Odstraň nahrazené vlastníky rozhodování, bezpodmínečné starty, catch-starty, timeout auto-start a kontaktní payloady. Žádný provider framework, obecný event bus, souběžná legacy business cesta, same-origin script fallback nebo oslabení CSP. Generované soubory vytvářej kanonickými generátory.

## Povinné důkazy dokončení

Testuj veřejné interface a skutečné wiring. Neoslabuj assertions a nenahrazuj chybějící dependency skipem nebo stubbem tam, kde se má ověřovat reálná DB/browser integrace. Pro externí reklamní backend použij deterministický testovací tag; jeho průchod nevydávej za živé doručení do Ads.

1. Startup se zpožděnou policy při skutečném pořadí konstrukce/start; visitor/staff/unknown; chyba a zotavení; změna identity během requestu.
2. Žádné cizí měřicí skripty nebo measurement requesty před souhlasem a po odmítnutí. Rozbitá CMP/helper výsledek nezmění. Kontroluj network a skutečné spuštění, nikoli jen volání setConsent.
3. Pending submit i rezervace přes revoke/regrant stejné session; hidden expiry, pagehide/BFCache, pozdní ACK, neschválený host a odpojený consent zdroj.
4. Parent policy A a Worker config B: žádné spuštění Unit kódu. Zvýšení consent version zneplatní uloženou volbu, ekvivalentní policy renewal zachová generaci.
5. Baseline a deduplikace přes neaktivní období, stejné SQL event ID při autorizovaném replay, žádné přehrání pre-consent interakcí. Seedované soukromé kontakty z formuláře nejsou v payloadu, historii dataLayer, zprávách ani konverzních faktech.
6. Measurement SQL assertions skutečně běží v kanonické seat-checkout lane nad disposable DB; nestačí aplikace migrací. Measurement browser suite běží v kanonické web-startup lane. Autoritou výběru CI zůstává automation/ci/checks.json.
7. Relevantní UI/MCP testy, source/migration parity a generované embed/runtime/MCP docs checks projdou. Uveď skutečné počty vybraných SQL testů a význam zbývajících skipů/nevykonaných kontrol.

Používej pnpm 11.24.0 a frozen lockfiles, FVM a nejvýše jeden Flutter task s --concurrency=1. Browser práci deleguj na gpt-6.1-terra podle AGENTS.md, s izolovaným background session, muted a light mode. Ověřuj coherent změny v dávkách. Pro budoucí publikaci platí affected canonical CI mirror lanes; pro release všech osm required GitHub jobs na přesném baseMainSha. Tato úloha publikaci ani release nepožaduje.

## Migrace, rozsah a předání

Pracuj pouze na sdíleném PR/main rozsahu, nepropaguj změny na prod větve. Stav aplikace původních migrací neodhaduj. Pokud ho nelze bezpečně doložit, ponech jejich obsah a vytvoř forward migraci. Canonical SQL a migrační výsledek musí být shodné. Produkční DB není testovací prostředí a zjišťování stavu nesmí přejít v zápis.

Bez zvláštního zadání neprováděj commit/push, komentář do PR, merge, produkční SQL, změnu GTM/collector/runtime konfigurace, zapnutí měření nebo deployment. Nevyžaduj kvůli tomu schválení před dokončením lokální implementace a testů.

Hotovo znamená celé cílové chování, splněný odstraňovací seznam a průkazné ověření. Build ani původní zelené CI toto samy nedokládají. Nezastavuj u plánu nebo první opravené chyby. Chybí-li skutečně nezbytný externí podklad, dokonči nezávislé části a pojmenuj přesný blokátor; netvrď plné dokončení.

Na konci stručně předej větev/worktree a výchozí SHA, dosažený kontrakt, odstraněné cesty, výsledky ověření a konkrétní neprovedené provozní kroky. Nový deploy/DB disable neukončuje již otevřený legacy always-on iframe; úplný provozní cutover bez důkazu netvrď. Festapp nekontroluje cizí host kód a živá Google/Meta atribuce je ověřená jen s odpovídajícím externím důkazem. Nezahajuj další architektonickou oponenturu jen pro jistotu; prověřený plán implementuj.
