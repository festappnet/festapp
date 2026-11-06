# Proveď redukci kódu a canonical cutover

Autoritativní plán je `docs/plans/code-reduction-canonical-cutover-plan-2026-11-06.md`. Přečti jej celý a potom implementuj jeho vlny, včetně konkrétního odpojení callers, mazání a důkazů chování/nedosažitelnosti.

Začni v čistém checkoutu aktuálního `origin/main` repozitáře `festappnet/festapp`. Původní `/Users/miakh/source/festapp` má předkompakční historii a cizí rozpracované změny. Plán přenes jako soubory; starou historii nemerguj, nedělej reset ani plošný stash. Referenční SHA průzkumu je `92ee5c61165cb214b2164ab424b46ef82d5047b1`. Jednou projdi nové změny dotčených modulů a při změně skutkového předpokladu aktualizuj autoritativní plán s důkazem.

Dodrž aktuální `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a `CONTRIBUTING.md`. Verification je standard pro kontakty/SQL/veřejné kontrakty/migrace, low-risk pro izolovaný úklid skriptů. pnpm 11.24.0; FVM a nejvýše jeden Flutter task, testy `--concurrency=1`.

Výsledek: jedna současná sada měřicích scénářů, jeden vlastník kontaktového lifecycle v dialogu i detailu, setup fonty odvozené z existujícího katalogu bez obří Dart kopie a pouze canonical serving notifikací. Zachovej durable intent/recovery, e-mailové send guardy, SQL oprávnění, frozen views a read/seen historii. Archivní vstupy a SQL font projekci ponech tam, kde jejich konkrétní konzument dál existuje; nemaž je pro kosmetické snížení LOC.

Nezaváděj obecný framework, druhý transport, implicitní fallback, paralelní business implementaci, alias pro odstraněnou interní cestu ani placeholder. Přesuň callers a smaž nahrazené implementace v jedné koherentní vlně. Moderní výběr objednávek dnes používá i starý notifikační selektor; shared DTO, batch helper a inherited baseline nejsou mrtvé. Po migraci zkontroluj i canonical manifests, assembler prerequisites, grants, schema a test registrace, ne pouze importy.

Vlny 1-3 dokonči nezávisle na notifikační compatibility gate. Staré veřejné RPC nesmíš přestat podporovat jen na základě zdroje mainu nebo nulového krátkodobého trafficu. Vyžádej si dostupné důkazy podporovaných klientů a skutečného nasazení podle plánu; pokud nejsou dostupné, zaznamenej přesné chybějící důkazy a dokonči ostatní lokální práci. Nevlož blokovanou contraction do automaticky aplikovaného publikovaného řetězce a netvrď úplné dokončení cutoveru.

Spusť cílené kontroly a před source publication affected canonical CI mirror lanes. Neopakuj passing checks bez změny pokrytého kódu. Nezahajuj nezadaný nezávislý audit ani subagenty; případný browser nebo pozdější deployment deleguj podle platných osobních pravidel.

Bez samostatného zadání neprováděj commit/push, produkční migraci/deploy, změnu minimální podporované verze klientů, tenant propagation ani další přepis Git historie. Na konci ulož stručný execution result: netto runtime redukce zvlášť od generated/evidence, sjednocení vlastníci, odstraněné vstupy, výsledky kontrol a přesný zbývající compatibility/provozní krok.
