# Festapp MCP directory identities

Publisher: Festapp. Source: https://github.com/festappnet/festapp. Support: info@festapp.net.

Both production endpoints passed live verification. Official MCP Registry
version 0.1.1 records include the canonical titles, websites and pinned logos:
[Festapp](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Ffestapp/versions/0.1.1)
and [vstupenky.online](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Fvstupenky-online/versions/0.1.1).
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

[PulseMCP submissions](https://www.pulsemcp.com/submit) are paused; automatic
Official Registry ingestion awaits resumption. MCP.so's remote form is paid;
no paid submission was made and a current supported free route was not established.
No support email or separate ChatGPT publication was sent.

## English

Festapp is an authenticated event-management connection including Festapp Tickets. A connection selects one configured, verified tenant environment, then explicitly selects organizers/events and functions. SQL checks current account rights on each operation. A URL shared by tenants does not grant access to other tenants. Additional environments require separate connections. Supported capabilities come from the granted tool catalog; read and write capabilities also depend on each OAuth client's scope ceiling and data profile. Membership, bank and payment restrictions remain those of the application. No payments are performed by connecting an account.

Use Streamable HTTP at `https://mcp.festapp.net/mcp`. The regional connection remains `https://mcp.vstupenky.online/mcp`. Both require a Festapp account with access to the selected environment and resources. Availability depends on the service's explicit tenant registry. Account pricing and organizer service terms remain those agreed for the selected tenant; this listing does not offer a new paid subscription. MFA issuance is currently unsupported and fails closed. Native clients and web clients require exact registered callbacks or an explicitly permitted client metadata document; unrestricted dynamic registration is disabled. Compatibility must be demonstrated with the client and profile being advertised.

Examples after consent: list accessible events; inspect the ticket layout of a selected event; read sales/order reports when granted; create a hidden event under a selected organizer when explicitly granted. Writes reuse application command IDs and receipts; retry an uncertain result with the same command and payload. Individual client profiles may be read-only. The existing public ChatGPT order-summary profile does not authorize arbitrary clients or write capabilities. No ChatGPT approval badge is claimed.

Revoke access in the selected environment's Settings > Connections. `https://mcp.festapp.net/connections` lists trusted management destinations. Disconnecting MCP revokes that delegation and its independent backend session, without signing out the ordinary application. Never put access tokens or customer data into a support request.

Regional support and legal pages: https://vstupenky.online/support/, https://vstupenky.online/privacy/, https://vstupenky.online/terms/. The global MCP service serves its dedicated privacy, connection terms and support at /privacy, /terms and /support on the issuer; live availability must pass the release probes before publication. Code is MIT under the repository `LICENCE`, retaining its historical copyright; hosted service terms are separate. Runtime distribution notices are generated from the frozen production graph, with embedded native-library notices retained separately.

## Česky

Festapp zpřístupňuje podporované funkce aplikace včetně Festapp Tickets podle aktuálních práv a výslovného souhlasu. Jedno připojení patří jednomu ověřenému prostředí. Vyberte pořadatele či akce a požadované funkce. Pro další prostředí vytvořte nové připojení. Regionální vstupenky.online zůstává samostatným připojením pod stejným vydavatelem.

Příklady: „Zobrazte moje dostupné akce“, „Ukažte podklad vstupenek této akce“, „Zjistěte stav objednávky podle symbolu“ nebo po výslovném povolení „Založte skrytou akci u tohoto pořadatele“. Nabídka závisí na schválených oprávněních konkrétního klienta. Připojení není veřejným vyhledávačem akcí ani nákupem vstupenek.

Potřebujete účet s oprávněním ve vybraném prostředí. Ceny a podmínky účtu se řídí zvolenou službou. Přístup můžete odebrat v Nastavení > Připojení. Vícefaktorové účty zatím tato hranice vydávání oddělených sessions nepodporuje a odmítne je. Podpora: info@festapp.net. Do požadavků podpory neposílejte tokeny ani údaje zákazníků.
