# Divider follow-up diagnosis - 2026-11-02

On local artifact `cc9d9e16e59257cdf2b11abfe04617abe0edb1fe246714687bac5ced21120caa`, an isolated headless 1280x900 browser at DPR 1 showed the colored divider at x679. At every 20px from y140 through y880, `ew-resize` appeared continuously across x668-691 and not at x667 or x692. DPR 2 emulation gave the same CSS-coordinate range at y140, 400, 600 and 880. The reported short segment or offset was not reproduced. Browser page zoom was not verified.

The fresh session had no service-worker controller or registrations; the local `main.dart.js` response had `Cache-Control: no-store`. The local-development bootstrap unregisters known app-shell workers, clears their caches and reloads once if an old worker controlled the page. This does not establish the state of another browser profile.

No fix or database writes were made in this diagnostic pass. The isolated browser was closed; local services remain running.
