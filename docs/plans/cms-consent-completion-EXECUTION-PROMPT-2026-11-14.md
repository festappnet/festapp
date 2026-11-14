# Implementace dokončení CMS přenosu souhlasu

Pracujte v repozitáři `/Users/miakh/source/festapp` podle aktuálních AGENTS.md,
CLAUDE.md a `docs/architecture/ai_context.md`. Kvůli migraci, oprávněním a
veřejnému kontraktu použijte verification: standard.

Přečtěte celý autoritativní plán:

`docs/plans/cms-consent-completion-plan-2026-11-14.md`

Výsledek: pořadatel konfiguruje a potvrzuje přenos pro svůj web ve Festappu.
WordPress/Joomla pouze přijmou jednotný export. Nesmí zůstat ruční ID/revize v
CMS, paralelní provider konfigurátory ani plošné přepisování cizích odkazů.
Starý export po změně či vypnutí nesmí obnovit grant; nestačí jen správně
vygenerovat nový JSON. Zachovejte současný checkout a lokální lištu.

Postupujte po vlnách plánu: kanonický SQL vlastník a forward migrace, runtime
binding a revokace, Festapp UI, zjednodušení CMS, skutečně zapojené testy,
kontrakce a finální readiness. Nepřepisujte historické migrace. Nevytvářejte
nový veřejný endpoint podle původního #858 ani druhý consent engine.

#856 a #857 použijte jako zdroj kódu. Review integrační větev
`review/cms-consent-20261114` je pouze lokální důkaz staré varianty; nezačínejte
z ní bez porovnání s aktuálním main. Zachovejte cizí rozpracované změny a podle
potřeby vytvořte vlastní worktree. Neobnovujte již odstraněné konfigurátory
pomocí compatibility fallbacků. Při změně faktů aktualizujte samotný plán.

Cílenými SQL, runtime, widget a skutečnými CMS/backend testy prokažte i neplatné
stavy, odvolání a absenci starých cest. Fixture test nepovažujte za úplný E2E.
Respektujte jeden Flutter proces a `--concurrency=1`; browser práci provádí
izolovaný muted Terra agent podle osobních pravidel.

Tento prompt sám neautorizuje commit, push, změny GitHub issue/PR, merge,
produkční migraci, tenant deploy ani publikaci CMS balíčků. Tyto kroky proveďte
jen v rozsahu samostatné instrukce pro implementaci/publikaci; nevyžadujte znovu
souhlas, který již konkrétní implementační session výslovně poskytla.

Na konci doložte změněné vlastníky/kontrakty, odstraněné cesty, přesné testy a
jejich výsledek, stav zdrojového sloučení a odděleně neprovedené provozní kroky.
