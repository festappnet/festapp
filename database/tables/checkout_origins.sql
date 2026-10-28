-- Provenance only. These records never authorize a purchase or establish a fee.
CREATE TABLE IF NOT EXISTS eshop.checkout_origin_signing_key (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 secret bytea NOT NULL CHECK(octet_length(secret)=32),
 app_id uuid NOT NULL,
 organization_id bigint NOT NULL CHECK(organization_id>0)
);
-- Deployment configuration for the assigned vstupenky.online application.
INSERT INTO eshop.checkout_origin_signing_key(singleton,secret,app_id,organization_id)
 VALUES(true,extensions.gen_random_bytes(32),'9c099206-ce3d-43de-bd9d-deb96bb4f51e',3)
 ON CONFLICT(singleton) DO NOTHING;
CREATE TABLE IF NOT EXISTS eshop.order_checkout_origins (
 order_id bigint PRIMARY KEY REFERENCES eshop.orders(id) ON DELETE CASCADE,
 form_id bigint NOT NULL REFERENCES public.forms(id),
 channel text NOT NULL CHECK(channel='wix'),
 instance_id uuid NOT NULL,
 site_id uuid NOT NULL,
 verified_at timestamptz NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.checkout_origin_signing_key ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.order_checkout_origins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.checkout_origin_signing_key,eshop.order_checkout_origins FROM PUBLIC,anon,authenticated,service_role;
