import {authorizeRequest} from '../_shared/auth.ts';
import {walletRegistry} from '../_shared/wallet/runtime.ts';
import {syncTicketWalletHandler} from './handler.ts';

Deno.serve(syncTicketWalletHandler({
 authorize: authorizeRequest,
 reconcile: () => walletRegistry.reconcile(),
}));
