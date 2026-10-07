Implementuj v /Users/miakh/source/festapp celý autoritativní plán:

`docs/plans/occasion-report-plan-2026-10-03.md`

Před editací ho přečti celý, spolu s AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Verification: standard, protože měníme finanční report, oprávnění a veřejný kontrakt.

Výsledek: ReportTab jako přehledná grafická obrazovka s vysvětlivkami, sekundárním textem a TXT exportem. Jediná stávající get_report_ws(occasion_link text) vrací původní data string a nový report objekt ze společného výpočtu. Žádné další RPC pro grafy/text/export, žádné opakované načítání při rebuild, žádné násobení plateb při joinu položek. Dodrž přesné definice metrik, bezpečnost a lifecycle načítání v plánu.

Mobilní použitelnost je explicitní podmínka dokončení: ověř šířky 360/390, text 200 %, žádný horizontální overflow, dotykové vysvětlivky a ovládací cíle alespoň 48 x 48. Produkty na telefonu zobraz jako seznam. Mobilní web a nativní export ověř odděleně, nedostupné prostředí přiznej.

Postupuj ve třech vlnách plánu: kontrakt a agregace, klient, odstranění starých výpočtů a ověření. Před SQL změnou dolož granularitu payment_info, jednotku produktů a chování vratek. Zachovej kompatibilní textové pole pro staré klienty. Odstraň původní výpočty a prověř historické čtecí aliasy podle ledgeru; bez DROP CASCADE a bez spekulativních adapterů.

Pokud fakta v repozitáři odporují plánu, aktualizuj plán s důkazem a přizpůsob příslušnou vlnu. Nenechávej placeholdery, druhou obchodní implementaci nebo tiché fallbacky. Respektuj nesouvisející rozpracované změny v pracovním stromu. Nespouštěj subagenty ani nezávislý audit bez zadání.

Proveď cílené SQL/model/widget kontroly, výkonový EXPLAIN na syntetických lokálních datech a povinné repository gates uvedené v plánu. Produkci nepoužívej pro testy. Bez samostatného zadání neprováděj produkční migraci, deployment, commit, push ani rollout tenantů.

Na závěr stručně uveď implementovaný kontrakt, odstraněné staré cesty, výsledky ověření a případný přesný blokátor nebo dosud neprovedený provozní krok.
