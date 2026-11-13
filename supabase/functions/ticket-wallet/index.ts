import {walletRegistry} from '../_shared/wallet/runtime.ts';
import {walletHandler} from './handler.ts';
Deno.serve(walletHandler(walletRegistry,(Deno.env.get('TICKET_WALLET_ALLOWED_ORIGINS')||Deno.env.get('GOOGLE_WALLET_ALLOWED_ORIGINS')||'').split(',').map(x=>x.trim()).filter(Boolean)));
