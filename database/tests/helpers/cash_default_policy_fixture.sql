CREATE TEMP TABLE cash_default_policy_cases(kind text,organization_id bigint);
WITH added AS (INSERT INTO public.organizations(title,data) VALUES('Výchozí hotovost','{"DEFAULT_URL":"https://vstupenky.online"}') RETURNING id)
INSERT INTO cash_default_policy_cases SELECT 'legacy',id FROM added;
WITH added AS (INSERT INTO public.organizations(title,data) VALUES('Výslovně vypnutá hotovost','{"DEFAULT_URL":"https://vstupenky.online"}') RETURNING id)
INSERT INTO cash_default_policy_cases SELECT 'explicit',id FROM added;
WITH added AS (INSERT INTO public.organizations(title,data) VALUES('Jiný pořadatel','{"DEFAULT_URL":"https://other.example.invalid"}') RETURNING id)
INSERT INTO cash_default_policy_cases SELECT 'other',id FROM added;
INSERT INTO eshop.organization_payment_method_policies(organization_id,method,enabled)
SELECT organization_id,'cash',false FROM cash_default_policy_cases;
INSERT INTO eshop.payment_method_policy_commands(id,organization_id,actor,input,response)
SELECT gen_random_uuid(),organization_id,gen_random_uuid(),
 jsonb_build_object('organizationId',organization_id,'method','cash','mode','disabled'),'{}'
FROM cash_default_policy_cases WHERE kind='explicit';
