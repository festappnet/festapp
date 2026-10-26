import { executeConfirmedOrder } from "./confirmedReplacement.ts";
import type { Gateway, RpcClient } from "./fakturoidPreparation.ts";
export async function executeConfirmedFormOrder(args: {
  administrativeOrder: {
    occasionId: number;
    organizationId: number;
    unitId?: number | null;
    formId: number;
    actorId: string;
    input: Record<string, unknown>;
    confirmationHash: string;
  };
  commandId: string;
  client: RpcClient;
  serviceClient: RpcClient;
  gateway: Gateway;
}): Promise<Record<string, unknown>> {
  const a = args.administrativeOrder;
  if (
    !a || !Number.isSafeInteger(a.occasionId) || a.occasionId <= 0 ||
    !Number.isSafeInteger(a.organizationId) || a.organizationId <= 0 ||
    !Number.isSafeInteger(a.formId) || a.formId <= 0 ||
    typeof a.actorId !== "string" || typeof a.confirmationHash !== "string" ||
    !/^[0-9a-f]{64}$/.test(a.confirmationHash) || !a.input ||
    typeof a.input !== "object" || Array.isArray(a.input)
  ) {
    return { code: 400, errorCode: "INVALID_CONFIRMED_FORM_ORDER" };
  }
  return executeConfirmedOrder({
    ...args,
    editor: false,
    replacement: false,
    rpcName: "create_admin_form_order",
    parameters: {
      p_occasion: a.occasionId,
      p_organization: a.organizationId,
      p_unit: a.unitId ?? null,
      p_form: a.formId,
      p_input: a.input,
      p_confirmation_hash: a.confirmationHash,
      p_expected_actor: a.actorId,
      p_command_id: args.commandId,
      p_client_id: args.commandId,
    },
  });
}
