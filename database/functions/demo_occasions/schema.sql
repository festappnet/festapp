-- Identity is server-owned and remains protected when removed from the catalogue.
CREATE UNIQUE INDEX IF NOT EXISTS occasions_id_organization_uidx ON public.occasions(id,organization);
CREATE TABLE IF NOT EXISTS public.demo_occasions (
 occasion bigint PRIMARY KEY,
 organization bigint NOT NULL REFERENCES public.organizations(id),
 demo_key text NOT NULL CHECK(demo_key IN ('ball','concert','weekend')),
 fixture_version text NOT NULL,
 bank_account bigint NOT NULL UNIQUE REFERENCES eshop.bank_accounts(id),
 is_listed boolean NOT NULL DEFAULT false,
 sort_order integer NOT NULL,
 description text NOT NULL,
 reference_at timestamptz NOT NULL,
 UNIQUE(organization,demo_key,fixture_version),
 FOREIGN KEY(occasion,organization) REFERENCES public.occasions(id,organization)
);
CREATE UNIQUE INDEX IF NOT EXISTS demo_occasions_listed_uidx
 ON public.demo_occasions(organization,demo_key) WHERE is_listed;
ALTER TABLE public.demo_occasions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.demo_occasions FROM PUBLIC,anon,authenticated,service_role;
