# Notification architecture: first-party industry evidence

Research date: 2026-11-05
Purpose: validate and refine the Festapp scalability plan, not infer private
implementation details or reproduce the infrastructure of a global social network.

## Evidence policy and scope

The sources below are company engineering publications, official documentation
or an official product announcement. Publication dates identify historical
accounts, not a claim that the same implementation is deployed unchanged today.
No single formal industry standard specifies notification inbox storage or read
semantics. The useful evidence is repeated engineering practice with explicit
workload and consistency tradeoffs.

Keep three different problems separate: durable in-app activity and read state;
selecting recipients/content/channels; delivering a mobile/web push. Ranked feeds
are adjacent examples, not proof of how a company's notification bell is stored.
Statements labelled **Festapp decision** are our inference/application.

## Source findings and limits

### R1. Meta Async - asynchronous work, fairness and urgency

2020-08-17. Meta describes background execution for notification-related work,
problems with large use cases dominating FIFO scheduling, delay tolerance and
capacity regulation. Adding workers alone did not solve the scheduling problems.
This documents shared asynchronous execution, not the Facebook inbox schema.
[Meta: Async](https://engineering.fb.com/2020/08/17/production-engineering/async/).

**Festapp decision:** define work classes and acceptable lag; rotate tenant
budgets; isolate backfills from live delivery/privacy repair. Measure oldest
pending age per class/tenant rather than only total jobs processed.

### R2. Meta FOQS - durable work with leases and acknowledgments

2021-02-22. FOQS is a persistent multitenant priority queue over sharded MySQL.
Consumers acknowledge success or negatively acknowledge failed work; leases,
delay and retry policy govern redelivery. Namespaces provide capacity isolation.
Async, including notifications, is one customer. This establishes queue semantics,
not exactly-once user-visible notifications.
[Meta: FOQS](https://engineering.fb.com/2021/02/22/production-engineering/foqs-scaling-a-distributed-priority-queue/).

**Festapp decision:** retain durable pending work and make repeated projection
idempotent. A lost wake-up must be recoverable. A poison item needs retry state
and an operator-visible failure path without blocking unrelated scopes. No new
broker is required to implement those responsibilities.

### R3. Facebook Multifeed - prepared indexes plus read-time work

2015-03-10. The described News Feed system had real-time input pipelines into
indexed in-memory leaves and an aggregator performing retrieval, ranking and
filtering for requests. Thus the publication does not support the claim that
large social services precompute every result. It is about News Feed, not bells.
[Meta: Multifeed](https://engineering.fb.com/2015/03/10/production-engineering/serving-facebook-multifeed-efficiency-performance-gains-through-redesign/).

**Festapp decision:** keep cheap context/permission checks and bounded preview
hydration at read time. Choose precomputed exact batch totals because of our
measured aggregation workload, not because Facebook supposedly mandates them.

### R4. LinkedIn Concourse - fanout and recipient decisions

2018-05-25. Concourse describes near-real-time candidate fanout, feature decoration
and relevance scoring. It distinguishes transactional from recommendation-style
notifications and explicitly separates candidate decisions from actual delivery.
It does not document durable notification inbox tables or read counters.
[LinkedIn: Concourse](https://www.linkedin.com/blog/engineering/messaging-notifications/concourse-generating-personalized-content-notifications-in-near).

**Festapp decision:** recipient discovery, summary projection and channel delivery
have separate costs. Do not introduce recommendation filtering or engagement
ranking into required organizer order activity. Permissions/preferences still apply.

### R5. LinkedIn ATC - one notification policy surface

2018-03-01. Air Traffic Controller describes recipient-oriented notification
policy, channel selection, aggregation, duplicate/expired filtering, rate limits
and input partitioning by recipient. It distinguishes in-app from device push.
The article is not evidence of an inbox materialization algorithm.
[LinkedIn: ATC](https://www.linkedin.com/blog/engineering/messaging-notifications/air-traffic-controller-member-first-notifications-at-linkedin).

**Festapp decision:** preserve one canonical in-app policy and recipient read
owner; treat grouping, source-event deduplication and optional transport coalescing
as different operations. Existing outbound email remains in its canonical queue.

### R6. Discord Read States - maintained read metadata and latency tails

2020-02-04. Discord describes per-user/per-channel read state, atomic counters,
a memory cache and persistent backing. The motivation included periodic latency
spikes, not only average throughput. This is messaging read metadata, not a
published notification center schema or a reason to change Festapp's language.
[Discord: Read States](https://discord.com/blog/why-discord-is-switching-from-go-to-rust).

**Festapp decision:** maintain personal seen/read metadata as explicit state;
measure p95/p99 and hot-recipient behavior. Do not copy the article's delayed
persistence policy for authoritative Festapp acknowledgment receipts.

### R7. YouTube - inbox and push are distinct product surfaces

2026-04-21. An official YouTube team announcement says inactive subscribers may
stop receiving mobile push while continuing to receive inbox notifications.
This documents product/channel behavior, not its internal storage, queue,
materialization, unread algorithm or privacy invalidation implementation.
[YouTube: push notification update](https://support.google.com/youtube/blog/425764939/updates-to-youtube-push-notifications-to-keep-your-audience-engaged?hl=en-JE).

**Festapp decision:** authoritative in-app activity must not depend on successful
or selected push delivery. Do not apply YouTube engagement suppression to required
organizer activity. No YouTube-specific inbox architecture is established here.

### R8. YouTube public webhooks - an important category boundary

Living documentation, accessed 2026-11-05. The YouTube Data API documents
PubSubHubbub-style server-to-server notifications for video uploads and title or
description updates. This is a public integration mechanism, not mobile push or
the YouTube internal bell.
[Google: YouTube push subscriptions](https://developers.google.com/youtube/data/guides/push_notifications).

**Festapp decision:** do not cite external webhook documentation as evidence of
an internal notification inbox design. Treat unverified internal claims as gaps.

### R9. Meta video delivery - authorization while serving

2024-12-10. Meta describes loading ranked video entities, checking viewer privacy
on the server and then assembling requested GraphQL fields. It also discusses
freshness versus client caching and fetch cost. Here field materialization means
response assembly, not persistent inbox construction. This is a video feed.
[Meta: video delivery](https://engineering.fb.com/2024/12/10/video-engineering/inside-facebooks-video-delivery-system/).

**Festapp decision:** a prepared candidate/count cannot authorize its own exposure.
Keep coherent current access checks at response time and invalidate summaries
that may contain hidden subjects. Bound hydration to returned references.

### R10. AWS transactional outbox - durable publication and idempotency

Living architecture guidance, accessed 2026-11-05. AWS describes recording a
business change and its event in one transaction to avoid inconsistent dual
writes, with idempotent handling of possible duplicate dispatch. This is generic
guidance, not evidence that any social company uses this precise pattern.
[AWS: transactional outbox](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html).

**Festapp decision:** retain the existing same-transaction domain publication
and durable recipient work. A broker wake-up is not the authoritative receipt.
Do not add a second outbox just to match a pattern's name or promise exactly-once
transport delivery.

### R11. Firebase transport - replaceable synchronization hints

Living official documentation, accessed 2026-11-05. FCM documents that delivery
order is not guaranteed and a pending collapsible message may be replaced by a
newer message. A common example is prompting the application to synchronize.
These are transport properties, not YouTube implementation evidence.
[Firebase: collapsible messages](https://firebase.google.com/docs/cloud-messaging/customize-messages/collapsible-message-types).

**Festapp decision:** any future realtime/push update can be a coalescible revision
hint followed by an authorized server read. Collapsing hints must not delete
underlying notification records, counts or read receipts. This research does not
add push delivery to the current implementation scope.

## Architectural consequences

The resulting Festapp design is a hybrid: incrementally maintained exact batch
summaries and read metadata; bounded token catalogs; live permission checks and
small contact hydration; durable asynchronous work with explicit idempotency,
lag budgets, fairness and recovery. That is our workload-specific choice.

This research adds concrete requirements to the authoritative execution plan:

1. Name committed-source, delivered, projection-ready, response and seen/read
   milestones separately. Report their lag instead of one misleading latency.
2. Add work-class fairness, retry/backoff, poison-work diagnostics and retained
   failure evidence. Never drop canonical transactional activity to meet a timer.
3. Keep three operations distinct: deduplicate one logical source revision;
   aggregate multiple real activities into a batch; coalesce wake/sync hints.
4. Compare a set-based indexed read approach with maintained exact totals in the
   benchmark wave. Choose using read savings, write amplification and invalidation
   cost. Public company blogs do not establish our 50ms target or token limits.
5. Preserve the separation between in-app activity, preferences and the existing
   outbound email/push transports. No provider call belongs on panel opening.
6. Treat privacy-generational fencing, view quotas/expiry and legacy RPC retention
   as Festapp contract decisions requiring their own correctness proof.

## What is not established

No primary source found in this research establishes YouTube's internal inbox
schema, its exact unread/read implementation, materialized summary algorithm,
notification deletion pipeline or current database choice. None of the cited
sources validates Festapp's proposed 30-minute lease, four-view quota or 50ms SLO.
Those are provisional local design parameters, not industry standards.

Likewise, Facebook News Feed and video feed designs do not prove the architecture
of Facebook's notification bell. Historical engineering posts are useful evidence
of techniques and tradeoffs, not a current deployment inventory.

No production data was read, no implementation was changed, and no performance
benchmark was run as part of this literature research.
