# Frozen protocol 2 external peers

These negative compatibility fixtures are copied from main 99dc29ae7f664796f6d1a9916d360ca28535411e, before PR #752. They are not imported by production or generators. Only runtime/bridge import paths were relocated: the old contract stays frozen, and unchanged layout/theme adapters are imported from their regular owner. helper.js and bootstrap.mjs are the actual generated historical bytes. Keep this provenance and the behavior, not a second implementation to maintain.
