import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { fakturoidGateway } from "../send-ticket-order/fakturoid.ts";
import { deleteOrderWithInvoice } from "./delete.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
Deno.serve(async (request) => {
  const reply = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers });
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") {
    return reply(405, { error: "METHOD_NOT_ALLOWED" });
  }
  const authorization = request.headers.get("authorization");
  if (!authorization) return reply(401, { error: "UNAUTHORIZED" });
  let body;
  try {
    body = await request.json();
  } catch {
    return reply(400, { error: "INVALID_REQUEST" });
  }
  if (
    !Number.isSafeInteger(body?.orderId) || body.orderId <= 0 ||
    body.deleteFakturoidInvoice !== true ||
    typeof body.commandId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(body.commandId)
  ) {
    return reply(400, { error: "INVALID_REQUEST" });
  }
  const scope=body.delegatedScope;
  if(scope!==undefined&&(!scope||typeof scope!=='object'||Array.isArray(scope)
    ||Object.keys(scope).some(k=>!['occasionId','organizationId','unitId','expectedRevision'].includes(k))
    ||!Number.isSafeInteger(scope.occasionId)||scope.occasionId<=0
    ||!Number.isSafeInteger(scope.organizationId)||scope.organizationId<=0
    ||!(scope.unitId===null||(Number.isSafeInteger(scope.unitId)&&scope.unitId>0))
    ||typeof scope.expectedRevision!=='string'||!/^[a-f0-9]{64}$/.test(scope.expectedRevision)))return reply(400,{error:'INVALID_REQUEST'});
  try {
    const result = await deleteOrderWithInvoice(
      body.orderId,
      body.commandId,
      createUserClient(authorization),
      supabaseAdmin,
      fakturoidGateway.deleteInvoice,
      scope,
    );
    return reply(200, result);
  } catch (error) {
    // Never return credentials, provider response bodies or customer data.
    const code = error instanceof Error ? error.message : "";
    return reply(code === "ORDER_DELETE_FORBIDDEN" ? 403 : 409, {
      error: code === "ORDER_DELETE_FORBIDDEN"
        ? code
        : "ORDER_INVOICE_DELETE_FAILED",
    });
  }
});
