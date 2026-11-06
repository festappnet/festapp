// Explicitly launched integration server; never used by a release build.
import fs from 'node:fs';
import https from 'node:https';
import {execFileSync} from 'node:child_process';
const tls = process.env.FESTAPP_EMBED_TLS_CERT && process.env.FESTAPP_EMBED_TLS_KEY;
const status = JSON.parse(fs.readFileSync(process.env.FESTAPP_EMBED_LOCAL_STATUS, 'utf8'));
if (status.API_URL === 'http://127.0.0.1:59941') {
    const marker = execFileSync('docker',['exec','supabase_db_festapp-native-embed-20261106',
        'psql','-X','-U','postgres','-d','postgres','-Atqc',
        "select project from festapp_test_support.disposable_environment where singleton"],{encoding:'utf8'}).trim();
    if (marker !== 'festapp-native-embed-20261106') throw Error('Dedicated native embed backend marker required');
} else if (status.API_URL === 'http://127.0.0.1:59921') {
    const marker = execFileSync('docker',['exec','supabase_db_festapp-wix-qa-20261025',
        'psql','-X','-U','postgres','-d','postgres','-Atqc',
        "select project from festapp_test_support.disposable_environment where singleton"],{encoding:'utf8'}).trim();
    if (marker !== 'festapp-wix-qa-20261025') throw Error('Dedicated Wix backend marker required');
} else if (status.API_URL === 'http://127.0.0.1:59931') {
    const marker = execFileSync('docker',['exec','supabase_db_festapp-joomla-help-20261029',
        'psql','-X','-U','postgres','-d','postgres','-Atqc',
        "select project from festapp_test_support.disposable_environment where singleton"],{encoding:'utf8'}).trim();
    if (marker !== 'festapp-joomla-help-20261029') throw Error('Dedicated Joomla backend marker required');
} else if (status.API_URL !== 'http://127.0.0.1:59821') throw Error('Disposable embed backend required');
export default {
    root: new URL('../../..', import.meta.url).pathname,
    server: { host: '127.0.0.1', port: 59801, strictPort: true, allowedHosts: tls ? ['vstupenky.online'] : [] },
    plugins: [{name:'embedded-checkout-disposable-backend', transformIndexHtml(html, context) {
        if (!new URL(context.originalUrl, 'http://localhost').searchParams.has('qaStorage')) return;
        return [{tag:'script', attrs:{type:'module',src:'/tests/fixtures/embedded-checkout/storage-probe.js'}, injectTo:'body'}];
    }, async configureServer(server) {
        if (tls) {
            const slot = Symbol.for('festapp.embed.fixtureHttps');
            const previous = globalThis[slot];
            if (previous) {
                previous.closeAllConnections();
                await new Promise(resolve => previous.close(resolve));
            }
            const secure = https.createServer({
                cert: fs.readFileSync(process.env.FESTAPP_EMBED_TLS_CERT),
                key: fs.readFileSync(process.env.FESTAPP_EMBED_TLS_KEY),
            }, server.middlewares);
            globalThis[slot] = secure;
            await new Promise((resolve, reject) => {
                secure.once('error', reject);
                secure.listen(59803, '127.0.0.1', resolve);
            });
            server.httpServer.once('close', () => secure.close());
        }
        server.middlewares.use((req, res, next) => {
            const match = /^\/assets\/translations\/(cs|en|sk|de|pl|uk)\.json$/.exec(req.url);
            if (!match) return next();
            res.setHeader('Content-Type', 'application/json');
            res.end(fs.readFileSync(new URL(`../../../../assets/translations/${match[1]}.json`, import.meta.url)));
        });
    }, transform(source, id) {
        if (!id.endsWith('/src/app_config.js')) return;
        if (!/static supabaseUrl = [^;]+;/.test(source) || !/static anonKey = [^;]+;/.test(source) ||
            !/static backendActivationTenantId = [^;]+;/.test(source)) throw Error('Unknown app config; refusing unsafe fixture');
        // A tenant branch must never reactivate its production backend here.
        source = source.replace(/static backendActivationTenantId = [^;]+;/, "static backendActivationTenantId = '';");
        return source.replace(/static supabaseUrl = [^;]+;/, `static supabaseUrl = ${JSON.stringify(status.API_URL)};`)
            .replace(/static anonKey = [^;]+;/, `static anonKey = ${JSON.stringify(status.ANON_KEY)};`);
    }}],
};
