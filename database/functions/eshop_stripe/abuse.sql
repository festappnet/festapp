-- Connect uses the existing admission/budget engine; no parallel rate limiter.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('stripe.connect.actor.day','stripe.connect','actor','rolling',86400,3600,30,100),
 ('stripe.connect.unit.burst','stripe.connect','unit','rolling',60,60,5,20),
 ('stripe.connect.organization.day','stripe.connect','organization','rolling',86400,3600,100,1000);

