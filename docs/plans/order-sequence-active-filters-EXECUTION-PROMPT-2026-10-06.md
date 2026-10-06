# Realizace: pořadí objednávky a nestornované filtry

Pracuj z aktuálního canonical Festapp main v izolovaném checkoutu, zachovej nesouvisející změny. Přečti `CLAUDE.md`, `docs/architecture/ai_context.md`, applicable AGENTS.md a celý autoritativní plán:

`docs/plans/order-sequence-active-filters-plan-2026-10-06.md`

Implementuj vlny A-D, verification **standard**. Výsledek: persisted readonly per-occasion pořadí objednávky v objednávkách, vstupenkách a historii; dva checkboxy nestornovaných s přesným count a bezpečným visible-only výběrem; užší plně čitelný order symbol.

Uživatel výslovně zvolil **MAX existujících + 1, včetně storno**, a **povolil opětovné použití nejvyššího čísla po úplném smazání**. Nezaváděj high-watermark counter. SQL musí zvládnout reálné paralelní transakce/nápor: per-occasion transaction lock před samostatným MAX query, named UNIQUE, stejná creation transakce a idempotentní facade. Číslo přiděl jednou mimo symbol collision retry. Neměň veřejný symbol, ID/FK, bank reference, QR, emaily ani uložené snapshots.

Filtr musí rozlišit partial ticket storno a parent order state, zachovat native filters, drafts a refresh, odstranit newly hidden selection a exportovat stejné rows. Použij existující Trina/controller/command seams; nezaváděj paralelní business logiku, persistentní trigger, klientský MAX, fallback na ID nebo nové lookup RPC. Dokonči ledger dočasného residual helperu.

Reconnaissance omez na rozdíly vůči recorded source revizi a runtime premise potřebné pro aktuální vlnu. Pokud fakt v plánu už neplatí, aktualizuj příslušnou sekci a vlnu. Souhrnnou targeted validaci proveď po coherent změně; povinný full repo gate jednou na final code, ne po každém editování. Pro load/concurrency použij skutečné clients ve vlastním disposable loopback DB, nikdy produkční fixtures. Nevytvářej subagenty bez výslovného požadavku.

Toto zadání po samostatném předání autorizuje implementaci a lokální ověření. Produkční migrace, commit/push/deploy nové změny vyžadují navazující autoritu; předchozí release souhlas se nepřenáší. Main publication musí respektovat PR/review protection. Před případnou publikací fetch/update authoritative target; výchozí tenant scope je pouze `prod/festapptickets`.

Při předání stručně uveď hotové invarianty, výsledky skutečných testů/náporu, zachování dat a přesný stav nasazení. Neprohlašuj skips nebo tolerovaný exit 0 za pass.
