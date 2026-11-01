-- Configuration history only. Physical placement remains eshop.spots.
CREATE TABLE IF NOT EXISTS public.form_seating_transitions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE RESTRICT,
 form bigint REFERENCES public.forms(id) ON DELETE SET NULL,
 blueprint bigint REFERENCES eshop.blueprints(id) ON DELETE SET NULL,
 state text NOT NULL DEFAULT 'organizer_managed' CHECK(state IN ('organizer_managed','published','cancelled')),
 revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 started_by uuid NOT NULL, started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 finished_by uuid, finished_at timestamptz,
 CHECK(state<>'organizer_managed' OR (form IS NOT NULL AND blueprint IS NOT NULL)),
 CHECK((state='organizer_managed' AND finished_at IS NULL AND finished_by IS NULL) OR
       (state<>'organizer_managed' AND finished_at IS NOT NULL AND finished_by IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS form_seating_transitions_active_form ON public.form_seating_transitions(form) WHERE state='organizer_managed';
CREATE INDEX IF NOT EXISTS form_seating_transitions_target ON public.form_seating_transitions(blueprint,state);
ALTER TABLE public.form_seating_transitions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.form_seating_transitions FROM PUBLIC,anon,authenticated,service_role;
