# Venue Layout demo

The public `VenueLayoutEditor` studio and customer picker demonstrate the full
Venue Layout flow: create a plan from the shared template gallery, edit its
objects, export a portable document and preview customer selection. Creating a
template allocates fresh identities. Demo prices and availability are synthetic
host data; the demo creates no real reservation or order.

Build prerequisites: the pinned FVM Flutter SDK, a populated Flutter/Dart dependency cache, Python 3 and Node.js. Dependency setup and browser installation can require internet. From the package root:

```sh
python3 tool/configure_workspace.py
fvm flutter pub get
(cd example && fvm flutter pub get)
(cd web && pnpm install --frozen-lockfile && pnpm exec playwright install chromium)
tool/demo.sh build
tool/demo.sh check
tool/demo.sh open
# Optional explicit browser preview, always a new tab:
tool/demo.sh open --new-tab
tool/demo.sh stop
```

`build/demo/` contains the Flutter app, the independent JS consumer and a SHA256 asset/source/protocol/SDK manifest. Copying the complete `build/demo/` directory is sufficient for runtime: run `python3 run.py open` inside the copy and `python3 run.py stop` to stop its owned loopback process. The launcher is tested on macOS/Linux and needs only Python 3, `ps` and a modern browser, without FVM, Node or source checkouts. Already-built assets run without a backend, login, `.env`, CDN or Festapp checkout. Flutter's loader fails under `file://` in the G0 experiment, so this launcher binds only `127.0.0.1` on an allocated port. `open` prints its URL; it opens Chrome only with `--new-tab`. `check` runs an isolated headless Chromium on the same kit, writes `build/demo/report/index.html`, screenshots and JSON failures, then stops its server/browser. The report itself opens directly from disk. `stop` only targets the PID whose command belongs to this launcher. The JS page is under `/js/demo/`, and its bundled classic-script version can also open directly from `build/demo/js/demo/index.html` via `file://`. It starts from a seed exported by the same public template API.

Use Save to confirm a local baseline. Autosave runs after a 500 ms pause and recovers on reload. Export portable demo preserves document, host sample prices and embedded font/image resources. Resource paths, byte limits, versions and SHA256 are validated before replacing the draft. Corrupt imports preserve the active draft. Export geometry only omits host prices/states and local resources. A receiving host must supply those resources.

**Webový náhled** opens the current plan in the JavaScript customer picker with
seat selection, atomic furniture units and standing quantities. It transfers the
complete validated portable bundle through a committed local IndexedDB
transaction, including fonts, images and sample prices. **Zpět do editoru**
restores that exact draft. No file export/import is needed, and customer
selections do not modify editor geometry or create reservations. The ordinary
**Náhled** button retains the Flutter picker preview. Manual portable import on
the standalone JS page remains available.

Selected objects use compact edge and corner resize handles. Click a selected
table's label or double-click an editable object to rename it inside the canvas.
New text opens directly in the canvas. Enter commits, Shift+Enter inserts a line,
Escape cancels, and clicking outside commits. A rename is one undo transaction;
new text and its initial content are one creation transaction.

Reset restores the current template with fresh identities and protects unsaved edits. Diagnostics offers restoring the saved baseline, deterministic success/conflict/timeout/resource outcomes, and simulated full storage. File export remains independent of browser storage. Host price controls appear in the selected object's inspector; table defaults are inherited unless a seat overrides them. Moving a free sample seat to another table clears its override, and history captures geometry plus price metadata. Lounge couches select their two seats together. Standing inputs show total capacity separately from selected quantity.

These scenarios simulate a host boundary. They prove no database atomicity, authentication, reservations, orders, payment processing, stock ledger or production access. Those remain outside stage A.

The fixture font sources, licenses and manifest are package assets under `assets/layout_fonts/`. No runtime font download is used.
