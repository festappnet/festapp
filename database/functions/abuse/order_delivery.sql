-- A separate allowance for checkout receipts and scheduled payment notices.
ALTER TABLE public.email_messages DROP CONSTRAINT email_messages_admission_class_check;
ALTER TABLE public.email_messages ADD CONSTRAINT email_messages_admission_class_check
 CHECK(admission_class IN ('ordinary','auth','commitment','notification','transactional')) NOT VALID;
ALTER TABLE public.email_messages VALIDATE CONSTRAINT email_messages_admission_class_check;

INSERT INTO public.abuse_policy_rules
 (rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap)
VALUES
 ('email.transactional.organization.day','email.transactional','organization','rolling',86400,3600,15000,30000),
 ('email.transactional.unit.day','email.transactional','unit','rolling',86400,3600,5000,10000),
 ('email.transactional.recipient.burst','email.transactional','recipient','rolling',60,60,12,20),
 ('email.transactional.recipient.day','email.transactional','recipient','rolling',86400,3600,60,120),
 ('email.send.transactional.recipient.burst','email.send.transactional','recipient','rolling',60,60,12,20),
 ('email.send.transactional.recipient.day','email.send.transactional','recipient','rolling',86400,3600,60,120);
