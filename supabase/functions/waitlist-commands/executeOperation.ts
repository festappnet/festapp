import type { WaitlistEmailContext } from "../_shared/waitlistEmail.ts";
type Result = { data: any; error: any };
type Rpc = (name: string, args: Record<string, unknown>) => PromiseLike<Result>;
// Shared UI/MCP transport coordinator. SQL remains the sole scope, mutation,
// receipt and queue owner; delivery preparation seals capabilities in memory.
export async function executeWaitlistOperation(args: {
  operation: string;
  payload: Record<string, unknown>;
  commandId: string;
  clientId: string;
  actor: string | null;
  administration?: Record<string, unknown> | null;
  userRpc: Rpc;
  serviceRpc: Rpc;
  prepareDelivery: (
    context: WaitlistEmailContext,
    code: "waitlist_confirmation" | "waitlist_offer",
  ) => Promise<unknown>;
}): Promise<Result> {
  const { administration: a, operation, payload, commandId, clientId, actor } =
    args;
  if (a != null) {
    if (
      !actor ||
      !["send", "cancel", "withdraw", "decline", "preview_accept"].includes(
        operation,
      ) ||
      typeof a !== "object" || Array.isArray(a) ||
      Object.keys(a).some((k) =>
        !["occasionId", "organizationId", "unitId", "formId"].includes(k)
      )
    ) {
      return { data: null, error: { message: "invalid_administration_scope" } };
    }
    const checked = await args.userRpc("get_form_waitlist_context", {
      p_occasion: a.occasionId,
      p_organization: a.organizationId,
      p_unit: a.unitId,
      p_form: a.formId,
      p_operation: operation === "preview_accept" ? "accept" : operation,
      p_payload: payload,
    });
    if (checked.error) {
      return { data: null, error: { message: "invalid_administration_scope" } };
    }
  }
  if (operation === "preview_accept") {
    return args.serviceRpc("preview_admin_waitlist_acceptance", {
      p_administration: a,
      p_payload: payload,
      p_actor: actor,
    });
  }
  const deliveries = [];
  if (operation === "register" || operation === "send") {
    const context = await args.serviceRpc("get_waitlist_email_context_v1", {
      p_operation: operation,
      p_payload: payload,
      p_actor: actor,
    });
    if (context.error) {
      return {
        data: null,
        error: { message: "waitlist_email_context_invalid" },
      };
    }
    const contexts: WaitlistEmailContext[] = Array.isArray(context.data)
      ? context.data
      : [context.data];
    for (const c of contexts) {
      deliveries.push(
        await args.prepareDelivery(
          c,
          operation === "register" ? "waitlist_confirmation" : "waitlist_offer",
        ),
      );
    }
  }
  return args.serviceRpc(
    a == null
      ? "execute_waitlist_command_client_sync_v1"
      : "execute_admin_waitlist_command_client_sync_v1",
    {
      ...(a == null ? {} : { p_administration: a }),
      p_operation: operation,
      p_payload: payload,
      p_command_id: commandId,
      p_client_id: clientId,
      p_actor: actor,
      p_deliveries: deliveries,
    },
  );
}
