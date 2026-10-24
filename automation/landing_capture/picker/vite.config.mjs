import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '../../../web_client');
const config = JSON.parse(fs.readFileSync(process.env.FESTAPP_CAPTURE_DEFINES, 'utf8'));
const endpoint = new URL(config.FESTAPP_SUPABASE_URL);
if (endpoint.hostname !== '127.0.0.1') throw Error('Capture requires disposable loopback backend');
export default {
  root,
  server: { host: '127.0.0.1', port: Number(process.env.FESTAPP_CAPTURE_PORT || 56841), strictPort: true },
  plugins: [{ name: 'local-capture-backend', configureServer(server) {
    server.middlewares.use((req, res, next) => {
      const match = /^\/assets\/translations\/(cs|en)\.json$/.exec(req.url);
      if (!match) return next();
      res.setHeader('Content-Type', 'application/json');
      res.end(fs.readFileSync(path.join(root, '../assets/translations', `${match[1]}.json`)));
    });
  }, transform(source, id) {
    if (!id.endsWith('/src/app_config.js')) return;
    return source.replace(/static supabaseUrl = [^;]+;/, `static supabaseUrl = ${JSON.stringify(endpoint.href.replace(/\/$/, ''))};`)
      .replace(/static anonKey = [^;]+;/, `static anonKey = ${JSON.stringify(config.FESTAPP_SUPABASE_ANON_KEY)};`);
  }}],
};
