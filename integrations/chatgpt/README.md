# vstupenky.online for ChatGPT

The regional MCP endpoint is **https://mcp.vstupenky.online/mcp**. The old
mcp.festapp.net host is retired with HTTP 410. The regional portal runs on
Festapp; the future global Festapp Tickets connection is a separate product.

This directory contains the public **draft package**, private-connection setup
and review evidence. A working private connection or ZIP is not directory
approval. See [submission readiness](review/readiness.md) for actual gates.

## Connect privately

Use the account's Add custom MCP form, name `vstupenky.online`, and the regional
endpoint above. Select the provided public client `festapp-chatgpt`, no client
secret (`tokenEndpointAuthMethod: none`), PKCE S256, and exactly these read scopes:

- `festapp:ticket-layouts:read`
- `festapp:orders:read`

Deselect other automatically discovered domain scopes. The verified callback is
`https://chatgpt.com/connector_platform_oauth_redirect`. Dynamic registration
is disabled. Select individual events on the first-party consent page; a whole
organizer grant also includes future events. No API keys or refresh tokens are
copied into ChatGPT. Access can be revoked at
https://vstupenky.online/settings/connections.

## Dedicated reviewer demo

The confirmed demo account has only order-reader memberships on two hidden,
closed synthetic events: January `1072614` and February `1072615`. Eight
synthetic orders cover ordered, paid, cancelled and waiting states. Event
`1072616` is inaccessible. There are no real buyer details or bank/Stripe links;
canonical suppression blocks delivery to every synthetic recipient.

Passwords are stored only in the operator's protected private directory and
must be supplied through the portal's secure review-credentials field, never
in this package or repository. [Demo data](review/demo-data.json) includes only
synthetic identifiers, symbols and canonical expected reports.

The imported synthetic paid state deliberately produces the canonical
`payment_total_without_ledger` warning. Current order value includes the
cancelled order. Neither is a verified bank transaction.

## Review cases and evidence

`plugin.json` contains exactly five positive and three negative review prompts.
[Hosted SDK evidence](review/hosted-demo-evidence.json) uses the dedicated
reviewer identity, normal password authentication, native OAuth PKCE, the real
Edge broker and hosted MCP. [ChatGPT evidence](review/chatgpt-demo-evidence.json)
uses the operator identity with consent limited to the same two synthetic events.
These are different actors and clients; do not describe them as all having run
in ChatGPT under the demo account. The readiness record preserves failed cases
and subsequent retests rather than replacing failures with fixture success.

## Build the public draft ZIP

Run `python3 integrations/chatgpt/build-package.py /tmp/vstupenky-online-1.0.0.zip`
from the repository root. The deterministic archive contains only:

- `plugin.json`
- `mcp.json`
- `assets/logo.png` (the owned regional ticket icon from the WordPress catalogue)

It excludes this README, provisioning code, private policy files, credentials,
SQL, SDK runner and evidence. No hooks, app references or speculative skills are
bundled. Publication is initially scoped to Czechia.

The root plugin manifest was checked against the published Agent Plugins schema.
The generic MCP schema currently rejects the per-server `extensions` object that
OpenAI explicitly requires for provided-client OAuth. We validate the generic
MCP base projection and the documented OpenAI OAuth extension separately; the
portal's import/scan remains an independent pending check. Never strip OAuth
settings merely to satisfy the generic schema.

Sources checked 2026-10-27:
[package/auth configuration](https://developers.openai.com/plugins/build/plugins#configure-mcp-authentication),
[submission manifest](https://developers.openai.com/plugins/deploy/submission),
[remote MCP review](https://developers.openai.com/plugins/deploy/app-review).

## Reviewer walkthrough

[50-second walkthrough](review/walkthrough-0a5d035015e9.mp4) shows reviewed
screenshots from actual ChatGPT event selection, the canonical sales report,
symbol search/detail and ignored hostile note. It is a screenshot-based
walkthrough, not a continuous recording. Only cropped synthetic demo content is
included. [Chapter metadata](review/walkthrough.json) records timings and hash.
