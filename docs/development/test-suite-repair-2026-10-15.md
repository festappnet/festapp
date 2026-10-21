# Oprava plné testovací sady - 2026-10-15

Stav: finální úplný běh automation/test_all.sh prošel s návratovým kódem 0. Opravy jsou oddělené od SEO změn na čistém mainu. Žádná výjimka z testovacího gate nebyla použita.

## Příčiny a opravy

- Původní localhost:55432 měl zastaralé schéma. Nová izolovaná instance `festapp-seo-tests-20261015` na localhost:59042 byla sestavena z kanonického baseline a všech migrací, bez zásahu do původní databáze nebo produkce. Bootstrap nyní přidává také existující verzované syntetické demo fixture, které jejich testy vyžadují.
- Test přecenění demo plesu potřebuje provozní `pg_temp` funkce a referenční plán ve stejném spojení. SQL test deklaruje zdrojové závislosti pomocí `-- test-setup: database/...sql`; runner je načte v testovací transakci. Nejde o kopii provozní implementace ani trvalé databázové objekty.
- Test horního počtu vstupenek používal neexistující formulář, takže se nedostal přes novou alokační hranici. Používá vlastní validní formulář, stále vyžaduje chybu 1023 nad limitem a navíc ověřuje, že nevznikla objednávka ani vstupenky. SQL obchodní logika se nemění.
- Formulářový widgetový test neměl editora, přesto očekával uložení. Fixture nyní výslovně nastavuje právo úprav; aplikační kontrola oprávnění se nemění.
- Test historie očekával tooltip odstraněný výslovnou změnou `acdc2e571`. Ověřuje čitelný cílový text, barvy a absenci redundantního tooltipu.
- Test obnovovací hlášky spojoval její text s novým diagnostickým podblokem. Ověřuje oba údaje samostatně a přesně.
- Search, feedback a offline banner v UI testech spouštěly neřízené platformní úložiště. Byly doplněny chybějící části existujícího rozhraní pro poskytování dat: načítání lokálních událostí, zápis cache feedbacku a datum poslední synchronizace. Výchozí služby a běžné chování aplikace zůstávají stejné. Regresní testy pokrývají obnovení lokálních událostí při nové projekci a úspěšný i selhávající zápis cache bez rozbití živého UI. Test fotografie používá podporované veřejné cache rozhraní s izolovaným souborovým prostředím a bez nativního SQLite pluginu.
- Build fixture v update_prompt testu neobsahoval současný IS_APP_SUPPORTED kontrakt. Generuje jej z konfigurace stejně jako ostatní veřejné identity fixture; ověřovací gate se neoslabuje.
- Image-worker integrace neměla nainstalované lockfile závislosti. Byly nainstalovány přes pnpm install --frozen-lockfile. Testovací skript používá místní balík a předem srozumitelně odmítne chybějící závislosti. Testy vyžadující vzdálený image worker se při localhost databázi nadále výslovně přeskakují podle jejich existujícího kontraktu; netváří se jako provedený živý E2E test.
- `automation/test_all.sh` dříve některá selhání webu, Flutteru nebo integrace pouze vypsal a mohl skončit úspěšně. Nyní je akumuluje do nenulového výsledku. Procesní regresní testy používají skutečný orchestrátor a simulované child suite, včetně případu neúspěšný web a následný úspěšný Flutter.

## Ověřování

Cílené kontroly: 185/185 SQL testů, původně selhávající widgetové scénáře, aktualizační UI/build fixture, test návratových kódů hlavního skriptu a cílená Dart analýza (bez nálezů). Finální plná sada používá tento příkaz:

```sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:59042/postgres?sslmode=disable' \
  bash automation/test_all.sh
```

Pro opakované vytvoření samostatné instance je její config v `/tmp/festapp-seo-db-20261015/supabase/config.toml` a bootstrap respektuje `FESTAPP_LOCAL_DB_WORKDIR`, `FESTAPP_LOCAL_DB_PROJECT_ID`, `FESTAPP_LOCAL_DB_PORT`. Výchozí sdílený testovací server nebyl přepsán. V produkci se neaplikovala žádná migrace ani demo seed.

Finální log: `/tmp/festapp-tests-all-final.log`. Opravy testů mají samostatný patch `docs/plans/vstupenky-test-repair-2026-10-15.patch` v původním pracovním stromu. Dříve připravený produkční bundle je změnou Dart zdrojů invalidován a před případným vydáním se musí znovu sestavit.


## Finální výsledek

Úplný orchestrátor doběhl úspěšně. Web: 348 pass, 0 fail, 9 skip. SQL: 185 pass, 0 fail. Flutter: 1468 pass, 0 fail, 1 skip. Deno: 336 pass, 0 fail. Automatizační kontroly včetně nových regresních testů orchestrátoru prošly. Vzdálená image-worker integrace: 27 výslovně přeskočených scénářů, protože lokální schema databáze neodpovídá vzdálenému Auth/workeru; nejde o živé E2E ověření. Cílená Dart analýza: No issues found.
