# MCP directory research - 2026-11-13

Research only; no submissions made. Recheck search results and live endpoints immediately before publication.

## Official MCP Registry

- The [publisher quickstart](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/quickstart.mdx) uses schema `https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json`. Remote-only servers use `name`, `title`, `description`, `version`, and `remotes` with `type: streamable-http` and a publicly accessible `url`; `packages` and package ownership markers are unnecessary. Install `mcp-publisher`, authenticate, then publish the `server.json`.
- The [remote guide](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/remote-servers.mdx) says namespace ownership is verified, but control of the remote URL is not. GitHub auth controls `io.github.<account>/...`; DNS or HTTP auth controls the corresponding reversed-domain namespace, e.g. `online.vstupenky/...`, subject to actual domain proof. Multiple names may reference one endpoint. Confirm exact namespace and authentication setup using the [authentication guide](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/authentication.mdx).
- Registry search for [festapp](https://registry.modelcontextprotocol.io/v0.1/servers?search=festapp) and [vstupenky](https://registry.modelcontextprotocol.io/v0.1/servers?search=vstupenky) returned zero entries. This is a name search, not proof that no differently named listing exists. Registry is in preview.

## PulseMCP

[Submission page](https://www.pulsemcp.com/submit) says new submissions and listing changes are temporarily paused (notice dated 2026-09-03). Publish to official registry first; Pulse says it will ingest automatically once its pipeline resumes. No date promised. Search for existing listings was not verified.

## MCP.so

[Remote submission form](https://mcp.so/submit?type=remote-server) requests a hosted endpoint URL and project name. The current anonymous UI only shows a $39 paid submission button; no free option was visible. Do not pay. A free path, existing listings and any authenticated-only options remain unverified.

## Glama

The [Festapp server search](https://glama.ai/mcp/servers?query=festapp) displayed an empty result list; [vstupenky search](https://glama.ai/mcp/servers?query=vstupenky) showed a retry-search error, so absence is not established. Server search does not establish connector absence. Add Server opened a sign-up dialog with CAPTCHA; no account action was taken. Hosted OAuth connector claim/index criteria, exact callback URI, OAuth client registration requirements, and connector duplicate checks remain unverified. Do not assume a callback or OAuth compatibility without primary-source confirmation or an authorized authenticated inspection.
