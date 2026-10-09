import { defineConfig } from 'vite';
import fs from 'fs';
import path from 'path';
import { APP_VERSION } from './src/version.js';

export default defineConfig({
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
    assetsDir: 'web-assets',
    rollupOptions: {
      output: {
        // Version the entry filename so shared chunks refer to the same module
        // identity and cached failures cannot survive a release.
        entryFileNames: `web-assets/[name]-[hash]-${APP_VERSION.replace('+', '-')}.js`,
      },
    }
  }
});
