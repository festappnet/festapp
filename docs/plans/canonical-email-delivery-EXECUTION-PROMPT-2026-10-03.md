# Implementace jednotné e-mailové fronty Festapp

Implementuj lokálně celé řešení v repozitáři `/Users/miakh/source/festapp`. Přečti celé autoritativní zadání:

`docs/plans/canonical-email-delivery-plan-2026-10-03.md`

Dodrž AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md; verification: standard. Zachovej cizí dirty změny. Sdílený kód implementuj z aktuálního main bez resetování pracovního stromu. Nevytvářej subagenty bez explicitního požadavku.

Výsledek: jedna trvalá fronta všech e-mailů, jeden izolovaný AWS SES API gateway, post-commit wake bez minutového čekání objednávky, bezpečné retry/unknown stavy, provider feedback a tenantově zabezpečený reporting doručení/bounce/complaint/open/click. Vzor Mendelio je v `/Users/miakh/source/roman_seznamka`; použij konkrétní zdroje uvedené v plánu, nekopíruj jeho produkční klíče, identity, limity příloh nebo schématové konvence.

Architektura musí zůstat jednoduchá a provozně úsporná. Dodrž sekci „Architektonická efektivita“: využij existující PostgreSQL/pg_net, šablony, PDF/QR a deployment. Jeden SQL vlastník stavu, jeden dispatcher, jeden gateway, jeden feedback adaptér. Žádný nový obecný workflow framework, Redis, další odchozí broker ani fronta pro každou organizaci. Retry, limiter a audit mají vždy jednu implementaci. Atomicky související DB kroky sluč, data tabulky načítej hromadně, přílohy připravuj jednou pro snapshot a wake slučuj. Přidávej pouze komponenty potřebné pro konkrétní kontrakt; odstraň nahrazené cesty. Efektivita nesmí oslabit oprávnění, transakčnost nebo ochranu proti duplicitám.

Uprav také závěrečnou hlášku objednávky ve webu i Flutteru: odstranit příslib „do minuty“, při queued „právě odesíláme“, po accepted „odeslali jsme“. Dodrž sekci o bezpečném čtení stavu, překladech, placených/bezplatných variantách a neblokuj vykreslení úspěchu/QR čekáním na SES. Ověř i odebrání platby, verze připomínek, souběh ručního a automatického sendu, neměnný snapshot příloh a obnovu SNS feedbacku.

Přímo v seznamu objednávek implementuj kompaktní sloupec E-mail: ikona se stavem, tooltip při hover/fokusu a vysvětlení při klepnutí s odkazem na historii. Dodrž pravidla souhrnu více zpráv, aby úspěšná pozdější zpráva neschovala nedoručené vstupenky. Data načítej hromadně s orders bundle, nikoli po jednom requestu na řádek. Zahrň mobilní, klávesnicové a tenantové testy popsané ve vlně 6.

Povinné je kapacitní řízení: jediný společný limit pro všechny organizace, akce, projekty a instance Festapp podle skutečné AWS account/region kvóty, s 20% rychlostní rezervou, denním budgetem a omezenou paralelní přípravou/send. Žádný samostatný limit na organizaci a žádná pevně zakódovaná hodnota 10/s nebo 14/s; autoritou je konfigurace AWS účtu. Přetížení odloží zprávu v téže durable frontě bez ztráty a bez spotřebování retry pokusů. Při sdílení SES s Mendelio ověř přidělený account rozpočet. Uživatel výslovně zakázal kapacitní/zátěžové testování včetně syntetické stub dávky: tyto testy neprováděj, kvótu nezjišťuj pokusným odesíláním. Čtení AWS kvóty a kontrola společné odesílací hranice nejsou zátěžový test.

Postupuj po vlnách. Zahrň order/payment/ticket implicitní frontu, všechny přímé account sendery a GoTrue. Zachovej Fakturoid gate, doménové post-actions a stávající veřejné mobilní kontrakty pomocí tenkých adaptérů ke stejné frontě. Nezaměňuj accepted za delivered a při nejasném SES výsledku automaticky neopakuj send. Nezaveď persistentní aplikační trigger, dual-write, SMTP fallback ani další frontu odesílání.

Při neplatném předpokladu aktualizuj autoritativní plán s konkrétním důkazem. Dokonči autorizovanou lokální implementaci, migrace v repozitáři, konfiguraci a cílené SQL/Deno/JS/Flutter kontroly bez kapacitních testů. Nezastavuj u nového návrhu nebo samotného happy-path sendu. Dokončení vyžaduje i realizaci mazacího seznamu, migration rehearsal a doložený runtime stav nebo přesný seznam neprovedených provozních kroků. Dokončení lokální implementace neoznačuj za dokončený produkční cutover.

Tento prompt sám neautorizuje produkční migrace/deploy, změny AWS/DNS, skutečné e-maily, commit ani push. Tyto kroky proveď jen při samostatné autorizaci. V handoffu stručně uveď kanonický kontrakt, převedené cesty, odstraněné artefakty, ověření a zbývající kroky.
