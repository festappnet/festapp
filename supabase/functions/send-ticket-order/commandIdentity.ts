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
