import { PaymentError, type PaymentMethodBinding, type PaymentOperationResult, record } from "../contracts.ts";

export type PaymentOperationRpc = (name: string, args: Record<string, unknown>, authorization: string) => Promise<unknown>;

/** Builtins execute the same authorized SQL command. A bank instruction never
 * claims to transfer money; only a later authenticated bank event settles it. */
export function builtinPaymentBinding(
  id: "cash" | "bank",
  rpc: PaymentOperationRpc,
): PaymentMethodBinding {
  return {
    connector: {id, displayName: id === "cash" ? "Cash" : "Bank transfer"},
    operation: {
      confirmation: id === "cash" ? "local_commit" : "bank_event",
      async execute(input, commandId, authorization): Promise<PaymentOperationResult> {
        if (input.method !== id) throw new PaymentError("payment_connector_identity_mismatch");
        const data = record(await rpc("command_payment_operation", {input_data: input, p_command_id: commandId}, authorization));
        return {kind: input.operation === "prepare_refund" && id === "bank"
          ? "show_bank_instructions" : "recorded", data};
      },
    },
  };
}
