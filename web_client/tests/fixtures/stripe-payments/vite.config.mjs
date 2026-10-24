import { fileURLToPath } from 'node:url';
export default {
  build: {
    outDir: '/tmp/festapp-stripe-component-bundle', emptyOutDir: true,
    lib: { entry: fileURLToPath(new URL('./entry.js',import.meta.url)), name: 'StripePaymentFixture', formats: ['iife'], fileName: () => 'fixture.js' },
    cssCodeSplit: false,
  },
};
