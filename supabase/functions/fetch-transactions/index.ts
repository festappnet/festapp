import { synchronizeCanonicalBankConnections } from '../_shared/bankSyncClient.ts';
import { createUserClient } from '../_shared/supabaseUtil.ts';
import { createTransactionFetchHandler } from './handler.ts';

Deno.serve(createTransactionFetchHandler({
  async connections(authorization, occasionLink) {
    const client = createUserClient(authorization);
    const { data: identity, error: identityError } = await client.auth.getUser();
    if (identityError || !identity.user) throw new Error('UNAUTHORIZED');
    const { data, error } = await client.rpc('get_bank_sync_connections_for_occasion', { p_link: occasionLink });
    if (error) throw new Error(error.code === '42501' ? 'BANK_SYNC_FORBIDDEN' : 'BANK_SYNC_UNAVAILABLE');
    return data ?? [];
  },
  synchronize: synchronizeCanonicalBankConnections,
}));
