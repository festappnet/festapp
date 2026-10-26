import { FakturoidInvoiceCreateRejected } from "./fakturoid.ts";
import type { FakturoidConfig, FakturoidOrder } from "./fakturoid.ts";

export type RpcClient = {
  rpc: (
    name: string,
    params: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>;
};
export type Gateway = {
  preparePayment: (
    request: {
      config: FakturoidConfig;
      order: FakturoidOrder;
      commandId: string;
      unitName: string;
      allowCreate?: boolean;
      beforeCreate?: () => Promise<void>;
    },
  ) => Promise<string>;
};
export type FakturoidPreparation = { ok: true } | {
  ok: false;
  retrySameCommand: boolean;
  reason: string;
};

// One fulfillment owner for UI and MCP replacements. A committed replacement
// retains its new seats while invoice preparation is retried under the same UUID.
export async function prepareFakturoidTicketOrder(args: {
  client: RpcClient;
  gateway: Gateway;
  order: FakturoidOrder & { id: number };
  commandId: string;
  unitName: string;
  replacement: boolean;
  durable?: boolean;
}): Promise<FakturoidPreparation> {
  const { client, gateway, order, commandId } = args;
  const fenced = args.replacement === true || args.durable === true;
  const rpc = async (name: string, params: Record<string, unknown>) => {
    const { data, error } = await client.rpc(name, params);
    if (error) throw error;
    return data;
  };
  const services = await rpc("get_external_services", { p_order_id: order.id });
  const service = Array.isArray(services)
    ? services.find((s) => s?.type === "FAKTUROID")
    : null;
  if (!service) return { ok: true };
  const state = await rpc("get_fakturoid_ticket_order_state_v1", {
    p_order_id: order.id,
  });
  if (state === "storno" || state === "waitlisted") {
    return {
      ok: false,
      retrySameCommand: false,
      reason: "ORDER_NO_LONGER_PREPARABLE",
    };
  }
  let token: string | undefined;
  let allowCreate = true;
  if (fenced && state === "preparing_payment") {
    const claim = await rpc("claim_replacement_invoice_preparation", {
      p_order: order.id,
      p_command: commandId,
    }) as { status?: string; token?: string; allowCreate?: boolean };
    if (claim?.status !== "claimed") {
      if (claim?.status === "complete") return { ok: true };
      return {
        ok: false,
        retrySameCommand: claim?.status !== "closed",
        reason: "PAYMENT_PREPARATION_PENDING_RETRY_SAME_COMMAND",
      };
    }
    if (
      typeof claim.token !== "string" || typeof claim.allowCreate !== "boolean"
    ) throw new Error("Invalid invoice preparation claim");
    token = claim.token;
    allowCreate = claim.allowCreate;
  }
  let variableSymbol = String(order.payment_info.variable_symbol);
  if (state === "preparing_payment") {
    try {
      variableSymbol = await gateway.preparePayment({
        config: service.data,
        order,
        commandId,
        unitName: args.unitName,
        allowCreate,
        beforeCreate: token
          ? async () => {
            await rpc("mark_replacement_invoice_dispatch", {
              p_order: order.id,
              p_command: commandId,
              p_token: token,
            });
          }
          : undefined,
      });
    } catch (error) {
      if (fenced) {
        if (token) {
          await rpc("release_replacement_invoice_preparation", {
            p_order: order.id,
            p_command: commandId,
            p_token: token,
            p_not_created: error instanceof FakturoidInvoiceCreateRejected &&
              error.definitelyNotCreated,
          });
        }
        return {
          ok: false,
          retrySameCommand: true,
          reason: "PAYMENT_PREPARATION_PENDING_RETRY_SAME_COMMAND",
        };
      }
      await rpc("abort_fakturoid_ticket_order_v1", {
        p_order_id: order.id,
        p_command_id: commandId,
      });
      return {
        ok: false,
        retrySameCommand: false,
        reason: "PAYMENT_PREPARATION_FAILED",
      };
    }
  }
  const confirmed = token
    ? await rpc("complete_replacement_invoice_preparation", {
      p_order: order.id,
      p_command: commandId,
      p_token: token,
      p_variable_symbol: Number(variableSymbol),
    })
    : await rpc("complete_fakturoid_ticket_order_v1", {
      p_order_id: order.id,
      p_command_id: commandId,
      p_variable_symbol: Number(variableSymbol),
    });
  order.payment_info.variable_symbol = String(confirmed);
  return { ok: true };
}
