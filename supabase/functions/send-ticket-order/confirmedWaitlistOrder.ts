import { executeConfirmedOrder } from "./confirmedReplacement.ts";
import type { Gateway, RpcClient } from "./fakturoidPreparation.ts";
export async function executeConfirmedWaitlistOrder(
  args: {
    administration: Record<string, unknown>;
    payload: Record<string, unknown>;
    actor: string;
    commandId: string;
    serviceClient: RpcClient;
    gateway: Gateway;
  },
) {
  return executeConfirmedOrder({
    ...args,
    client: args.serviceClient,
    editor: false,
    replacement: false,
    rpcName: "execute_admin_waitlist_command_client_sync_v1",
    parameters: {
      p_administration: args.administration,
      p_operation: "accept",
      p_payload: args.payload,
      p_command_id: args.commandId,
      p_client_id: args.commandId,
      p_actor: args.actor,
      p_deliveries: [],
    },
  });
}
