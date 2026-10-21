# Implementuj zrychlení klientských testů podle naměřeného bottlenecku

Pracuj v repozitáři `/Users/miakh/source/festapp`, ale změny prováděj v čistém
odděleném worktree z aktuálního autoritativního `main`. Původní pracovní adresář
má rozsáhlé rozpracované změny; nepřenášej je a nečisti je.

Přečti celé autoritativní zadání:
`docs/archive/plans/client-test-loading-performance-plan-2026-10-21.md`.
Je-li plán jen v původním pracovním adresáři, přenes do nového worktree pouze
nový plán a tento prompt. Přečti také AGENTS.md, CLAUDE.md a ai_context.md.
Implementace používá verification: standard; plánování samo testy nespouštělo.

Cíl: alespoň 15 % nižší medián celého `./automation/test_client.sh` při zachování
všech původních případů, assertions, skipů a právě-jednou registrace. Hlavní práce
je přesun významného balíku kompatibilních kořenů do existujících explicitních
sessions. Shortlist 40 kořenů je v plánu; potvrď prostředí a začni největším
bezpečným balíkem. Nevrať se k izolovanému přesunu dvou drobných sad.

Proveď vlny v pořadí. Reuse registerClientSuites, inventory cases() a existující
benchmark runner. Žádný nový framework, interní reset cache/singletonů,
generování nového baseline manifestu, vypínání guardů nebo snížení pokrytí.
Ověř změněné sessions v normálním i obráceném pořadí až po koherentním balíku.
Proveď novou baseline a finální benchmark, každý warm-up + tři měřené běhy,
s neměnným fingerprintem, jedním Flutter workerem a volným workstation slotem.
Celý passing benchmark už zahrnuje architekturu a inventář, neopakuj je bez důvodu.

Historických 204,85 s není nový referenční medián a 74,292 s loading událostí není
slíbená úspora. Pokud nová evidence zneplatní předpoklad, aktualizuj plán a uprav
postiženou vlnu. Při menší bezpečné úspoře uveď částečný výsledek a nesplněný cíl;
neprohlašuj 15 % bez měření. Nepřidávej placeholdery, aliasové test roots nebo
nesouvisející produkční změny. Neprováděj commit/push/deploy v rámci tohoto zadání.

Při předání stručně uveď: skutečný medián před/po a procento, počet odstraněných
kořenů, zachovaný inventář a skipy, normal/reverse výsledek, peak RSS a odkaz na
receipts. Dokončení zahrnuje odstranění starých kořenů, správné manifesty a PASS
finálního přesně měřeného zdroje. Při dokončení archivuj plán a prompt podle
pravidel repozitáře.
