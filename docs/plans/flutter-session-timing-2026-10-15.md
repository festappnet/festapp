# Live session timing - vstupenky.online, 2026-10-15

Five separate navigations to a unit administration route in the authorized signed-in Chrome session. New background tab via Panerelay; existing browser cache and ordinary network. Measurements use browser ResourceTiming, rounded to milliseconds, and include request round trips rather than server execution alone. No tokens, response bodies or user identifiers were recorded.

| Start | Session refresh | Organization validation | Sequential span including gaps |
| --- | ---: | ---: | ---: |
| 1 | 286 ms | 84 ms | 377 ms |
| 2 | 153 ms | 66 ms | 222 ms |
| 3 | 190 ms | 93 ms | 287 ms |
| 4 | 182 ms | 157 ms | 341 ms |
| 5 | 276 ms | 65 ms | 346 ms |

Median refresh: **190 ms** (153-286 ms). Median organization validation: **84 ms** (65-157 ms). Median complete sequential span: **341 ms** (222-377 ms). Medians of individual stages do not add to the median of the total.

Each navigation made one successful refresh and one successful organization-validation request (HTTP 200). This sample shows no duplicate refresh within the measured startup interval.

The maximum observed opportunity from removing both round trips is roughly 0.22-0.38 seconds for these runs; preserving authorization and refresh behavior may require keeping some or all of that work. This is an upper bound from observation, not a measured improvement from an implementation. These numbers do not support treating session work as the main explanation for a multi-second startup.

Scope limitation: background rendering can pause at startup phase S12. This experiment measures completed authentication requests, not time until the administration is fully rendered or interactive. Five cached desktop navigations do not establish mobile, cold-cache or tail-latency performance.

Sanitized timings are preserved in [flutter-session-timing-2026-10-15.json](flutter-session-timing-2026-10-15.json).
