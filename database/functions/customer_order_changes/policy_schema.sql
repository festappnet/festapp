-- Additive: no existing form receives permission or a write credential.
ALTER TABLE public.occasions ADD COLUMN customer_self_service_epoch bigint NOT NULL DEFAULT 0;
CREATE TABLE eshop.customer_order_change_policies (
 form_id bigint PRIMARY KEY REFERENCES public.forms(id) ON DELETE CASCADE,
 revision bigint NOT NULL CHECK(revision>0),
 policy jsonb NOT NULL CHECK(jsonb_typeof(policy)='object'),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE eshop.customer_order_change_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.customer_order_change_policies FROM PUBLIC,anon,authenticated,service_role;
