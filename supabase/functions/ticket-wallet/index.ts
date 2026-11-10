import { emailRpc } from '../_shared/emailQueueClient.ts';
import { configuredGoogleWallet } from '../_shared/googleWallet.ts';
import { walletHandler } from './handler.ts';
Deno.serve(walletHandler(emailRpc,configuredGoogleWallet,(Deno.env.get('GOOGLE_WALLET_ALLOWED_ORIGINS')||'').split(',').map(x=>x.trim()).filter(Boolean)));
