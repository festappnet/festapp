import type { FakturoidConfig } from "../send-ticket-order/fakturoid.ts";

type RpcClient = {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<{
    data: any;
    error: unknown;
  }>;
};

/** User RPCs own authorization. The privileged client reads credentials only. */
export async function deleteOrderWithInvoice(
  orderId: number,
  commandId: string,
  user: RpcClient,
  admin: RpcClient,
  deleteInvoice: (request: {
    config: FakturoidConfig;
    commandId?: string | null;
    variableSymbol: string | number;
  }) => Promise<void>,
) {
  const context = await user.rpc("get_order_deletion_context_v1", {
    p_order: orderId,
    p_command_id: commandId,
  });
  if (context.error || !context.data) throw new Error("ORDER_DELETE_FORBIDDEN");
  if (context.data.response) return context.data.response;
  if (!context.data.hasFakturoid) throw new Error("FAKTUROID_NOT_CONFIGURED");
  const services = await admin.rpc("get_external_services", {
    p_order_id: orderId,
  });
  if (services.error) throw new Error("FAKTUROID_CONFIG_UNAVAILABLE");
  const matches = services.data?.filter((service: any) =>
    service.type === "FAKTUROID"
  );
  if (matches?.length !== 1) throw new Error("FAKTUROID_CONFIG_AMBIGUOUS");
  await deleteInvoice({
    config: matches[0].data,
    commandId: context.data.commandId,
    variableSymbol: context.data.variableSymbol,
  });
  // Rechecks permissions and deletion constraints, and publishes normal sync effects.
  const result = await user.rpc("delete_order_client_sync_v1", {
    p_order: orderId,
    p_command_id: commandId,
  });
  if (result.error || result.data?.code !== 200) {
    throw new Error("ORDER_DELETE_INCOMPLETE");
  }
  return result.data;
}
