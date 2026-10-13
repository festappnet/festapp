// Node exercises the real component code; Vite owns stylesheet loading.
import { registerHooks } from 'node:module';
registerHooks({
    load(url, context, nextLoad) {
        if (url.startsWith('file:') && new URL(url).pathname.endsWith('.css')) {
            return { format: 'module', source: '', shortCircuit: true };
        }
        return nextLoad(url, context);
    },
});
