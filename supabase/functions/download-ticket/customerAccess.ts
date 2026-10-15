/** A customer capability authorizes only issued tickets belonging to its order journey. */
export async function authorizeCustomerTicket(
  request: { token?: unknown; orderId?: unknown; ticketId?: unknown },
  readOverview: (token: string, orderId: number) => Promise<{ data: any; error: unknown }>,
): Promise<boolean> {
  if (typeof request.token !== 'string' || !/^[a-f0-9]{64}$/.test(request.token) ||
      !Number.isSafeInteger(request.orderId) || Number(request.orderId) <= 0 ||
      !Number.isSafeInteger(request.ticketId) || Number(request.ticketId) <= 0) return false;
  const { data, error } = await readOverview(request.token, request.orderId as number);
  return !error && data?.code === 200 && data.root?.hasTickets === true &&
    Array.isArray(data.orders) && data.orders.some((order: any) =>
      ['paid', 'sent', 'used'].includes(order.state) && Array.isArray(order.tickets) &&
      order.tickets.some((ticket: any) => ticket.id === request.ticketId &&
        ['paid', 'sent', 'used'].includes(ticket.rawState)));
}
