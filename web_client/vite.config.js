import { defineConfig } from 'vite';
import fs from 'fs';
import path from 'path';
import { APP_VERSION } from './src/version.js';

export default defineConfig({
  plugins: [{
    name: 'festapp-release-entry',
    transformIndexHtml: {
      order: 'post',
      handler(html, context) {
        if (!context.bundle) return html;
        // Bind the entry URL to this release even when its bytes/hash did not
        // change, so a cached failure from an earlier release cannot block it.
        return html.replace(/(<script\b[^>]*\bsrc=")([^"?]*\/web-assets\/[^"?]+\.js)("[^>]*>)/g,
          (_, prefix, src, suffix) => `${prefix}${src}?release=${encodeURIComponent(APP_VERSION)}${suffix}`);
      },
    },
  }],
  server: {
    host: true, // Expose to network
    port: 5173, // Default, but explicit is good
    proxy: {}
  },
  configureServer: (server) => {
    server.middlewares.use((req, res, next) => {
      console.log('>> [Vite Req]', req.method, req.url);
      next();
    });
  },
  build: {
    assetsDir: 'web-assets'
  }
});
