/** Read-only authoring metadata. No rendering, customer lookup or queue access. */
export interface AuthoringContextDependencies {
  senderAddress: string;
  catalog: (
    authorization: string,
    entityType: "occasion" | "unit",
    entityId: number,
  ) => Promise<any | null>;
  resolve: (code: string, context: Record<string, number>) => Promise<any>;
}

export async function authoringContextResponse(
  input: any,
  authorization: string,
  dependencies: AuthoringContextDependencies,
  headers: Record<string, string> = {},
): Promise<Response> {
  const reply = (body: unknown, status = 200) =>
    Response.json(body, {
      status,
      headers: { ...headers, "Cache-Control": "no-store" },
    });
  if (!authorization.startsWith("Bearer ") || authorization.length <= 7) {
    return reply({ error: "Authentication required" }, 401);
  }
  const { entityType, entityId, templateCode } = input;
  if (
    !["occasion", "unit"].includes(entityType) ||
    !Number.isSafeInteger(entityId) || entityId <= 0 ||
    typeof templateCode !== "string" ||
    !/^[A-Za-z_][A-Za-z0-9_]{0,127}$/.test(templateCode)
  ) return reply({ error: "Invalid authoring context" }, 400);
  try {
    // This existing RPC validates the requested hierarchy and reader permission
    // under the caller's JWT. Service-role resolution only follows that gate.
    const catalog = await dependencies.catalog(
      authorization,
      entityType,
      entityId,
    );
    if (!catalog) return reply({ error: "Forbidden" }, 403);
    const entity = entityType === "occasion" ? catalog.occasion : catalog.unit;
    if (
      entity?.id !== entityId ||
      !catalog.templates?.some((template: any) =>
        template.code === templateCode
      )
    ) return reply({ error: "Template unavailable in this scope" }, 404);
    const context: Record<string, number> = {
      organization: catalog.organization.id,
      unit: catalog.unit.id,
      ...(entityType === "occasion" ? { occasion: entityId } : {}),
    };
    if (
      !Object.values(context).every((id) => Number.isSafeInteger(id) && id > 0)
    ) {
      return reply({ error: "Invalid email hierarchy" }, 503);
    }
    const senderAddress = dependencies.senderAddress.trim();
    if (!/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(senderAddress)) {
      return reply({ error: "Sender unavailable" }, 503);
    }
    const resolved = await dependencies.resolve(templateCode, context);
    return reply({
      senderAddress,
      wrapperHtml: typeof resolved?.wrapper?.html === "string"
        ? resolved.wrapper.html
        : null,
    });
  } catch (_) {
    return reply({ error: "Authoring context unavailable" }, 503);
  }
}
