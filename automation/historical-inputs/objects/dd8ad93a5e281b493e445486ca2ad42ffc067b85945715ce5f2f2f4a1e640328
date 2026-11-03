-- Legal identity belongs to Unit; never store approval or drafts in units.data.
CREATE TABLE public.unit_legal_profiles (
 unit_id bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 revision bigint NOT NULL CHECK (revision > 0),
 status text NOT NULL DEFAULT 'unverified' CHECK (status IN ('unverified','pending','verified','rejected','revoked')),
 legal_name text NOT NULL DEFAULT '' CHECK (length(legal_name)<=200),
 country_code text NOT NULL DEFAULT '' CHECK (country_code='' OR country_code ~ '^[A-Z]{2}$'),
 registration_number text NOT NULL DEFAULT '' CHECK (length(registration_number)<=50),
 vat_id text NOT NULL DEFAULT '' CHECK (length(vat_id)<=50),
 street text NOT NULL DEFAULT '' CHECK (length(street)<=200),
 city text NOT NULL DEFAULT '' CHECK (length(city)<=100),
 postal_code text NOT NULL DEFAULT '' CHECK (length(postal_code)<=20),
 contact_email text NOT NULL DEFAULT '' CHECK (length(contact_email)<=254),
 phone text NOT NULL DEFAULT '' CHECK (length(phone)<=40),
 website text NOT NULL DEFAULT '' CHECK (length(website)<=500),
 submitted_at timestamptz, submitted_by uuid,
 reviewed_at timestamptz, reviewed_by uuid, reviewed_organization_id bigint,
 feedback_to_applicant text, review_note text, review_source text,
 CHECK (length(feedback_to_applicant)<=4000 AND length(review_note)<=4000 AND length(review_source)<=2000)
);
CREATE INDEX unit_legal_profiles_queue_idx ON public.unit_legal_profiles(status,submitted_at,unit_id);
CREATE TABLE public.unit_legal_profile_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 unit_id bigint NOT NULL, organization_id bigint NOT NULL, revision bigint NOT NULL,
 actor_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
 action text NOT NULL CHECK (action IN ('save','submit','approve','reject','revoke')),
 snapshot jsonb NOT NULL,
 UNIQUE(unit_id,revision)
);
ALTER TABLE public.unit_legal_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unit_legal_profile_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.unit_legal_profiles,public.unit_legal_profile_audit FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE public.unit_legal_profile_audit_id_seq FROM PUBLIC,anon,authenticated;
COMMENT ON TABLE public.unit_legal_profile_audit IS 'Append-only RPC-owned history; survives Unit deletion. No sync or public table access.';
