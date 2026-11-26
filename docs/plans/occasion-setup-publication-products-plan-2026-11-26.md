# Dokončení akce, úvodní obrázek a produkty

Jedna PR na `main` a jedno ověřené nasazení na `prod/festapptickets` pro vstupenky.online.

1. Zahrnout [ověřenou opravu šablon vstupenek](occasion-setup-ticket-gallery-plan-2026-11-26.md) a její dopřednou migraci.
2. Na kroku zveřejnění zobrazit stávající nahrávání úvodního obrázku. U vybrané propagace nebo při zveřejnění v katalogu s otevřeným či naplánovaným prodejem vyžadovat obrázek. Povolit uložení rozpracovaného konceptu a přechod do souhrnu. V souhrnu označit chybějící obrázek barvou chyby i textem a odkazem na krok nahrání. Doplnit regresi a lokalizovanou nápovědu.
3. Prověřit vytvoření a úpravu produktu v editoru formuláře, uložení a načtení rozpracovaného konceptu a vytvoření skutečných produktů při dokončení akce. Opravit nalezené vady v téže PR a ověřit zachování ceny, měny a vazby na správný formulář či typ produktu podle zjištěného chování.
4. Spustit cílené Flutter, SQL a obsahové testy. Ověřit vlastnictví testů, aktuální základ PR a kanonické migrace. Připravit jednu PR s výsledky.
5. Po splnění pravidel pro merge sloučit PR. Po úspěchu všech povinných CI kontrol přesného SHA použít schválený postup pro kanonický backend a jedinou produkční větev. Ověřit migraci a veřejnou verzi vstupenky.online. Produkční koncept organizátora ponechat rozpracovaný.

Autoritu obrázku vlastní existující nahrávání obrázků jednotky. Flutter používá výslednou URL v konceptu. Výpočet zveřejnění vychází z existujícího pravidla plánování prodeje. Ověření na skutečné akci provádíme na testovacích datech.

## Zjištění při provedení

- Průvodce při vytvoření pole `ticket` nastavil `is_ticket_field=true`. Editor formuláře tak hlavní pole skryl společně s jeho vnořenými poli. Normalizace průvodce opraví i uložené koncepty. Test otevře starší koncept, přidá produkt, upraví cenu a znovu načte uloženou verzi.
- Databázový test ověřuje stejný tok přes uložení a načtení konceptu. Při dokončení vznikne trvalý produkt se správnou cenou, měnou a vazbou na skupinu formuláře.

## Kontrola CI před produkcí

GitHub zobrazil `Seat checkout regressions / database-service-regressions`. Job ve skutečnosti testuje databázové služby, nastavení akce, výkon dotazů a druhou část kontraktů MCP. Selhal při druhém ověření dřívějšího výsledku, ještě před spuštěním testů. Runner už v té chvíli nemohl bezpečně přejít na přímé testování, protože instalace závislostí se řídila původním plánem.

1. Projít všechny povinné joby podle příkazů v `automation/ci/checks.json`. Upravit zavádějící zobrazované názvy workflow a zdokumentovat rozsah jobů. Zachovat stabilní klíče jobů pro nasazení a artefakty důkazů.
2. Čerstvé ověření použitého výsledku dokončit před rozhodnutím o instalaci závislostí. Při timeoutu nebo neověřitelném důkazu přejít na přímý běh všech testů daného jobu. Runner musí přijmout jen přesně ten ověřený plán, který vybral přípravu prostředí.
3. Přidat test timeoutu a test změněného plánu, znovu spustit kontroly téže PR. Pokračovat k merge a produkci až po průchodu CI.

### Rozsah povinných kontrol

| Workflow v GitHubu | Klíč jobu | Co skutečně ověřuje |
| --- | --- | --- |
| Database and ticketing regressions | `seat-checkout` | Místa, oprávnění, platby, objednávky, doručení a průchod checkoutem v prohlížeči |
| Database and ticketing regressions | `database-regressions` | Reprodukci schématu, runtime databáze, životní cyklus akcí, přihlášení, měření a notifikace |
| Database and ticketing regressions | `mcp-database-contracts` | Oprávnění a první část databázových kontraktů MCP |
| Database and ticketing regressions | `database-service-regressions` | Databázové služby včetně vytvoření akce, výkon dotazů a druhou část kontraktů MCP |
| Database and ticketing regressions | `ticket-preview-and-delivery` | Náhled, nastavení a doručení vstupenek, včetně průvodce |
| Database and ticketing regressions | `ticket-rendering-contracts` | Šablony, vykreslování, fonty a palety vstupenek |
| Web, server and client contracts | `server-policy` | Serverové a webové kontrakty pro obrázky, měření, nasazení, autentizaci, MCP a HTTP API |
| Web, server and client contracts | `client-contract` | Flutter adaptéry, widgety, přihlášení a katalog prodeje |
| Web, server and client contracts | `client-browser-contract` | Flutter web v Chromiu |
| Navigation interaction regressions | `navigation-interactions` | Navigaci a interakce v administraci, například nastavení, kalendář a objednávky |
| Website checkout integrations | `wix-checkout-compatibility` | Wix, Joomla a HTML integraci prodeje |
| Website checkout integrations | `wordpress-checkout-compatibility` | Instalovanou integraci prodeje ve WordPressu |
