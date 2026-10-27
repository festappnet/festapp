# Festapp Tickets and vstupenky.online: identity and endpoint decision

Checked 2026-10-27. This investigation informs the current read-only pilot;
it does not authorize DNS changes, another production client, public submission,
or publication. The live pilot still uses `https://mcp.festapp.net/mcp`. The user approved the
regional target `https://mcp.vstupenky.online/mcp` for implementation **before further ChatGPT setup and pilot acceptance**; authoritative plan wave 2b owns the cutover.

## Product presentation

The intended presentation is two identifiable connections: `Festapp Tickets` for
the global product, and `vstupenky.online` for the regional product. A user searching
for the regional brand should recognize that exact name. Do not claim that a
private connection has directory search placement or that description keywords
are guaranteed to be indexed.

Regional consent explains: “Toto připojení platí pro vstupenky.online, který běží
na společné platformě Festapp.” The deployment's optional `regionalPortal` settings
supply the labels. Global deployments omit these settings. If one issuer later
serves both products, bind presentation and tenant policy to its registered clients
before sharing that deployment; never show a regional deployment default to a
global client. Labels do not select data or authorize operations.

Share the maintained MCP/OAuth implementation and SQL owners. Separate public
products need independent package identities, exact client registrations, tenant
bindings, demo accounts and review evidence; they do not need copied business
logic. The present change registers neither a global client nor another tenant.

## What official rules establish

| Question | Evidence and practical conclusion |
| --- | --- |
| Can one publisher publish two connectors? | The [remote MCP review requirements](https://developers.openai.com/plugins/deploy/app-review) expressly allow an organization to publish multiple unique MCP plugins. This rules out a blanket one-plugin-per-publisher restriction. It does not automatically approve these two products. |
| Can they be identical clones under different names? | The [plugin guidelines](https://developers.openai.com/plugins/plugin-guidelines) require a clear purpose and accurate branding and reject misleading, copycat or spam experiences. Two authentic regional/global products are more defensible than two indistinguishable listings created for search coverage. This is an inference, not preapproval. |
| Must every product have separate source code or database hardware? | The fetched rules impose no such requirement. They assess the submitted endpoint, useful behavior, identity, permissions and review cases. Shared implementation is an architectural choice; absence of a ban is not a guarantee of listing approval. |
| Can two integrations share a verification path? | The [submission guide](https://developers.openai.com/plugins/deploy/submission#domain-verification-details) explicitly addresses another plugin using the same challenge URL. Preserve its token and use an eligible parent origin or a different hostname; contact support when neither works. It does not promise that any two listings sharing an endpoint will be accepted. |
| What names are available? | The [submission validation reference](https://developers.openai.com/plugins/deploy/submission-errors) currently limits public display names to 30 characters. Both individual brand names fit. A long combined name would not be a sound universal naming strategy. |
| Does a regional URL guarantee approval? | No. It improves brand/domain alignment and avoids a verification-token collision, but the product still needs normal review. Documentation does not establish whether these particular two branded listings are sufficiently distinct. |

No public rule found expressly prohibits these two brands from sharing the same
internal backend. No fetched rule conclusively approves two integrations at an
identical URL, either. Definitive advance confirmation would require OpenAI
support or actual review. No support message or submission was sent.

## Approved URL decision and migration boundary

| Use | Address | State |
| --- | --- | --- |
| Current private pilot | `https://mcp.festapp.net/mcp` | Active historical target; no further ChatGPT setup/acceptance here. Replace through the approved cutover first. |
| Proposed regional public connection | `https://mcp.vstupenky.online/mcp` | Accepted by the user on 2026-10-27; not yet provisioned, registered or published. Separates MCP routing from the main site's application shell. |
| Alternative regional route | `https://vstupenky.online/mcp` | Technically possible with deliberate proxy, discovery and OAuth routing. Sharing the app's root well-known paths needs extra care. |
| Global public connection | Stable endpoint under the verified Festapp global domain | Domain choice remains outstanding; do not invent ownership or register a speculative hostname. |

A public name, public MCP resource URL, OAuth issuer and actual backend are
separate concepts. An OAuth issuer may be on a different origin from the MCP
resource, subject to correct discovery and exact validation; see the
[authentication contract](https://developers.openai.com/plugins/build/auth).

The existing Festapp implementation intentionally derives its resource from the
issuer and checks an exact Host. A DNS alias or unreviewed forwarding header will
not establish another supported resource. For either proposed regional address:

1. Verify ownership, route collision/hosting behavior, TLS and the final public
   resource URL before provisioning.
2. Explicitly choose resource and issuer URLs. Update trusted proxy/Host checks,
   protected-resource metadata and issuer discovery as one bounded change.
3. Retain the existing authorization owner and static registration policy. Bind
   each public product to its registered client, scope ceiling and tenant.
4. Recheck exact callbacks, resource/audience, consent continuation and session
   bindings. An issuer/resource change may require fresh consent; do not translate
   old tokens into a new audience or expose credentials in the proxy.
5. Keep current keys/state and scope ceilings protected. Test refresh, revocation,
   both protocol eras and wrong-resource denial before switching the private
   connection. Do not treat a 301/302 redirect as an OAuth migration.
6. Verify domain challenges without replacing an existing plugin's token, then
   repeat the real ChatGPT acceptance on the final endpoint before public review.

Moving the implementation, machine or upstream API **behind an unchanged public
MCP URL** is different from changing the published MCP URL. Preserve the published
contract and security bindings when moving infrastructure.

## Published URL changes: documentation conflict

The [detailed review page](https://developers.openai.com/plugins/deploy/app-review#other-changes)
says an origin change (scheme, hostname or port) requires a new plugin and full
review/publication; it describes path-only changes as a new version of the same
plugin. The [current general submission guide](https://developers.openai.com/plugins/deploy/submission#update-your-published-plugin)
says the update flow does not support changing an existing MCP URL and directs
such changes to support. These are not identical instructions.

Use the conservative common conclusion: choose final public addresses before
submission, keep them stable, and do not promise a self-service URL replacement.
Treat an origin change as a new-plugin migration unless OpenAI support explicitly
provides a supported migration for that integration. Confirm even a path-only
change against the actual portal/support because of the documented discrepancy.
Infrastructure can move behind those stable addresses without renaming products.
