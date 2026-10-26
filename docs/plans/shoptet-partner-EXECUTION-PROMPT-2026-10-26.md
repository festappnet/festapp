# Navázat: Shoptet partnerství a nativní prodej vstupenek

V repozitáři Festapp přečti platné AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Pracuj v čistém izolovaném worktree a používej ověřování standard.

Autoritativní plán je `docs/plans/shoptet-partner-onboarding-2026-10-26.md`; přečti jej celý včetně `docs/plans/shoptet-partner-technical-2026-10-26.md`. Text pro partnerský tým je `docs/plans/shoptet-partner-proposal-2026-10-26.md`.

Nejdřív ověř současné důkazy a otevřené platformní brány. Přeinstalace zachovává obchodní identitu, nikoli staré oprávnění. Bez API po odpojení neslibuj synchronizaci. Finanční zdroj rozšiřuje existující projekci a neobchází ji přes paid_externally.

Cíl: Shoptet vede košík a platbu, Festapp společnou kapacitu, místa, vstupenky a odbavení. Pokračuj kroky v plánu. Nejdřív konkretizuj a projednej návrh; bez přístupů a ověřené rezervace před nákupem nelze přejít k produkčnímu vývoji. Nepřidávej náhradní externí checkout ani druhé objednávky/kapacitu. Změní-li aktuální API podstatný předpoklad, oprav plán a výslovně popiš dopad.

Před jakýmkoli odesláním prověř duplicitu, skutečnou identitu/IČO, cenový model, potřebná oprávnění a pravdivost formulářových potvrzení. Tento plán sám neprovádí odeslání, nepřijímá smlouvu, pevné poplatky, produkční migraci ani nasazení. Pro konkrétní další akci posuď skutečnou autorizaci v navazující session; nevymýšlej opakované souhlasy, pokud už byly uděleny. Žádná hromadná změna ostatních integrací nebo tenantů.

Hotovo rozlišuj na návrh, podání, schválení, otestovaný pilot a veřejné zveřejnění. Uveď skutečné důkazy a přesný zbývající blocker. Nepouštěj testy jen kvůli čtení plánu ani další agentní audit bez požadavku.
