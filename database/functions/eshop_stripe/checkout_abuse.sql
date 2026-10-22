INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('stripe.checkout.token.minute','stripe.checkout','actor','rolling',60,60,5,10),
 ('stripe.checkout.unit.minute','stripe.checkout','unit','rolling',60,60,100,200),
 ('stripe.checkout.organization.day','stripe.checkout','organization','rolling',86400,3600,5000,10000);
