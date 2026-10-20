import { registerHooks } from 'node:module';

// Match Vite's asset URL while executing the actual archived kernel unchanged.
registerHooks({ resolve(specifier, context, nextResolve) {
    if (specifier === '@festapp/venue-layout/kernel?url') {
        const url = nextResolve('@festapp/venue-layout/kernel', context).url;
        return {url: `data:text/javascript,${encodeURIComponent(`export default ${JSON.stringify(url)}`)}`, shortCircuit: true};
    }
    return nextResolve(specifier, context);
}});
globalThis.self = globalThis;
await import('@festapp/venue-layout/kernel');

export const emptyLayout = {schemaVersion: 2, symbolSetVersion: 1,
    canvas: {x: 0, y: 0, width: 600, height: 400, fill: '#FFFFFFFF'},
    textPolicy: {language: 'und', direction: 'auto'}, styles: {}, seatingDefaults: {},
    nodes: [], sections: [], selectionUnits: [], attachments: [], presets: [], background: null};
