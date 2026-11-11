# Implementace webclientového embedu a společných pravidel obnovy

Pracuj v repozitáři `/Users/miakh/source/festapp`. Nejdříve přečti platné
`AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`, `CONTRIBUTING.md`
a celý autoritativní plán:

`docs/plans/web-embed-architecture-plan-2026-11-08.md`

Cílem je zachovat funkčnost PR #769 pro **výhradně webclientový produkční
embed**, sjednotit kontext/startup/update politiku a základní wire kontrakt,
rozdělit transport/layout/measurement a odstranit nahrazené interní cesty.
Verification: **standard**, protože se mění veřejný protokol, kontrola původu
zpráv, souhlasy a asynchronní obnovování aplikace.

**Provedení musí být tokenově úsporné podle části 5.1 plánu.** Udělej jeden
vstupní průzkum, dále čti pouze nový relevantní kód. Dokončuj ucelené přesuny
vlastníků a validuj je dávkově; žádné testy po každém souboru. Veď krátkou
tabulku důkazů navázaných na vstupy a neopakuj platné kontroly. Plné suite,
buildy a povinné CI gates spusť nad stabilním celkem; případný další běh musí
mít důvod v nové změně nebo selhání. Překryv scénářů s kanonickým lane
neověřuj znovu ručně. Úspora nesnižuje režim `standard` ani povinné gates.
Browser práci dávkuj do jednoho přesného zadání pro Terra, nevytvářej další
review agenty. Logy ukládej na disk, do kontextu vracej jen souhrn nebo výřez
selhání. Při předání další relaci ulož jeden krátký průběžný záznam podle 5.1;
nepřepisuj plán ani historii do dalšího dlouhého dokumentu.

Před editací zjisti aktuální stav `main` a PR #769, jehož ověřený head byl
`987574b9dbe9a9617a4f070332fffa511b2b1004`. Aktuální pracovní větev při zápisu
plánu byla cizí dokumentační větev; nepoužívej ji jako implementační základ.
Pracuj v izolovaném checkoutu z aktuálního autoritativního základu, zachovej
novější změny a případný merge PR nezopakuj jako slepé přepsání souborů.

Proveď všech šest etap v pořadí. Nejprve převezmi správný rozsah změny a
zachyť skutečné browserové regresní scénáře. Zachovej protokol 1, CMS markup
a `FestappEmbed`, 120/240/800 kompatibilitu, původní measurement kontrakt,
ready/recovery globální rozhraní a bezpečnost současného worker handshaku.
Flutter není varianta embedu. Jeho normální startup a runtime recovery dál
fungují přes společného vlastníka; nevytvářej druhý update engine.

Hotovo vyžaduje všechny podmínky části 9 a uzavření deletion ledgeru.
Nevytvářej placeholdery, V2 souběh, spekulativní fallbacky ani nové externí
runtime importy CMS helperu. Zachované externí kompatibilitní meze mají být
výslovně otestované, nikoli odstraněné jako údajný legacy kód.

Pokud současné důkazy vyvrátí faktický předpoklad, aktualizuj autoritativní
plán a odpovídající etapu; neměň potichu požadovaný výsledek. Testuj chování
přes skutečné rozhraní, dodržuj plánované gates a vyhni se opakování již
platných kontrol beze změny pokrytých vstupů. Nové browserové případy musí být
součástí existujícího kanonického testovacího toku. Deleguj browser operace
na `gpt-6.1-terra` podle osobních pravidel; neprováděj nezávislý subagent review
bez samostatného zadání. Flutter úlohy běží pouze po jedné.

Neprováděj commit, push, merge, produkční migraci ani nasazení bez dalšího
zadání. Nevytvářej skutečné platby, objednávky v produkci nebo e-maily.
Na závěr stručně uveď vlastníky a migrované volající, odstraněné implementace,
ponechané externí kontrakty, skutečně provedené kontroly, přesné blokátory
a provozní kroky, které zůstávají neprovedené. Ukliď pouze vlastní testovací
prostředí a zachovej nesouvisející práci ostatních.
