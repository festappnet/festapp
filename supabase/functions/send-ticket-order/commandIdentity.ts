export type TicketOrderCommandIdentity = {
  commandId: string;
  clientId: string;
};

export function resolveTicketOrderCommandIdentity(
  commandId: string | undefined,
  clientId: string | undefined,
  _replacement: unknown,
  _randomUuid: () => string = () => crypto.randomUUID(),
): TicketOrderCommandIdentity | null {
  if (!commandId || !clientId) return null;
  return {
    commandId,
    clientId,
  };
}

// Transport-only mapping. SQL binds the actual organization, units, selections,
// prices and receipt; clients cannot replace those checks with this envelope.
export function confirmedReplacementParameters(replacement: {
  spotIds: number[];
  inputData: Record<string, unknown>;
  confirmation: {
    actorId: string;
    occasionId: number;
    organizationId: number;
    unitId?: number | null;
    blueprintId: number;
    targetSpotIds: number[];
    affectedSpotIds: number[];
    blueprints: Array<{ id: number; revision: number }>;
    confirmationHash: string;
    editor?: boolean;
  };
}, commandId: string): Record<string, unknown> {
  const c = replacement.confirmation;
  if (!c || typeof c !== "object" || typeof c.editor !== "boolean") {
    throw new Error("Invalid confirmed replacement");
  }
  const max = c.editor ? 20000 : 1000;
  const positive = (v: unknown) => Number.isSafeInteger(v) && Number(v) > 0;
  if (
    typeof c.actorId !== "string" ||
    !(/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
      .test(c.actorId) ||
    !positive(c.occasionId) || !positive(c.organizationId) ||
    !positive(c.blueprintId) ||
    (c.unitId != null && !positive(c.unitId)) ||
    typeof c.confirmationHash !== "string" ||
    !(/^[0-9a-f]{64}$/).test(c.confirmationHash) ||
    !replacement.inputData || typeof replacement.inputData !== "object" ||
    Array.isArray(replacement.inputData)
  ) throw new Error("Invalid confirmed replacement");
  for (const ids of [replacement.spotIds, c.targetSpotIds, c.affectedSpotIds]) {
    if (
      !Array.isArray(ids) || !ids.length || ids.length > max ||
      new Set(ids).size !== ids.length || ids.some((id) => !positive(id))
    ) throw new Error("Invalid confirmed replacement selection");
  }
  if (
    !Array.isArray(c.blueprints) || !c.blueprints.length ||
    c.blueprints.length > max ||
    c.blueprints.some((b) =>
      !b || !positive(b.id) || !Number.isSafeInteger(b.revision) ||
      b.revision < 0
    ) ||
    new Set(c.blueprints.map((b) => b.id)).size !== c.blueprints.length
  ) throw new Error("Invalid confirmed replacement revisions");
  return {
    p_occasion: c.occasionId,
    p_organization: c.organizationId,
    p_unit: c.unitId ?? null,
    p_blueprint: c.blueprintId,
    p_spots: replacement.spotIds,
    p_input: replacement.inputData,
    p_target_spots: c.targetSpotIds,
    p_affected_spots: c.affectedSpotIds,
    p_blueprints: c.blueprints,
    p_confirmation_hash: c.confirmationHash,
    p_command_id: commandId,
    // Fulfillment needs the private order internally. The final Edge response
    // projects it separately; no extra intent or database mutation is introduced.
    p_editor: true,
    p_expected_actor: c.actorId,
  };
}

export function projectConfirmedReplacementResponse(
  envelope: Record<string, unknown>,
  editor: boolean,
  fulfillment?: "ready" | "closed" | "pending",
) {
  const result = { ...envelope };
  if (!editor) {
    delete result.sync;
    if (result.status === "applied" || result.status === "unchanged") {
      const data = envelope.data as Record<string, unknown>;
      const order = data.order as Record<string, unknown>;
      const original = data.quote as Record<string, unknown>;
      const quote: Record<string, unknown> = {
        ...original,
        newOrder: { ...original.newOrder as Record<string, unknown> },
      };
      delete quote.seats;
      delete (quote.newOrder as Record<string, unknown>).products;
      result.data = {
        code: data.code,
        orderId: order.id,
        orderSymbol: order.order_symbol,
        quote,
      };
    }
  }
  return fulfillment
    ? { ...result, fulfillment: { status: fulfillment } }
    : result;
}

export function hasSingleTicketOrderPayload(
  payload: {
    orderDetails?: unknown;
    replacement?: unknown;
    waitlistAcceptance?: unknown;
  },
): boolean {
  return [payload.orderDetails, payload.replacement, payload.waitlistAcceptance]
    .filter((value) => value !== undefined && value !== null).length === 1;
}
