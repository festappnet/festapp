--
-- PostgreSQL database dump
--


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: payment_providers; Type: TABLE DATA; Schema: eshop; Owner: -
--

INSERT INTO eshop.payment_providers VALUES ('bank', NULL, NULL, NULL);
INSERT INTO eshop.payment_providers VALUES ('stripe', 'public.stripe_payment_provider_internal(text,jsonb)', 'stripePaymentSource', 'stripeConnectionId');
INSERT INTO eshop.payment_providers VALUES ('barion', 'public.barion_payment_provider_internal(text,jsonb)', 'barionPaymentSource', NULL);
INSERT INTO eshop.payment_providers VALUES ('cash', NULL, NULL, NULL);


--
-- Data for Name: abuse_policy_revision; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.abuse_policy_revision VALUES (true, 1);


--
-- Data for Name: abuse_policy_rules; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.abuse_policy_rules VALUES ('occasion.create.actor.burst', 'occasion.creation', 'operations', 'actor', 'rolling', 600, 60, 5, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.create.actor.day', 'occasion.creation', 'operations', 'actor', 'rolling', 86400, 3600, 20, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.create.unit.burst', 'occasion.creation', 'operations', 'unit', 'rolling', 600, 60, 10, 40, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.create.unit.day', 'occasion.creation', 'operations', 'unit', 'rolling', 86400, 3600, 40, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.create.organization.burst', 'occasion.creation', 'operations', 'organization', 'rolling', 600, 60, 40, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.create.organization.day', 'occasion.creation', 'operations', 'organization', 'rolling', 86400, 3600, 200, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('draft.create.actor.burst', 'occasion.draft', 'operations', 'actor', 'rolling', 600, 60, 10, 30, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('draft.create.actor.day', 'occasion.draft', 'operations', 'actor', 'rolling', 86400, 3600, 40, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('draft.create.organization.day', 'occasion.draft', 'operations', 'organization', 'rolling', 86400, 3600, 200, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('draft.work.actor.burst', 'occasion.draft', 'operations', 'actor', 'rolling', 600, 60, 20, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('unit.create.actor.day', 'unit.creation', 'operations', 'actor', 'rolling', 86400, 3600, 3, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('unit.create.organization.day', 'unit.creation', 'operations', 'organization', 'rolling', 86400, 3600, 30, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('unit.create.global.day', 'unit.creation', 'operations', 'global', 'rolling', 86400, 3600, 100, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.ordinary.organization.day', 'email.ordinary', 'operations', 'organization', 'rolling', 86400, 3600, 2000, 20000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.ordinary.recipient.burst', 'email.ordinary', 'operations', 'recipient', 'rolling', 60, 60, 6, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.ordinary.recipient.day', 'email.ordinary', 'operations', 'recipient', 'rolling', 86400, 3600, 20, 40, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.auth.organization.day', 'email.auth', 'operations', 'organization', 'rolling', 86400, 3600, 1000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.auth.recipient.burst', 'email.auth', 'operations', 'recipient', 'rolling', 60, 60, 1, 2, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.auth.recipient.day', 'email.auth', 'operations', 'recipient', 'rolling', 86400, 3600, 10, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.auth.global.day', 'email.auth', 'operations', 'global', 'rolling', 86400, 3600, 10000, 50000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.prepare.organization.burst', 'email.prepare', 'operations', 'organization', 'rolling', 60, 60, 60, 300, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.prepare.recipient.burst', 'email.prepare', 'operations', 'recipient', 'rolling', 60, 60, 3, 6, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.create.unit.day', 'order.creation', 'operations', 'unit', 'rolling', 86400, 3600, 2000, 20000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.create.organization.day', 'order.creation', 'operations', 'organization', 'rolling', 86400, 3600, 10000, 100000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('qr.exchange.global.burst', 'qr.global', 'operations', 'global', 'rolling', 60, 60, 600, 1200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('qr.exchange.proof.burst', 'qr.proof', 'operations', 'recipient', 'rolling', 60, 60, 30, 30, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.ordinary.unit.day', 'email.ordinary', 'operations', 'unit', 'rolling', 86400, 3600, 500, 10000, 'existing_orders', 3);
INSERT INTO public.abuse_policy_rules VALUES ('hold.acquire.unit.burst', 'spot.hold', 'operations', 'unit', 'rolling', 60, 60, 1000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('hold.acquire.organization.burst', 'spot.hold', 'operations', 'organization', 'rolling', 60, 60, 5000, 30000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('reset.source', 'auth.reset.source', 'operations', 'recipient', 'rolling', 900, 300, 20, 40, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('reset.account', 'auth.reset.account', 'operations', 'recipient', 'rolling', 900, 300, 3, 3, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('google.source', 'auth.google.source', 'operations', 'recipient', 'rolling', 60, 60, 20, 40, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('google.client', 'auth.google.client', 'operations', 'recipient', 'rolling', 60, 60, 30, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('google.global', 'auth.google.global', 'operations', 'recipient', 'rolling', 60, 60, 100, 300, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('google.attempt', 'auth.google.attempt', 'operations', 'recipient', 'rolling', 60, 60, 10, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('google.proof', 'auth.google.proof', 'operations', 'recipient', 'rolling', 60, 60, 5, 5, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.upload.actor.burst', 'image.upload', 'operations', 'actor', 'rolling', 600, 60, 30, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.upload.unit.burst', 'image.upload', 'operations', 'unit', 'rolling', 600, 60, 60, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('qr.payload.bytes', 'qr.payload', 'bytes', 'global', 'bytes', NULL, NULL, 1024, 4096, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('sync.work.source.burst', 'sync.work', 'operations', 'actor', 'rolling', 600, 60, 10, 30, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('reset.global', 'auth.reset.source', 'operations', 'global', 'rolling', 60, 60, 300, 600, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('organization.create.global.day', 'organization.creation', 'operations', 'global', 'rolling', 86400, 3600, 5, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('draft.payload.bytes', 'occasion.draft', 'bytes', 'unit', 'bytes', NULL, NULL, 262144, 262144, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.backlog.unit.bytes', 'email.backlog', 'bytes', 'unit', 'bytes', NULL, NULL, 33554432, 268435456, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.backlog.organization.bytes', 'email.backlog', 'bytes', 'organization', 'bytes', NULL, NULL, 134217728, 1073741824, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.payload.bytes', 'email.payload', 'bytes', 'global', 'bytes', NULL, NULL, 16777216, 33554432, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.upload.actor.bytes', 'image.upload', 'bytes', 'actor', 'rolling', 86400, 3600, 268435456, 1073741824, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.upload.unit.bytes', 'image.upload', 'bytes', 'unit', 'rolling', 86400, 3600, 1073741824, 4294967296, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.upload.organization.bytes', 'image.upload', 'bytes', 'organization', 'rolling', 86400, 3600, 10737418240, 42949672960, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('sync.snapshot.bytes', 'sync.snapshot', 'bytes', 'global', 'bytes', NULL, NULL, 4194304, 16777216, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('hold.duration.seconds', 'hold.duration', 'seconds', 'unit', 'duration', NULL, NULL, 900, 900, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.stored.unit', 'occasion.creation', 'items', 'unit', 'occupancy', NULL, NULL, 50, 2000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.stored.organization', 'occasion.creation', 'items', 'organization', 'occupancy', NULL, NULL, 1000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('draft.stored.unit', 'occasion.draft', 'items', 'unit', 'occupancy', NULL, NULL, 20, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('draft.stored.organization', 'occasion.draft', 'items', 'organization', 'occupancy', NULL, NULL, 200, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.backlog.unit', 'email.backlog', 'items', 'unit', 'occupancy', NULL, NULL, 1000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.backlog.organization', 'email.backlog', 'items', 'organization', 'occupancy', NULL, NULL, 5000, 50000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.auth.backlog.organization', 'email.auth.backlog', 'items', 'organization', 'occupancy', NULL, NULL, 1000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.outstanding.unit', 'order.creation', 'items', 'unit', 'occupancy', NULL, NULL, 5000, 20000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.outstanding.organization', 'order.creation', 'items', 'organization', 'occupancy', NULL, NULL, 20000, 100000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('hold.active.buyer', 'spot.hold', 'items', 'recipient', 'occupancy', NULL, NULL, 20, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('sync.snapshot.items', 'sync.snapshot', 'items', 'global', 'occupancy', NULL, NULL, 1000, 5000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.actor.day', 'email.actor', 'operations', 'actor', 'rolling', 86400, 3600, 2000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.fetch.actor.burst', 'image.fetch', 'operations', 'actor', 'rolling', 600, 60, 30, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.fetch.actor.day', 'image.fetch', 'operations', 'actor', 'rolling', 86400, 3600, 200, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.fetch.unit.day', 'image.fetch', 'operations', 'unit', 'rolling', 86400, 3600, 1000, 5000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.fetch.organization.day', 'image.fetch', 'operations', 'organization', 'rolling', 86400, 3600, 5000, 20000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.fetch.payload.bytes', 'image.fetch', 'bytes', 'actor', 'bytes', NULL, NULL, 10485760, 10485760, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.bulk.max_wait.seconds', 'email.dispatch', 'seconds', 'global', 'duration', NULL, NULL, 3600, 21600, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.document.actor.burst', 'ticket.document', 'operations', 'actor', 'rolling', 60, 60, 30, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.document.actor.day', 'ticket.document', 'operations', 'actor', 'rolling', 86400, 3600, 500, 2000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.document.unit.day', 'ticket.document', 'operations', 'unit', 'rolling', 86400, 3600, 2000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.document.organization.day', 'ticket.document', 'operations', 'organization', 'rolling', 86400, 3600, 10000, 50000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.preview.actor.burst', 'ticket.preview', 'operations', 'actor', 'rolling', 60, 60, 20, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.preview.unit.day', 'ticket.preview', 'operations', 'unit', 'rolling', 86400, 3600, 1000, 5000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.preview.organization.day', 'ticket.preview', 'operations', 'organization', 'rolling', 86400, 3600, 5000, 20000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('bank.operation.actor.day', 'bank.operation', 'operations', 'actor', 'rolling', 86400, 3600, 50, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('bank.operation.account.burst', 'bank.operation', 'operations', 'recipient', 'rolling', 60, 60, 5, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('bank.operation.global.day', 'bank.operation', 'operations', 'global', 'rolling', 86400, 3600, 1000, 5000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('ticket.preview.payload.bytes', 'ticket.preview', 'bytes', 'actor', 'bytes', NULL, NULL, 40000, 40000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.copy.items', 'occasion.copy', 'items', 'unit', 'items', NULL, NULL, 30000, 100000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('occasion.copy.bytes', 'occasion.copy', 'bytes', 'unit', 'bytes', NULL, NULL, 33554432, 134217728, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.operation.unit.burst', 'scan.operation', 'operations', 'unit', 'rolling', 60, 60, 2000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.operation.organization.burst', 'scan.operation', 'operations', 'organization', 'rolling', 60, 60, 10000, 30000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.invalid.global.burst', 'scan.invalid.global', 'operations', 'global', 'rolling', 60, 60, 600, 3000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.invalid.source.burst', 'scan.invalid.source', 'operations', 'recipient', 'rolling', 60, 60, 30, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.password.account', 'scan.password', 'operations', 'recipient', 'rolling', 900, 300, 3, 3, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.password.unit.burst', 'scan.password', 'operations', 'unit', 'rolling', 60, 60, 30, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('reception.create.actor', 'reception.create', 'operations', 'actor', 'rolling', 60, 60, 20, 40, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('reception.issue.actor', 'reception.issue', 'operations', 'actor', 'rolling', 60, 60, 30, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('reception.revoke.actor', 'reception.revoke', 'operations', 'actor', 'rolling', 60, 60, 30, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('reception.cancel.actor', 'reception.cancel', 'operations', 'actor', 'rolling', 60, 60, 30, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.export.items', 'scan.export', 'items', 'unit', 'items', NULL, NULL, 30000, 100000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('scan.export.bytes', 'scan.export', 'bytes', 'unit', 'bytes', NULL, NULL, 33554432, 67108864, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.mutation.actor.burst', 'order.mutation', 'operations', 'actor', 'rolling', 60, 60, 60, 300, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.mutation.unit.burst', 'order.mutation', 'operations', 'unit', 'rolling', 60, 60, 600, 3000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.mutation.organization.burst', 'order.mutation', 'operations', 'organization', 'rolling', 60, 60, 2000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('order.mutation.items', 'order.mutation', 'items', 'unit', 'items', NULL, NULL, 2000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.calls.unit.day', 'push.delivery', 'operations', 'unit', 'rolling', 86400, 3600, 50, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.calls.organization.day', 'push.delivery', 'operations', 'organization', 'rolling', 86400, 3600, 200, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.calls.global.day', 'push.delivery', 'operations', 'global', 'rolling', 86400, 3600, 500, 2000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.targets.unit.day', 'push.delivery', 'operations', 'unit', 'rolling', 86400, 3600, 50000, 200000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.targets.organization.day', 'push.delivery', 'operations', 'organization', 'rolling', 86400, 3600, 100000, 500000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.payload.bytes', 'push.delivery', 'bytes', 'unit', 'bytes', NULL, NULL, 16384, 65536, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.delivery.targets', 'push.delivery', 'items', 'unit', 'items', NULL, NULL, 10000, 20000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.delivery.age.seconds', 'push.delivery', 'seconds', 'unit', 'duration', NULL, NULL, 86400, 172800, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.calls.actor.day', 'push.delivery', 'operations', 'actor', 'rolling', 86400, 3600, 50, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.targets.global.day', 'push.delivery', 'operations', 'global', 'rolling', 86400, 3600, 200000, 1000000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('cleaning.report.actor', 'cleaning.report', 'operations', 'actor', 'rolling', 900, 300, 5, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('cleaning.note.bytes', 'cleaning.report', 'bytes', 'actor', 'bytes', NULL, NULL, 4096, 16384, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('cleaning.report.bytes', 'cleaning.report', 'bytes', 'actor', 'bytes', NULL, NULL, 65536, 262144, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.dispatch.unit.burst', 'push.dispatch', 'operations', 'unit', 'rolling', 60, 60, 30, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('push.dispatch.global.burst', 'push.dispatch', 'operations', 'global', 'rolling', 60, 60, 300, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.send.ordinary.recipient.burst', 'email.send.ordinary', 'operations', 'recipient', 'rolling', 60, 60, 6, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.send.ordinary.recipient.day', 'email.send.ordinary', 'operations', 'recipient', 'rolling', 86400, 3600, 20, 40, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.send.auth.recipient.burst', 'email.send.auth', 'operations', 'recipient', 'rolling', 60, 60, 1, 2, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.send.auth.recipient.day', 'email.send.auth', 'operations', 'recipient', 'rolling', 86400, 3600, 10, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.send.commitment.recipient.burst', 'email.send.commitment', 'operations', 'recipient', 'rolling', 60, 60, 30, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('email.send.commitment.recipient.day', 'email.send.commitment', 'operations', 'recipient', 'rolling', 86400, 3600, 120, 500, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.actor.burst', 'image.records', 'operations', 'actor', 'rolling', 600, 60, 60, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.unit.burst', 'image.records', 'operations', 'unit', 'rolling', 600, 60, 120, 500, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.organization.burst', 'image.records', 'operations', 'organization', 'rolling', 600, 60, 600, 2000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.actor.day', 'image.records', 'operations', 'actor', 'rolling', 86400, 3600, 500, 2000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.unit.day', 'image.records', 'operations', 'unit', 'rolling', 86400, 3600, 2000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.organization.day', 'image.records', 'operations', 'organization', 'rolling', 86400, 3600, 10000, 50000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.link.bytes', 'image.records', 'bytes', 'actor', 'bytes', NULL, NULL, 2048, 8192, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.stored.unit', 'image.records', 'items', 'unit', 'occupancy', NULL, NULL, 10000, 100000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.records.stored.organization', 'image.records', 'items', 'organization', 'occupancy', NULL, NULL, 100000, 1000000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('password.verify.actor.burst', 'auth.password', 'operations', 'actor', 'rolling', 60, 60, 10, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('password.verify.actor.window', 'auth.password', 'operations', 'actor', 'rolling', 900, 60, 30, 60, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('document.input.bytes', 'document.output', 'bytes', 'global', 'bytes', NULL, NULL, 1048576, 4194304, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('document.asset.bytes', 'document.output', 'bytes', 'global', 'bytes', NULL, NULL, 5242880, 10485760, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('document.output.bytes', 'document.output', 'bytes', 'global', 'bytes', NULL, NULL, 16777216, 33554432, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('document.output.pages', 'document.output', 'items', 'global', 'items', NULL, NULL, 20, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.storage.unit.bytes', 'image.storage', 'bytes', 'unit', 'cumulative', NULL, NULL, 2147483648, 21474836480, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.storage.organization.bytes', 'image.storage', 'bytes', 'organization', 'cumulative', NULL, NULL, 21474836480, 107374182400, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('image.storage.global.bytes', 'image.storage', 'bytes', 'global', 'cumulative', NULL, NULL, 107374182400, 500000000000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('monitor.auth.age.seconds', 'monitor.thresholds', 'seconds', 'global', 'duration', NULL, NULL, 60, 300, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('monitor.commitment.age.seconds', 'monitor.thresholds', 'seconds', 'global', 'duration', NULL, NULL, 300, 1800, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('monitor.ordinary.age.seconds', 'monitor.thresholds', 'seconds', 'global', 'duration', NULL, NULL, 3600, 21600, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('monitor.cleanup.age.seconds', 'monitor.thresholds', 'seconds', 'global', 'duration', NULL, NULL, 300, 1800, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('monitor.growth.age.seconds', 'monitor.thresholds', 'seconds', 'global', 'duration', NULL, NULL, 900, 3600, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('monitor.provider.quota.age.seconds', 'monitor.thresholds', 'seconds', 'global', 'duration', NULL, NULL, 3600, 21600, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('password.change.actor.burst', 'auth.password.change', 'operations', 'actor', 'rolling', 60, 60, 30, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('password.change.account.window', 'auth.password.change', 'operations', 'recipient', 'rolling', 900, 60, 3, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('password.change.payload.bytes', 'auth.password.change', 'bytes', 'actor', 'bytes', NULL, NULL, 1024, 4096, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('stripe.connect.actor.day', 'stripe.connect', 'operations', 'actor', 'rolling', 86400, 3600, 30, 100, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('stripe.connect.unit.burst', 'stripe.connect', 'operations', 'unit', 'rolling', 60, 60, 5, 20, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('stripe.connect.organization.day', 'stripe.connect', 'operations', 'organization', 'rolling', 86400, 3600, 100, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('stripe.checkout.token.minute', 'stripe.checkout', 'operations', 'actor', 'rolling', 60, 60, 5, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('stripe.checkout.unit.minute', 'stripe.checkout', 'operations', 'unit', 'rolling', 60, 60, 100, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('stripe.checkout.organization.day', 'stripe.checkout', 'operations', 'organization', 'rolling', 86400, 3600, 5000, 10000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('batch-document.actor.burst', 'batch-document', 'operations', 'actor', 'rolling', 600, 60, 300, 1000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('batch-document.unit.burst', 'batch-document', 'operations', 'unit', 'rolling', 600, 60, 1000, 5000, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('batch-create.items', 'batch-create', 'operations', 'unit', 'items', NULL, NULL, 200, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('barion.checkout.token.minute', 'barion.checkout', 'operations', 'actor', 'rolling', 60, 60, 5, 10, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('barion.checkout.unit.minute', 'barion.checkout', 'operations', 'unit', 'rolling', 60, 60, 100, 200, 'none', 0);
INSERT INTO public.abuse_policy_rules VALUES ('barion.checkout.organization.day', 'barion.checkout', 'operations', 'organization', 'rolling', 86400, 3600, 5000, 10000, 'none', 0);


--
-- Data for Name: canonical_asset_cutover; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.canonical_asset_cutover VALUES (true, false, NULL);


--
-- Data for Name: client_sync_component_sources; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.client_sync_component_sources VALUES (1, 'occasion_config', 'public.images', 'images.occasion', '{id,link,occasion}', '{add_image_record,remove_image_records}', '{}', 'migrate', 'occasion_image_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_profile', 'public.user_group_info', 'user_group_info.occasion/members', '{title,description,type,place,data}', '{save_user_group_client_sync_v1,delete_user_group_client_sync_v1,replace_group_assignments_client_sync_v1,import_profiles_client_sync_v1,game_guess_client_sync_v1,delete_occasion_user_client_sync_v1,delete_owned_companion_internal_v1,record_account_deletion_sync_v1,delete_occasion_internal_v1,create_reception_user_v1,import_users_from_tickets_client_sync_v1,cancel_reception_registration_v1}', '{import_user_group_assignments,import_occasion_users_from_csv,delete_occasion_user,delete_occasion_user_ws,game_guess,"process_occasion_auto_import/service ticket import"}', 'migrate', 'user_group_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_profile', 'public.user_groups', 'group -> occasion/members', '{user,group,is_admin}', '{save_user_group_client_sync_v1,delete_user_group_client_sync_v1,replace_group_assignments_client_sync_v1,import_profiles_client_sync_v1,delete_occasion_user_client_sync_v1,delete_owned_companion_internal_v1,record_account_deletion_sync_v1,delete_occasion_internal_v1,create_reception_user_v1,game_guess_client_sync_v1,import_users_from_tickets_client_sync_v1,cancel_reception_registration_v1}', '{import_user_group_assignments,import_occasion_users_from_csv,delete_occasion_user,delete_occasion_user_ws,game_guess,"process_occasion_auto_import/service ticket import"}', 'migrate', 'user_group_membership_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_activity', 'public.activities', 'activities.occasion', '{title,description,data,type,is_hidden,order}', '{publish_activities_client_sync_v1,delete_occasion_user_client_sync_v1,delete_owned_companion_internal_v1,record_account_deletion_sync_v1,delete_occasion_internal_v1,import_users_from_tickets_client_sync_v1,cancel_reception_registration_v1}', '{update_activities,shift_occasion_schedule_backward,"process_occasion_auto_import/service ticket import"}', 'migrate', 'activity_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_activity', 'public.activity_assignments', 'activity -> activities.occasion', '{activity_id,user,start_time,end_time,title,description,data}', '{publish_activities_client_sync_v1,delete_occasion_user_client_sync_v1,delete_owned_companion_internal_v1,record_account_deletion_sync_v1,delete_occasion_internal_v1,import_users_from_tickets_client_sync_v1,cancel_reception_registration_v1}', '{update_activities,shift_occasion_schedule_backward,"process_occasion_auto_import/service ticket import"}', 'migrate', 'activity_assignment_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_activity', 'public.activity_assignment_places', 'assignment -> activity -> occasion', '{assignment_id,place_id}', '{publish_activities_client_sync_v1,delete_occasion_user_client_sync_v1,delete_owned_companion_internal_v1,record_account_deletion_sync_v1,delete_occasion_internal_v1,import_users_from_tickets_client_sync_v1,cancel_reception_registration_v1}', '{update_activities,shift_occasion_schedule_backward,"process_occasion_auto_import/service ticket import"}', 'migrate', 'activity_assignment_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_activity', 'public.activity_assignment_events', 'assignment -> activity -> occasion', '{assignment_id,event_id}', '{publish_activities_client_sync_v1,delete_occasion_user_client_sync_v1,delete_owned_companion_internal_v1,record_account_deletion_sync_v1,delete_occasion_internal_v1,import_users_from_tickets_client_sync_v1,cancel_reception_registration_v1}', '{update_activities,shift_occasion_schedule_backward,"process_occasion_auto_import/service ticket import"}', 'migrate', 'activity_assignment_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_profile', 'public.places', 'places -> owning/referencing groups -> members/companion owners', '{title,description,coordinates,icon,is_hidden,type}', '{save_user_group_client_sync_v1,delete_user_group_client_sync_v1,save_place_client_sync_v1,move_place_client_sync_v1,delete_place_client_sync_v1}', '{save_place_location,"shared map direct DML"}', 'migrate', 'canonical_group_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', '0', 'form -> forms.occasion', '{offer_id,participant_id,outcome,resulting_order_id}', '{execute_waitlist_command_client_sync_v1,expire_waitlist_offers,abort_fakturoid_ticket_order_v1}', '{}', 'migrate', 'waitlist_slot_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'public.forms', 'forms.occasion', '{blueprint,waitlist_enabled,capacity_revision,participant_capacity,data,waitlist_offer_duration_seconds,show_remaining_capacity}', '{storno_order_client_sync_v1,complete_stripe_connection_flow_internal,expire_waitlist_offers,publish_seating_transitions,execute_waitlist_command_client_sync_v1,save_occasion_client_sync_v1,update_form_client_sync_v1,storno_tickets_client_sync_v1}', '{}', 'migrate', 'form_capacity_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.orders', 'orders.occasion', '{source_waitlist_order_id,data,state,email_payment_version}', '{complete_fakturoid_ticket_order_v1,abort_fakturoid_ticket_order_v1,execute_waitlist_command_client_sync_v1,ingest_stripe_payment_internal,decide_stripe_partial_refund_client_sync_v1,sell_ticket_batch_items_client_sync_v1,create_ticket_batch_client_sync_v1,create_ticket_order_client_sync_v1,repair_order_email_client_sync_v1}', '{}', 'migrate', 'waitlist_order_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.waitlist_offers', 'form -> forms.occasion', '{order_id,revision,form_id,expires_at}', '{execute_waitlist_command_client_sync_v1}', '{}', 'migrate', 'waitlist_offer_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.waitlist_offer_slots', 'form -> forms.occasion', '{offer_id,ticket_id,outcome,resulting_order_id}', '{execute_waitlist_command_client_sync_v1,expire_waitlist_offers,abort_fakturoid_ticket_order_v1}', '{}', 'migrate', 'waitlist_slot_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.stripe_payment_movements', 'attempt_id -> stripe_checkout_attempts.order_id -> orders.occasion', '{provider_id,kind,amount_minor,currency,occurred_at}', '{ingest_stripe_payment_internal}', '{}', 'migrate', 'database/tests/eshop/stripe/create_order_test.sql', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.stripe_disputes', 'attempt_id -> stripe_checkout_attempts.order_id -> orders.occasion', '{provider_id,amount_minor,status,observed_at}', '{ingest_stripe_payment_internal}', '{}', 'migrate', 'database/tests/eshop/stripe/create_order_test.sql', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.ticket_batches', 'ticket_batches.occasion', '{stock_order_id,snapshot,manifest_hash}', '{create_ticket_batch_client_sync_v1,complete_ticket_batch_resources_internal}', '{}', 'migrate', 'database/tests/eshop/ticket_batches/lifecycle_test.sql', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.ticket_batch_items', 'batch_id -> ticket_batches.occasion', '{ticket_id,ordinal,sale_order_id}', '{create_ticket_batch_client_sync_v1,sell_ticket_batch_items_client_sync_v1,void_ticket_batch_items_client_sync_v1}', '{}', 'migrate', 'database/tests/eshop/ticket_batches/lifecycle_test.sql', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.ticket_batch_document_parts', 'batch_id -> ticket_batches.occasion', '{state,content_digest,byte_count}', '{complete_ticket_batch_resources_internal,claim_ticket_batch_document,complete_ticket_batch_document_internal,fail_ticket_batch_document_internal}', '{}', 'migrate', 'database/tests/eshop/ticket_batches/lifecycle_test.sql', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.order_product_ticket', 'order -> orders.occasion', '{order,ticket,product}', '{create_ticket_batch_client_sync_v1,sell_ticket_batch_items_client_sync_v1,void_ticket_batch_items_client_sync_v1}', '{}', 'migrate', 'database/tests/eshop/ticket_batches/lifecycle_test.sql', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.tickets', 'tickets.occasion', '{waitlist_queue_at,data,state}', '{sell_ticket_batch_items_client_sync_v1,create_ticket_batch_client_sync_v1,create_ticket_order_client_sync_v1,storno_order_client_sync_v1,expire_waitlist_offers,abort_fakturoid_ticket_order_v1,void_ticket_batch_items_client_sync_v1,execute_waitlist_command_client_sync_v1,ingest_stripe_payment_internal,storno_tickets_client_sync_v1,decide_stripe_partial_refund_client_sync_v1}', '{}', 'migrate', 'waitlist_ticket_factory', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'public.form_seating_transitions', 'form_seating_transitions.occasion', '{form,blueprint,state,revision}', '{save_occasion_client_sync_v1,start_seating_configuration,cancel_seating_configuration,set_ticket_seat_assignments,publish_seating_transitions}', '{}', 'migrate', 'database/tests/blueprint/seating_transition_test.sql', false);
INSERT INTO public.client_sync_component_sources VALUES (1, 'private_inventory', 'eshop.spots', 'spots.occasion', '{order_product_ticket,state}', '{set_ticket_seat_assignments}', '{}', 'migrate', 'database/tests/blueprint/seating_assignment_test.sql', false);


--
-- Data for Name: email_capacity; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.email_capacity VALUES (true, NULL, NULL, true, NULL, NULL, NULL, NULL, NULL, NULL, true, NULL, NULL, 0, NULL, NULL, '2026-11-11 00:30:19.227983+00', NULL, 1, 2, 2, NULL, NULL);


--
-- Data for Name: email_templates; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.email_templates VALUES (1, '<p>Obdrželi jsme žádost o smazání účtu v {{appName}}.</p><p><a href="{{confirmationUrl}}">Zkontrolovat a potvrdit smazání účtu</a></p><p>Odkaz platí do {{expiresAt}}. Pouhé otevření odkazu účet nesmaže. Nikomu jej nepřeposílejte.</p>', NULL, 'Potvrďte smazání účtu v {{appName}}', NULL, 'ACCOUNT_DELETION_CONFIRM', NULL, 'Smazání účtu - potvrzení');
INSERT INTO public.email_templates VALUES (2, '<p>Váš účet v {{appName}} byl smazán. Soukromá účastnická data a propojená push identita byly odstraněny; právně vyžadované záznamy mohou zůstat pouze bez přímé identity.</p>', NULL, 'Účet v {{appName}} byl smazán', NULL, 'ACCOUNT_DELETION_COMPLETE', NULL, 'Smazání účtu - dokončeno');
INSERT INTO public.email_templates VALUES (3, '{{appLinks}}', NULL, 'Aplikace {{appName}}', NULL, 'APP_LINKS', NULL, 'Odkazy na aplikaci');
INSERT INTO public.email_templates VALUES (12, '<h2>Pozvánka do týmu akce {{eventTitle}}</h2><p>{{appName}} zve ke spolupráci na správě akce s oprávněním {{roleLabel}}.</p><p><a href="{{invitationUrl}}">Zobrazit a přijmout pozvánku</a></p><p>Pozvánka platí 14 dní. Přijetí vyžaduje přihlášení k pozvanému účtu nebo vytvoření nového účtu s vlastním heslem.</p>', NULL, 'Pozvánka ke správě akce - {{eventTitle}}', NULL, 'TEAM_INVITATION', NULL, NULL);
INSERT INTO public.email_templates VALUES (13, '<h2>Přístup k akci {{eventTitle}}</h2><p>V aplikaci {{appName}} je dostupná akce s oprávněním {{roleLabel}}.</p><p><a href="{{eventUrl}}">Otevřít správu akce</a></p><p>Přihlaste se svým účtem. Pokud heslo neznáte, použijte na přihlašovací stránce odkaz pro obnovu hesla. Tato zpráva heslo nemění.</p>', NULL, 'Přístup k akci - {{eventTitle}}', NULL, 'TEAM_ACCESS_NOTICE', NULL, NULL);
INSERT INTO public.email_templates VALUES (9, '<h2>{{waitlist_confirmation_heading}}</h2><p>Potvrzujeme přihlášku <strong>{{order_symbol}}</strong> pro {{participant_phrase}} na {{occasion_title}}.</p><p>{{waitlist_confirmation_explanation}}</p><p>{{manage_waitlist_button}}</p>', NULL, 'Potvrzení zařazení mezi náhradníky - {{occasion_title}}', NULL, 'waitlist_confirmation', NULL, NULL);
INSERT INTO public.email_templates VALUES (10, '<h2>{{waitlist_offer_heading}}</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_places}}. Nabídka platí do <span style="white-space:nowrap">{{offer_expires_at}}</span>.</p><p>{{waitlist_offer_instructions}}</p><p>{{offer_button}}</p>', NULL, 'Nabídka pro {{offered_places}} - {{occasion_title}}', NULL, 'waitlist_offer', NULL, NULL);
INSERT INTO public.email_templates VALUES (11, '<h2>{{occasion_title}}</h2><p>Přehled přihlášky {{order_symbol}}, objednávek, evidovaných úhrad a vstupenek:</p><p>{{order_overview_button}}</p>', NULL, 'Přehled objednávky - {{occasion_title}}', NULL, 'ORDER_OVERVIEW', NULL, NULL);
INSERT INTO public.email_templates VALUES (4, '<p>Ahoj,</p>
<p>Tvá objednávka na akci {{occasionTitle}} byla změněna.</p>
{{changeOverview}}
{{balanceReasoning}}
{{fullOrder}}
<p>&nbsp;</p>
<p>Přejeme pěkný den</p>
<p>Organizační tým {{occasionTitle}}</p>', NULL, '{{occasionTitle}} - Změna objednávky - {{orderSymbol}}', NULL, 'TICKET_ORDER_UPDATE', NULL, 'TICKET_ORDER_UPDATE');
INSERT INTO public.email_templates VALUES (5, '<p>Ahoj,</p>
{{balanceReasoning}}
{{fullOrder}}
<p>Přejeme pěkný den</p>
<p>Organizační tým {{occasionTitle}}</p>', NULL, '{{occasionTitle}} - Připomínka objednávky - {{orderSymbol}}', NULL, 'TICKET_ORDER_REMINDER', NULL, 'TICKET_ORDER_REMINDER');
INSERT INTO public.email_templates VALUES (6, '<h3>Tvá platba na akci {{occasionTitle}} dorazila</h3>
<p>Ahoj,<br>
potvrzujeme přijetí platby za Tvou registraci na akci {{occasionTitle}}.</p>
{{balanceReasoning}}
<p>Těšíme se na setkání!</p>
<p>Organizační tým {{occasionTitle}}</p>
<p>Symbol objednávky: <strong>{{orderSymbol}}</strong></p>', NULL, '{{occasionTitle}} - Přijatá platba - {{orderSymbol}}', NULL, 'TICKET_ORDER_PAYMENT_DONE', NULL, 'TICKET_ORDER_PAYMENT_DONE');
INSERT INTO public.email_templates VALUES (7, '<p>Ahoj,</p>
<p>Tvá objednávka na akci {{occasionTitle}} byla stornována.</p>
<p>&nbsp;</p>
<p>Přejeme pěkný den</p>
<p>Organizační tým {{occasionTitle}}</p>
<p>Symbol objednávky: <strong>{{orderSymbol}}</strong></p>', NULL, '{{occasionTitle}} - Storno rezervace - {{orderSymbol}}', NULL, 'TICKET_ORDER_STORNO', NULL, 'TICKET_ORDER_STORNO');
INSERT INTO public.email_templates VALUES (8, '<h3>{{occasionTitle}}</h3>
<p>Ahoj, potvrzujeme Tvou registraci na akci <strong>{{occasionTitle}}</strong>.</p>
{{balanceReasoning}}
{{fullOrder}}
<p>Těšíme se na setkání!</p>
<p>Organizační tým {{occasionTitle}}</p>
', NULL, '{{occasionTitle}} - Potvrzení objednávky - {{orderSymbol}}', NULL, 'TICKET_ORDER_CONFIRMATION', NULL, 'TICKET_ORDER_CONFIRMATION');
INSERT INTO public.email_templates VALUES (14, '<h2>{{sale_opening_heading}}</h2><p>{{occasion_title}}</p><p>{{sale_opening_action}}</p><p>{{sale_opening_disclaimer}}</p><p>{{sale_opening_unsubscribe}}</p>', NULL, '{{sale_opening_subject}} - {{occasion_title}}', NULL, 'sale_opening_opened', NULL, NULL);


--
-- Data for Name: notification_runtime; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.notification_runtime VALUES (true, NULL);


--
-- Data for Name: wix_billing_activation; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.wix_billing_activation VALUES ('9c099206-ce3d-43de-bd9d-deb96bb4f51e', false, NULL, NULL, NULL, NULL);


--
-- Name: email_templates_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.email_templates_id_seq', 14, true);


--
-- PostgreSQL database dump complete
--


-- Reuse the canonical, checksum-pinned public font registries.
\ir ../../database/seeds/ticket_font_assets.sql
\ir ../../database/seeds/ticket_font_families.sql
-- Installation-local secrets are generated, never captured or copied from replay.
INSERT INTO public.abuse_identity_key VALUES(true,extensions.gen_random_bytes(32));
INSERT INTO eshop.checkout_origin_signing_key(singleton,secret,app_id,organization_id)
VALUES(true,extensions.gen_random_bytes(32),'9c099206-ce3d-43de-bd9d-deb96bb4f51e',3);
SELECT pg_catalog.setval('eshop.bank_account_requests_id_seq',1,false);
SELECT pg_catalog.setval('eshop.bank_account_users_id_seq',1,false);
SELECT pg_catalog.setval('eshop.bank_accounts_id_seq',1,false);
SELECT pg_catalog.setval('eshop.bank_sync_connections_id_seq',1,false);
SELECT pg_catalog.setval('eshop.bank_sync_observation_ids',1,false);
SELECT pg_catalog.setval('eshop.blueprints_id_seq',1,false);
SELECT pg_catalog.setval('eshop.external_services_id_seq',1,false);
SELECT pg_catalog.setval('eshop.order_product_ticket_id_seq',1,false);
SELECT pg_catalog.setval('eshop.orders_history_id_seq',1,false);
SELECT pg_catalog.setval('eshop.orders_id_seq',1,false);
SELECT pg_catalog.setval('eshop.payment_info_id_seq',1,false);
SELECT pg_catalog.setval('eshop.planned_changes_id_seq',1,false);
SELECT pg_catalog.setval('eshop.product_inventory_contexts_id_seq',1,false);
SELECT pg_catalog.setval('eshop.product_price_waves_id_seq',1,false);
SELECT pg_catalog.setval('eshop.product_types_id_seq',1,false);
SELECT pg_catalog.setval('eshop.products_id_seq',1,false);
SELECT pg_catalog.setval('eshop.secrets_id_seq',1,false);
SELECT pg_catalog.setval('eshop.spots_id_seq',1,false);
SELECT pg_catalog.setval('eshop.tickets_id_seq',1,false);
SELECT pg_catalog.setval('eshop.transaction_pairing_events_id_seq',1,false);
SELECT pg_catalog.setval('eshop.transactions_id_seq',1,false);
SELECT pg_catalog.setval('eshop.transactions_log_id_seq',1,false);
SELECT pg_catalog.setval('eshop.unit_bank_accounts_id_seq',1,false);
SELECT pg_catalog.setval('public.activity_history_id_seq',1,false);
SELECT pg_catalog.setval('public.cleaning_reports_id_seq',1,false);
SELECT pg_catalog.setval('public.client_sync_release_revision_seq',1,false);
SELECT pg_catalog.setval('public.email_messages_id_seq',1,false);
SELECT pg_catalog.setval('public.email_templates_id_seq',14,true);
SELECT pg_catalog.setval('public.email_wrappers_id_seq',1,false);
SELECT pg_catalog.setval('public.event_feedback_id_seq',1,false);
SELECT pg_catalog.setval('public.event_groups_event_parent_seq',1,false);
SELECT pg_catalog.setval('public.events_id_seq',1,false);
SELECT pg_catalog.setval('public.exclusive_groups_id_seq',1,false);
SELECT pg_catalog.setval('public.external_sync_maps_id_seq',1,false);
SELECT pg_catalog.setval('public.form_fields_id_seq',1,false);
SELECT pg_catalog.setval('public.forms_id_seq',1,false);
SELECT pg_catalog.setval('public.icons_id_seq',1,false);
SELECT pg_catalog.setval('public.images_id_seq',1,false);
SELECT pg_catalog.setval('public.information_hidden_id_seq',1,false);
SELECT pg_catalog.setval('public.information_id_seq',1,false);
SELECT pg_catalog.setval('public.inventory_contexts_id_seq',1,false);
SELECT pg_catalog.setval('public.inventory_pools_id_seq',1,false);
SELECT pg_catalog.setval('public.log_app_config_id_seq',1,false);
SELECT pg_catalog.setval('public.log_emails_id_seq',1,false);
SELECT pg_catalog.setval('public.news_id_seq',1,false);
SELECT pg_catalog.setval('public.occasions_hidden_id_seq',1,false);
SELECT pg_catalog.setval('public.occasions_id_seq',1,false);
SELECT pg_catalog.setval('public.organizations_id_seq',1,false);
SELECT pg_catalog.setval('public.path_groups_id_seq',1,false);
SELECT pg_catalog.setval('public.place_types_id_seq',1,false);
SELECT pg_catalog.setval('public.places_id_seq',1,false);
SELECT pg_catalog.setval('public.request_secrets_id_seq',1,false);
SELECT pg_catalog.setval('public.resource_slots_id_seq',1,false);
SELECT pg_catalog.setval('public.resources_id_seq',1,false);
SELECT pg_catalog.setval('public.role_info_id_seq',1,false);
SELECT pg_catalog.setval('public.speaker_topics_id_seq',1,false);
SELECT pg_catalog.setval('public.speakers_id_seq',1,false);
SELECT pg_catalog.setval('public.unit_legal_profile_audit_id_seq',1,false);
SELECT pg_catalog.setval('public.units_id_seq',1,false);
SELECT pg_catalog.setval('public.user_group_info_id_seq',1,false);
