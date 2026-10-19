# Spustit: úplné napojení plánku V2 do Festappu

Implementuj etapu B podle celého autoritativního plánu:

`/Users/miakh/source/festapp/docs/plans/blueprint-v2-integration-plan-2026-10-19.md`

Pracuj s repozitáři `/Users/miakh/source/festapp` a
`/Users/miakh/source/venue_seat_picker`. Nejdřív načti applicable AGENTS.md,
Festapp CLAUDE.md a docs/architecture/ai_context.md, plán a celou 54řádkovou
paritu, na kterou odkazuje. Použij `verification: standard`.

Cíl je skutečný host s úplnými funkcemi V1: produkty/ceny a jejich výjimky,
skupiny/stavy/blokování, objednávka z výběru s konflikty/storny, finančně správné
přesazení/swap, oba zákaznické pickery, atomic units, stání, uložení a setup/copy.
Demo mock ani existence tlačítek nejsou hotové napojení.

Začni vlnou 0, potom plň závislé vlny plánu až do integračního předání. Zachovej
cizí dirty změny a nepřepínej uživatelovy checkouty. Nerozbíjej stávající editor,
neimplementuj druhý finanční/rezervační engine, renderer, font katalog ani
samoúčelné abstrakce. Existující command/receipt/Edge hranice mají zůstat autoritou.

Povinně splň i architektonickou bránu plánu: core/Flutter/JS balíčky zůstávají
samostatné a bez Festapp/Supabase dependency. Ceny, spot bindings, orders, oprávnění
a RPC vlastní host. Znovupoužij obecné presentation/activation/history seams;
neimportuj package `src/`, nekopíruj renderer a nevytvářej framework pluginů.
Čistý Flutter a JS consumer musí fungovat ze skutečných archivů bez Festappu,
sibling checkoutu a backendu. Ověř i oddělené zabalení core a lifecycle pending
výběru při presentation patchi. Lokální dependency override není důkaz distribuce.

Deleguj podle plánu, nejvýše 3 pracovní subagenti současně. **UI i jeho grafickou
kontrolu musí dělat `gpt-6-astra`, `reasoning_effort: medium`, `fork_turns: none`,
s povinným skillem `/Users/miakh/.codex/skills/ui-ux-pro-max/SKILL.md`.** Předej mu
self-contained brief z UI části plánu a schválený kontrakt. Nedostupnost Astra
Medium oznam, nenahrazuj ji potichu. Ostatní vlastníci mají oddělené soubory.

Pracuj efektivně: jednou zmrazit DTO, reuse existujících služeb a UI, testovat u
vlastníka pravidla, nedělat full build po každé editaci ani redundantní audit.
Finální build/testy spouštět až nad zmrazenými zdroji; passing checks neopakovat
bez změny. SQL, souběh a financial authority ověř skutečně, ne mockem. Prohlížeč
pouze izolovaný headless, full-app E2E podle festapp-local-e2e.

Při vyvrácení faktu aktualizuj autoritativní plán s důkazem a pokračuj; nezmenšuj
potichu rozsah, nevymýšlej spekulativní fallbacky. Ke každému řádku parity doplň
důkaz a ponech ho otevřený, pokud nebyl ověřen. Odstraň nahrazené aktivní cesty
podle deletion ledgeru; historická client-sync `_v1` není verze geometrie.

Tento prompt autorizuje implementaci a místní disposable ověření. **Neautorizuje
produkční migrace, převod skutečných dat, nasazení, publikaci, skutečnou komunikaci,
commit ani push.** K nim se nepřibližuj skrytým validačním krokem. Neskonči jen
plánem či stubem; odevzdej ověřenou B a přesný zbývající provozní krok C, nebo
konkrétní doložený blocker. Předání stručně uvede stav 54 požadavků, skutečné testy,
model/skill UI, odstraněné cesty a neprovedené produkční kroky.
