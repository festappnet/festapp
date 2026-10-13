# Implementace kapacity formuláře a náhradníků

Pracuj v `/Users/miakh/source/festapp`. Nejdříve přečti AGENTS.md, CLAUDE.md,
docs/architecture/ai_context.md a celý autoritativní plán:

[form-capacity-waitlist-plan-2026-10-13.md](form-capacity-waitlist-plan-2026-10-13.md)

Implementuj jeho vlny v závislostním pořadí, verification **standard**. Náhradník
je existující typ záznamu eshop.orders v novém stavu, s vlastní evidencí osob a
nabídek. Úplné přijetí zachová ID/symbol/pořadí, částečné vytvoří propojenou běžnou
objednávku a zmenší původní. Nabídka drží jen kapacitu osob; vybrané produkty se
obsadí atomicky teprve potvrzením objednávky, i pokud není zaplacená. Všechny
kapacitní a stavové přechody vlastní SQL, ne klient.

Použij **GPT-6.1-Sol Medium** pro koordinaci/backend a **Astra Medium** pro samotnou
implementaci UI a UX. Zapoj implementační subagenty podle sekce 14 plánu: UI/UX,
e-maily a backendové regresní testy. Nejdříve zafixuj SQL/DTO kontrakty; potom
paralelizuj nezávislé soubory, maximálně čtyři aktivní agenty včetně koordinátora.
Pro model overrides spawnuj s fork_turns="none" a explicitním kontextem. Model
Astra pro UI nenahrazuj bez konzultace. Sekce 13 určuje moduly, algoritmus přijetí
a Fakturoid recovery; tyto části nesmí zůstat na domýšlení workerů.

Zachovej existující UI, oprávnění, platební flow, jedinou e-mailovou frontu a Client
Sync kontrakt. Neimplementuj dříve opuštěný samostatný waitlist root typ, paralelní
finalizaci objednávek, přímé e-maily, business triggery ani rezervaci nevybraných
produktů. Dokončení musí splnit acceptance matrix i deletion ledger plánu.

Pracovní strom je výrazně rozpracovaný. Před editací dotčených souborů zkontroluj
jejich diff, nic cizího nevracej ani nepřepisuj. Pokud aktuální evidence vyvrátí
faktický předpoklad, aktualizuj tento plán a příslušnou vlnu. Produktové změny
konzultuj s uživatelem po jedné otázce s kontextem. Nevytvářej placeholdery,
neplánované fallbacky ani kompatibilní paralelní business implementace.

Testuj cíleně podle plánu a CONTRIBUTING.md v izolované disposable DB; pro skutečné
lokální UI použij repository E2E skill a izolovaný headless browser. Žádné skutečné
e-maily lidem ani produkční testovací data. Implementační subagenti jsou požadovaní;
nepřidávej nad ně nevyžádaný nezávislý obecný audit.
Opakuj passing check pouze při změně pokrytého kódu nebo novém konkrétním riziku.

Tento prompt je zadání pro budoucí implementační relaci, není pokynem k zahájení
implementace během přípravy plánu. Commit, push, produkční migrace, deploy a tenant
rollout vyžadují samostatnou autorizaci. Při předání uveď výsledek, cílené ověření,
přesný zbývající blocker a dosud neaplikované produkční kroky.
