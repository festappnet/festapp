-- Conservative proposed defaults, activation requires selected-tenant runtime evidence.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('occasion.create.actor.burst','occasion.creation','actor','rolling',600,60,5,20),
 ('occasion.create.actor.day','occasion.creation','actor','rolling',86400,3600,20,100),
 ('occasion.create.unit.burst','occasion.creation','unit','rolling',600,60,10,40),
 ('occasion.create.unit.day','occasion.creation','unit','rolling',86400,3600,40,200),
 ('occasion.create.organization.burst','occasion.creation','organization','rolling',600,60,40,200),
 ('occasion.create.organization.day','occasion.creation','organization','rolling',86400,3600,200,1000),
 ('occasion.stored.unit','occasion.creation','unit','occupancy',NULL,NULL,50,2000),
 ('occasion.stored.organization','occasion.creation','organization','occupancy',NULL,NULL,1000,10000),
 ('draft.create.actor.burst','occasion.draft','actor','rolling',600,60,10,30),
 ('draft.create.actor.day','occasion.draft','actor','rolling',86400,3600,40,100),
 ('draft.create.organization.day','occasion.draft','organization','rolling',86400,3600,200,1000),
 ('draft.work.actor.burst','occasion.draft','actor','rolling',600,60,20,60),
 ('draft.stored.unit','occasion.draft','unit','occupancy',NULL,NULL,20,100),
 ('draft.stored.organization','occasion.draft','organization','occupancy',NULL,NULL,200,1000),
 ('draft.payload.bytes','occasion.draft','unit','bytes',NULL,NULL,262144,262144),
 ('unit.create.actor.day','unit.creation','actor','rolling',86400,3600,3,10),
 ('unit.create.organization.day','unit.creation','organization','rolling',86400,3600,30,200),
 ('unit.create.global.day','unit.creation','global','rolling',86400,3600,100,1000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('email.ordinary.organization.day','email.ordinary','organization','rolling',86400,3600,2000,20000),
 ('email.ordinary.unit.day','email.ordinary','unit','rolling',86400,3600,500,10000),
 ('email.ordinary.recipient.burst','email.ordinary','recipient','rolling',60,60,6,10),
 ('email.ordinary.recipient.day','email.ordinary','recipient','rolling',86400,3600,20,40),
 ('email.auth.organization.day','email.auth','organization','rolling',86400,3600,1000,10000),
 ('email.auth.recipient.burst','email.auth','recipient','rolling',60,60,1,2),
 ('email.auth.recipient.day','email.auth','recipient','rolling',86400,3600,10,20),
 ('email.auth.global.day','email.auth','global','rolling',86400,3600,10000,50000),
 ('email.backlog.unit','email.backlog','unit','occupancy',NULL,NULL,1000,10000),
 ('email.backlog.organization','email.backlog','organization','occupancy',NULL,NULL,5000,50000),
 ('email.backlog.unit.bytes','email.backlog','unit','bytes',NULL,NULL,33554432,268435456),
 ('email.backlog.organization.bytes','email.backlog','organization','bytes',NULL,NULL,134217728,1073741824),
 ('email.payload.bytes','email.payload','global','bytes',NULL,NULL,16777216,33554432),
 ('email.prepare.organization.burst','email.prepare','organization','rolling',60,60,60,300),
 ('email.prepare.recipient.burst','email.prepare','recipient','rolling',60,60,3,6),
 ('order.create.unit.day','order.creation','unit','rolling',86400,3600,2000,20000),
 ('order.create.organization.day','order.creation','organization','rolling',86400,3600,10000,100000),
 ('qr.exchange.global.burst','qr.global','global','rolling',60,60,600,1200),
 ('qr.exchange.proof.burst','qr.proof','recipient','rolling',60,60,30,30);
-- Growth is earned by orders backed by recorded positive payments, never by
-- traffic, attendee capacity, new accounts or this admission's own usage.
UPDATE public.abuse_policy_rules SET growth_basis='existing_orders',growth_increment=3
 WHERE rule_key='email.ordinary.unit.day';

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,base_limit,hard_cap) VALUES
 ('email.auth.backlog.organization','email.auth.backlog','organization','occupancy',1000,10000),
 ('order.outstanding.unit','order.creation','unit','occupancy',5000,20000),
 ('order.outstanding.organization','order.creation','organization','occupancy',20000,100000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,base_limit,hard_cap) VALUES
 ('qr.payload.bytes','qr.payload','global','bytes',1024,4096);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('hold.active.buyer','spot.hold','recipient','occupancy',NULL,NULL,20,20),
 ('hold.acquire.unit.burst','spot.hold','unit','rolling',60,60,1000,10000),
 ('hold.acquire.organization.burst','spot.hold','organization','rolling',60,60,5000,30000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('reset.source','auth.reset.source','recipient','rolling',900,300,20,40),
 ('reset.account','auth.reset.account','recipient','rolling',900,300,3,3),
 ('google.source','auth.google.source','recipient','rolling',60,60,20,40),
 ('google.client','auth.google.client','recipient','rolling',60,60,30,100),
 ('google.global','auth.google.global','recipient','rolling',60,60,100,300),
 ('google.attempt','auth.google.attempt','recipient','rolling',60,60,10,10),
 ('google.proof','auth.google.proof','recipient','rolling',60,60,5,5);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('image.upload.actor.burst','image.upload','actor','rolling',600,60,30,100),
 ('image.upload.unit.burst','image.upload','unit','rolling',600,60,60,200),
 ('image.upload.actor.bytes','image.upload','actor','rolling',86400,3600,268435456,1073741824),
 ('image.upload.unit.bytes','image.upload','unit','rolling',86400,3600,1073741824,4294967296),
 ('image.upload.organization.bytes','image.upload','organization','rolling',86400,3600,10737418240,42949672960);

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,base_limit,hard_cap) VALUES
 ('hold.duration.seconds','hold.duration','unit','duration',900,900),
 ('sync.snapshot.bytes','sync.snapshot','global','bytes',4194304,16777216),
 ('sync.snapshot.items','sync.snapshot','global','occupancy',1000,5000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('sync.work.source.burst','sync.work','actor','rolling',600,60,10,30);

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('reset.global','auth.reset.source','global','rolling',60,60,300,600),
 ('organization.create.global.day','organization.creation','global','rolling',86400,3600,5,20);
UPDATE public.abuse_policy_rules SET measure_unit='bytes' WHERE rule_key LIKE '%.bytes';
UPDATE public.abuse_policy_rules SET measure_unit='seconds' WHERE kind='duration';
UPDATE public.abuse_policy_rules SET measure_unit='items' WHERE kind='occupancy';

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('email.actor.day','email.actor','actor','rolling',86400,3600,2000,10000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('image.fetch.actor.burst','image.fetch','actor','rolling',600,60,30,100),
 ('image.fetch.actor.day','image.fetch','actor','rolling',86400,3600,200,1000),
 ('image.fetch.unit.day','image.fetch','unit','rolling',86400,3600,1000,5000),
 ('image.fetch.organization.day','image.fetch','organization','rolling',86400,3600,5000,20000),
 ('image.fetch.payload.bytes','image.fetch','actor','bytes',NULL,NULL,10485760,10485760);
UPDATE public.abuse_policy_rules SET measure_unit='bytes' WHERE rule_key='image.fetch.payload.bytes';
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('email.bulk.max_wait.seconds','email.dispatch','global','duration','seconds',3600,21600);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('ticket.document.actor.burst','ticket.document','actor','rolling',60,60,30,100),
 ('ticket.document.actor.day','ticket.document','actor','rolling',86400,3600,500,2000),
 ('ticket.document.unit.day','ticket.document','unit','rolling',86400,3600,2000,10000),
 ('ticket.document.organization.day','ticket.document','organization','rolling',86400,3600,10000,50000),
 ('ticket.preview.actor.burst','ticket.preview','actor','rolling',60,60,20,60),
 ('ticket.preview.unit.day','ticket.preview','unit','rolling',86400,3600,1000,5000),
 ('ticket.preview.organization.day','ticket.preview','organization','rolling',86400,3600,5000,20000),
 ('ticket.preview.payload.bytes','ticket.preview','actor','bytes',NULL,NULL,40000,40000),
 ('bank.operation.actor.day','bank.operation','actor','rolling',86400,3600,50,200),
 ('bank.operation.account.burst','bank.operation','recipient','rolling',60,60,5,20),
 ('bank.operation.global.day','bank.operation','global','rolling',86400,3600,1000,5000);
UPDATE public.abuse_policy_rules SET measure_unit='bytes' WHERE rule_key='ticket.preview.payload.bytes';
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('occasion.copy.items','occasion.copy','unit','items','items',30000,100000),
 ('occasion.copy.bytes','occasion.copy','unit','bytes','bytes',33554432,134217728);
-- Estimated entry throughput: 20 lanes * 1 ticket/second = 1200/minute;
-- 2000 per Unit leaves reserve without growing from attacker requests.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('scan.operation.unit.burst','scan.operation','unit','rolling',60,60,2000,10000),
 ('scan.operation.organization.burst','scan.operation','organization','rolling',60,60,10000,30000),
 ('scan.invalid.global.burst','scan.invalid.global','global','rolling',60,60,600,3000),
 ('scan.invalid.source.burst','scan.invalid.source','recipient','rolling',60,60,30,60),
 ('scan.password.account','scan.password','recipient','rolling',900,300,3,3),
 ('scan.password.unit.burst','scan.password','unit','rolling',60,60,30,60),
 ('reception.create.actor','reception.create','actor','rolling',60,60,20,40),
 ('reception.issue.actor','reception.issue','actor','rolling',60,60,30,60),
 ('reception.revoke.actor','reception.revoke','actor','rolling',60,60,30,60),
 ('reception.cancel.actor','reception.cancel','actor','rolling',60,60,30,60);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('scan.export.items','scan.export','unit','items','items',30000,100000),
 ('scan.export.bytes','scan.export','unit','bytes','bytes',33554432,67108864);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('order.mutation.actor.burst','order.mutation','actor','rolling',60,60,60,300),
 ('order.mutation.unit.burst','order.mutation','unit','rolling',60,60,600,3000),
 ('order.mutation.organization.burst','order.mutation','organization','rolling',60,60,2000,10000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('order.mutation.items','order.mutation','unit','items','items',2000,10000);
-- Push costs count requested recipient targets; provider subscription fan-out is
-- separately constrained by its account contract, not falsely equated to users.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('push.calls.unit.day','push.delivery','unit','rolling',86400,3600,50,200),
 ('push.calls.organization.day','push.delivery','organization','rolling',86400,3600,200,1000),
 ('push.calls.global.day','push.delivery','global','rolling',86400,3600,500,2000),
 ('push.targets.unit.day','push.delivery','unit','rolling',86400,3600,50000,200000),
 ('push.targets.organization.day','push.delivery','organization','rolling',86400,3600,100000,500000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('push.payload.bytes','push.delivery','unit','bytes','bytes',16384,65536),
 ('push.delivery.targets','push.delivery','unit','items','items',10000,20000),
 ('push.delivery.age.seconds','push.delivery','unit','duration','seconds',86400,172800);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('push.calls.actor.day','push.delivery','actor','rolling',86400,3600,50,200),
 ('push.targets.global.day','push.delivery','global','rolling',86400,3600,200000,1000000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('cleaning.report.actor','cleaning.report','actor','rolling',900,300,5,10);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('cleaning.note.bytes','cleaning.report','actor','bytes','bytes',4096,16384),
 ('cleaning.report.bytes','cleaning.report','actor','bytes','bytes',65536,262144);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('push.dispatch.unit.burst','push.dispatch','unit','rolling',60,60,30,100),
 ('push.dispatch.global.burst','push.dispatch','global','rolling',60,60,300,1000);

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('email.send.ordinary.recipient.burst','email.send.ordinary','recipient','rolling',60,60,6,10),
 ('email.send.ordinary.recipient.day','email.send.ordinary','recipient','rolling',86400,3600,20,40),
 ('email.send.auth.recipient.burst','email.send.auth','recipient','rolling',60,60,1,2),
 ('email.send.auth.recipient.day','email.send.auth','recipient','rolling',86400,3600,10,20),
 ('email.send.commitment.recipient.burst','email.send.commitment','recipient','rolling',60,60,30,60),
 ('email.send.commitment.recipient.day','email.send.commitment','recipient','rolling',86400,3600,120,500);

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('image.records.actor.burst','image.records','actor','rolling',600,60,60,200),
 ('image.records.unit.burst','image.records','unit','rolling',600,60,120,500),
 ('image.records.organization.burst','image.records','organization','rolling',600,60,600,2000),
 ('image.records.actor.day','image.records','actor','rolling',86400,3600,500,2000),
 ('image.records.unit.day','image.records','unit','rolling',86400,3600,2000,10000),
 ('image.records.organization.day','image.records','organization','rolling',86400,3600,10000,50000);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('image.records.link.bytes','image.records','actor','bytes','bytes',2048,8192),
 ('image.records.stored.unit','image.records','unit','occupancy','items',10000,100000),
 ('image.records.stored.organization','image.records','organization','occupancy','items',100000,1000000);

-- Permanent reusable passwords: attempts are bounded independently of delivery.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('password.verify.actor.burst','auth.password','actor','rolling',60,60,10,20),
 ('password.verify.actor.window','auth.password','actor','rolling',900,60,30,60);

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('document.input.bytes','document.output','global','bytes','bytes',1048576,4194304),
 ('document.asset.bytes','document.output','global','bytes','bytes',5242880,10485760),
 ('document.output.bytes','document.output','global','bytes','bytes',16777216,33554432),
 ('document.output.pages','document.output','global','items','items',20,100);

-- Allocation is conservative and permanent: failed/overwritten/deleted objects
-- never automatically refund capacity. Existing R2 objects remain the fixed
-- historical baseline; these caps bound all additional storage after activation.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('image.storage.unit.bytes','image.storage','unit','cumulative','bytes',2147483648,21474836480),
 ('image.storage.organization.bytes','image.storage','organization','cumulative','bytes',21474836480,107374182400),
 ('image.storage.global.bytes','image.storage','global','cumulative','bytes',107374182400,500000000000);

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('monitor.auth.age.seconds','monitor.thresholds','global','duration','seconds',60,300),
 ('monitor.commitment.age.seconds','monitor.thresholds','global','duration','seconds',300,1800),
 ('monitor.ordinary.age.seconds','monitor.thresholds','global','duration','seconds',3600,21600),
 ('monitor.cleanup.age.seconds','monitor.thresholds','global','duration','seconds',300,1800),
 ('monitor.growth.age.seconds','monitor.thresholds','global','duration','seconds',900,3600),
 ('monitor.provider.quota.age.seconds','monitor.thresholds','global','duration','seconds',3600,21600);

INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('password.change.actor.burst','auth.password.change','actor','rolling',60,60,30,100),
 ('password.change.account.window','auth.password.change','recipient','rolling',900,60,3,10);
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,measure_unit,base_limit,hard_cap) VALUES
 ('password.change.payload.bytes','auth.password.change','actor','bytes','bytes',1024,4096);
