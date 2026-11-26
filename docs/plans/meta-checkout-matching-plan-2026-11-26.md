# Stabilní předání souhlasu při potvrzení objednávky

## Výsledek a rozhodnutí

Kupující dokončí objednávku i při pomalém měření. Je-li stále platný stejný souhlas, hostitel s ním může při potvrzení předat Meta identifikátory. Platí i při návratu z náhledu, kde prohlížeč vyvolá `popstate` a `hashchange`.

PR #1090 obnovu navázal na zavření náhledu. Kód a reprodukce ukázaly, že `FormMeasurementSession` může první RPC zahodit při druhé události. Přidání dalšího čekání by zachovalo tuto vazbu a zdrželo nákup. Změnu proto postavíme na aktuálním `main` a využijeme původní zjištění z #1090.

## Vlastnictví a bezpečnost

- `publicFormLocation` určuje povolenou veřejnou adresu. Odvozený klíč zachová origin, cestu a přesný query string. Vynechá pouze fragmenty již povolených pohledů. U nepovolené adresy klíč nevznikne.
- `FormMeasurementSession` porovnává klíče při navigaci. Náhled a výběr sedadel ve stejném veřejném formuláři ponechají platnou policy a rozpracované měření. Zahájení dalšího nákupu z obrazovky s výsledkem výslovně obnoví kontext před načtením formuláře a znovu použije tutéž kontrolu při vykreslení. Změna adresy nebo identity, odchod dokumentu a privátní kontext nadále využijí existující ověření. Výsledky hostitele zůstávají chráněné aktuálním kontextem souhlasu.
- Potvrzení objednávky má společný limit 1,5 s pro volitelné získání identifikátorů. Před požadavkem hostiteli i po odpovědi kontroluje stejnou relaci formuláře, epochu kontextu, revizi oznámení a aktuální rozhodnutí. Po vypršení limitu už o identifikátory nepožádá. Serverové ověření, revokace, rezervace, hlavní požadavek a bezpečné opakování příkazu zůstávají v současných vrstvách.
- Samostatné URL kroky vícestránkového formuláře zatím nemají potvrzený kontrakt. Pokud kroky dostanou vlastní adresy, jejich povolené mapování na tentýž checkout bude explicitní v routeru a v kontraktu veřejných adres. Přechody uvnitř stejného povoleného kontextu už teď nepotřebují znát konkrétní náhled.

## Provedení a akceptace

1. Ověřit návrat z veřejného náhledu s oběma událostmi historie a přechody na jiný formulář, jinou atribuci nebo soukromou adresu. Doplnit klíč a předat navigační události do `FormMeasurementSession`.
2. Otestovat skutečný vstup do `FormNetwork.submitOrder` po potvrzení s platným souhlasem a zastavené načtení oznámení nebo odpovědi hostitele. Použít jeden časový rozpočet a zachovat ochranu proti odvolání souhlasu. Zamezit vzniku druhé implementace čekající na zavření náhledu.
3. Aktualizovat integrační dokumentaci, spustit cílené testy a příslušnou prohlížečovou sadu. Případné zveřejnění podléhá ochraně hlavní větve. Nasazení vyžaduje schválený rozsah a ověření živého buildu.
