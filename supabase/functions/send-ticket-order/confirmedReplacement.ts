import {
  confirmedReplacementParameters,
  projectConfirmedReplacementResponse,
} from "./commandIdentity.ts";
import { prepareFakturoidTicketOrder } from "./fakturoidPreparation.ts";
import type { Gateway, RpcClient } from "./fakturoidPreparation.ts";

// The HTTP binding and the real integration harness call this same coordinator.
// SQL owns the single intent/receipt; this preserves its immutable acknowledgement
// while the existing invoice owner completes a separate external preparation.
export async function executeConfirmedSeatOrder(args: {
  replacement: Parameters<typeof confirmedReplacementParameters>[0];
  commandId: string;
  client: RpcClient;
  serviceClient: RpcClient;
  gateway: Gateway;
}): Promise<Record<string, unknown>> {
  const { replacement, commandId } = args;
  let parameters: Record<string, unknown>;
  try {
    parameters = confirmedReplacementParameters(replacement, commandId);
  } catch {
    return { code: 400, errorCode: "INVALID_CONFIRMED_REPLACEMENT" };
  }
  return executeConfirmedOrder({
    ...args,
    rpcName: "create_blueprint_seat_order",
    parameters,
    editor: replacement.confirmation.editor === true,
    replacement: true,
  });
}

// One coordinator for confirmed seat and form orders. Persistence and invoices
// retain their existing owners; transport recovery never creates a second intent.
export async function executeConfirmedOrder(args: {
  commandId: string;
  client: RpcClient;
  serviceClient: RpcClient;
  gateway: Gateway;
  rpcName:
    | "create_blueprint_seat_order"
    | "create_admin_form_order"
    | "execute_admin_waitlist_command_client_sync_v1";
  parameters: Record<string, unknown>;
  editor: boolean;
  replacement: boolean;
}): Promise<Record<string, unknown>> {
  const { commandId } = args;
  const { data, error } = await args.client.rpc(
    args.rpcName,
    args.parameters,
  );
  if (error) {
    const sqlCode = String((error as { code?: string }).code ?? "");
    const code = sqlCode === "42501"
      ? 403
      : ["22023", "23514", "54000"].includes(sqlCode)
      ? 409
      : 503;
    return {
      code,
      errorCode:
        ["42501", "40001", "40P01", "22023", "23514", "54000"].includes(sqlCode)
          ? sqlCode
          : "UPSTREAM_TEMPORARY_FAILURE",
    };
  }
  if (!data || typeof data !== "object") {
    return { code: 503, errorCode: "UPSTREAM_CONTRACT_FAILURE" };
  }
  const envelope = data as Record<string, unknown>;
  if (
    envelope.code !== 200 ||
    !["applied", "unchanged"].includes(String(envelope.status))
  ) {
    return projectConfirmedReplacementResponse(
      envelope,
      args.editor,
    );
  }
  const committed = envelope.data as {
    order?: Record<string, unknown>;
    quote?: { newOrder?: { state?: string } };
  };
  if (
    !committed?.order || typeof committed.order.id !== "number" ||
    !committed.quote?.newOrder?.state
  ) {
    return { code: 503, errorCode: "UPSTREAM_CONTRACT_FAILURE" };
  }
  // Provider presentation may update its working copy, never the DB receipt.
  type PreparedOrder = Parameters<
    typeof prepareFakturoidTicketOrder
  >[0]["order"];
  const source = structuredClone(committed.order);
  const order: PreparedOrder = {
    id: committed.order.id,
    payment_info: source.payment_info as PreparedOrder["payment_info"],
    data: source.data as PreparedOrder["data"],
  };
  if (committed.quote.newOrder.state === "preparing_payment") {
    let preparation;
    try {
      preparation = await prepareFakturoidTicketOrder({
        client: args.serviceClient,
        gateway: args.gateway,
        order,
        commandId,
        unitName: String((source.occasion as { title?: unknown })?.title ?? ""),
        replacement: args.replacement,
        durable: true,
      });
    } catch {
      preparation = {
        ok: false as const,
        retrySameCommand: true,
        reason: "PAYMENT_PREPARATION_PENDING_RETRY_SAME_COMMAND",
      };
    }
    if (!preparation.ok) {
      if (!preparation.retrySameCommand) {
        return projectConfirmedReplacementResponse(
          envelope,
          args.editor,
          "closed",
        );
      }
      return {
        code: 503,
        errorCode: preparation.reason,
        committed: projectConfirmedReplacementResponse(
          envelope,
          args.editor,
          "pending",
        ),
      };
    }
  }
  return projectConfirmedReplacementResponse(
    envelope,
    args.editor,
    "ready",
  );
}
