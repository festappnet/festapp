# Dokončení akce se šablonou vstupenky

Uložený koncept se šablonou Hedvábí - tmavé končí v `normalize_occasion_setup_appearance_internal` chybou `Shared ticket style mismatch`. V kroku Vzhled má formulář barvu `4465A6` a šablona má vlastní pozadí `0E1523`. Vybraná šablona musí projít dokončením a zachovat barvy z náhledu. Totéž platí pro dříve uložené koncepty.

1. Sestavit návrhy skutečným převodem z katalogu pro všech 15 šablon, 18 palet a oba režimy pozadí. Ověřit výstup proti současné kontrole průvodce a proti databázové validaci rozvržení vstupenky.
2. Upravit `database/functions/occasion_setup/appearance.sql`. Společné nastavení určuje paletu formuláře a písmo vstupenky. Barvy rozvržení vstupenky spravuje šablona. Ponechat kontrolu shody formuláře a písma i validaci rozvržení a vazeb ve finalizaci. Přidat dopřednou migraci funkce. Již uložené návrhy se opraví při dalším dokončení bez přepisu dat.
3. Přidat rychlou regresi do stávajícího SQL testu vzhledu v CI. Ověřit solidní i přechodové pozadí šablony, zachování rozvržení a odmítnutí odlišného písma. Ověřit i skutečný katalog po opravě a doplnit lokalizovanou nápovědu vzhledu vstupenky.

Výsledek ověříme v izolované databázi. Produkční aplikace migrace je samostatný provozní krok.

## Výsledek provedení

Před opravou kontrola průvodce zamítla 504 z 540 kombinací. Prošla jen šablona Jmenná na výšku. Validace rozvržení a jeho vazeb prošla u všech 540 kombinací. Po aplikaci dopředné migrace v izolované databázi prošlo všech 540 kombinací oběma kontrolami. Nový regresní případ nejdřív selhal na původní chybě a po opravě prošel společně s testy finalizace a doručení vstupenek. Prošlo i šest testů sestavení lokalizované nápovědy.
