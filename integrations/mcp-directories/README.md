# Festapp MCP directory identities

Publisher: Festapp. Source: https://github.com/festappnet/festapp. Support: info@festapp.net.

Both production endpoints passed live verification. Official MCP Registry
version 0.1.2 records include the canonical titles, websites and pinned logos:
[Festapp](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Ffestapp/versions/0.1.2)
and [vstupenky.online](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Fvstupenky-online/versions/0.1.2).
Both canonical Glama records are public, ownership-verified, branded and searchable:
[Festapp](https://glama.ai/mcp/connectors/net.festapp/festapp) and
[vstupenky.online](https://glama.ai/mcp/connectors/net.festapp/vstupenky-online).
Both show **Healthy** and **Works in Glama**. Actual OAuth and refresh after
access-token expiry passed with dedicated, narrowly scoped health grants.
The earlier manual Glama copies
are deprecated with these canonical replacements and excluded from search.
There are two active identities; Festapp Tickets is included in Festapp.
See the [production verification evidence](../../docs/operations/releases/global-mcp-20261113/live-verification.md).

The [full supported catalog](https://vstupenky.online/napoveda/mcp-podporovane-operace/)
documents 196 operations. Discovery depends on current rights, consent, client
profile and application variant. The 83 functional permissions are delegation
ceilings over the application's canonical authorization, not new account roles.

## Additional directory distribution

| Directory | Verified state on 2026-11-13 |
| --- | --- |
| [MCPfinder](https://mcpfinder.dev/) | Both canonical identities were verified at 0.1.1 in the 06:54 UTC snapshot, imported from Official Registry; upstream is now 0.1.2. |
| [MCPservers.org](https://mcpservers.org/submit) | Both Free submissions accepted into review; not yet published. The form estimates review within two weeks. |
| MCP.so | No-charge manual review requested in [Festapp #7255](https://github.com/chatmcp/mcpso/issues/7255) and [vstupenky.online #7256](https://github.com/chatmcp/mcpso/issues/7256). Acceptance and free review remain unconfirmed. |
| Awesome Remote MCP Servers | [PR #4589](https://github.com/punkpeye/awesome-remote-mcp-servers/pull/4589) adds both endpoints; endpoint/OAuth/badge validation passed. Maintainer review is pending. |
| [PulseMCP](https://www.pulsemcp.com/submit) | Submissions paused; automatic Official Registry ingestion awaits resumption. |
| [MCP.directory](https://mcp.directory/submit) | Advertises automatic import; our entries are not verified there. Its repo-only form was not used to create an ambiguous monorepo listing. |
| [Smithery](https://www.smithery.ai/future) | Public curated directory remains after the October 31 shutdown of its proxy/accounts/API/CLI. No current new-submission route found. |
| [LobeHub](https://market.lobehub.com/s/publish-mcp) | Not submitted. Its publisher guide requires human CLI login and GitHub ownership connection and explicitly says not to automate these steps. Remote cloudEndpoint metadata is supported; LobeHub-client OAuth compatibility is unverified. |

See [additional-directory evidence](../../docs/operations/releases/global-mcp-20261113/additional-directories-20261113.json).
No paid placement, support email, new service, or separate ChatGPT publication
was used. Existing production endpoints and retained health grants were preserved.

## What you can do

### Festapp

Turn an event idea into a working plan with your AI assistant. Create the event, build its program, lay out tables and seats, and set up ticket types and prices with Festapp and Festapp Tickets. Manage reservations and orders, see how sales are doing and handle guest check-in.

Try: "Prepare a ball for 180 guests, with tables of six and two ticket categories." Or: "Show ticket sales and the seats still available for this event."

Available actions depend on the selected Festapp environment, your account permissions and the access you approve for the connection.

### vstupenky.online

Get your ball, concert or festival ready for ticket sales with your AI assistant. Create the event, lay out its tables and seats, and set ticket categories, prices and capacity on vstupenky.online. Work with reservations and orders, track sales and payments, and manage guest check-in.

Try: "Prepare a seating plan with 20 tables of six and a VIP section." Or: "Show orders awaiting payment and how many tickets have been sold."

Your existing vstupenky.online permissions and the access you approve for the connection determine which actions are available.

The practical English copy is live in Official Registry 0.1.2 and Glama, and
updated in the MCP.so review requests and remote-catalogue PR. The already
submitted MCPservers.org forms have no supported pending-edit route and retain
their original text while awaiting review.

The canonical short/long English and Czech copy and its operation references
are in [catalogue-copy.json](catalogue-copy.json). Venue copy describes event
hall/seating plans; it does not advertise a venue-booking marketplace.

## Co s připojením zvládnete

### Festapp

Proměňte nápad v připravenou akci se svým AI asistentem. Založte událost, sestavte program, rozvrhněte stoly a sedadla a nastavte kategorie vstupenek i ceny ve Festapp a Festapp Tickets. Pracujte s rezervacemi a objednávkami, sledujte prodej a odbavujte hosty.

Zkuste třeba: „Připrav ples pro 180 hostů, stoly po šesti a dvě cenové kategorie vstupenek.“ Nebo: „Ukaž prodej vstupenek a zbývající místa na této akci.“

Dostupné funkce se řídí vybraným prostředím Festapp, Vašimi právy a přístupem, který připojení povolíte.

### vstupenky.online

Připravte ples, koncert nebo festival k prodeji vstupenek se svým AI asistentem. Založte akci, navrhněte rozmístění stolů a sedadel a nastavte kategorie, ceny i kapacity vstupenek na vstupenky.online. Pracujte s rezervacemi a objednávkami, sledujte prodej i platby a spravujte odbavení hostů.

Zkuste třeba: „Připrav plán sálu s dvaceti stoly po šesti místech a VIP sektorem.“ Nebo: „Ukaž objednávky čekající na platbu a počet prodaných vstupenek.“

Dostupné funkce se řídí Vašimi právy ve vstupenky.online a přístupem, který připojení povolíte.

## English connection details

Festapp is an authenticated event-management connection including Festapp Tickets. A connection selects one configured, verified tenant environment, then explicitly selects organizers/events and functions. SQL checks current account rights on each operation. A URL shared by tenants does not grant access to other tenants. Additional environments require separate connections. Supported capabilities come from the granted tool catalog; read and write capabilities also depend on each OAuth client's scope ceiling and data profile. Membership, bank and payment restrictions remain those of the application. No payments are performed by connecting an account.

Use Streamable HTTP at `https://mcp.festapp.net/mcp`. The regional connection remains `https://mcp.vstupenky.online/mcp`. Both require a Festapp account with access to the selected environment and resources. Availability depends on the service's explicit tenant registry. Account pricing and organizer service terms remain those agreed for the selected tenant; this listing does not offer a new paid subscription. MFA issuance is currently unsupported and fails closed. Native clients and web clients require exact registered callbacks or an explicitly permitted client metadata document; unrestricted dynamic registration is disabled. Compatibility must be demonstrated with the client and profile being advertised.

Examples after consent: list accessible events; inspect the ticket layout of a selected event; read sales/order reports when granted; create a hidden event under a selected organizer when explicitly granted. Writes reuse application command IDs and receipts; retry an uncertain result with the same command and payload. Individual client profiles may be read-only. The existing public ChatGPT order-summary profile does not authorize arbitrary clients or write capabilities. No ChatGPT approval badge is claimed.

Revoke access in the selected environment's Settings > Connections. `https://mcp.festapp.net/connections` lists trusted management destinations. Disconnecting MCP revokes that delegation and its independent backend session, without signing out the ordinary application. Never put access tokens or customer data into a support request.

Regional support and legal pages: https://vstupenky.online/support/, https://vstupenky.online/privacy/, https://vstupenky.online/terms/. The global MCP service serves its dedicated privacy, connection terms and support at /privacy, /terms and /support on the issuer; live availability must pass the release probes before publication. Code is MIT under the repository `LICENCE`, retaining its historical copyright; hosted service terms are separate. Runtime distribution notices are generated from the frozen production graph, with embedded native-library notices retained separately.

## Česky

Festapp zpřístupňuje podporované funkce aplikace včetně Festapp Tickets podle aktuálních práv a výslovného souhlasu. Jedno připojení patří jednomu ověřenému prostředí. Vyberte pořadatele či akce a požadované funkce. Pro další prostředí vytvořte nové připojení. Regionální vstupenky.online zůstává samostatným připojením pod stejným vydavatelem.

Příklady: „Zobrazte moje dostupné akce“, „Ukažte podklad vstupenek této akce“, „Zjistěte stav objednávky podle symbolu“ nebo po výslovném povolení „Založte skrytou akci u tohoto pořadatele“. Nabídka závisí na schválených oprávněních konkrétního klienta. Připojení není veřejným vyhledávačem akcí ani nákupem vstupenek.

Potřebujete účet s oprávněním ve vybraném prostředí. Ceny a podmínky účtu se řídí zvolenou službou. Přístup můžete odebrat v Nastavení > Připojení. Vícefaktorové účty zatím tato hranice vydávání oddělených sessions nepodporuje a odmítne je. Podpora: info@festapp.net. Do požadavků podpory neposílejte tokeny ani údaje zákazníků.
