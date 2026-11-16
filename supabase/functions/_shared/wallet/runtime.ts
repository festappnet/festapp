import {emailRpc} from '../emailQueueClient.ts';
import {configuredGoogleWallet} from '../googleWallet.ts';
import {configuredAppleWallet} from '../appleWallet.ts';
import {googleWalletConnector} from './connectors/google.ts';
import {appleWalletConnector} from './connectors/apple.ts';
import {WalletRegistry} from './registry.ts';
/** Composition root: installation is explicit and provider SDKs stay in adapters. */
export const walletRegistry=new WalletRegistry([
 ['google',()=>googleWalletConnector(emailRpc,configuredGoogleWallet)],
 ['apple',()=>appleWalletConnector(emailRpc,configuredAppleWallet)],
],'google');
