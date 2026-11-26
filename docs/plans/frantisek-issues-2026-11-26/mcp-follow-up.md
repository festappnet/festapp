# Navazující ověření uzavřených #958 a #959

## #958 Připojení a očekávání oprávnění

Loopback je vyřešený. `client-policy.mjs` podporuje přesně `localhost`
pouze u registrovaných veřejných nativních klientů, s odpovídající cestou.
README má samostatný postup pro Claude Code a základní read-only příkaz
pro Codex. `src/mcp/protocol.mjs` používá u počátečního 401
`READ_SCOPE` a `remote/delegation.mjs` získává rozsah konkrétní chybějící
operace. Souhlas může přidělit pouze požadované a autorizované rozsahy.
`McpConnectionPage` už má kontextovou nápovědu `individualOnlyHint`,
`organizerReadHint` a `organizerCreateHint` s vazbou na přístupný ovládací prvek.

Doplň do postupu Codexu a Claude Code praktickou větu o read-only startu,
výslovném požadavku na scope a rozdílu mezi celým pořadatelem a akcí.
Příklad rozšířeného přístupu odvoď z `packages/festapp_contracts/mcp-permissions.mjs`
a z povolené registrace příslušného klienta. Pokud klient neumožňuje scope
nastavit, popiš dostupný bezpečný postup a neuváděj neověřený příkaz.
Ověř fixture pro base-only, schválené požadavky na čtení/zápis a výběr
vhodného pořadatele. Detaily připojení vycházejí ze stávajících rolí a
požadovaných rozsahů. Neměň scope ceiling, 401 challenge ani RBAC na
základě samotného komentáře. Jestli fixture prokáže chybějící schopnost
nebo zavádějící stav v UI, zdokumentuj konkrétní podmínku a případnou
změnu autorizační politiky řeš samostatně.

Ověř dokumentaci s `pnpm --dir tools/festapp run docs:check` a související
regresní testy `client-policy.test.mjs`, `remote.test.mjs` a
`mcp_connection_page.test.js`. Při doplnění nápovědy zachovej jazyk stránek.

## #959 Potvrzení výsledku zápisu a verze runtime

Při auditu veřejný [health endpoint](https://mcp.vstupenky.online/healthz)
vrátil `ok:true` a sourceCommit
`0e19d23ff81f5d702e98119e5a847819955e7c3f`. Lokální
`git merge-base --is-ancestor 537fb08b23365d804fcd02cefd601dc7ba3b3023 0e19d23ff81f5d702e98119e5a847819955e7c3f`
potvrdil přítomnost #984. Tato kontrola nedokládá, že každý živý
`forms.inspect` úspěšně přečte konkrétní formulář.

Pro finální ověření spusť kontrakty `tools/festapp/test/forms.test.mjs`
pro inspekci, neznámá pole snapshotu a replay stejného `commandId` po
zapsaném příkazu a selhaném readbacku. Pokud je po ruce autorizovaná
read-only relace a vhodný schválený testovací formulář, ověř přes hosted MCP
jeden skutečný `forms.inspect` a zaznamenej build. Při chybě zaznamenej
operation/correlation ID bez údajů formuláře a přiřaď nové konkrétní
zjištění. Pro ověření nikdy nevytvářej živý formulář. Reprodukce chování
zápisu a replay patří do jednorázové DB. Samotná veřejná health odpověď
není spouštěčem opětovného nasazení.
