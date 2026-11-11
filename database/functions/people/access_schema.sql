-- Forward rename preserves token hashes, IDs, acceptance and message references.
DO $$ BEGIN
 IF to_regclass('public.access_invitations') IS NULL THEN
  ALTER TABLE public.occasion_team_invitations RENAME TO access_invitations;
 END IF;
END $$;
ALTER TABLE public.access_invitations ALTER COLUMN draft DROP NOT NULL;
ALTER TABLE public.access_invitations ALTER COLUMN occasion DROP NOT NULL;
ALTER TABLE public.access_invitations DROP CONSTRAINT IF EXISTS occasion_team_invitations_draft_fkey;
ALTER TABLE public.access_invitations ADD CONSTRAINT access_invitation_source_draft_fkey
 FOREIGN KEY(draft) REFERENCES public.occasion_setup_drafts(id) ON DELETE SET NULL;
ALTER TABLE public.access_invitations DROP CONSTRAINT IF EXISTS occasion_team_invitations_draft_email_key;
ALTER TABLE public.access_invitations ADD COLUMN scope_type text;
ALTER TABLE public.access_invitations ADD COLUMN offered_roles jsonb;
-- Stable identity snapshot intentionally survives account deletion as a tombstone.
-- A deleted bound identity invalidates the offer; it never retargets a new account.
ALTER TABLE public.access_invitations ADD COLUMN recipient_user uuid;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.access_invitations i JOIN public.user_info ui ON ui.organization=i.organization AND lower(btrim(ui.email_readonly))=i.email
  WHERE i.accepted_at IS NULL GROUP BY i.id HAVING count(*)>1) THEN
  RAISE invalid_parameter_value USING MESSAGE='ambiguous_invitation_identity'; END IF;
END $$;
UPDATE public.access_invitations i SET recipient_user=coalesce(i.accepted_by,
 (SELECT ui.id FROM public.user_info ui WHERE ui.organization=i.organization AND lower(btrim(ui.email_readonly))=i.email));
ALTER TABLE public.access_invitations ADD COLUMN revoked_at timestamptz;
ALTER TABLE public.access_invitations ADD COLUMN predecessor uuid REFERENCES public.access_invitations(id);
UPDATE public.access_invitations SET scope_type='occasion',offered_roles=jsonb_build_object('is_editor',role='editor','is_editor_view',true);
ALTER TABLE public.access_invitations ALTER COLUMN scope_type SET NOT NULL;
ALTER TABLE public.access_invitations ALTER COLUMN offered_roles SET NOT NULL;
ALTER TABLE public.access_invitations ADD CONSTRAINT access_invitation_scope_check CHECK
 ((scope_type='unit' AND occasion IS NULL) OR (scope_type='occasion' AND occasion IS NOT NULL));
ALTER TABLE public.access_invitations ADD CONSTRAINT access_invitation_roles_check CHECK(jsonb_typeof(offered_roles)='object');
CREATE UNIQUE INDEX IF NOT EXISTS access_unit_identity_key ON public.units(id,organization);
CREATE UNIQUE INDEX IF NOT EXISTS access_occasion_identity_key ON public.occasions(id,unit,organization);
ALTER TABLE public.access_invitations ADD CONSTRAINT access_invitation_unit_scope_fkey
 FOREIGN KEY(unit,organization) REFERENCES public.units(id,organization);
ALTER TABLE public.access_invitations ADD CONSTRAINT access_invitation_occasion_scope_fkey
 FOREIGN KEY(occasion,unit,organization) REFERENCES public.occasions(id,unit,organization);
CREATE INDEX access_invitation_recipient ON public.access_invitations(unit,email) WHERE accepted_at IS NULL AND revoked_at IS NULL;
ALTER TABLE public.access_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.access_invitations FROM PUBLIC,anon,authenticated,service_role;

-- A short-lived trusted render deposit, never a business queue or delivery state.
-- Only the verified Edge renderer writes; the authenticated domain transaction
-- consumes it without changing auth.uid() or trusting client-supplied content.
CREATE TABLE public.access_email_preparations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 command_id uuid NOT NULL, intent_hash text NOT NULL, preview_hash text NOT NULL,
 prepared jsonb NOT NULL, token_hash text, credential bytea,
 expires_at timestamptz NOT NULL DEFAULT now()+interval '15 minutes',
 UNIQUE(actor,command_id), CHECK(intent_hash ~ '^[0-9a-f]{64}$'), CHECK(preview_hash ~ '^[0-9a-f]{64}$')
);
ALTER TABLE public.access_email_preparations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.access_email_preparations FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.access_preparation_key(singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),secret bytea NOT NULL);
INSERT INTO public.access_preparation_key VALUES(true,extensions.gen_random_bytes(32));
ALTER TABLE public.access_preparation_key ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.access_preparation_key FROM PUBLIC,anon,authenticated,service_role;
