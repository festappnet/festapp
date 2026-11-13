# Realizace společného API Festapp a MCP

Pracujte v `/Users/miakh/source/festapp`. Přečtěte AGENTS.md, CLAUDE.md,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/festapp-unified-api-plan-2026-11-13.md`

Cíl: obecné HTTP API nad stejným `Operations` a doménovými vlastníky jako MCP.
Má dva veřejné vstupy, Festapp / Festapp Tickets a vstupenky.online, proxyované
do jedné kanonické služby. Regionální fasáda má pevný ověřený profil a vlastní
audience; nevytvářejte kopii API implementace, redirect ani supertoken proxy.
API je další adaptér ve stávajícím kanonickém MCP runtime. Nepřidávejte
samostatný API Node proces/kontejner, docs server, Redis nebo další auth store.
Make je běžný klient tohoto API; zvláštní `/make/v1` se po prokázaném přechodu
konzumentů odstraní. Neimplementujte druhý business dispatch, authorization
engine, receipt store ani privilegovaný API klíč. MCP nemusí volat API po HTTP.

Použijte verification: standard. Postupujte po vlnách plánu, zachovejte cizí
rozpracované změny a nejprve porovnejte aktuální main i souběžný globální MCP
binding. Pokud kód vyvrátí předpoklad plánu, aktualizujte plán s konkrétním
důkazem a přizpůsobte dotčenou vlnu. Neměňte potichu výsledek a nezavádějte
neplánované kompatibilní aliasy. Dočasný starý Make adaptér smí existovat jen
s evidovaným vlastníkem, koncem a plánem přechodu podle vlny 4.

Začněte vlnami 0 a 0I: resource/issuer/profile binding, explicitní OAuth
client/proof profily, bezpečnost DPoP bez bearer downgrade a důvěryhodný
ingress. API resources oddělte od MCP i od sebe; původní Make granty se na
nové API nepřenášejí. Make potřebuje nové připojení s regionální API audience
u kanonického authorization serveru. OAuth 2.1 a Idempotency-Key jsou v datu
plánu stále drafty; používejte doložené RFC a protokolové verze, bez tvrzení
neověřené FAPI compliance. HTTP chyby mají RFC 9457, interní/MCP protokol
zůstává vlastním adaptérem stejného operation výsledku.

Dokončení vyžaduje generovaný verzovaný API kontrakt, společný hosted runner,
čtení i připravené zápisy se zachovaným scope/preview/retry/recovery, autorizované
artefakty, Make generovaný z veřejného kontraktu a uzavřený deletion ledger.
Povinné jsou raw OpenAPI a úplná automaticky generovaná statická reference
pro oba vstupy, nikoli jen seznam rout. Použijte runtime schémata, build-time
lint/generování, validované příklady, obousměrnou route/operation parity,
směrový breaking-change check a stejný release manifest pro API i docs.
Návaznost na Mendelio Voice a konkrétní owning soubory jsou v autoritativním
plánu. Dokumentace nesmí potřebovat běžící generátor nebo backendový login.
Připnuté dokumentační nástroje patří do build/dev dependencies.
Zahrňte token rotation/reuse/race, kapacitu auth store, key rotation a obnovu
starší zálohy bez oživení revokovaných přístupů. Rozlišujte revokaci nových
požadavků od již přijatého SQL commitu; neobcházejte bezpečné dohledání
nejistého výsledku novým UUID. Porovnejte paměť a MCP latenci baseline a
kandidáta ve stejném workloadu podle rozpočtu plánu; stávající compose limity
384 MiB/0,5 CPU a Node heap 192 MiB nezvyšujte jako vedlejší efekt API.
Zachovejte summary profil Make, clientId,
callback a scope ceiling, ale proveďte požadovaný reconsent nové audience/issueru.
Neoznačujte
blokovanou operaci nebo neprovedenou produkční migraci za dokončenou.

Service identities mají výslovně oddělenou navazující vlnu S. Navrhněte je
podle plánu, ale neaktivujte `client_credentials` bez schváleného canonical
principal/SQL ADR a odpovídající implementace. Samotný provider flag nesmí
vydávat strojové identity vydávané za běžného člověka nebo service_role.

Proveďte přiměřené cílené Node/DB kontroly a povinné canonical CI lanes před
publikací zdroje. Nespouštějte nezávislý agentní audit bez zadání. Tento prompt
sám neautorizuje commit/push, produkční migrace/deploy ani publikaci konektoru;
platí případné výslovné další zadání uživatele. Při handoffu stručně uveďte
výsledek, ověření, odstraněné cesty a přesné neprovedené provozní kroky.
