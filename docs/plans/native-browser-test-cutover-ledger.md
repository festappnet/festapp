# Native browser test cutover ledger

The original startup run counted 306 Node tests. The new run counted 290: 26 CLI helper tests retired with the daemon and retry protocol, nine native lifecycle tests added, and one startup appearance test added. The complete TAP subtest-name multiset comparison contains exactly these 26 removals and 10 additions; all other subtest names and multiplicities match. Both runs emit the same 30 form-access and PWA browser reports.

The native tests cover context state and service-worker isolation, page/popup/service-worker/WebSocket egress containment, synchronous XMLHttpRequest denial, exact origin registration, external-origin approval, independent closure, restricted context options, IPv6 loopback, pending sockets, launch failure and context-close failure. Native navigation and interaction errors propagate without setup or assertion retry.

## Retired CLI protocol tests

- lost startup daemon is replaced before checking page isolation
- a healthy daemon opens once
- repeated startup loss fails after three task-owned sessions
- wrong isolation is a failure, never a startup retry
- navigation errors propagate without retrying page actions
- timed out launch continues only after a healthy owned daemon is confirmed
- a non-timeout launch error remains fatal
- a launched browser without a page retries only startup before page assertions
- repeated empty browser startup is bounded to three fresh sessions
- lost blank target after navigation is replaced before page assertions
- unexpected nonblank navigation fails without replacing the page
- initial readiness recovers the reported lost CDP setup session before any page actions
- initial readiness keeps real UI failures fatal instead of retrying them
- repeated CDP setup loss during initial readiness fails after three fresh sessions
- lost CDP setup session during open recovers only startup
- lost CDP setup session during navigate recovers only startup
- an ordinary navigation failure remains fatal
- startup accepts only an explicitly expected URL normalization
- a different query remains an unexpected navigation
- a live blank tab waits for its in-flight navigation before exact URL checks
- a delayed navigation still rejects an unexpected final URL
- a vanished page is not queried in a way that can relaunch a blank browser
- exact CLI CDP loss during viewport and first frame check retries before interactions
- fresh sessions receive containment and later calls do not reapply launch settings
- direct target launch verifies isolation and URL without navigating twice
- direct target launch falls back only from a blank page and rejects a different URL

## Added native and appearance tests

- native contexts isolate state and proxy contains page, popup, websocket and service-worker egress
- fixture origin registration rejects unowned network targets
- external access requires an explicitly approved exact origin
- owned contexts close independently and browser disposal closes remaining contexts
- context options cannot override isolation or egress policy
- registered IPv6 loopback reaches only its explicit fixture
- owner closes pending upstream sockets and cleanup is idempotent
- failed browser launch closes the already-listening owned proxy
- a failing context close still closes browser and proxy
- validated host appearance reveals the embedded startup symbol without enabling form inheritance

## Later main integration

The counts above describe the controlled comparison against `bae4f2e29`.
Main #774 was then incorporated before publication. Its additional tests remain
intact: the final startup run passes 291 Node cases and the same 31 aggregate
browser reports; measurement passes 193 Node cases plus 12 browser reports.
Both overlapping measurement-driver changes retain the new `form_page_view`
assertion through native Playwright waits. All eight canonical jobs pass again.
