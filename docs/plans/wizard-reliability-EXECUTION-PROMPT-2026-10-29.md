# Realizace oprav průvodce po UI QA

Repozitář: `/Users/miakh/source/festapp`.

Autoritativní plán je [wizard-reliability-plan-2026-10-29.md](wizard-reliability-plan-2026-10-29.md). Přečtěte jej celý spolu s AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Výchozí důkazy jsou v docs/operations/wizard-ui-qa-2026-10-29.md.

Cíl: zastavit amplifikaci konfliktů náhledů e-mailu, umožnit dokončení všech nabízených vzhledů a odstranit ruční strategii VS z běžného wizardu a ponechat přidělování stávajícímu kanonickému backendu. Zachovat koncepty, vlastní šablony, kopírované zdroje, oprávnění a transakční receipty.

Postupujte W0-W4. W0 musí rozlišit počet frontendových invokací, HTTP požadavků a DB chyb; jejich počty nezaměňovat. Vytvořte bounded reproduktor a teprve podle něj dokončete návrh konkrétní concurrency/retry opravy. Proveďte účelný architektonický refaktor podle pojmenovaných hranic plánu: jeden preview modul, jedna projekce plateb a jedna fontová nabídka. Nevymýšlejte globální retry framework ani druhého vlastníka ukládání. Fontové mapování musí vycházet z jednoho výběrového manifestu odkazujícího do stávajícího immutable katalogu; neaktualizujte fontové bajty. Wizard nesmí nově vyžadovat počáteční číslo ani generovat vlastní VS. Nový formulář používá současný automatický default, kopie zachová explicitní platnou policy a pokročilý editor dál umí ruční volbu s řádnou validací. Přidělení, registry a watermarky zůstávají u existujícího SQL ownera.

Verification: standard a konkrétní brány plánu. Jeden Flutter task na celém stroji, testy --concurrency=1, pnpm 11.24.0. Použijte čistý worktree z aktuálního main; původní checkout obsahuje cizí rozpracované změny. Zastaralý lokální main není autoritativní základ. Pokud evidence změní předpoklad plánu, aktualizujte jeho autoritativní sekci a související wave, nikoli tichý fallback.

Nedělejte nezávislý review/subagent audit bez výslovného požadavku. Nenechávejte placeholdery, V2 endpointy, paralelní business pravidla, neomezené retry ani dočasné logy. Přechod chybového kódu má přesně popsanou kompatibilitu a musí být otestovaný proti starším callerům.

Tento prompt sám neautorizuje implementaci, commit/push, produkční migraci, Edge reload, rozesílání ani nasazení. Proveďte pouze rozsah povolený aktuálním pokynem uživatele. Po případné autorizaci vydání platí pouze prod/festapptickets; lokální build a automation/deploy_direct.sh, kanonický backend workflow a delegace rutinního deploye podle AGENTS.md. Nepoužívat GitHub Deploy dispatch ani ostatní tenanty.

Při předání stručně uveďte skutečně opravené chování, testy a zbývající neprovedené provozní kroky. Netvrďte nasazení jen podle commitu nebo push.
