import { renderDraftPreview } from "./content.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};
type ReadContext = (
  authorization: string,
  params: Record<string, unknown>,
) => Promise<{ data: any; error: { code?: string } | null }>;

export function previewHandler(readContext: ReadContext) {
  return async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers });
    if (req.method !== "POST") {
      return new Response(null, { status: 405, headers });
    }
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return Response.json({ error: "unauthorized" }, { status: 401, headers });
    }
    try {
      const input = await req.json();
      if (
        !input || typeof input !== "object" || Array.isArray(input) ||
        typeof input.draftId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          input.draftId,
        ) ||
        !Number.isSafeInteger(input.revision) || input.revision < 1 ||
        Object.keys(input).some((key) => !["draftId", "revision"].includes(key))
      ) {
        return Response.json({ error: "invalid_preview_request" }, {
          status: 400,
          headers,
        });
      }
      const { data, error } = await readContext(authorization, {
        p_id: input.draftId,
        p_expected_revision: input.revision,
      });
      if (error) {
        const status = error.code === "40001"
          ? 409
          : error.code === "42501"
          ? 403
          : error.code === "22023"
          ? 400
          : 503;
        return Response.json({
          error: status === 409
            ? "draft_revision_conflict"
            : "preview_unavailable",
        }, { status, headers });
      }
      return Response.json(await renderDraftPreview(data), { headers });
    } catch (error) {
      const status = error instanceof SyntaxError ? 400 : 503;
      return Response.json({ error: "preview_unavailable" }, {
        status,
        headers,
      });
    }
  };
}
