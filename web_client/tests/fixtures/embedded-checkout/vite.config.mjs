// Explicitly launched integration server; never used by a release build.
import fs from 'node:fs';
const status = JSON.parse(fs.readFileSync(process.env.FESTAPP_EMBED_LOCAL_STATUS, 'utf8'));
if (status.API_URL !== 'http://127.0.0.1:59821') throw Error('Disposable embed backend required');
const international=process.env.FESTAPP_EMBED_PRODUCT==='festapp-tickets';
export default {
    root: new URL('../../..', import.meta.url).pathname,
    server: { host: '127.0.0.1', port: process.env.FESTAPP_EMBED_TLS_CERT ? 59803 : international ? 59804 : 59801, strictPort: true, ...(process.env.FESTAPP_EMBED_TLS_CERT ? {https:{cert:fs.readFileSync(process.env.FESTAPP_EMBED_TLS_CERT),key:fs.readFileSync(process.env.FESTAPP_EMBED_TLS_KEY)}} : {}) },
    plugins: [{name:'embedded-checkout-disposable-backend', configureServer(server) {
        server.middlewares.use((req, res, next) => {
            const match = /^\/assets\/translations\/(cs|en|sk|de|pl|uk)\.json$/.exec(req.url);
            if (!match) return next();
            res.setHeader('Content-Type', 'application/json');
            res.end(fs.readFileSync(new URL(`../../../../assets/translations/${match[1]}.json`, import.meta.url)));
        });
    }, transform(source, id) {
        if (!id.endsWith('/src/app_config.js')) return;
        return source.replace(/static supabaseUrl = [^;]+;/, `static supabaseUrl = ${JSON.stringify(status.API_URL)};`)
            .replace(/static anonKey = [^;]+;/, `static anonKey = ${JSON.stringify(status.ANON_KEY)};`)
            .replace(/static (appName|appTitleShort) = [^;]+;/g, (_,key)=>`static ${key} = ${JSON.stringify(international ? 'Festapp Tickets' : 'vstupenky.online')};`)
            .replace(/https:\/\/vstupenky\.online/g, international ? 'https://tickets.festapp.net' : 'https://vstupenky.online');
    }}],
};
