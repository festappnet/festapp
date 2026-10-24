import {editor, widget} from '@wix/editor';
import {createClient} from '@wix/sdk';
import {initSettings} from './settings_controller.js';
try {
  const client = createClient({host: editor.host(), modules: {widget}});
  initSettings(document, client.widget);
} catch {
  document.getElementById('status').textContent = 'Nastavení nelze načíst. Otevřete tento panel přímo v editoru Wix.';
}
