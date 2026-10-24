# Proveď navazující tři řezy testovacích závislostí

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/flutter-test-dependency-cuts-plan-2026-10-15.md`

Proveď všechny jeho vlny: odděl feature modely od editorů a smluvních UI defaultů;
přesuň jediný parser ClientCommandResponse do core/sync a odděl app applier;
zaveď scoped testovací lokalizační logování bez oslabení warning/error kontrol.
Ověřování je standard. Plán nahrazuje pouze navazující tři řezy, nikoli historii
původního Flutter architektonického plánu.

Zachovej všechny původní scénáře a skipy, wire payloady, mutace feature draftů,
ticket callbacky, saved-program fencing, notifikace a await pořadí. Neměň verze
aplikace/balíčků, transport/retry, SQL, tenant konfiguraci, dva workery ani auth
kompozici. Žádné forwarding shimy, druhé implementace, test-only produkční
přepínače, nový DI/reset framework nebo subagenti. Dirty pracovní strom obsahuje
cizí změny: před editací ukládej konkrétní dotčené vstupy, neobnovuj hromadně HEAD.

Dokonči i odstranění starých metod, souborů a registrací dle deletion ledgeru.
Přesuny scénářů zapisuj do existujícího inventáře; nikdy nepřepisuj baseline.
Když současný kód vyvrátí předpoklad, oprav plán s důkazem a uprav příslušnou
vlnu. Nerozšiřuj tiše rozsah; zbylou cestu k routeru nebo jiný limit přiznej.

Nepouštěj další opakované celé benchmarky. Po soudržných změnách proveď cílené
gates a příslušné obrácené pořadí; na finálních vstupech jeden celý klientský běh
a jeden sekvenční produkční web compile podle plánu, s RSS watchdogem pod
3 000 000 000 B a SHA vstupů. Neopakuj prošlý check bez změny pokrytého kódu.
Cíl celého příkazu pod 30 s není předem slíbený a nesmí se zaměnit za čas Flutter
reporteru. Výchozí poslední celý běh je 34,90 s / 2,44 GB, 1 301 případů,
1 300 prošlých a jeden původní skip; nejde o medián.

Bez backend operací, commitu, push nebo nasazení. Nakonec aktualizuj
implementační záznam a receipts, zachovej staré výsledky a stručně uveď skutečný
strukturální i časový přínos, ověření a případný přesný nesplněný cíl.
