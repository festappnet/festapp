import {window as wixWindow} from '@wix/site-window';
import {site} from '@wix/site';
import {createClient} from '@wix/sdk';
import registration from '../wix-app.json' with {type:'json'};
import {registerTicketElement} from './element.js';
// Self-managed extensions do not receive the implicit SDK context available
// to Wix-managed code. Bind frontend APIs to this app's actual site host.
let client;
registerTicketElement(window, () => {
  client ??= createClient({
    host:site.host({applicationId:registration.appId}),
    modules:{wixWindow},
  });
  return client.wixWindow.viewMode();
});
