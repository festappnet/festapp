# Startup theme consistency

Base: main `6f33711bc2f5b47605fb255e036a292bb8d80d72`. Deployment remains paused.

The web client previously rendered a hardcoded white startup overlay and light logo before ThemeService initialized. Both startup shells now embed the same preference policy used by ThemeService, without an extra request. Saved light/dark overrides the OS; auto follows the OS. Explicit form appearance keeps its existing priority.

Validation:
- 67 targeted tests passed across startup consistency, theme preferences and bootstrap lifecycle. Includes both shells, saved and legacy preferences, blocked storage, OS combinations, runtime ownership and deterministic generation.
- Vite production build passed.
- Isolated browser checks: eight cases across both shells, saved light/dark against the opposite OS appearance and auto with either OS appearance. Before application initialization, computed background, color scheme and decoded logo matched the selected theme. First-paint timing was not separately recorded.
- Full JS suite: 871 tests, 834 passed, 7 failed, 30 skipped. The same seven failures reproduce on unchanged main: six field HTML security expectations and one order cancellation translation expectation. The two affected test files produce the identical 9 passed / 7 failed result with and without this patch.

No production writes, database changes or Flutter build were performed. The separate paused seat-zoom PR is not included.
