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


The protected registration explicitly uses `dataProfile: order-summary`. It
returns order IDs/symbols, states, counts and amounts, withholding buyer names,
contacts, notes and registration fields. IDs/symbols are pseudonymous, not
anonymous. Organizer-authored event labels and template configuration must not
contain children’s data or government identifiers. This connector targets
organizers, not children.

For a trusted private model or native tool, register a separate client with
`dataProfile: operator`. Full data remains available subject to its own scope
ceiling, user consent and current backend permissions. No global MCP restriction
was added. See [per-client architecture](../../tools/festapp/README.md#per-client-data-profiles).

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
[Hosted public SDK evidence](review/hosted-public-demo-evidence.json) uses the
dedicated reviewer identity, ordinary password sign-in, PKCE, real Edge broker
and hosted public ChatGPT registration. All 13 checks passed on the deployed
`order-summary` profile. [Current ChatGPT evidence](review/chatgpt-public-reviewer-evidence.json)
and its [sanitized transcript](review/chatgpt-public-reviewer-transcript.txt)
cover the five positive and three negative scenarios in four real conversation
turns under the dedicated reviewer account. Related requests were grouped;
this was not eight independent fresh chats. The ambiguity check was a fresh
chat before any event selection.

[Earlier native SDK evidence](review/hosted-demo-evidence.json) and
[earlier operator ChatGPT evidence](review/chatgpt-demo-evidence.json) remain
historical evidence of the full operator profile, including hostile-note
retrieval. The current public profile withholds that note instead.

## Build the public draft ZIP

Run `python3 integrations/chatgpt/build-package.py /tmp/vstupenky-online-1.0.1.zip`
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
portal import and six-tool scan succeeded on 2026-10-27; the final public-profile refresh is recorded in the readiness record. Never strip OAuth
settings merely to satisfy the generic schema.

Sources checked 2026-10-27:
[package/auth configuration](https://developers.openai.com/plugins/build/plugins#configure-mcp-authentication),
[submission manifest](https://developers.openai.com/plugins/deploy/submission),
[remote MCP review](https://developers.openai.com/plugins/deploy/app-review).

## Reviewer walkthrough

[Current 50-second walkthrough](review/walkthrough-public-e6fd4177e317.mp4)
shows actual dedicated-reviewer ChatGPT screenshots: ambiguity, canonical sales
summary, order detail with private fields withheld, and scope/write denials.
It is a screenshot-based walkthrough, not a continuous recording or proof of
every individual call. Only cropped synthetic demo content is included.
[Current chapter metadata](review/walkthrough-public.json) records timings and
hash. The earlier operator walkthrough is retained as historical evidence.
