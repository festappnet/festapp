# Current Flutter web startup bottleneck - 2026-10-15

Live version: `0.20.212+696` (versioned asset suffix `0.20.212-696`). Read-only measurements against vstupenky.online; no deployment or application changes.

## Reproducible isolated startup

Three fresh, headless, isolated Chrome sessions and one repeated cached navigation to the same unit administration URL. These sessions have no login and therefore measure startup into the login screen, not an authenticated administration table. Startup phases were captured in page-local JavaScript. S13 is the bootstrap usable-frame signal.

| Run | Before loader | Load/evaluate entrypoint | Initialize engine | After engine until ready | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold 1 | 591 ms | 641 ms | 565 ms | 397 ms | 2194 ms |
| Cold 2 | 437 ms | 844 ms | 461 ms | 323 ms | 2065 ms |
| Cold 3 | 397 ms | 590 ms | 567 ms | 377 ms | 1931 ms |
| Cached | 39 ms | 94 ms | 124 ms | 151 ms | 408 ms |

Cold median total: **2,065 ms**. Median loader-to-engine-ready interval: **1,206 ms**. Across these cold runs, **80-85%** of startup occurs before Dart starts. The stage intervals include overlapping network downloads; they are not pure CPU measurements.

On cold run 1, the main JS transferred 2,896,509 bytes and completed at 1,137 ms. CanvasKit WASM transferred 2,014,589 bytes and completed at 1,619 ms. Engine initialization completed at 1,797 ms. Main JS and WASM together transfer approximately **4.91 MB** before fonts and remaining assets. A CPU long task of 247-275 ms was observed in each cold run. The timing observer does not identify the exact function responsible.

## Authenticated background observation

A separate authorized signed-in background tab, with cached resources, reached S03 at 1,338 ms and S12 at 1,880 ms. Main JS was available from cache by 225 ms; S02 was at 792 ms. Thus cached delivery alone does not account for all engine startup latency in this browser. Session refresh took 278 ms and organization validation 95 ms.

The tab remained hidden, so Chrome withheld the final Flutter frame: no S13 by 8 seconds. That wait is a background-tab artifact and must not be presented as an application bottleneck. Another observation that became visible contained later user navigation; it was excluded from controlled startup totals. A second hidden-tab observation missed the phase-hook installation and was excluded from phase statistics.

## Findings and next experiment

The demonstrated cold-start bottleneck is loading and starting the Flutter runtime and entrypoint. Session consolidation has a smaller observed ceiling, as documented in the separate five-start session report. The cached isolated startup of 408 ms shows that this is not a fixed multi-second backend delay.

The next narrow experiment should test starting main JS and CanvasKit downloads earlier from the HTML shell. The current loader starts inside the window load handler; it begins 397-591 ms after navigation in these cold runs. This interval is only an upper bound for overlap and includes HTML delivery, so it is not a promised saving. Validate preload URLs and cache behavior against the existing versioned loader before implementing. Further bundle splitting or renderer changes need an A/B measurement, rather than an assumed speedup.

An end-to-end bottleneck for a real authenticated administration table remains unproven: it requires a visible rendering context, or additional in-app timing instrumentation during an ordinary user-visible startup. The available authorized background session cannot establish that rendering duration.

Evidence: [flutter-web-bottleneck-2026-10-15.json](flutter-web-bottleneck-2026-10-15.json).
