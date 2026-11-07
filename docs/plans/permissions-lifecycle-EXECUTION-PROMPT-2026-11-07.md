# Realizace: účinná práva pořadatele, akce a MCP

Pracujte ve Festapp podle AGENTS.md, CLAUDE.md a ai_context.md,
verification: standard. Autoritativní návrh je:

`docs/plans/permissions-lifecycle-plan-2026-11-07.md`

Přečtěte ho celý. Cílem je živé jednotné dědění odpovídajících unit rolí
vedle explicitních occasion grants, bez přetrvávajících kopií při enrolmentu.
Stejná SQL autorita musí řídit doménové příkazy, replay, RLS, capabilities
a MCP; MCP scopes/souhlas přístup pouze dále omezují.

Začněte reprodukcí `automation/authorization/probe-membership-lifecycle.mjs`
na vlastní markerované lokální DB a cílovými regresními testy. Postupujte
vlnami plánu. Připravené změny obnovy kontextu a bezpečných MCP messages
nejsou dokončený permission cutover; nezaměňujte je za něj.

Nevytvářejte další role engine, string permission dispatcher, permission
preflight RPC ani kopírovací trigger. Dodržte mapování rolí a samostatná bank,
tenant-admin a demo pravidla. Nehádejte příčinu denialu z textu SQL chyby.
Při rozporu s aktuálním kódem aktualizujte plán doloženou skutečností.

Z historického booleanu nelze spolehlivě poznat kopii a explicitní grant.
Nesmíte je plošně odstranit ani jim vymyslet původ. Splňte migrační bránu
plánu a vykazujte nerozlišené záznamy až do jejich skutečného vypořádání.

Produkční migraci, změnu konkrétních grants a deployment proveďte pouze
v konkrétně autorizovaném scope a po repository review/release gates.
Neobcházejte ochranu main. Neprovádějte další nezávislý agent audit bez
výslovného požadavku. Handoff musí rozlišit lokální implementaci,
vypořádaná data, odstraněné staré cesty a skutečný stav produkce.
