export interface BankConnection {
  connection_id: number | string;
  remote_bank_account_id: string;
}
interface Dependencies {
  connections(authorization: string, occasionLink: string): Promise<BankConnection[]>;
  synchronize(connections: BankConnection[]): Promise<unknown>;
}
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};
export function createTransactionFetchHandler(dependencies: Dependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method === 'OPTIONS') return new Response('ok', { headers });
    const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
    if (request.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' });
    const authorization = request.headers.get('Authorization');
    if (!authorization) return reply(401, { error: 'Unauthorized' });
    let body;
    try { body = await request.json(); } catch { return reply(400, { error: 'Invalid request' }); }
    if (typeof body?.occasionLink !== 'string' || !body.occasionLink.trim() || body.occasionLink.length > 200) {
      return reply(400, { error: 'Missing occasion link' });
    }
    try {
      // One authenticated data request owns the actual occasion/unit binding
      // and both bank roles. No Edge role calculation or service-wide listing.
      const connections = await dependencies.connections(authorization, body.occasionLink);
      return reply(200, { results: await dependencies.synchronize(connections) });
    } catch (error) {
      const code = error instanceof Error ? error.message : '';
      if (code === 'UNAUTHORIZED') return reply(401, { error: 'Unauthorized' });
      if (code === 'BANK_SYNC_FORBIDDEN') return reply(403, { error: 'bank_account_admin_required' });
      return reply(503, { error: 'canonical_bank_sync_failed' });
    }
  };
}
