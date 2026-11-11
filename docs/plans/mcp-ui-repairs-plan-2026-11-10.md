# Oprava mezer nalezených živým MCP UI testem

Výchozí produkční zdroj: `ac690c654d11b8b1f863faa8dfb314b48f6ee855`. Nálezy a evidence: `/Users/miakh/Downloads/festapp-mcp-ui-20261110/sophisticated/`.

## Cíl a hranice

Obecný MCP má podporovat stejné doménové úkony jako administrace v rozsahu explicitního souhlasu a aktuálních práv uživatele. Úspěchem je funkční duplikace v oprávněném případě, individuální výběr požadovaných oprávnění v reálné tenantové souhlasové stránce a ověřený skladový scénář. Žádné plošné rozšíření rolí, obcházení doménových kontrol ani druhý implementační vlastník operací. Cílem nasazení je pouze `festapptickets` / vstupenky.online.

## Postup

1. Reprodukovat chyby na skutečných cestách. Zachovat UI-only pravidlo pro živé business operace přes Panerelay a MCP Inspector. U duplikace prokázat shodu účtu, zdroje a cíle mezi MCP a administrací; pomocí cíleného lokálního integračního testu odlišit chybu adaptéru, souhlasu a doménového oprávnění. U skladů nejdřív rozlišit vypnutou funkci od chybějící role.
2. Doplnit do skutečné `/settings/mcp-connect` volbu jednotlivých požadovaných funkcí. Použít existující katalog `mcp-permissions.mjs`, zachovat závislosti oprávnění, povinný základ a stávající rozsah pořadatelů/akcí. Vypnutí nadřazeného čtení odebere závislé zápisy; opětovné zapnutí čtení je samo neobnoví. Explicitní prázdný výběr musí zůstat prázdný i v přenosu. Založení nové akce musí jít odmítnout nezávisle na přístupu k celému pořadateli.
3. Opravit skutečně prokázanou příčinu nesouladu duplikace. Zachovat současný SQL UI command, jediný receipt/UUID, kontrolu zdrojového i cílového rozsahu a živých oprávnění včetně replay. Nepřidávat paralelní SQL writer ani rozšiřovat oprávnění jen kvůli testu.
4. Spustit cílené regresní testy reálného souhlasového komponentu a integrační testy s disposable PostgreSQL. Pokrýt částečný souhlas, závislosti, explicitní nulová funkční oprávnění, zákaz cizí akce a oprávněnou duplikaci/replay. Ověřit původní negativní hranice.
5. Publikovat validovaný kanonický zdroj. Před produkcí vyžadovat všech osm CI kontrol na přesném main SHA a dodržet main/tenant ancestry a drift gate. Nasadit jen dotčené komponenty podporovaným postupem, zachovat klienty a existující granty. Rutinní release provede delegovaný release agent; produkční Flutter build lokálně, nikoli GitHub Deploy workflow.
6. Zopakovat přes UI duplikaci a nezávislou úpravu kopie, částečný souhlas bez smyčky a bez zapisovacích nástrojů, zákaz cizí akce a skladové přiřazení/replay/atomické odmítnutí překročené kapacity na oprávněné skryté fixture. Odvolat jen vlastní testovací granty a ukončit vlastní relace. Výsledek označit po jednotlivých scénářích; blokovaný krok není úspěch.

## Architektura a rizika

Klientská stránka vybírá souhlas; issuer jej validuje a zužuje token; Operations adaptují transport; kanonické SQL predikáty a UI command vlastní oprávnění a doménovou transakci. Budoucí API používá stejnou hranici. Existující granty se nemění automaticky. Nejistoty před reprodukcí: identita a přesná UI cesta duplikace, dostupnost skladové funkce a případný produkční drift. Opravy těchto oblastí řídí evidence, ne předpoklad, že každý `FORBIDDEN` je chyba.

Ověřování: `standard` kvůli autentizaci, autorizaci a veřejnému kontraktu; navíc povinné release gates. Cizí rozpracované změny v původním checkoutu zůstávají nedotčené.

## Implementované řešení a lokální důkazy

- Produkční definice pěti funkcí formulářů odpovídají zdroji; SQL drift byl vyloučen.
- Nový integrační test bez předchozího otevření administrace nejprve selhal: nově vytvořená akce neměla zděděné členství tvůrce. Kanonický creation command nyní atomicky volá existující `add_user_to_occasion_internal_v1`, stejný owner jako první vstup do administrace. Dědí skutečné role jednotky; nepřidává paušální editor/manager práva. Replay se vrací před inicializací členství a nemůže obnovit odvolaná práva. Migrace `20261110120000_mcp_creation_membership.sql` se týká budoucích vytvoření, neopravuje ani nerozšiřuje role existujících akcí.
- Tenantová webová souhlasová stránka nabízí požadované funkce jednotlivě, udržuje jejich tranzitivní závislosti podle sdíleného katalogu a výslovně přenáší i prázdný výběr. Zakládání akcí lze odmítnout samostatně při zachování přístupu k pořadateli. Nemění se klientský strop ani již vydané granty.
- Reálný webový komponent: 45 testů prošlo, včetně všech požadovaných funkcí katalogu a odmítnutí tvorby/zápisu. PostgreSQL: 22 testů prošlo, žádný přeskočený; zahrnují vytvoření před UI návštěvou, duplikaci/replay, odvolání práv, přesné dědění manager-only a editor-only rolí a skladová pravidla. Soubor `forms-postgres.test.mjs` je přidán do skutečného PostgreSQL CI kroku, ne jen do inventáře testů.
- Povinné source/release gates a finální živý UI retest jsou následující kroky, nikoli již splněný výsledek.
