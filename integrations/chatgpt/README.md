# Private ChatGPT connection

This is private connection configuration for the approved regional target, not a
public submission package. Do not connect until the regional cutover is verified.
The currently deployed old address is `https://mcp.festapp.net/mcp`.
Import `mcp.json` through the account's supported private configuration surface.
For a provided-client form, use client `festapp-chatgpt`, token auth `none`,
resource `https://mcp.vstupenky.online/mcp`, and both explicit scopes:
`festapp:ticket-layouts:read festapp:orders:read`. Verify the exact callback in
ChatGPT against the protected issuer registration; the prepared callback is
`https://chatgpt.com/connector_platform_oauth_redirect`.

The issuer's protected client entry must have
`"allowedScopes": ["festapp:ticket-layouts:read", "festapp:orders:read"]`.
This ceiling is enforced independently of this file. Existing native clients
can retain their policy; every new external registration needs an explicit ceiling.
An endpoint-only connection requesting just the base scope is valid but cannot
read sales or orders. Do not enable dynamic registration or copy tokens.

Complete the normal first-party login, select individual occasions, and consent
to reads. Check all six expected tools and follow the
[pilot acceptance record](../../docs/operations/chatgpt-mcp-pilot-2026-10-26.md).
Missing account configuration support is an external blocker, not permission to
widen registration. Public plugin manifests/assets follow actual acceptance.

[Official configuration contract](https://developers.openai.com/plugins/build/plugins)
and [tool authentication](https://developers.openai.com/plugins/build/auth),
checked 2026-10-27. Account-specific import/installation remains to be verified.

Rollback must retain this client's ceiling. Use a compatible previous image or
disable/revoke the pilot client before restoring an older config. Never drop the
ceiling to make an old image start with wider grants.

## Platform and regional identity

The intended presentation has two independent connections: **FestUp Tickets**
for the global platform and **vstupenky.online** for the regional portal. They can
share this MCP implementation and endpoint. Use separate registered OAuth clients,
exact callbacks, explicit scope ceilings and consent; do not infer their backend
or privileges from the display name. This pilot retains `festapp-chatgpt` for the
regional connection. No global client is registered or enabled by this change.

Merge `regional-portal.json` into the protected regional issuer configuration.
Consent then explains in the user's language that vstupenky.online runs on FestUp
and that this connection applies to that portal. A global deployment omits
`regionalPortal`; global users see no regional explanation. Presentation never
selects a backend or grants access. A future shared issuer serving both products
must bind this presentation and tenant policy to the registered client, rather
than use the regional deployment's default for both.

Regional app name: `vstupenky.online`. Regional description: “vstupenky.online běží
na společné platformě FestUp. Toto připojení platí pro vstupenky.online.”
The regional name is explicit for user recognition and later directory search.
The private name alone does not prove public search indexing.

Separate public listings remain a wave-5 review decision. The official
[guidelines](https://developers.openai.com/plugins/plugin-guidelines) require
clear, accurate branding and prohibit misleading/copycat/spam listings; they do
not explicitly establish whether these two branded products may publish two
listings with one backend. [Submission limits](https://developers.openai.com/plugins/deploy/submission-errors)
currently cap the display name at 30 characters. Do not claim two listings are
approved or invent a duplicate endpoint to evade review. No public package,
submission or global tenant selector is included here.
