# Implementace: konkrétní product type na vstupence

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md a `docs/architecture/ai_context.md`, potom celý autoritativní plán:

`docs/plans/ticket-product-type-cutover-plan-2026-10-13.md`

Implementuj jeho vlny s `verification: standard`. Výsledkem je editor s přidáním konkrétního `productTypeId`, upravitelným popiskem a skutečným non-hidden příkladem; shodný výběr podle ID v canvas/preview/download/email PDF; bezpečná jednorázová migrace večeře a doloženého odvozu; atomické přemapování při kopii akce. Produktový tisk nesmí určovat skupinu podle `product_types.type`. Globální zrušení tohoto sloupce pro spot/form doménu není součástí zadání.

Zachovej cizí necommitované změny. Aktuální checkout není main a má rozsáhlý dirty stav; vyber bezpečný pracovní základ bez resetu či přepsání cizí práce. Nehádej produkční tenant, organization ID ani konkrétní product type ID. Produkční canonical tenant festapptickets / organization 3 byl read-only ověřen; přečti evidence vedle plánu. Prázdná aktivace development checkoutu nepřebíjí ověřený produkční profil.

Navazuj na doloženou produkční inventuru a UI revizi. Callers existujícího editoru používají occasion context, takže nepřidávej spekulativní per-form runtime protokol. Konkrétní typ vyber podle jeho použití ve formuláři; další nepoužívané katalogové typy nevyžadují ruční mapování. Uzavřené formuláře a hidden pole s historickými produkty jsou relevantní. Nepoužívané tiskové pole odstraň se zachováním zbývající flow geometrie; nepoužívaný odvoz nemigruj. Produkce nemá víceznačný food případ ani taxi tiskový binding. Production apply vyžaduje fresh hashes a schválený rozsah sdílených konzumentů; dalších 11 organizací má legacy ticket konfigurace.

Dokončení vyžaduje schema 3, render data/flow/warnings po element ID, contextual SQL reference validation, katalog skutečných příkladů, preservation hidden historical products, conflict/replay/sync semantics, přemapování kopie akce a celý removal ledger. Nepřidávej runtime legacy fallback, druhý renderer, dual write, selector podle title ani persistent business trigger. Aplikované migrace nepřepisuj. Jednorázový převod smí číst staré type hodnoty, cílový runtime nesmí.

Pokud nový důkaz vyvrátí fakt v plánu, uprav autoritativní plán i dotčenou vlnu před pokračováním. Spusť předepsané cílené kontroly a rehearsal; nespouštěj nezávislý review ani subagenty bez explicitního zadání.

Tento prompt po zadání implementace autorizuje lokální kód, SQL soubory, testy a migrační nástroje. Produkční migraci, deployment, commit, push a rozšíření rollout scope proveď pouze při samostatném výslovném oprávnění. Při handoffu uveď hotový kontrakt, migrované callers, odstraněné legacy cesty, výsledky ověření a přesné neprovedené provozní kroky.

Dodrž UI kontrakt a část Efektivní implementace v plánu: existující panels, explicitní picker confirm/cancel, bezpečné umístění pole, grouped label undo, konkrétní názvy/warnings a dynamické previewData místo statických resources.scenarios. Setup wizard používá source-preview a nesmí nabízet cizí produkty blank draftu; nevytvářej dočasná type ID ani publisher. Jeden normalizovaný katalog snapshot, lokální projekce příkladů, nulové implicitní resolve/PDF requests při editaci a jeden krátký headless browser smoke. Vlny jsou jeden koherentní implementační celek, nikoli mezireleasy.
