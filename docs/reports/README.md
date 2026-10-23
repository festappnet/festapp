# Přehled schopností administrace

[Otevřít statický přehled](admin-capabilities-2026-10-23.html).

Stránka funguje přímo z disku bez serveru, přihlášení a sítě. Má vyhledávání
bez diakritiky a filtry podle oblasti, dostupnosti a typu operace. Technické
podklady jsou až v rozbaleném detailu. Tlačítko tisku umožní uložit aktuálně
vyfiltrovaný přehled do PDF.

Zdroj dokumentace je `admin-capabilities-2026-10-23.json`; HTML je generovaný
výstup, neupravuje se samostatně. Doménová oprávnění a registrace MCP nadále
patří runtime kódu, nikoliv tomuto katalogu. Generátor kontroluje pokrytí všech
aktuálních vzdálených MCP nástrojů proti skutečnému `Operations.catalog` a
sdílenému registru scopes. UI operace jsou ručně doložené konkrétními zdroji;
existence všech dalších ovládacích prvků se automatickou kontrolou netvrdí.

Při změně pokrytí aktualizovat příslušné položky JSON, doloženou revizi a datum,
prováděcí plán a potom spustit z kořene repozitáře:

```sh
node automation/reports/generate_admin_capabilities.mjs
node automation/reports/generate_admin_capabilities.mjs --check
```

Generátor používá existující operátorské moduly; jejich závislosti se instalují
běžně pomocí `pnpm --dir tools/festapp install --frozen-lockfile`. Nevytváří
runtime session a nevolá backend. Do soupisu nepatří zákaznické údaje, přístupové
klíče ani skutečné údaje o rezervacích.

## Datová a síťová evidence

[První baseline](admin-data-network-baseline-2026-10-23.json) zachycuje skutečný
produktový RPC a MCP executor na lokální označené fixture. Při 1000 produktech
se pro každou stránku 50 produktů vrací z DB všech 1000. Nejde o měření produkce
ani o dokončený audit ostatních oblastí. Záznam odlišuje velikost serializovaného
JSON od hypotetické gzip velikosti a jednorázového lokálního času.

Reproduktor vyžaduje explicitní podporovanou disposable databázi, ověřuje její
identitu a vypnuté e-mailové zpracování; všechna data i dočasné DDL vrátí rollback.
Nesmí se pouštět proti produkci. Pro další měření zvolit nový výstup, původní
baseline nelze přepsat:

```sh
FESTAPP_MCP_TEST_DATABASE_URL="$FESTAPP_AUTHORIZATION_DATABASE_URL" node automation/reports/audit_admin_data_path.mjs --output /private/tmp/festapp-catalog-next-measurement.json
```

Po opravě dotazu přizpůsobit reproduktor nové stránkované RPC smlouvě a porovnat
stejné velikosti fixture; původní měření zůstává zachované.
