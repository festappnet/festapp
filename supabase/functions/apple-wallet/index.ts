import {emailRpc} from '../_shared/emailQueueClient.ts';
import {configuredAppleWallet} from '../_shared/appleWallet.ts';
import {appleWalletHandler} from './handler.ts';
Deno.serve(appleWalletHandler(emailRpc,configuredAppleWallet));
