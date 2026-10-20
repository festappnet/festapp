-- Additive client_sync_v1 expansion. Capability remains off until the release
-- runbook gates (external privileged-DML audit, CDN/Worker, load and smoke)
-- have all passed. This migration deliberately creates no application trigger.
SET lock_timeout = '5s';
SET statement_timeout = '120s';

-- Older hosted installations were created before this base column was added
-- to database/tables/tables.sql and have no timestamped migration for it.
-- Materializers and aggregate responses require one deterministic ordering
-- value, so close that drift idempotently before defining any functions.
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS "order" bigint NOT NULL DEFAULT 0;

-- Unit ownership is part of the canonical icon contract. Older installations
-- may still have organization-only icon rows; NULL unit keeps those rows as
-- read-only compatibility data.
ALTER TABLE public.icons ADD COLUMN IF NOT EXISTS unit bigint
  REFERENCES public.units(id);
ALTER TABLE public.icons ADD COLUMN IF NOT EXISTS created_by uuid
  REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS icons_unit_idx ON public.icons(unit);

CREATE TABLE public.client_sync_component_sources (
  registry_version integer NOT NULL,
  component text NOT NULL,
  source_relation regclass NOT NULL,
  scope_resolver text NOT NULL,
  tracked_columns text[] NOT NULL,
  canonical_writers text[] NOT NULL CHECK (cardinality(canonical_writers) > 0),
  legacy_writers text[] NOT NULL DEFAULT '{}',
  disposition text NOT NULL CHECK (disposition IN ('migrate', 'boundary', 'delete')),
  test_factory text NOT NULL,
  cutover_ready boolean NOT NULL DEFAULT false,
  PRIMARY KEY (registry_version, component, source_relation)
);

CREATE TABLE public.client_sync_scopes (
  component text NOT NULL,
  scope_type text NOT NULL CHECK (scope_type IN ('occasion', 'unit')),
  scope_id bigint NOT NULL,
  source_revision bigint NOT NULL DEFAULT 0 CHECK (source_revision >= 0),
  source_fingerprint text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (component, scope_type, scope_id)
);

CREATE TABLE public.client_sync_private_scopes (
  component text NOT NULL CHECK (component LIKE 'private_%'),
  occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.user_info(id) ON DELETE CASCADE,
  source_revision bigint NOT NULL DEFAULT 0 CHECK (source_revision >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (component, occasion, user_id)
);
CREATE INDEX client_sync_private_scopes_handshake_idx
  ON public.client_sync_private_scopes (occasion, user_id, component, source_revision);

CREATE TABLE public.client_sync_publications (
  component text NOT NULL,
  scope_type text NOT NULL,
  scope_id bigint NOT NULL,
  published_revision bigint NOT NULL CHECK (published_revision >= 0),
  media_type text NOT NULL,
  artifact_url text NOT NULL,
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint NOT NULL CHECK (byte_size >= 0),
  source_fingerprint text,
  published_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (component, scope_type, scope_id, published_revision),
  UNIQUE (sha256)
);

CREATE TABLE public.client_sync_release_manifests (
  scope_type text NOT NULL,
  scope_id bigint NOT NULL,
  release_revision bigint NOT NULL,
  manifest jsonb NOT NULL,
  artifact_url text NOT NULL,
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 16384),
  published_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scope_type, scope_id, release_revision),
  UNIQUE (sha256)
);

CREATE TABLE public.client_sync_public_heads (
  scope_type text NOT NULL,
  scope_id bigint NOT NULL,
  release_revision bigint,
  manifest_sha256 text,
  live_revision bigint,
  live_sha256 text,
  head_etag text NOT NULL,
  head_json jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scope_type, scope_id)
);
-- Composite FK keeps the pointer within its exact scope.
ALTER TABLE public.client_sync_public_heads
  ADD CONSTRAINT client_sync_public_heads_manifest_fkey
  FOREIGN KEY (scope_type, scope_id, release_revision)
  REFERENCES public.client_sync_release_manifests(scope_type, scope_id, release_revision);

CREATE TABLE public.client_commits (
  commit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Scope IDs are immutable audit facts, not ownership FKs: deleting an
  -- occasion or unit must not erase or block its historical ledger.
  occasion bigint,
  unit bigint,
  organization bigint,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_id uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
  actor_display text,
  actor_kind text NOT NULL CHECK (actor_kind IN ('user', 'system', 'service', 'break_glass', 'unknown')),
  source text NOT NULL,
  change_class text NOT NULL,
  client_version text,
  correlation_id uuid,
  db_role name NOT NULL DEFAULT current_user,
  reason text,
  CHECK ((occasion IS NOT NULL)::integer + (unit IS NOT NULL)::integer
    + (organization IS NOT NULL)::integer = 1)
);
CREATE INDEX client_commits_keyset_idx
  ON public.client_commits (occasion, occurred_at DESC, commit_id DESC);
CREATE INDEX client_commits_unit_keyset_idx
  ON public.client_commits (unit, occurred_at DESC, commit_id DESC)
  WHERE unit IS NOT NULL;
CREATE INDEX client_commits_organization_keyset_idx
  ON public.client_commits (organization, occurred_at DESC, commit_id DESC)
  WHERE organization IS NOT NULL;

ALTER TABLE public.queue_emails
  ADD COLUMN IF NOT EXISTS processing_at timestamptz,
  ADD COLUMN IF NOT EXISTS attempt_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_error text;
CREATE UNIQUE INDEX queue_emails_ticket_order_command_idx
  ON public.queue_emails ((data->>'command_id'))
  WHERE code='TICKET_ORDER_CONFIRMATION' AND data ? 'command_id';

-- Transport idempotency is deliberately separate from the audit ledger.
-- Receipts exist for unchanged/rejected/conflict commands as well; commits do
-- not. A domain RPC claims its receipt before any domain DML.
CREATE TABLE public.client_mutation_receipts (
  command_id uuid PRIMARY KEY,
  command_name text NOT NULL CHECK (command_name ~ '^[a-z][a-z0-9_.]{2,95}$'),
  -- Receipt scope IDs survive deletion long enough for exact retry/audit.
  occasion bigint,
  unit bigint,
  actor_id uuid REFERENCES public.user_info(id) ON DELETE CASCADE,
  actor_client_id uuid,
  request_sha256 text NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
  status text NOT NULL DEFAULT 'processing'
    CHECK (status IN ('processing','completed')),
  response jsonb,
  commit_id uuid REFERENCES public.client_commits(commit_id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  CHECK ((actor_id IS NOT NULL)::integer +
    (actor_client_id IS NOT NULL)::integer = 1),
  CHECK ((occasion IS NOT NULL)::integer + (unit IS NOT NULL)::integer = 1),
  CHECK ((status='processing' AND response IS NULL AND completed_at IS NULL)
      OR (status='completed' AND response IS NOT NULL AND completed_at IS NOT NULL))
);
CREATE INDEX client_mutation_receipts_retention_idx
  ON public.client_mutation_receipts (completed_at)
  WHERE status='completed';

CREATE TABLE public.client_aggregate_versions (
  aggregate_type text NOT NULL,
  scope_type text NOT NULL CHECK (scope_type IN ('occasion','unit')),
  scope_id bigint NOT NULL,
  aggregate_id text NOT NULL,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (aggregate_type, scope_type, scope_id, aggregate_id)
);

CREATE TABLE public.client_commit_items (
  commit_id uuid NOT NULL REFERENCES public.client_commits(commit_id) ON DELETE RESTRICT,
  item_index integer NOT NULL,
  entity_type text NOT NULL,
  entity_id text,
  operation text NOT NULL CHECK (operation IN ('insert', 'update', 'delete', 'import', 'publish')),
  safe_label text,
  changed_fields text[] NOT NULL DEFAULT '{}',
  PRIMARY KEY (commit_id, item_index)
);

CREATE TABLE public.client_commit_components (
  commit_id uuid NOT NULL REFERENCES public.client_commits(commit_id) ON DELETE RESTRICT,
  component text NOT NULL,
  scope_type text NOT NULL,
  scope_id bigint NOT NULL,
  user_id uuid,
  resulting_revision bigint NOT NULL,
  UNIQUE NULLS NOT DISTINCT (commit_id, component, scope_type, scope_id, user_id)
);

CREATE TABLE public.client_projection_dirty_keys (
  component text NOT NULL,
  scope_type text NOT NULL,
  scope_id bigint NOT NULL,
  entity_id bigint NOT NULL DEFAULT 0,
  source_revision bigint NOT NULL,
  dirty_since timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  claim_token uuid,
  PRIMARY KEY (component, scope_type, scope_id, entity_id)
);
CREATE INDEX client_projection_dirty_claim_idx
  ON public.client_projection_dirty_keys (dirty_since)
  WHERE claimed_at IS NULL;

CREATE TABLE public.event_public_state (
  occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  event bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  participant_count bigint NOT NULL DEFAULT 0,
  saved_count bigint NOT NULL DEFAULT 0,
  remaining_capacity bigint,
  revision bigint NOT NULL,
  projected_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (occasion, event)
);

CREATE TABLE public.cleaning_public_state (
  occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  place bigint NOT NULL REFERENCES public.places(id) ON DELETE CASCADE,
  status text NOT NULL,
  open_report_count bigint NOT NULL DEFAULT 0,
  revision bigint NOT NULL,
  projected_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (occasion, place)
);

ALTER TABLE public.client_sync_component_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_sync_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_sync_private_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_sync_publications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_sync_release_manifests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_sync_public_heads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_commits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_aggregate_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_commit_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_commit_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_projection_dirty_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_public_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cleaning_public_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.client_sync_component_sources, public.client_sync_scopes,
  public.client_sync_private_scopes, public.client_sync_publications,
  public.client_sync_release_manifests, public.client_sync_public_heads,
  public.client_commits, public.client_mutation_receipts,
  public.client_aggregate_versions, public.client_commit_items,
  public.client_commit_components, public.client_projection_dirty_keys,
  public.event_public_state, public.cleaning_public_state
FROM PUBLIC, anon, authenticated;

INSERT INTO public.client_sync_component_sources
  (registry_version, component, source_relation, scope_resolver, tracked_columns,
   canonical_writers, legacy_writers, disposition, test_factory)
VALUES
  (1,'occasion_config','public.occasions','occasion.id',ARRAY['data','features','is_hidden','is_open','start_time','end_time','title','services'],ARRAY['create_occasion_client_sync_v1','save_occasion_client_sync_v1','create_service_item_client_sync_v1','update_service_item_client_sync_v1','delete_service_item_client_sync_v1','game_update_settings_client_sync_v1','sync_source_via_http_client_sync_v1'],ARRAY['occasion/service/game/external-sync facades'],'migrate','occasion_factory'),
  (1,'unit_catalog','public.units','unit fan-out to visible occasion scopes',ARRAY['title','data','features'],ARRAY['save_unit_client_sync_v1'],ARRAY['update_unit'],'migrate','unit_factory'),
  (1,'unit_catalog','public.occasions','occasion.unit fan-out to visible occasion scopes',ARRAY['unit','title','link','start_time','end_time','description','is_open','is_promoted','is_hidden'],ARRAY['create_occasion_client_sync_v1','save_occasion_client_sync_v1','duplicate_occasion_client_sync_v1','delete_occasion_client_sync_v1','sync_source_via_http_client_sync_v1'],ARRAY['update_occasion_203','duplicate_occasion','delete_occasion','sync_source_via_http'],'migrate','unit_occasion_factory'),
  (1,'program_catalog','public.events','events.occasion',ARRAY['title','start_time','end_time','max_participants','description','place','is_hidden','type','data','order'],ARRAY['save_event_client_sync_v1','delete_event_client_sync_v1','create_counseling_slots_client_sync_v1','delete_empty_counseling_slots_client_sync_v1'],ARRAY['DbEvents direct DML','delete_event'],'migrate','event_factory'),
  (1,'program_catalog','public.event_groups','event_parent -> events.occasion',ARRAY['event_parent','event_child'],ARRAY['save_event_client_sync_v1'],ARRAY[]::text[],'migrate','event_relation_factory'),
  (1,'program_catalog','public.event_roles','event -> events.occasion',ARRAY['event','role'],ARRAY['save_event_client_sync_v1'],ARRAY[]::text[],'migrate','event_relation_factory'),
  (1,'program_catalog','public.event_speakers','event -> events.occasion',ARRAY['event','speaker'],ARRAY['save_event_speakers_client_sync_v1','create_counseling_slots_client_sync_v1','delete_empty_counseling_slots_client_sync_v1'],ARRAY['set_event_speakers'],'migrate','event_speaker_factory'),
  (1,'map_catalog','public.places','places.occasion',ARRAY['title','description','type','coordinates','is_hidden','order','icon'],ARRAY['save_place_client_sync_v1','delete_place_client_sync_v1','save_user_group_client_sync_v1','delete_user_group_client_sync_v1'],ARRAY['DbPlaces direct DML','save_place_location'],'migrate','place_factory'),
  (1,'map_catalog','public.place_types','place_types.occasion',ARRAY['code','title','icon','order','is_hidden','is_default'],ARRAY['save_place_type_client_sync_v1','delete_place_type_client_sync_v1'],ARRAY['DbPlaceTypes direct DML'],'migrate','place_type_factory'),
  (1,'map_catalog','public.path_groups','path_groups.occasion',ARRAY['title','path_data','data','icon','is_hidden','order'],ARRAY['save_path_client_sync_v1','delete_path_client_sync_v1'],ARRAY['DbPlaces direct DML'],'migrate','path_factory'),
  (1,'map_catalog','public.icons','reverse icon dependency',ARRAY['link','data'],ARRAY['save_icon_client_sync_v1','delete_icon_client_sync_v1'],ARRAY['icon admin direct DML'],'migrate','icon_factory'),
  (1,'content_catalog','public.information','information.occasion',ARRAY['title','description','is_hidden','order','type','data'],ARRAY['save_information_client_sync_v1','delete_information_client_sync_v1'],ARRAY['DbInformation direct DML'],'migrate','information_factory'),
  (1,'content_catalog','public.news','news.occasion',ARRAY['message','updated_at'],ARRAY['save_news_client_sync_v1','delete_news_client_sync_v1','publish_news_client_sync_v1'],ARRAY['DbNews direct DML'],'migrate','news_factory'),
  (1,'content_catalog','public.speakers','speakers.occasion',ARRAY['title','subtitle','description','image','order','is_hidden','data'],ARRAY['save_speaker_client_sync_v1','delete_speaker_client_sync_v1'],ARRAY['update_speaker','delete_speaker'],'migrate','speaker_factory'),
  (1,'content_catalog','public.speaker_topics','speaker_topics.occasion',ARRAY['title','order','is_hidden'],ARRAY['save_speaker_topic_client_sync_v1','delete_speaker_topic_client_sync_v1'],ARRAY['update_speaker_topic','delete_speaker_topic'],'migrate','speaker_topic_factory'),
  (1,'content_catalog','public.speaker_topic_links','speaker -> speakers.occasion',ARRAY['speaker','topic'],ARRAY['save_speaker_client_sync_v1'],ARRAY['update_speaker'],'migrate','speaker_topic_link_factory'),
  (1,'content_catalog','public.event_speakers','event -> events.occasion',ARRAY['event','speaker'],ARRAY['save_event_speakers_client_sync_v1','create_counseling_slots_client_sync_v1','delete_empty_counseling_slots_client_sync_v1'],ARRAY['set_event_speakers'],'migrate','event_speaker_factory'),
  (1,'live_public','public.event_users','event -> events.occasion',ARRAY['event','user'],ARRAY['set_event_attendance_client_sync_v1','delete_occasion_user_client_sync_v1','import_profiles_client_sync_v1','delete_companion_client_sync_v1'],ARRAY['sign_user_to_event','sign_user_out_of_event'],'migrate','event_user_factory'),
  (1,'live_public','public.event_users_saved','event -> events.occasion',ARRAY['event','user'],ARRAY['set_saved_program_client_sync_v1','delete_occasion_user_client_sync_v1','import_profiles_client_sync_v1','delete_companion_client_sync_v1'],ARRAY['synchronize_my_schedule'],'migrate','saved_event_factory'),
  (1,'live_public','public.cleaning_reports','cleaning_reports.occasion',ARRAY['place','problem_type','resolved_at'],ARRAY['report_cleaning_issue_client_sync_v1','resolve_cleaning_place_client_sync_v1'],ARRAY['cleaning RPCs'],'migrate','cleaning_report_factory'),
  (1,'private_profile','public.user_info','organization/user',ARRAY['name','surname','sex','phone','birth_date','data'],ARRAY['save_profile_client_sync_v1','create_occasion_user_client_sync_v1','import_profiles_client_sync_v1','create_companion_client_sync_v1','delete_companion_client_sync_v1'],ARRAY['update_user','imports'],'migrate','user_info_factory'),
  (1,'private_profile','public.occasion_users','occasion_users.occasion/user',ARRAY['data','role','services','is_cleaning_blocked','ticket'],ARRAY['save_profile_client_sync_v1','create_occasion_user_client_sync_v1','delete_occasion_user_client_sync_v1','import_profiles_client_sync_v1','import_users_from_tickets_client_sync_v1','set_cleaning_notifications_muted_client_sync_v1','set_cleaning_reporter_blocked_client_sync_v1','create_companion_client_sync_v1','delete_companion_client_sync_v1','delete_service_item_client_sync_v1','add_user_to_occasion_client_sync_v1','delete_unit_user_client_sync_v1','create_ticket_order_client_sync_v1','delete_order_client_sync_v1','storno_tickets_client_sync_v1','storno_order_client_sync_v1','record_account_deletion_sync_v1','delete_occasion_client_sync_v1'],ARRAY['add_user_to_occasion facade','delete_unit_user facade','delete_user companion-only facade','commerce facades'],'migrate','occasion_user_factory'),
  (1,'private_profile','public.user_companions','owner and companion occasion membership',ARRAY['user','companion'],ARRAY['create_companion_client_sync_v1','delete_companion_client_sync_v1'],ARRAY['create_companion_in_organization','delete_user'],'migrate','companion_factory'),
  (1,'private_profile','public.user_group_info','user_group_info.occasion/members',ARRAY['title','description','type','place','data'],ARRAY['save_user_group_client_sync_v1','delete_user_group_client_sync_v1','replace_group_assignments_client_sync_v1','import_profiles_client_sync_v1','game_guess_client_sync_v1'],ARRAY['DbGroups direct DML','group imports','game_guess'],'migrate','user_group_factory'),
  (1,'private_profile','public.user_groups','group -> occasion/members',ARRAY['user','group','is_admin'],ARRAY['save_user_group_client_sync_v1','delete_user_group_client_sync_v1','replace_group_assignments_client_sync_v1','import_profiles_client_sync_v1'],ARRAY['DbGroups direct DML','group imports'],'migrate','user_group_membership_factory'),
  (1,'private_news','public.user_news','user_news.occasion/user',ARRAY['news','user'],ARRAY['mark_news_read_client_sync_v1'],ARRAY[]::text[],'migrate','user_news_factory'),
  (1,'private_feedback','public.event_feedback','event_feedback.occasion/user or anonymous client',ARRAY['event','user','client_id','rating','note','data'],ARRAY['submit_event_feedback_client_sync_v1','delete_event_feedback_client_sync_v1'],ARRAY['submit_event_feedback','delete_event_feedback'],'migrate','event_feedback_factory'),
  (1,'private_activity','public.activities','activities.occasion',ARRAY['title','description','data','type','is_hidden','order'],ARRAY['publish_activities_client_sync_v1'],ARRAY['update_activities'],'migrate','activity_factory'),
  (1,'private_activity','public.activity_assignments','activity -> activities.occasion',ARRAY['activity_id','user','start_time','end_time','title','description','data'],ARRAY['publish_activities_client_sync_v1'],ARRAY['update_activities'],'migrate','activity_assignment_factory'),
  (1,'private_activity','public.activity_assignment_places','assignment -> activity -> occasion',ARRAY['assignment_id','place_id'],ARRAY['publish_activities_client_sync_v1'],ARRAY['update_activities'],'migrate','activity_assignment_factory'),
  (1,'private_activity','public.activity_assignment_events','assignment -> activity -> occasion',ARRAY['assignment_id','event_id'],ARRAY['publish_activities_client_sync_v1'],ARRAY['update_activities'],'migrate','activity_assignment_factory'),
  (1,'private_inventory','public.inventory_pools','inventory_pools.occasion',ARRAY['title','sellable_capacity','description','type','data'],ARRAY['save_inventory_pool_client_sync_v1','delete_inventory_pool_client_sync_v1'],ARRAY['update_inventory_pool_bundle','delete_inventory_pool'],'migrate','inventory_pool_factory'),
  (1,'private_inventory','public.inventory_contexts','context -> pool -> occasion',ARRAY['inventory_pool','block_date','title','order','data'],ARRAY['save_inventory_pool_client_sync_v1'],ARRAY['update_inventory_pool_bundle'],'migrate','inventory_pool_factory'),
  (1,'private_inventory','public.resources','resources.occasion',ARRAY['inventory_pool','title','capacity','booking_rules','place','data'],ARRAY['save_resource_client_sync_v1','delete_resource_client_sync_v1'],ARRAY['update_resource','delete_resource'],'migrate','resource_factory'),
  (1,'private_inventory','public.resource_slots','resource -> occasion',ARRAY['resource','title','data'],ARRAY['save_resource_client_sync_v1','delete_resource_client_sync_v1'],ARRAY['update_resource','delete_resource'],'migrate','resource_factory'),
  (1,'private_inventory','eshop.spots','spots.occasion/order owner',ARRAY['inventory_context','resource','resource_slot','order_product_ticket','state'],ARRAY['update_spot_assignments_client_sync_v1','swap_spot_tickets_client_sync_v1','update_ticket_products_client_sync_v1','confirm_blueprint_order_change_client_sync_v1','replace_blueprint_order_client_sync_v1','create_ticket_order_client_sync_v1','update_blueprint_client_sync_v1','delete_order_client_sync_v1','storno_tickets_client_sync_v1','storno_order_client_sync_v1','save_inventory_pool_client_sync_v1','save_resource_client_sync_v1','update_product_inventory_contexts_client_sync_v1','delete_occasion_client_sync_v1','duplicate_occasion_client_sync_v1'],ARRAY['select_spot ephemeral reservation columns only','commerce facades'],'migrate','spot_factory'),
  (1,'private_inventory','eshop.products','products.occasion',ARRAY['title','description','data','product_type','is_hidden','order'],ARRAY['create_occasion_client_sync_v1','save_occasion_client_sync_v1','update_product_client_sync_v1','delete_product_client_sync_v1','update_form_client_sync_v1','create_form_client_sync_v1','duplicate_form_to_occasion_client_sync_v1','apply_planned_changes_client_sync_v1','delete_occasion_client_sync_v1','duplicate_occasion_client_sync_v1'],ARRAY['occasion, product and form facades'],'migrate','product_factory'),
  (1,'private_inventory','eshop.product_inventory_contexts','context -> pool -> occasion',ARRAY['product','inventory_context','quantity'],ARRAY['update_product_inventory_contexts_client_sync_v1','update_product_client_sync_v1','delete_product_client_sync_v1'],ARRAY['product facades'],'migrate','product_context_factory'),
  (1,'private_inventory','eshop.order_product_ticket','ticket -> occasion user',ARRAY['ticket','product'],ARRAY['update_ticket_products_client_sync_v1','create_ticket_order_client_sync_v1','replace_blueprint_order_client_sync_v1','swap_spot_tickets_client_sync_v1','delete_order_client_sync_v1','storno_tickets_client_sync_v1','storno_order_client_sync_v1','delete_occasion_client_sync_v1'],ARRAY['commerce facades'],'migrate','ticket_product_factory')
ON CONFLICT DO NOTHING;

INSERT INTO public.client_sync_scopes(component,scope_type,scope_id,source_revision)
SELECT component,'occasion',o.id,0
FROM public.occasions o CROSS JOIN unnest(ARRAY[
  'occasion_config','program_catalog','map_catalog','content_catalog','unit_catalog','live_public'
]) component
ON CONFLICT DO NOTHING;
INSERT INTO public.client_projection_dirty_keys
  (component,scope_type,scope_id,entity_id,source_revision)
SELECT component,scope_type,scope_id,0,source_revision FROM public.client_sync_scopes
ON CONFLICT DO NOTHING;

CREATE SEQUENCE public.client_sync_release_revision_seq AS bigint;
REVOKE ALL ON SEQUENCE public.client_sync_release_revision_seq FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.is_service_role()
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path = '' AS $$
DECLARE v_role text:=NULLIF(current_setting('request.jwt.claim.role',true),'');
  v_claims text;
BEGIN
  IF session_user='postgres' THEN RETURN true; END IF;
  IF v_role IS NULL THEN
    v_claims:=NULLIF(current_setting('request.jwt.claims',true),'');
    IF v_claims IS NOT NULL THEN
      BEGIN v_role:=v_claims::jsonb->>'role';
      EXCEPTION WHEN OTHERS THEN RETURN false; END;
    END IF;
  END IF;
  RETURN COALESCE(v_role='service_role',false);
END; $$;
REVOKE ALL ON FUNCTION public.is_service_role() FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.require_service_role()
RETURNS void LANGUAGE plpgsql STABLE SET search_path = '' AS $$
BEGIN
  IF NOT public.is_service_role() THEN
    RAISE insufficient_privilege USING MESSAGE='service role required';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.require_service_role() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.require_service_role() TO service_role;

CREATE OR REPLACE FUNCTION public.require_client_sync_service_role_v1()
RETURNS void LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT public.require_service_role();
$$;
REVOKE ALL ON FUNCTION public.require_client_sync_service_role_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.require_client_sync_service_role_v1() TO service_role;

CREATE OR REPLACE FUNCTION public.record_client_sync_commit_v1(
  p_occasion bigint,
  p_source text,
  p_change_class text,
  p_items jsonb,
  p_public_components text[],
  p_private_impacts jsonb DEFAULT '[]',
  p_dirty_keys jsonb DEFAULT '[]',
  p_actor_kind text DEFAULT 'user',
  p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_commit public.client_commits%ROWTYPE;
  v_component text;
  v_revision bigint;
  v_item jsonb;
  v_index integer := 0;
  v_user uuid := auth.uid();
  v_dirty jsonb;
  v_private jsonb;
  v_private_user uuid;
BEGIN
  IF p_actor_kind='user' THEN
    IF v_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.user_info ui
      WHERE ui.id=v_user) THEN
      RAISE insufficient_privilege USING MESSAGE='authenticated actor required';
    END IF;
  ELSIF p_actor_kind IN ('service','break_glass','system') THEN
    PERFORM public.require_client_sync_service_role_v1();
    IF p_actor_kind='break_glass' AND nullif(btrim(p_reason),'') IS NULL THEN
      RAISE EXCEPTION 'break-glass reason is required';
    END IF;
  ELSE
    IF p_actor_kind<>'unknown' OR v_user IS NOT NULL THEN
      RAISE insufficient_privilege USING MESSAGE='unsupported commit actor';
    END IF;
  END IF;
  INSERT INTO public.client_commits
    (occasion, actor_id, actor_display, actor_kind, source, change_class,
     reason)
  SELECT p_occasion, v_user,
    nullif(concat_ws(' ', ui.name, ui.surname), ''), p_actor_kind, p_source,
    p_change_class, p_reason
  FROM (SELECT 1) seed LEFT JOIN public.user_info ui ON ui.id = v_user
  RETURNING * INTO v_commit;

  FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_items, '[]')) LOOP
    INSERT INTO public.client_commit_items
      (commit_id, item_index, entity_type, entity_id, operation, safe_label, changed_fields)
    VALUES (v_commit.commit_id, v_index, v_item->>'entityType', v_item->>'entityId',
      v_item->>'operation', left(v_item->>'safeLabel', 240),
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_item->'changedFields','[]'))));
    v_index := v_index + 1;
  END LOOP;

  FOREACH v_component IN ARRAY COALESCE(p_public_components, '{}') LOOP
    INSERT INTO public.client_sync_scopes(component, scope_type, scope_id, source_revision)
    VALUES (v_component, 'occasion', p_occasion, 1)
    ON CONFLICT (component, scope_type, scope_id) DO UPDATE
      SET source_revision = public.client_sync_scopes.source_revision + 1,
          updated_at = now()
    RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id, component, scope_type, scope_id, user_id, resulting_revision)
    VALUES (v_commit.commit_id, v_component, 'occasion', p_occasion,
      NULL, v_revision);
    IF v_component<>'live_public' OR NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(p_dirty_keys,'[]')) impact
      WHERE impact->>'component'=v_component) THEN
      INSERT INTO public.client_projection_dirty_keys
        (component, scope_type, scope_id, entity_id, source_revision)
      VALUES (v_component, 'occasion', p_occasion, 0, v_revision)
      ON CONFLICT (component, scope_type, scope_id, entity_id) DO UPDATE
        SET source_revision = EXCLUDED.source_revision, dirty_since = now(),
            claimed_at = NULL, claim_token = NULL;
    END IF;
  END LOOP;

  FOR v_private IN SELECT DISTINCT value
    FROM jsonb_array_elements(COALESCE(p_private_impacts,'[]')) LOOP
      v_component:=v_private->>'component';
      v_private_user:=(v_private->>'userId')::uuid;
      IF v_component NOT LIKE 'private\_%' OR NOT EXISTS (
        SELECT 1 FROM public.occasion_users ou
        WHERE ou.occasion=p_occasion AND ou."user"=v_private_user) THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid private sync impact';
      END IF;
      INSERT INTO public.client_sync_private_scopes(component, occasion, user_id, source_revision)
      VALUES (v_component, p_occasion, v_private_user, 1)
      ON CONFLICT (component, occasion, user_id) DO UPDATE
        SET source_revision = public.client_sync_private_scopes.source_revision + 1,
            updated_at = now()
      RETURNING source_revision INTO v_revision;
      INSERT INTO public.client_commit_components
        (commit_id, component, scope_type, scope_id, user_id, resulting_revision)
      VALUES (v_commit.commit_id, v_component, 'occasion', p_occasion,
        v_private_user, v_revision);
  END LOOP;

  FOR v_dirty IN SELECT value FROM jsonb_array_elements(COALESCE(p_dirty_keys, '[]')) LOOP
    INSERT INTO public.client_projection_dirty_keys
      (component, scope_type, scope_id, entity_id, source_revision)
    VALUES (v_dirty->>'component', 'occasion', p_occasion,
      (v_dirty->>'entityId')::bigint, COALESCE((v_dirty->>'revision')::bigint,
        (SELECT s.source_revision FROM public.client_sync_scopes s
         WHERE s.component=v_dirty->>'component' AND s.scope_type='occasion'
           AND s.scope_id=p_occasion),0))
    ON CONFLICT (component, scope_type, scope_id, entity_id) DO UPDATE
      SET source_revision = GREATEST(public.client_projection_dirty_keys.source_revision,
          EXCLUDED.source_revision), dirty_since = now(), claimed_at = NULL, claim_token = NULL;
  END LOOP;

  RETURN jsonb_build_object('commitId', v_commit.commit_id,
    'occurredAt', v_commit.occurred_at);
END;
$$;
REVOKE ALL ON FUNCTION public.record_client_sync_commit_v1(bigint,text,text,jsonb,text[],jsonb,jsonb,text,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.begin_client_mutation_v1(
  p_command_id uuid,
  p_command_name text,
  p_occasion bigint,
  p_actor_id uuid,
  p_request_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_receipt public.client_mutation_receipts%ROWTYPE;
  v_inserted integer;
BEGIN
  IF p_command_id IS NULL OR p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid() THEN
    RAISE insufficient_privilege USING MESSAGE='authenticated command actor required';
  END IF;
  IF p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid mutation receipt metadata';
  END IF;

  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_occasion,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  SELECT * INTO STRICT v_receipt
  FROM public.client_mutation_receipts
  WHERE command_id=p_command_id
  FOR UPDATE;

  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS DISTINCT FROM p_occasion
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value
      USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  END IF;
  IF v_inserted <> 1 THEN
    RAISE serialization_failure
      USING MESSAGE='incomplete mutation receipt cannot be resumed';
  END IF;
  RETURN jsonb_build_object('disposition','claimed');
END;
$$;

CREATE OR REPLACE FUNCTION public.begin_anonymous_client_mutation_v1(
  p_command_id uuid,
  p_command_name text,
  p_occasion bigint,
  p_actor_client_id uuid,
  p_request_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_receipt public.client_mutation_receipts%ROWTYPE;
  v_inserted integer;
BEGIN
  IF auth.uid() IS NOT NULL OR p_actor_client_id IS NULL
     OR p_command_id IS NULL OR p_occasion IS NULL
     OR p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid anonymous mutation receipt claim';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_client_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_occasion,p_actor_client_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS DISTINCT FROM p_occasion
     OR v_receipt.actor_id IS NOT NULL
     OR v_receipt.actor_client_id IS DISTINCT FROM p_actor_client_id
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value
      USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  END IF;
  IF v_inserted<>1 THEN
    RAISE serialization_failure
      USING MESSAGE='incomplete mutation receipt cannot be resumed';
  END IF;
  RETURN jsonb_build_object('disposition','claimed');
END;
$$;

CREATE OR REPLACE FUNCTION public.begin_unit_client_mutation_v1(
  p_command_id uuid,p_command_name text,p_unit bigint,p_actor_id uuid,
  p_request_sha256 text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  IF p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid()
     OR p_command_id IS NULL OR p_unit IS NULL
     OR p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$'
     OR NOT public.get_is_manager_on_unit(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='invalid unit mutation receipt claim';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,unit,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_unit,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS NOT NULL OR v_receipt.unit IS DISTINCT FROM p_unit
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id
     OR v_receipt.actor_client_id IS NOT NULL
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value
      USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  END IF;
  IF v_inserted<>1 THEN
    RAISE serialization_failure
      USING MESSAGE='incomplete mutation receipt cannot be resumed';
  END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $$;

CREATE OR REPLACE FUNCTION public.finish_client_mutation_v1(
  p_command_id uuid,
  p_response jsonb,
  p_commit_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_receipt public.client_mutation_receipts%ROWTYPE;
BEGIN
  -- Aggregate commands may carry one bounded private replacement (activities
  -- and inventory are the largest). The receipt must preserve the exact
  -- response for retry, so its bound must exceed the aggregate DTO bounds.
  IF p_response IS NULL OR octet_length(p_response::text) > 8388608 THEN
    RAISE program_limit_exceeded USING MESSAGE='mutation response exceeds receipt limit';
  END IF;
  SELECT * INTO STRICT v_receipt
  FROM public.client_mutation_receipts
  WHERE command_id=p_command_id
  FOR UPDATE;
  IF (v_receipt.actor_id IS NOT NULL
      AND v_receipt.actor_id IS DISTINCT FROM auth.uid())
    OR (v_receipt.actor_client_id IS NOT NULL AND auth.uid() IS NOT NULL) THEN
    RAISE insufficient_privilege USING MESSAGE='mutation receipt actor mismatch';
  END IF;
  IF v_receipt.status <> 'processing' THEN
    RAISE invalid_parameter_value USING MESSAGE='mutation receipt already completed';
  END IF;
  IF p_commit_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.client_commits c
    WHERE c.commit_id=p_commit_id
      AND c.occasion IS NOT DISTINCT FROM v_receipt.occasion
      AND c.unit IS NOT DISTINCT FROM v_receipt.unit
      AND c.organization IS NULL
      AND c.actor_id IS NOT DISTINCT FROM v_receipt.actor_id
  ) THEN
    RAISE foreign_key_violation USING MESSAGE='commit does not belong to mutation receipt';
  END IF;

  UPDATE public.client_mutation_receipts
  SET status='completed', response=p_response, commit_id=p_commit_id,
      completed_at=clock_timestamp()
  WHERE command_id=p_command_id;
  RETURN p_response;
END;
$$;

REVOKE ALL ON FUNCTION public.begin_client_mutation_v1(uuid,text,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.begin_anonymous_client_mutation_v1(uuid,text,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.finish_client_mutation_v1(uuid,jsonb,uuid)
  FROM PUBLIC,anon,authenticated;

-- Deep mutation-protocol module. Domain RPCs retain all authorization, locks,
-- validation and DML; these helpers only standardize terminal outcomes and the
-- receipt/audit/revision/replacement protocol.
CREATE OR REPLACE FUNCTION public.complete_client_mutation_outcome_v1(
  p_command_id uuid,p_status text,p_code integer,p_data jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb;
BEGIN
  IF p_status NOT IN ('unchanged','rejected','conflict')
    OR p_code NOT BETWEEN 100 AND 599 OR p_data IS NULL
    OR octet_length(p_data::text)>4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid mutation outcome';
  END IF;
  v_response:=jsonb_build_object('status',p_status,'code',p_code,'data',p_data,
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
    'sync',jsonb_build_object('replacements','[]'::jsonb));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
END; $$;
REVOKE ALL ON FUNCTION public.complete_client_mutation_outcome_v1(uuid,text,integer,jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.fanout_unit_catalog_v1(
  p_commit_id uuid,p_unit bigint
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_occasion bigint; v_revision bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.client_commits c
    WHERE c.commit_id=p_commit_id) THEN
    RAISE foreign_key_violation USING MESSAGE='unit fanout requires an audit commit';
  END IF;
  FOR v_occasion IN SELECT o.id FROM public.occasions o
    WHERE o.unit=p_unit AND NOT o.is_hidden ORDER BY o.id LOOP
    INSERT INTO public.client_sync_scopes
      (component,scope_type,scope_id,source_revision)
    VALUES ('unit_catalog','occasion',v_occasion,1)
    ON CONFLICT (component,scope_type,scope_id) DO UPDATE
      SET source_revision=public.client_sync_scopes.source_revision+1,
          updated_at=now()
    RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
    VALUES (p_commit_id,'unit_catalog','occasion',v_occasion,NULL,v_revision);
    INSERT INTO public.client_projection_dirty_keys
      (component,scope_type,scope_id,entity_id,source_revision)
    VALUES ('unit_catalog','occasion',v_occasion,0,v_revision)
    ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE
      SET source_revision=EXCLUDED.source_revision,dirty_since=now(),
          claimed_at=NULL,claim_token=NULL;
  END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.fanout_unit_catalog_v1(uuid,bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.complete_client_mutation_applied_v1(
  p_command_id uuid,p_occasion bigint,p_source text,p_change_class text,
  p_items jsonb,p_public_components text[],p_private_impacts jsonb,
  p_dirty_keys jsonb,p_data jsonb,
  p_immediate_public_components text[] DEFAULT '{}',
  p_extra_replacements jsonb DEFAULT '[]',p_actor_kind text DEFAULT 'user',
  p_reason text DEFAULT NULL,p_immediate_private_replacements jsonb DEFAULT '[]',
  p_unit_catalog_fanout_units bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_commit jsonb; v_component text; v_component_data jsonb;
  v_private_replacement jsonb; v_private_revision bigint;
  v_replacements jsonb:=COALESCE(p_extra_replacements,'[]'::jsonb);
  v_response jsonb; v_fanout_unit bigint;
BEGIN
  IF p_data IS NULL OR octet_length(p_data::text)>4194304
    OR jsonb_typeof(v_replacements)<>'array'
    OR jsonb_typeof(COALESCE(p_immediate_private_replacements,'[]'))<>'array'
    OR NOT COALESCE(p_immediate_public_components,'{}')
      <@ COALESCE(p_public_components,'{}') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid applied mutation result';
  END IF;
  v_commit:=public.record_client_sync_commit_v1(p_occasion,p_source,p_change_class,
    p_items,p_public_components,p_private_impacts,p_dirty_keys,p_actor_kind,p_reason);
  FOR v_fanout_unit IN SELECT DISTINCT id FROM unnest(
    COALESCE(p_unit_catalog_fanout_units,'{}')) id LOOP
    PERFORM public.fanout_unit_catalog_v1(
      (v_commit->>'commitId')::uuid,v_fanout_unit);
  END LOOP;
  FOREACH v_component IN ARRAY COALESCE(p_immediate_public_components,'{}') LOOP
    v_component_data:=public.get_public_client_sync_component_v1(
      v_component,'occasion',p_occasion);
    v_replacements:=v_replacements||jsonb_build_array(jsonb_build_object(
      'component',v_component,'revision',v_component_data->'revision',
      'payload',v_component_data->'payload'));
  END LOOP;
  FOR v_private_replacement IN SELECT value FROM jsonb_array_elements(
      COALESCE(p_immediate_private_replacements,'[]')) LOOP
    IF v_private_replacement->>'component' NOT LIKE 'private\_%'
      OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(
        COALESCE(p_private_impacts,'[]')) impact
        WHERE impact->>'component'=v_private_replacement->>'component'
          AND impact->>'userId'=v_private_replacement->>'userId') THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid immediate private replacement';
    END IF;
    SELECT s.source_revision INTO STRICT v_private_revision
    FROM public.client_sync_private_scopes s
    WHERE s.component=v_private_replacement->>'component'
      AND s.occasion=p_occasion
      AND s.user_id=(v_private_replacement->>'userId')::uuid;
    v_replacements:=v_replacements||jsonb_build_array(jsonb_build_object(
      'component',v_private_replacement->>'component',
      'revision',v_private_revision,'payload',v_private_replacement->'payload'));
  END LOOP;
  v_response:=jsonb_build_object('status','applied','code',200,'data',p_data,
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,
      'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',v_replacements));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $$;
REVOKE ALL ON FUNCTION public.complete_client_mutation_applied_v1(uuid,bigint,text,text,jsonb,text[],jsonb,jsonb,jsonb,text[],jsonb,text,text,jsonb,bigint[])
  FROM PUBLIC,anon,authenticated;

-- Shared protocol shell for transactional commerce writers. Domain commands
-- retain their own validation and DML; this centralizes the private-inventory
-- component identity, revision fan-out and current-actor replacement.
CREATE OR REPLACE FUNCTION public.complete_private_inventory_mutation_v1(
  p_command_id uuid,p_occasion bigint,p_source text,p_items jsonb,
  p_impacted_users uuid[],p_data jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',u.id) ORDER BY u.id),'[]'::jsonb) INTO v_impacts
  FROM (SELECT DISTINCT id FROM unnest(COALESCE(p_impacted_users,'{}')) id) u
  JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=u.id;
  IF v_actor IS NOT NULL AND v_actor=ANY(COALESCE(p_impacted_users,'{}'))
    AND EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=v_actor) THEN
    v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_inventory','userId',v_actor,
      'payload',public.get_user_inventory_for_occasion_v1(p_occasion)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    p_source,'inventory',p_items,'{}',v_impacts,'[]',p_data,
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.complete_private_inventory_mutation_v1(
  uuid,bigint,text,jsonb,uuid[],jsonb) FROM PUBLIC,anon,authenticated;

-- Occasion-scoped private inventory producer. The legacy no-argument helper
-- spans all of a user's tickets and must not feed an occasion cache namespace.
CREATE OR REPLACE FUNCTION public.get_user_inventory_for_occasion_v1(
  p_occasion bigint
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH user_ticket_products AS (
    SELECT opt.id order_product_ticket_id,opt.product product_id
    FROM public.occasion_users ou
    JOIN eshop.order_product_ticket opt ON opt.ticket=ou.ticket
    WHERE ou."user"=auth.uid() AND ou.occasion=p_occasion
      AND ou.ticket IS NOT NULL AND opt.product IS NOT NULL
  ), assigned AS (
    SELECT s.id,s.title,s.state,s.resource_slot,s.resource,s.inventory_context,
      ic.inventory_pool,utp.product_id
    FROM eshop.spots s
    JOIN user_ticket_products utp
      ON utp.order_product_ticket_id=s.order_product_ticket
    JOIN public.inventory_contexts ic ON ic.id=s.inventory_context
    JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
    WHERE ip.occasion=p_occasion
  )
  SELECT jsonb_build_object(
    'inventory_contexts',COALESCE((SELECT jsonb_object_agg(ic.id,
      jsonb_build_object('id',ic.id,'order',ic."order",'block_date',ic.block_date,
        'title',ic.title,'data',ic.data,'inventory_pool',ic.inventory_pool,
        'spots',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,
          'title',a.title,'state',a.state,'resource_slot',a.resource_slot,
          'resource',a.resource,'product_id',a.product_id) ORDER BY a.id),'[]')
          FROM assigned a WHERE a.inventory_context=ic.id)))
      FROM public.inventory_contexts ic
      WHERE ic.id IN (SELECT DISTINCT a.inventory_context FROM assigned a)),'{}'),
    'inventory_pools',COALESCE((SELECT jsonb_object_agg(ip.id,
      jsonb_strip_nulls(jsonb_build_object('id',ip.id,'data',ip.data,
        'title',ip.title,'description',ip.description,'type',ip.type,
        'sellable_capacity',ip.sellable_capacity,'occasion',ip.occasion)))
      FROM public.inventory_pools ip
      WHERE ip.occasion=p_occasion AND ip.id IN (
        SELECT DISTINCT a.inventory_pool FROM assigned a)),'{}'),
    'resources',COALESCE((SELECT jsonb_object_agg(r.id,to_jsonb(r))
      FROM public.resources r WHERE r.occasion=p_occasion AND r.id IN (
        SELECT DISTINCT a.resource FROM assigned a WHERE a.resource IS NOT NULL)),'{}'),
    'products',COALESCE((SELECT jsonb_object_agg(p.id,jsonb_build_object(
      'id',p.id,'title',p.title,'description',p.description,'price',p.price,
      'data',p.data,'product_type',p.product_type,'occasion',p.occasion,
      'is_hidden',p.is_hidden,'currency_code',p.currency_code,'order',p."order",
      'maximum',p.maximum,'is_dynamically_available',
        public.is_product_dynamically_available(p.id)))
      FROM eshop.products p WHERE p.id IN (
        SELECT DISTINCT a.product_id FROM assigned a)),'{}'),
    'product_inventory_contexts',COALESCE((SELECT jsonb_object_agg(pic.id,to_jsonb(pic))
      FROM eshop.product_inventory_contexts pic
      WHERE (pic.inventory_context,pic.product) IN (
        SELECT DISTINCT a.inventory_context,a.product_id FROM assigned a)),'{}'),
    'places',COALESCE((SELECT jsonb_object_agg(pl.id,to_jsonb(pl))
      FROM public.places pl WHERE pl.occasion=p_occasion AND pl.id IN (
        SELECT DISTINCT (ip.data->>'place_id')::bigint
        FROM public.inventory_pools ip
        WHERE ip.id IN (SELECT DISTINCT a.inventory_pool FROM assigned a)
          AND ip.data ? 'place_id' AND ip.data->>'place_id' IS NOT NULL)),'{}'));
$$;
REVOKE ALL ON FUNCTION public.get_user_inventory_for_occasion_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_private_feedback_payload_v1(
  p_occasion bigint,p_user uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('eventId',f.event,
    'rating',f.rating,'note',f.note,'data',f.data,'updatedAt',f.updated_at)
    ORDER BY f.event),'[]'::jsonb)
  FROM public.event_feedback f
  WHERE f."user"=p_user AND f.occasion=p_occasion;
$$;
REVOKE ALL ON FUNCTION public.get_private_feedback_payload_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_private_profile_payload_v1(
  p_occasion bigint,p_user uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'user',(SELECT jsonb_build_object('id',u.id,'email',u.email_readonly,
      'name',u.name,'surname',u.surname,'sex',u.sex,'phone',u.phone,
      'birthDate',u.birth_date,'data',u.data) FROM public.user_info u
      WHERE u.id=p_user),
    'occasion',(SELECT jsonb_build_object('role',ou.role,'services',ou.services,
      'data',ou.data,'isCleaningBlocked',ou.is_cleaning_blocked,
      'isCleaningCrew',ou.is_cleaning_crew) FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_user),
    'companions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',ui.id,'name',ui.name,'event_ids',COALESCE((SELECT jsonb_agg(
        eu.event ORDER BY eu.event) FROM public.event_users eu
        JOIN public.events e ON e.id=eu.event WHERE eu."user"=ui.id
          AND e.occasion=p_occasion),'[]'::jsonb)) ORDER BY ui.name,ui.id)
      FROM public.user_companions uc JOIN public.user_info ui
        ON ui.id=uc.companion JOIN public.occasion_users ou
        ON ou."user"=ui.id AND ou.occasion=p_occasion
      WHERE uc."user"=p_user),'[]'::jsonb),
    'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',g.id,'title',g.title,'description',g.description,'type',g.type,
      'data',g.data,'place',g.place,'isAdmin',mine.is_admin,
      'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'userId',members."user",'isAdmin',members.is_admin,
        'name',ui.name,'surname',ui.surname) ORDER BY members."user")
        FROM public.user_groups members JOIN public.user_info ui
          ON ui.id=members."user" WHERE members."group"=g.id),'[]'::jsonb),
      'placeData',(SELECT to_jsonb(p) FROM public.places p WHERE p.id=g.place))
      ORDER BY g.id) FROM public.user_groups mine JOIN public.user_group_info g
        ON g.id=mine."group" WHERE mine."user"=p_user
        AND g.occasion=p_occasion),'[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.get_private_profile_payload_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.complete_private_profile_mutation_v1(
  p_command_id uuid,p_occasion bigint,p_source text,p_items jsonb,
  p_impacted_users uuid[],p_public_components text[],p_dirty_keys jsonb,
  p_data jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,u.id::text,1
  FROM (SELECT DISTINCT id FROM unnest(COALESCE(p_impacted_users,'{}')) id) u
  JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=u.id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',u.id) ORDER BY u.id),'[]'::jsonb) INTO v_impacts
  FROM (SELECT DISTINCT id FROM unnest(COALESCE(p_impacted_users,'{}')) id) u
  JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=u.id;
  IF v_actor IS NOT NULL AND v_actor=ANY(COALESCE(p_impacted_users,'{}'))
    AND EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=v_actor) THEN
    v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    p_source,'profile',p_items,p_public_components,v_impacts,p_dirty_keys,p_data,
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.complete_private_profile_mutation_v1(
  uuid,bigint,text,jsonb,uuid[],text[],jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.complete_profile_inventory_membership_mutation_v1(
  p_command_id uuid,p_occasion bigint,p_source text,p_items jsonb,
  p_before_users uuid[],p_data jsonb,p_actor_kind text DEFAULT 'user'
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_after_users uuid[]; v_removed uuid[];
  v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_after_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT ARRAY(SELECT id FROM unnest(COALESCE(p_before_users,'{}')) id
    WHERE NOT id=ANY(v_after_users)) INTO v_removed;
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=p_occasion
    AND s.user_id=ANY(v_removed);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=p_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed) id));
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,id::text,1
    FROM unnest(v_after_users) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component',component,
    'userId',id) ORDER BY id,component),'[]'::jsonb) INTO v_impacts
  FROM unnest(v_after_users) id CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component;
  IF cardinality(v_removed)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=p_occasion;
  END IF;
  IF v_actor IS NOT NULL AND v_actor=ANY(v_after_users) THEN
    v_replacements:=jsonb_build_array(
      jsonb_build_object('component','private_profile','userId',v_actor,
        'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)),
      jsonb_build_object('component','private_inventory','userId',v_actor,
        'payload',public.get_user_inventory_for_occasion_v1(p_occasion)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    p_source,'inventory',p_items,v_public,v_impacts,v_dirty,p_data,
    '{}','[]',p_actor_kind,NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.complete_profile_inventory_membership_mutation_v1(
  uuid,bigint,text,jsonb,uuid[],jsonb,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.record_account_deletion_sync_v1(
  p_user uuid,p_organization bigint
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_commit public.client_commits%ROWTYPE; v_occasion bigint;
  v_revision bigint; v_event bigint; v_member uuid;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF p_user IS NULL OR p_organization IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id=p_user AND ui.organization=p_organization) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid account deletion sync scope';
  END IF;
  INSERT INTO public.client_commits
    (organization,actor_id,actor_display,actor_kind,source,change_class,reason)
  VALUES (p_organization,p_user,NULL,'service','account.delete','profile',
    'confirmed account deletion') RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'user',p_user::text,'delete',NULL,
    ARRAY['membership','profile','private_data']);
  FOR v_occasion IN SELECT ou.occasion FROM public.occasion_users ou
    JOIN public.occasions o ON o.id=ou.occasion
    WHERE ou."user"=p_user AND o.organization=p_organization
    ORDER BY ou.occasion LOOP
    IF EXISTS (SELECT 1 FROM public.event_users eu JOIN public.events e
        ON e.id=eu.event WHERE eu."user"=p_user AND e.occasion=v_occasion)
      OR EXISTS (SELECT 1 FROM public.event_users_saved es JOIN public.events e
        ON e.id=es.event WHERE es."user"=p_user AND e.occasion=v_occasion) THEN
      INSERT INTO public.client_sync_scopes
        (component,scope_type,scope_id,source_revision)
      VALUES ('live_public','occasion',v_occasion,1)
      ON CONFLICT (component,scope_type,scope_id) DO UPDATE SET
        source_revision=public.client_sync_scopes.source_revision+1,
        updated_at=now() RETURNING source_revision INTO v_revision;
      INSERT INTO public.client_commit_components
        (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
      VALUES (v_commit.commit_id,'live_public','occasion',v_occasion,NULL,v_revision);
      FOR v_event IN SELECT DISTINCT id FROM (
        SELECT eu.event id FROM public.event_users eu JOIN public.events e
          ON e.id=eu.event WHERE eu."user"=p_user AND e.occasion=v_occasion
        UNION SELECT es.event FROM public.event_users_saved es JOIN public.events e
          ON e.id=es.event WHERE es."user"=p_user AND e.occasion=v_occasion
      ) affected ORDER BY id LOOP
        INSERT INTO public.client_projection_dirty_keys
          (component,scope_type,scope_id,entity_id,source_revision)
        VALUES ('live_public','occasion',v_occasion,v_event,v_revision)
        ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE SET
          source_revision=EXCLUDED.source_revision,dirty_since=now(),
          claimed_at=NULL,claim_token=NULL;
      END LOOP;
    END IF;
    FOR v_member IN SELECT ou."user" FROM public.occasion_users ou
      WHERE ou.occasion=v_occasion AND ou."user"<>p_user ORDER BY ou."user" LOOP
      INSERT INTO public.client_sync_private_scopes
        (component,occasion,user_id,source_revision)
      VALUES ('private_profile',v_occasion,v_member,1)
      ON CONFLICT (component,occasion,user_id) DO UPDATE SET
        source_revision=public.client_sync_private_scopes.source_revision+1,
        updated_at=now() RETURNING source_revision INTO v_revision;
      INSERT INTO public.client_commit_components
        (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
      VALUES (v_commit.commit_id,'private_profile','occasion',v_occasion,
        v_member,v_revision);
    END LOOP;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='user_group'
      AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id IN (
        SELECT ug."group"::text FROM public.user_groups ug
        WHERE ug."user"=p_user);
  END LOOP;
  RETURN v_commit.commit_id;
END; $$;
REVOKE ALL ON FUNCTION public.record_account_deletion_sync_v1(uuid,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_account_deletion_sync_v1(uuid,bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.get_private_client_sync_v1(
  p_context jsonb,
  p_known_private_vector jsonb DEFAULT '{}'
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_occasion bigint := (p_context->>'occasionId')::bigint;
  v_user uuid := auth.uid();
  v_components jsonb;
  v_vector jsonb;
BEGIN
  IF p_context IS NULL OR jsonb_typeof(p_context) <> 'object'
     OR octet_length(p_context::text) > 4096
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(p_context) key
       WHERE key NOT IN ('organizationId','occasionId'))
     OR p_known_private_vector IS NULL
     OR jsonb_typeof(p_known_private_vector) <> 'object'
     OR octet_length(p_known_private_vector::text) > 4096
     OR EXISTS (
       SELECT 1 FROM jsonb_each_text(p_known_private_vector) entry
       WHERE entry.key NOT IN ('private_program','private_profile',
         'private_inventory','private_activity','private_news','private_feedback')
         OR entry.value !~ '^[0-9]{1,19}$') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid private sync request';
  END IF;
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=v_occasion AND ou."user"=v_user
  ) OR NOT EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE o.id = v_occasion
      AND o.organization = (p_context->>'organizationId')::bigint
      AND (NOT o.is_hidden OR public.get_is_editor_view_on_occasion(v_occasion))
  ) THEN RETURN jsonb_build_object('code', 403); END IF;

  WITH names(component) AS (VALUES
    ('private_program'),('private_profile'),('private_inventory'),
    ('private_activity'),('private_news'),('private_feedback')
  ), heads AS (
    SELECT n.component, COALESCE(s.source_revision, 0) revision
    FROM names n LEFT JOIN public.client_sync_private_scopes s
      ON s.component=n.component AND s.occasion=v_occasion AND s.user_id=v_user
  ) SELECT jsonb_object_agg(component, revision) INTO v_vector FROM heads;

  WITH changed AS (
    SELECT key component, value::text::bigint revision FROM jsonb_each(v_vector)
    WHERE value::text::bigint > COALESCE((p_known_private_vector->>key)::bigint, -1)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'component', c.component, 'revision', c.revision, 'payload',
    CASE c.component
      WHEN 'private_program' THEN jsonb_build_object(
        'signedIn', (SELECT COALESCE(jsonb_agg(eu.event ORDER BY eu.event),'[]') FROM public.event_users eu JOIN public.events e ON e.id=eu.event WHERE eu."user"=v_user AND e.occasion=v_occasion),
        'saved', (SELECT COALESCE(jsonb_agg(es.event ORDER BY es.event),'[]') FROM public.event_users_saved es JOIN public.events e ON e.id=es.event WHERE es."user"=v_user AND e.occasion=v_occasion))
      WHEN 'private_profile' THEN public.get_private_profile_payload_v1(
        v_occasion,v_user)
      WHEN 'private_inventory' THEN public.get_user_inventory_for_occasion_v1(v_occasion)
      WHEN 'private_activity' THEN public.get_my_events_and_activities(v_occasion,true)->'data'
      WHEN 'private_news' THEN (SELECT COALESCE(jsonb_agg(jsonb_build_object('newsId',un.news_id,'readAt',un.created_at) ORDER BY un.news_id),'[]') FROM public.user_news un WHERE un.occasion=v_occasion AND un."user"=v_user)
      WHEN 'private_feedback' THEN public.get_private_feedback_payload_v1(
        v_occasion,v_user)
    END)),'[]') INTO v_components FROM changed c;

  RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
    'serverTime',clock_timestamp(),'vector',v_vector,'components',v_components));
END;
$$;
REVOKE ALL ON FUNCTION public.get_private_client_sync_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_private_client_sync_v1(jsonb,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_news_read_client_sync_v1(
  p_occasion bigint,p_news_id bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_user uuid:=auth.uid();
  v_revision bigint;
  v_begin jsonb;
  v_commit jsonb;
  v_read_at timestamptz;
  v_data jsonb;
  v_response jsonb;
  v_request_sha256 text;
BEGIN
  IF v_user IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.occasion_users ou
       WHERE ou.occasion=p_occasion AND ou."user"=v_user)
     OR NOT EXISTS (SELECT 1 FROM public.news n
       WHERE n.id=p_news_id AND n.occasion=p_occasion)
  THEN RETURN jsonb_build_object('code',403); END IF;

  v_request_sha256:=encode(extensions.digest(convert_to(
    jsonb_build_object('occasion',p_occasion,'newsId',p_news_id)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'news.mark_read',
    p_occasion,v_user,v_request_sha256);
  IF v_begin->>'disposition'='replay' THEN
    RETURN v_begin->'response';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text||':'||p_occasion::text,0));

  SELECT COALESCE(source_revision,0) INTO v_revision
  FROM (SELECT 1) seed LEFT JOIN public.client_sync_private_scopes s
    ON s.component='private_news' AND s.occasion=p_occasion AND s.user_id=v_user;
  IF (SELECT count(*)=1 AND max(news_id)=p_news_id
      FROM public.user_news
      WHERE "user"=v_user AND occasion=p_occasion) THEN
    v_data:=jsonb_build_object('revision',v_revision,'payload',jsonb_build_array(
      jsonb_build_object('newsId',p_news_id)));
    v_response:=jsonb_build_object('status','unchanged','code',200,'data',v_data,
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;

  v_read_at:=clock_timestamp();
  v_data:=jsonb_build_object('revision',v_revision+1,'payload',jsonb_build_array(
    jsonb_build_object('newsId',p_news_id,'readAt',v_read_at)));
  DELETE FROM public.user_news WHERE "user"=v_user AND occasion=p_occasion;
  INSERT INTO public.user_news(news_id,"user",occasion) VALUES(p_news_id,v_user,p_occasion);
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'mark_news_read','private',
    jsonb_build_array(jsonb_build_object('entityType','news_marker',
      'entityId',p_news_id,'operation','update','safeLabel','News read marker',
    'changedFields',jsonb_build_array('news_id'))),'{}',jsonb_build_array(
      jsonb_build_object('component','private_news','userId',v_user)),'[]',
    'user',NULL);
  SELECT source_revision INTO v_revision FROM public.client_sync_private_scopes
    WHERE component='private_news' AND occasion=p_occasion AND user_id=v_user;
  v_data:=v_data||jsonb_build_object('revision',v_revision);
  v_response:=jsonb_build_object('status','applied','code',200,'data',v_data,
    'mutation',jsonb_build_object('commandId',p_command_id,
      'receiptId',p_command_id,'commitId',v_commit->>'commitId','replayed',false,
      'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',jsonb_build_array(jsonb_build_object(
      'component','private_news','revision',v_revision,'payload',v_data->'payload'))));
  RETURN public.finish_client_mutation_v1(
    p_command_id,v_response,(v_commit->>'commitId')::uuid);
END; $$;
REVOKE ALL ON FUNCTION public.mark_news_read_client_sync_v1(bigint,bigint,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_news_read_client_sync_v1(bigint,bigint,uuid) TO authenticated;

-- Event aggregate readback used by the event commands and their conflict/no-op
-- responses. It is not granted to clients; the public interface remains the
-- two explicitly named intent RPCs below.
CREATE OR REPLACE FUNCTION public.get_event_command_data_v1(p_event_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id',e.id,'title',e.title,'startTime',e.start_time,'endTime',e.end_time,
    'maxParticipants',e.max_participants,'description',e.description,
    'placeId',e.place,'splitForMenWomen',e.split_for_men_women,
    'isGroupEvent',e.is_group_event,'isHidden',e.is_hidden,'type',e.type,
    'data',e.data,'order',e."order",
    'parentEventIds',COALESCE((SELECT jsonb_agg(g.event_parent ORDER BY g.event_parent)
      FROM public.event_groups g WHERE g.event_child=e.id),'[]'::jsonb),
    'eventRoleIds',COALESCE((SELECT jsonb_agg(r.role ORDER BY r.role)
      FROM public.event_roles r WHERE r.event=e.id),'[]'::jsonb))
  FROM public.events e WHERE e.id=p_event_id;
$$;
REVOKE ALL ON FUNCTION public.get_event_command_data_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.save_event_client_sync_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_event jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_event_id bigint := (p_event->>'id')::bigint;
  v_version bigint;
  v_begin jsonb;
  v_commit jsonb;
  v_data jsonb;
  v_current jsonb;
  v_requested jsonb;
  v_response jsonb;
  v_program jsonb;
  v_hash text;
  v_changed boolean := true;
  v_is_publishable boolean;
  v_parent_ids bigint[];
  v_role_ids bigint[];
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable
  FROM public.occasions o WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  IF p_event IS NULL OR jsonb_typeof(p_event)<>'object'
     OR octet_length(p_event::text)>131072
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_event) key WHERE key NOT IN
       ('id','title','startTime','endTime','maxParticipants','description',
        'placeId','splitForMenWomen','isGroupEvent','isHidden','type','data',
        'order','parentEventIds','eventRoleIds'))
     OR NOT (p_event ?& ARRAY['title','startTime','endTime','splitForMenWomen',
       'isGroupEvent','isHidden','order','parentEventIds','eventRoleIds'])
     OR jsonb_typeof(p_event->'parentEventIds')<>'array'
     OR jsonb_typeof(p_event->'eventRoleIds')<>'array'
     OR jsonb_array_length(p_event->'parentEventIds')>1000
     OR jsonb_array_length(p_event->'eventRoleIds')>1000
     OR length(p_event->>'title') NOT BETWEEN 1 AND 500
     OR (p_event->>'startTime')::timestamptz >= (p_event->>'endTime')::timestamptz
     OR COALESCE((p_event->>'maxParticipants')::bigint,0)<0 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid event aggregate';
  END IF;

  SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}')
    INTO v_parent_ids FROM jsonb_array_elements_text(p_event->'parentEventIds');
  SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}')
    INTO v_role_ids FROM jsonb_array_elements_text(p_event->'eventRoleIds');
  IF cardinality(v_parent_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_parent_ids)))
     OR cardinality(v_role_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_role_ids)))
     OR (v_event_id IS NOT NULL AND v_event_id=ANY(v_parent_ids))
     OR EXISTS (SELECT 1 FROM unnest(v_parent_ids) id LEFT JOIN public.events e
       ON e.id=id AND e.occasion=p_occasion WHERE e.id IS NULL)
     OR EXISTS (SELECT 1 FROM unnest(v_role_ids) id LEFT JOIN public.role_info r
       ON r.id=id AND r.occasion=p_occasion WHERE r.id IS NULL)
     OR ((p_event->>'placeId') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.places p WHERE p.id=(p_event->>'placeId')::bigint
         AND p.occasion=p_occasion)) THEN
    RAISE invalid_parameter_value USING MESSAGE='event aggregate contains cross-scope references';
  END IF;
  v_requested:=jsonb_build_object(
    'id',v_event_id,'title',p_event->>'title',
    'startTime',(p_event->>'startTime')::timestamptz,
    'endTime',(p_event->>'endTime')::timestamptz,
    'maxParticipants',(p_event->>'maxParticipants')::bigint,
    'description',p_event->>'description',
    'placeId',(p_event->>'placeId')::bigint,
    'splitForMenWomen',(p_event->>'splitForMenWomen')::boolean,
    'isGroupEvent',(p_event->>'isGroupEvent')::boolean,
    'isHidden',(p_event->>'isHidden')::boolean,'type',p_event->>'type',
    'data',p_event->'data','order',(p_event->>'order')::bigint,
    'parentEventIds',to_jsonb(v_parent_ids),'eventRoleIds',to_jsonb(v_role_ids));

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,'event',p_event)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'event.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_event_id IS NOT NULL THEN
    PERFORM 1 FROM public.events e WHERE e.id=v_event_id AND e.occasion=p_occasion
      FOR UPDATE;
    IF NOT FOUND THEN
      v_response:=jsonb_build_object('status','rejected','code',404,
        'data',jsonb_build_object('eventId',v_event_id),
        'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
          'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('event','occasion',p_occasion,v_event_id::text,0)
    ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='event' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_event_id::text FOR UPDATE;
    v_current:=public.get_event_command_data_v1(v_event_id);
    IF p_expected_version IS DISTINCT FROM v_version THEN
      v_response:=jsonb_build_object('status','conflict','code',409,
        'data',jsonb_build_object('version',v_version,'event',v_current),
        'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
          'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;
    v_changed:=v_current IS DISTINCT FROM v_requested;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new event must not have an expected version';
  END IF;

  IF NOT v_changed THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('version',v_version,'event',v_current),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;

  IF v_event_id IS NULL THEN
    INSERT INTO public.events(title,start_time,end_time,max_participants,description,
      place,split_for_men_women,is_group_event,is_hidden,occasion,type,data,"order")
    VALUES (p_event->>'title',(p_event->>'startTime')::timestamptz,
      (p_event->>'endTime')::timestamptz,(p_event->>'maxParticipants')::bigint,
      p_event->>'description',(p_event->>'placeId')::bigint,
      (p_event->>'splitForMenWomen')::boolean,(p_event->>'isGroupEvent')::boolean,
      (p_event->>'isHidden')::boolean,p_occasion,p_event->>'type',p_event->'data',
      (p_event->>'order')::bigint) RETURNING id INTO v_event_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('event','occasion',p_occasion,v_event_id::text,v_version);
  ELSE
    UPDATE public.events SET title=p_event->>'title',
      start_time=(p_event->>'startTime')::timestamptz,
      end_time=(p_event->>'endTime')::timestamptz,
      max_participants=(p_event->>'maxParticipants')::bigint,
      description=p_event->>'description',place=(p_event->>'placeId')::bigint,
      split_for_men_women=(p_event->>'splitForMenWomen')::boolean,
      is_group_event=(p_event->>'isGroupEvent')::boolean,
      is_hidden=(p_event->>'isHidden')::boolean,type=p_event->>'type',
      data=p_event->'data',"order"=(p_event->>'order')::bigint,updated_at=now()
    WHERE id=v_event_id;
    UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp()
      WHERE aggregate_type='event' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_event_id::text
      RETURNING version INTO v_version;
  END IF;
  DELETE FROM public.event_groups WHERE event_child=v_event_id;
  INSERT INTO public.event_groups(event_parent,event_child)
    SELECT id,v_event_id FROM unnest(v_parent_ids) id;
  DELETE FROM public.event_roles WHERE event=v_event_id;
  INSERT INTO public.event_roles(event,role)
    SELECT v_event_id,id FROM unnest(v_role_ids) id;

  v_data:=jsonb_build_object('version',v_version,
    'event',public.get_event_command_data_v1(v_event_id));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'event.save','program',jsonb_build_array(jsonb_build_object(
      'entityType','event','entityId',v_event_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_event->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable THEN ARRAY['program_catalog'] ELSE '{}'::text[] END,
    '[]','[]',v_data);
END; $$;
REVOKE ALL ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_event_client_sync_v1(
  p_occasion bigint,p_event_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_version bigint; v_event jsonb;
  v_commit jsonb; v_program jsonb; v_response jsonb; v_hash text;
  v_is_publishable boolean; v_users uuid[]; v_private_impacts jsonb;
  v_had_speakers boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable
  FROM public.occasions o WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'eventId',p_event_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'event.delete',p_occasion,
    v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.events e WHERE e.id=p_event_id AND e.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('eventId',p_event_id,'deleted',false),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('event','occasion',p_occasion,p_event_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='event' AND scope_type='occasion' AND scope_id=p_occasion
      AND aggregate_id=p_event_id::text FOR UPDATE;
  v_event:=public.get_event_command_data_v1(p_event_id);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    v_response:=jsonb_build_object('status','conflict','code',409,
      'data',jsonb_build_object('version',v_version,'event',v_event),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  SELECT ARRAY(SELECT DISTINCT id FROM (
    SELECT eu."user" id FROM public.event_users eu WHERE eu.event=p_event_id
    UNION SELECT eus."user" FROM public.event_users_saved eus
      WHERE eus.event=p_event_id) users ORDER BY id) INTO v_users;
  SELECT EXISTS (SELECT 1 FROM public.event_speakers es WHERE es.event=p_event_id)
    INTO v_had_speakers;
  DELETE FROM public.event_users WHERE event=p_event_id;
  DELETE FROM public.event_users_saved WHERE event=p_event_id;
  DELETE FROM public.exclusive_events WHERE event=p_event_id;
  DELETE FROM public.event_roles WHERE event=p_event_id;
  DELETE FROM public.event_groups WHERE event_parent=p_event_id OR event_child=p_event_id;
  DELETE FROM public.events WHERE id=p_event_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='event'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_event_id::text;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_program',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts
    FROM unnest(COALESCE(v_users,'{}'::uuid[])) id
    JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'event.delete','program',jsonb_build_array(jsonb_build_object(
      'entityType','event','entityId',p_event_id,'operation','delete',
      'safeLabel',left(v_event->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable THEN ARRAY['program_catalog','live_public']||
      CASE WHEN v_had_speakers THEN ARRAY['content_catalog'] ELSE '{}'::text[] END
      ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_is_publishable THEN jsonb_build_array(jsonb_build_object(
      'component','live_public','entityId',p_event_id)) ELSE '[]'::jsonb END,
    jsonb_build_object('eventId',p_event_id,'deleted',true));
END; $$;
REVOKE ALL ON FUNCTION public.delete_event_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_event_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

-- Guarded attendance transition. Lock order is participant advisory lock,
-- sorted exclusive-group advisory locks, then the authoritative event row.
-- This serializes schedule/counseling decisions per participant and capacity
-- decisions per event without relying on the eventually-consistent projection.
CREATE OR REPLACE FUNCTION public.set_event_attendance_client_sync_v1(
  p_event_id bigint,p_participant_id uuid,p_action text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_occasion bigint; v_event public.events%ROWTYPE;
  v_begin jsonb; v_hash text; v_response jsonb; v_commit jsonb;
  v_private_revision bigint; v_live_revision bigint; v_private_payload jsonb;
  v_live_payload jsonb; v_code integer; v_registration_start timestamptz;
  v_feature jsonb; v_limit integer; v_count bigint; v_group bigint;
  v_is_male boolean; v_changed boolean:=false; v_status text;
  v_needs_occasion_join boolean:=false; v_profile_revision bigint;
  v_profile_payload jsonb; v_private_impacts jsonb; v_items jsonb;
  v_is_publishable boolean; v_companion_owner uuid;
BEGIN
  IF p_action NOT IN ('sign_in','sign_out') OR p_participant_id IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid attendance command';
  END IF;
  SELECT e.occasion,NOT o.is_hidden INTO v_occasion,v_is_publishable
  FROM public.events e JOIN public.occasions o ON o.id=e.occasion
  WHERE e.id=p_event_id;
  IF v_actor IS NULL OR v_occasion IS NULL OR NOT (
    v_actor=p_participant_id OR EXISTS (SELECT 1 FROM public.user_companions c
      WHERE c."user"=v_actor AND c.companion=p_participant_id)
    OR public.get_is_editor_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='participant attendance permission required';
  END IF;
  SELECT c."user" INTO v_companion_owner FROM public.user_companions c
    JOIN public.occasion_users ou ON ou."user"=c."user" AND ou.occasion=v_occasion
    WHERE c.companion=p_participant_id ORDER BY c."user" LIMIT 1;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('eventId',p_event_id,
    'participantId',p_participant_id,'action',p_action)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'event.attendance.'||p_action,
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'attendance-user:'||p_participant_id::text||':'||v_occasion::text,0));
  FOR v_group IN SELECT ee."group" FROM public.exclusive_events ee
      WHERE ee.event=p_event_id ORDER BY ee."group" LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'attendance-group:'||v_group::text,0));
  END LOOP;
  SELECT * INTO STRICT v_event FROM public.events e WHERE e.id=p_event_id
    AND e.occasion=v_occasion FOR UPDATE;

  IF p_action='sign_out' THEN
    IF NOT EXISTS (SELECT 1 FROM public.event_users eu
      WHERE eu.event=p_event_id AND eu."user"=p_participant_id) THEN
      v_status:='unchanged'; v_code:=404;
    ELSIF clock_timestamp() > v_event.end_time THEN
      v_status:='rejected'; v_code:=201;
    ELSE
      DELETE FROM public.event_users WHERE event=p_event_id AND "user"=p_participant_id;
      v_changed:=true; v_code:=200;
    END IF;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=v_occasion AND ou."user"=p_participant_id) THEN
      IF v_actor=p_participant_id AND EXISTS (SELECT 1 FROM public.occasions o
        WHERE o.id=v_occasion AND o.is_open) THEN
        v_needs_occasion_join:=true;
      END IF;
      IF NOT v_needs_occasion_join THEN
        v_status:='rejected'; v_code:=403;
      END IF;
    END IF;
    IF v_code IS NULL AND EXISTS (SELECT 1 FROM public.event_users eu
      WHERE eu.event=p_event_id AND eu."user"=p_participant_id) THEN
      v_status:='unchanged'; v_code:=103;
    END IF;
    IF v_code IS NULL AND clock_timestamp() > v_event.end_time THEN
      v_status:='rejected'; v_code:=100;
    END IF;

    IF v_code IS NULL AND COALESCE((v_event.data->>'is_counseling_slot')::boolean,false) THEN
      SELECT f INTO v_feature FROM public.occasions o,
        LATERAL jsonb_array_elements(o.features) f
      WHERE o.id=v_occasion AND f->>'code'='counseling' LIMIT 1;
      IF v_feature IS NULL OR COALESCE((v_feature->>'is_enabled')::boolean,false)=false THEN
        v_status:='rejected'; v_code:=108;
      ELSE
        v_registration_start:=(v_feature->>'registration_start_time')::timestamptz;
        IF v_registration_start IS NOT NULL AND clock_timestamp()<v_registration_start THEN
          v_status:='rejected'; v_code:=104;
        END IF;
        v_limit:=COALESCE((v_feature->>'max_active_bookings')::integer,1);
        IF v_code IS NULL AND v_limit>0 THEN
          SELECT count(*) INTO v_count FROM public.event_users eu
          JOIN public.events e ON e.id=eu.event
          WHERE eu."user"=p_participant_id AND e.occasion=v_occasion
            AND COALESCE((e.data->>'is_counseling_slot')::boolean,false)
            AND e.end_time>clock_timestamp();
          IF v_count>=v_limit THEN v_status:='rejected'; v_code:=109; END IF;
        END IF;
      END IF;
    ELSIF v_code IS NULL THEN
      SELECT f INTO v_feature FROM public.occasions o,
        LATERAL jsonb_array_elements(o.features) f
      WHERE o.id=v_occasion AND f->>'code'='workshops' LIMIT 1;
      IF v_feature IS NOT NULL THEN
        IF COALESCE((v_feature->>'is_enabled')::boolean,false)=false THEN
          v_status:='rejected'; v_code:=108;
        ELSE
          v_registration_start:=(v_feature->>'start_time')::timestamptz;
          IF v_registration_start IS NOT NULL AND clock_timestamp()<v_registration_start THEN
            v_status:='rejected'; v_code:=104;
          END IF;
        END IF;
      END IF;
    END IF;

    IF v_code IS NULL AND EXISTS (
      SELECT 1 FROM public.exclusive_events target
      JOIN public.exclusive_events occupied ON occupied."group"=target."group"
      JOIN public.event_users eu ON eu.event=occupied.event
      WHERE target.event=p_event_id AND eu."user"=p_participant_id) THEN
      v_status:='rejected'; v_code:=102;
    END IF;
    IF v_code IS NULL AND EXISTS (
      SELECT 1 FROM public.event_users eu JOIN public.events e ON e.id=eu.event
      WHERE eu."user"=p_participant_id AND e.id<>p_event_id
        AND e.start_time<v_event.end_time AND e.end_time>v_event.start_time) THEN
      v_status:='rejected'; v_code:=107;
    END IF;
    IF v_code IS NULL AND COALESCE(v_event.max_participants,0)>0 THEN
      SELECT count(*) INTO v_count FROM public.event_users eu WHERE eu.event=p_event_id;
      IF v_event.split_for_men_women THEN
        SELECT COALESCE(u.sex='male',false) INTO v_is_male
          FROM public.user_info u WHERE u.id=p_participant_id;
        SELECT count(*) INTO v_count FROM public.event_users eu
          JOIN public.user_info u ON u.id=eu."user" WHERE eu.event=p_event_id
            AND (u.sex='male')=v_is_male;
        IF v_count>=v_event.max_participants/2 THEN
          v_status:='rejected'; v_code:=CASE WHEN v_is_male THEN 105 ELSE 106 END;
        END IF;
      ELSIF v_count>=v_event.max_participants THEN
        v_status:='rejected'; v_code:=101;
      END IF;
    END IF;
    IF v_code IS NULL THEN
      IF v_needs_occasion_join THEN
        PERFORM public.add_user_to_occasion_internal_v1(v_occasion,p_participant_id);
        IF NOT EXISTS (SELECT 1 FROM public.occasion_users ou
          WHERE ou.occasion=v_occasion AND ou."user"=p_participant_id) THEN
          RAISE EXCEPTION 'occasion membership handler did not create membership';
        END IF;
      END IF;
      INSERT INTO public.event_users(event,"user") VALUES(p_event_id,p_participant_id);
      v_changed:=true; v_code:=200;
    END IF;
  END IF;

  IF NOT v_changed THEN
    v_response:=jsonb_build_object('status',v_status,'code',v_code,
      'data',jsonb_build_object('eventId',p_event_id,'participantId',p_participant_id,
        'isSignedIn',EXISTS(SELECT 1 FROM public.event_users eu
          WHERE eu.event=p_event_id AND eu."user"=p_participant_id),
        'eventsRegistrationStart',v_registration_start),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;

  v_items:=jsonb_build_array(jsonb_build_object(
      'entityType','event_attendance','entityId',p_event_id||':'||p_participant_id::text,
      'operation','update','safeLabel','Event attendance',
      'changedFields',jsonb_build_array('is_signed_in')));
  v_private_impacts:=jsonb_build_array(jsonb_build_object(
    'component','private_program','userId',p_participant_id));
  IF v_companion_owner IS NOT NULL THEN
    v_private_impacts:=v_private_impacts||jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_companion_owner));
  END IF;
  IF v_needs_occasion_join THEN
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'entityType','occasion_membership','entityId',p_participant_id,
      'operation','insert','safeLabel','Occasion membership',
      'changedFields',jsonb_build_array('occasion')));
    v_private_impacts:=v_private_impacts||jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',p_participant_id));
  END IF;
  v_commit:=public.record_client_sync_commit_v1(v_occasion,
    'event.attendance.'||p_action,'attendance',v_items,
    CASE WHEN v_is_publishable THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    v_private_impacts,CASE WHEN v_is_publishable THEN jsonb_build_array(
      jsonb_build_object('component','live_public','entityId',p_event_id))
      ELSE '[]'::jsonb END,'user',NULL);
  SELECT source_revision INTO v_private_revision FROM public.client_sync_private_scopes
    WHERE component='private_program' AND occasion=v_occasion AND user_id=p_participant_id;
  IF v_needs_occasion_join OR v_companion_owner IS NOT NULL THEN
    SELECT source_revision INTO STRICT v_profile_revision
    FROM public.client_sync_private_scopes
    WHERE component='private_profile' AND occasion=v_occasion
      AND user_id=COALESCE(v_companion_owner,p_participant_id);
    v_profile_payload:=public.get_private_profile_payload_v1(
      v_occasion,COALESCE(v_companion_owner,p_participant_id));
  END IF;
  SELECT jsonb_build_object(
    'signedIn',COALESCE(jsonb_agg(eu.event ORDER BY eu.event),'[]'::jsonb),
    'saved',(SELECT COALESCE(jsonb_agg(es.event ORDER BY es.event),'[]'::jsonb)
      FROM public.event_users_saved es JOIN public.events e ON e.id=es.event
      WHERE es."user"=p_participant_id AND e.occasion=v_occasion))
    INTO v_private_payload FROM public.event_users eu JOIN public.events e ON e.id=eu.event
    WHERE eu."user"=p_participant_id AND e.occasion=v_occasion;
  IF v_is_publishable THEN
    SELECT source_revision INTO v_live_revision FROM public.client_sync_scopes
      WHERE component='live_public' AND scope_type='occasion' AND scope_id=v_occasion;
    INSERT INTO public.event_public_state
      (occasion,event,participant_count,saved_count,remaining_capacity,revision,projected_at)
    SELECT v_occasion,v_event.id,count(DISTINCT eu."user"),count(DISTINCT es."user"),
      CASE WHEN v_event.max_participants IS NULL THEN NULL
        ELSE GREATEST(v_event.max_participants-count(DISTINCT eu."user"),0) END,
      v_live_revision,clock_timestamp()
    FROM (SELECT 1) seed LEFT JOIN public.event_users eu ON eu.event=v_event.id
    LEFT JOIN public.event_users_saved es ON es.event=v_event.id
    ON CONFLICT (occasion,event) DO UPDATE SET
      participant_count=EXCLUDED.participant_count,saved_count=EXCLUDED.saved_count,
      remaining_capacity=EXCLUDED.remaining_capacity,revision=EXCLUDED.revision,
      projected_at=EXCLUDED.projected_at;
    SELECT jsonb_build_object(
      'events',COALESCE(jsonb_agg(jsonb_build_object('eventId',s.event,
        'participantCount',s.participant_count,'savedCount',s.saved_count,
        'remainingCapacity',s.remaining_capacity) ORDER BY s.event),'[]'::jsonb),
      'cleaning',(SELECT COALESCE(jsonb_agg(jsonb_build_object('placeId',c.place,
        'status',c.status,'openReportCount',c.open_report_count) ORDER BY c.place),'[]'::jsonb)
        FROM public.cleaning_public_state c WHERE c.occasion=v_occasion))
      INTO v_live_payload FROM public.event_public_state s JOIN public.events e ON e.id=s.event
      WHERE s.occasion=v_occasion AND NOT e.is_hidden;
  END IF;
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('eventId',p_event_id,'participantId',p_participant_id,
      'isSignedIn',p_action='sign_in'),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',
      CASE WHEN v_is_publishable THEN jsonb_build_array(jsonb_build_object(
        'component','live_public','revision',v_live_revision,
        'payload',v_live_payload)) ELSE '[]'::jsonb END ||
      CASE WHEN v_actor=p_participant_id THEN jsonb_build_array(jsonb_build_object(
        'component','private_program','revision',v_private_revision,
        'payload',v_private_payload)) ELSE '[]'::jsonb END ||
        CASE WHEN v_needs_occasion_join OR v_companion_owner=v_actor
          THEN jsonb_build_array(jsonb_build_object(
          'component','private_profile','revision',v_profile_revision,
          'payload',v_profile_payload)) ELSE '[]'::jsonb END));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $$;
REVOKE ALL ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_saved_program_client_sync_v1(
  p_occasion bigint,p_event_ids bigint[],p_mode text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_ids bigint[]; v_before bigint[]; v_after bigint[];
  v_changed_ids bigint[]; v_begin jsonb; v_hash text; v_commit jsonb;
  v_private_revision bigint; v_live_revision bigint; v_private_payload jsonb;
  v_live_payload jsonb; v_response jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR p_mode NOT IN ('join','remove','replace')
    OR cardinality(COALESCE(p_event_ids,'{}'))>5000
    OR NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=v_actor) THEN
    RAISE insufficient_privilege USING MESSAGE='invalid saved-program command';
  END IF;
  SELECT NOT o.is_hidden INTO STRICT v_is_publishable
  FROM public.occasions o WHERE o.id=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT id ORDER BY id),'{}') INTO v_ids
    FROM unnest(COALESCE(p_event_ids,'{}')) id;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) id LEFT JOIN public.events e
    ON e.id=id AND e.occasion=p_occasion WHERE e.id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='saved program contains cross-scope events';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'eventIds',to_jsonb(v_ids),'mode',p_mode)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.saved.'||p_mode,
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'saved-program:'||v_actor::text||':'||p_occasion::text,0));
  SELECT COALESCE(array_agg(es.event ORDER BY es.event),'{}') INTO v_before
    FROM public.event_users_saved es JOIN public.events e ON e.id=es.event
    WHERE es."user"=v_actor AND e.occasion=p_occasion;
  IF p_mode='replace' THEN
    DELETE FROM public.event_users_saved es USING public.events e
      WHERE es.event=e.id AND es."user"=v_actor AND e.occasion=p_occasion
        AND NOT es.event=ANY(v_ids);
    INSERT INTO public.event_users_saved(event,"user")
      SELECT id,v_actor FROM unnest(v_ids) id ON CONFLICT DO NOTHING;
  ELSIF p_mode='join' THEN
    INSERT INTO public.event_users_saved(event,"user")
      SELECT id,v_actor FROM unnest(v_ids) id ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.event_users_saved es
      WHERE es."user"=v_actor AND es.event=ANY(v_ids);
  END IF;
  SELECT COALESCE(array_agg(es.event ORDER BY es.event),'{}') INTO v_after
    FROM public.event_users_saved es JOIN public.events e ON e.id=es.event
    WHERE es."user"=v_actor AND e.occasion=p_occasion;
  IF v_before=v_after THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('saved',to_jsonb(v_after)),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  SELECT array_agg(DISTINCT id ORDER BY id) INTO v_changed_ids FROM (
    (SELECT unnest(v_before) id EXCEPT SELECT unnest(v_after)) UNION
    (SELECT unnest(v_after) id EXCEPT SELECT unnest(v_before))) changed;
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'program.saved.'||p_mode,
    'saved_program',jsonb_build_array(jsonb_build_object('entityType','saved_program',
      'entityId',v_actor,'operation','update','safeLabel','Saved program',
      'changedFields',jsonb_build_array('event_ids'))),
    CASE WHEN v_is_publishable THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    jsonb_build_array(jsonb_build_object('component','private_program','userId',v_actor)),
    CASE WHEN v_is_publishable THEN (SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',id)) FROM unnest(v_changed_ids) id)
      ELSE '[]'::jsonb END,'user',NULL);
  SELECT source_revision INTO v_private_revision FROM public.client_sync_private_scopes
    WHERE component='private_program' AND occasion=p_occasion AND user_id=v_actor;
  SELECT jsonb_build_object(
    'signedIn',(SELECT COALESCE(jsonb_agg(eu.event ORDER BY eu.event),'[]'::jsonb)
      FROM public.event_users eu JOIN public.events e ON e.id=eu.event
      WHERE eu."user"=v_actor AND e.occasion=p_occasion),
    'saved',to_jsonb(v_after)) INTO v_private_payload;
  IF v_is_publishable THEN
    SELECT source_revision INTO v_live_revision FROM public.client_sync_scopes
      WHERE component='live_public' AND scope_type='occasion' AND scope_id=p_occasion;
    INSERT INTO public.event_public_state
      (occasion,event,participant_count,saved_count,remaining_capacity,revision,projected_at)
    SELECT e.occasion,e.id,count(DISTINCT eu."user"),count(DISTINCT es."user"),
      CASE WHEN e.max_participants IS NULL THEN NULL
        ELSE GREATEST(e.max_participants-count(DISTINCT eu."user"),0) END,
      v_live_revision,clock_timestamp()
    FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
    LEFT JOIN public.event_users_saved es ON es.event=e.id
    WHERE e.occasion=p_occasion AND e.id=ANY(v_changed_ids)
    GROUP BY e.occasion,e.id,e.max_participants
    ON CONFLICT (occasion,event) DO UPDATE SET participant_count=EXCLUDED.participant_count,
      saved_count=EXCLUDED.saved_count,remaining_capacity=EXCLUDED.remaining_capacity,
      revision=EXCLUDED.revision,projected_at=EXCLUDED.projected_at;
    SELECT jsonb_build_object(
      'events',COALESCE(jsonb_agg(jsonb_build_object('eventId',s.event,
        'participantCount',s.participant_count,'savedCount',s.saved_count,
        'remainingCapacity',s.remaining_capacity) ORDER BY s.event),'[]'::jsonb),
      'cleaning',(SELECT COALESCE(jsonb_agg(jsonb_build_object('placeId',c.place,
        'status',c.status,'openReportCount',c.open_report_count) ORDER BY c.place),'[]'::jsonb)
        FROM public.cleaning_public_state c WHERE c.occasion=p_occasion))
      INTO v_live_payload FROM public.event_public_state s JOIN public.events e ON e.id=s.event
      WHERE s.occasion=p_occasion AND NOT e.is_hidden;
  END IF;
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('saved',to_jsonb(v_after)),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',
      CASE WHEN v_is_publishable THEN jsonb_build_array(jsonb_build_object(
        'component','live_public','revision',v_live_revision,
        'payload',v_live_payload)) ELSE '[]'::jsonb END ||
      jsonb_build_array(jsonb_build_object('component','private_program',
        'revision',v_private_revision,'payload',v_private_payload))));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $$;
REVOKE ALL ON FUNCTION public.set_saved_program_client_sync_v1(bigint,bigint[],text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_saved_program_client_sync_v1(bigint,bigint[],text,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.publish_activities_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,
  p_activities_data jsonb,p_history_data jsonb,p_parent_history_id bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_version bigint;
  v_handler jsonb; v_history_id bigint; v_commit jsonb; v_response jsonb;
  v_private_impacts jsonb; v_old_users uuid[]; v_activity jsonb; v_assignment jsonb;
  v_actor_private_revision bigint; v_actor_private_payload jsonb;
  v_latest_publish_unchanged boolean:=false;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  IF p_activities_data IS NULL OR jsonb_typeof(p_activities_data)<>'array'
     OR p_history_data IS NULL OR jsonb_typeof(p_history_data)<>'object'
     OR octet_length(p_activities_data::text)>2097152
     OR octet_length(p_history_data::text)>2097152
     OR jsonb_array_length(p_activities_data)>2000 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid activities aggregate';
  END IF;
  FOR v_activity IN SELECT value FROM jsonb_array_elements(p_activities_data) LOOP
    IF jsonb_typeof(v_activity)<>'object' OR NOT (v_activity ?& ARRAY[
      'id','title','is_hidden','order','assignments'])
      OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_activity) key WHERE key NOT IN
        ('id','title','description','type','unit','is_hidden','order','data','assignments'))
      OR jsonb_typeof(v_activity->'assignments')<>'array'
      OR EXISTS (SELECT 1 FROM public.activities a
        WHERE a.id=(v_activity->>'id')::uuid AND a.occasion<>p_occasion) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid or cross-scope activity';
    END IF;
    FOR v_assignment IN SELECT value FROM jsonb_array_elements(v_activity->'assignments') LOOP
      IF jsonb_typeof(v_assignment)<>'object'
        OR NOT (v_assignment ?& ARRAY['id','linked_place_ids','linked_event_ids'])
        OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_assignment) key WHERE key NOT IN
          ('id','user','start_time','end_time','title','description','data',
           'linked_place_ids','linked_event_ids'))
        OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(
          COALESCE(v_assignment->'linked_place_ids','[]')) id
          LEFT JOIN public.places p ON p.id=id::bigint AND p.occasion=p_occasion
          WHERE p.id IS NULL)
        OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(
          COALESCE(v_assignment->'linked_event_ids','[]')) id
          LEFT JOIN public.events e ON e.id=id::bigint AND e.occasion=p_occasion
          WHERE e.id IS NULL)
        OR ((v_assignment->>'user') IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM public.occasion_users ou
          WHERE ou.occasion=p_occasion AND ou."user"=(v_assignment->>'user')::uuid))
        OR EXISTS (SELECT 1 FROM public.activity_assignments aa
          JOIN public.activities a ON a.id=aa.activity_id
          WHERE aa.id=(v_assignment->>'id')::uuid AND a.occasion<>p_occasion) THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid activity assignment references';
      END IF;
    END LOOP;
  END LOOP;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'activities',p_activities_data,
    'history',p_history_data,'parentHistoryId',p_parent_history_id)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'activities.publish',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('activities','occasion',p_occasion,p_occasion::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion
      AND aggregate_id=p_occasion::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    v_response:=jsonb_build_object('status','conflict','code',409,
      'data',jsonb_build_object('version',v_version),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  SELECT h.activities_data=p_history_data INTO v_latest_publish_unchanged
  FROM public.activity_history h WHERE h.occasion_id=p_occasion
    AND h.history_type='PUBLISH' ORDER BY h.id DESC LIMIT 1;
  IF COALESCE(v_latest_publish_unchanged,false) THEN
    v_response:=jsonb_build_object('status','unchanged','code',200,
      'data',jsonb_build_object('version',v_version,'historyId',p_parent_history_id),
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;
  SELECT array_agg(DISTINCT aa."user") INTO v_old_users
    FROM public.activity_assignments aa JOIN public.activities a ON a.id=aa.activity_id
    WHERE a.occasion=p_occasion;
  v_handler:=public.update_activities(p_occasion,p_activities_data);
  IF COALESCE((v_handler->>'code')::integer,500)<>200 THEN
    RAISE EXCEPTION 'activities aggregate handler failed: %',v_handler->>'message';
  END IF;
  INSERT INTO public.activity_history
    (occasion_id,user_id,activities_data,history_type,note,parent_history_id)
  VALUES (p_occasion,v_actor,p_history_data,'PUBLISH','Published via application',
    p_parent_history_id) RETURNING id INTO v_history_id;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='activities'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text
    RETURNING version INTO v_version;
  WITH affected(user_id) AS (
    SELECT v_actor UNION
    SELECT unnest(COALESCE(v_old_users,'{}'::uuid[])) UNION
    SELECT aa."user" FROM public.activity_assignments aa
      JOIN public.activities a ON a.id=aa.activity_id WHERE a.occasion=p_occasion
  ) SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_activity',
      'userId',user_id)),'[]'::jsonb) INTO v_private_impacts FROM affected
      WHERE user_id IS NOT NULL;
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'activities.publish',
    'activities',jsonb_build_array(jsonb_build_object('entityType','activities',
      'entityId',p_occasion,'operation','publish','safeLabel','Activities',
    'changedFields',jsonb_build_array('aggregate'))),'{}',v_private_impacts,
    '[]','user',NULL);
  SELECT s.source_revision INTO STRICT v_actor_private_revision
  FROM public.client_sync_private_scopes s
  WHERE s.component='private_activity' AND s.occasion=p_occasion
    AND s.user_id=v_actor;
  v_actor_private_payload:=public.get_my_events_and_activities(
    p_occasion,true)->'data';
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('version',v_version,'historyId',v_history_id,
      'activities',p_activities_data),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',jsonb_build_array(
      jsonb_build_object('component','private_activity',
        'revision',v_actor_private_revision,'payload',v_actor_private_payload))));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $$;
REVOKE ALL ON FUNCTION public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_inventory_pool_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_bundle jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_pool_id bigint:=(p_bundle#>>'{pool,id}')::bigint;
  v_version bigint; v_begin jsonb; v_hash text; v_result jsonb;
  v_commit jsonb; v_response jsonb; v_private_impacts jsonb;
  v_current_command_data jsonb; v_requested_command_data jsonb;
  v_actor_private_revision bigint; v_actor_private_payload jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_order_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required';
  END IF;
  IF p_bundle IS NULL OR jsonb_typeof(p_bundle)<>'object'
    OR octet_length(p_bundle::text)>1048576
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_bundle) key
      WHERE key NOT IN ('pool','contexts'))
    OR jsonb_typeof(p_bundle->'pool')<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_bundle->'pool') key
      WHERE key NOT IN ('id','title','sellable_capacity','occasion',
        'description','type','data'))
    OR jsonb_typeof(p_bundle->'contexts')<>'array'
    OR jsonb_array_length(p_bundle->'contexts')>2000
    OR (p_bundle#>>'{pool,occasion}')::bigint IS DISTINCT FROM p_occasion
    OR (v_pool_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.inventory_pools ip
      WHERE ip.id=v_pool_id AND ip.occasion=p_occasion))
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_bundle->'contexts') c
      WHERE jsonb_typeof(c)<>'object' OR EXISTS (
        SELECT 1 FROM jsonb_object_keys(c) key
        WHERE key NOT IN ('id','inventory_pool','block_date','title','order','data'))
      OR ((c->>'id') IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.inventory_contexts ic
        WHERE ic.id=(c->>'id')::bigint AND ic.inventory_pool=v_pool_id))) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid or cross-scope inventory aggregate';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'bundle',p_bundle)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.pool.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_pool_id IS NOT NULL THEN
    PERFORM 1 FROM public.inventory_pools ip WHERE ip.id=v_pool_id
      AND ip.occasion=p_occasion FOR UPDATE;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('inventory_pool','occasion',p_occasion,v_pool_id::text,0)
    ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='inventory_pool' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_pool_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      v_response:=jsonb_build_object('status','conflict','code',409,
        'data',jsonb_build_object('version',v_version,
          'bundle',public.get_inventory_pool_bundle(v_pool_id)),
        'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
          'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;

    SELECT jsonb_build_object(
      'pool',jsonb_build_object('id',ip.id,'title',ip.title,
        'sellable_capacity',ip.sellable_capacity,'occasion',ip.occasion,
        'description',ip.description,'type',ip.type,'data',ip.data),
      'contexts',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id',ic.id,'inventory_pool',ic.inventory_pool,
        'block_date',ic.block_date,'title',ic.title,'order',ic."order",
        'data',ic.data) ORDER BY ic."order",ic.id)
        FROM public.inventory_contexts ic
        WHERE ic.inventory_pool=ip.id),'[]'::jsonb))
      INTO v_current_command_data
    FROM public.inventory_pools ip WHERE ip.id=v_pool_id;
    SELECT jsonb_build_object(
      'pool',jsonb_build_object('id',(p_bundle#>>'{pool,id}')::bigint,
        'title',p_bundle#>>'{pool,title}',
        'sellable_capacity',(p_bundle#>>'{pool,sellable_capacity}')::bigint,
        'occasion',(p_bundle#>>'{pool,occasion}')::bigint,
        'description',p_bundle#>>'{pool,description}',
        'type',p_bundle#>>'{pool,type}','data',p_bundle#>'{pool,data}'),
      'contexts',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id',(c->>'id')::bigint,'inventory_pool',v_pool_id,
        'block_date',(c->>'block_date')::date,'title',c->>'title',
        'order',(c->>'order')::bigint,'data',c->'data')
        ORDER BY (c->>'order')::bigint,(c->>'id')::bigint)
        FROM jsonb_array_elements(p_bundle->'contexts') c),'[]'::jsonb))
      INTO v_requested_command_data;
    IF v_current_command_data = v_requested_command_data THEN
      v_response:=jsonb_build_object('status','unchanged','code',200,
        'data',jsonb_build_object('version',v_version,
          'bundle',public.get_inventory_pool_bundle(v_pool_id)),
        'mutation',jsonb_build_object('commandId',p_command_id,
          'receiptId',p_command_id,'commitId',NULL,'replayed',false,
          'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new inventory pool must not have expected version';
  END IF;

  v_result:=public.update_inventory_pool_bundle(p_bundle);
  IF v_result ? 'code' AND COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE EXCEPTION 'inventory aggregate handler failed: %',v_result->>'message';
  END IF;
  v_pool_id:=(v_result#>>'{pool,id}')::bigint;
  IF v_pool_id IS NULL THEN RAISE EXCEPTION 'inventory handler returned no pool id'; END IF;
  IF v_version IS NULL THEN
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('inventory_pool','occasion',p_occasion,v_pool_id::text,v_version);
  ELSE
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='inventory_pool'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_pool_id::text
      RETURNING version INTO v_version;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_private_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'inventory.pool.save',
    'inventory',jsonb_build_array(jsonb_build_object('entityType','inventory_pool',
      'entityId',v_pool_id,'operation',CASE WHEN (p_bundle#>>'{pool,id}') IS NULL
        THEN 'insert' ELSE 'update' END,'safeLabel',left(v_result#>>'{pool,title}',240),
      'changedFields',jsonb_build_array('aggregate'))),'{}',v_private_impacts,
    '[]','user',NULL);
  SELECT s.source_revision INTO STRICT v_actor_private_revision
  FROM public.client_sync_private_scopes s
  WHERE s.component='private_inventory' AND s.occasion=p_occasion
    AND s.user_id=v_actor;
  v_actor_private_payload:=public.get_user_inventory_for_occasion_v1(p_occasion);
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version);
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('version',v_version,'bundle',v_result),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',jsonb_build_array(
      jsonb_build_object('component','private_inventory',
        'revision',v_actor_private_revision,'payload',v_actor_private_payload))));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $$;
REVOKE ALL ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

-- Map editor read model. Public map consumers still use the closed
-- map_catalog artifact; this authenticated view includes hidden rows and the
-- optimistic-concurrency versions required by editor commands.
CREATE OR REPLACE FUNCTION public.get_map_editor_bundle_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE WHEN NOT public.get_is_editor_view_on_occasion(p_occasion)
    THEN jsonb_build_object('code',403)
    ELSE jsonb_build_object(
      'code',200,
      'places',COALESCE((SELECT jsonb_agg(to_jsonb(p)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY p."order" NULLS LAST,p.id)
        FROM public.places p LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='place' AND v.scope_type='occasion'
          AND v.scope_id=p_occasion AND v.aggregate_id=p.id::text
        WHERE p.occasion=p_occasion),'[]'::jsonb),
      'placeTypes',COALESCE((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY t."order" NULLS LAST,t.id)
        FROM public.place_types t LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='place_type' AND v.scope_type='occasion'
          AND v.scope_id=p_occasion AND v.aggregate_id=t.id::text
        WHERE t.occasion=p_occasion),'[]'::jsonb),
      'paths',COALESCE((SELECT jsonb_agg(to_jsonb(pg)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY pg."order" NULLS LAST,pg.id)
        FROM public.path_groups pg LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='path' AND v.scope_type='occasion'
          AND v.scope_id=p_occasion AND v.aggregate_id=pg.id::text
        WHERE pg.occasion=p_occasion),'[]'::jsonb),
      'icons',COALESCE((SELECT jsonb_agg(to_jsonb(i)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0)) ORDER BY i.link,i.id)
        FROM public.occasions o JOIN public.icons i ON i.organization=o.organization
          AND (i.unit=o.unit OR i.unit IS NULL)
        LEFT JOIN public.client_aggregate_versions v
          ON v.aggregate_type='icon' AND v.scope_type='unit'
          AND v.scope_id=o.unit AND v.aggregate_id=i.id::text
        WHERE o.id=p_occasion),'[]'::jsonb)) END;
$$;
REVOKE ALL ON FUNCTION public.get_map_editor_bundle_v1(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_map_editor_bundle_v1(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_icon_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_icon jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_unit bigint; v_organization bigint; v_id bigint;
  v_begin jsonb; v_hash text; v_commit jsonb; v_icon jsonb; v_response jsonb;
BEGIN
  SELECT o.unit,o.organization INTO v_unit,v_organization FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_actor IS NULL OR v_unit IS NULL OR NOT public.get_is_editor_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit editor required';
  END IF;
  IF p_icon IS NULL OR jsonb_typeof(p_icon)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_icon) key WHERE key NOT IN ('link','svg'))
    OR NOT (p_icon ?& ARRAY['link','svg'])
    OR length(p_icon->>'link') NOT BETWEEN 1 AND 200
    OR octet_length(COALESCE(p_icon->>'svg','')) NOT BETWEEN 1 AND 51200 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid icon';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'icon',p_icon)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'map.icon.save',p_occasion,
    v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  INSERT INTO public.icons(link,data,organization,unit,created_by)
  VALUES (p_icon->>'link',p_icon->>'svg',v_organization,v_unit,v_actor)
  RETURNING id INTO v_id;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('icon','unit',v_unit,v_id::text,1);
  SELECT to_jsonb(i)||jsonb_build_object('aggregate_version',1)
    INTO v_icon FROM public.icons i WHERE i.id=v_id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'map.icon.save','map',
    jsonb_build_array(jsonb_build_object('entityType','icon','entityId',v_id,
      'operation','insert','safeLabel',left(p_icon->>'link',240),
      'changedFields',jsonb_build_array('aggregate'))),'{}','[]','[]',
    jsonb_build_object('icon',v_icon));
END; $$;
REVOKE ALL ON FUNCTION public.save_icon_client_sync_v1(bigint,uuid,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_icon_client_sync_v1(bigint,uuid,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_icon_client_sync_v1(
  p_occasion bigint,p_icon_id bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_unit bigint; v_icon public.icons%ROWTYPE;
  v_begin jsonb; v_hash text; v_commit jsonb; v_response jsonb;
  v_places bigint; v_paths bigint; v_types bigint; v_refs jsonb;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR v_unit IS NULL OR NOT public.get_is_editor_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit editor required';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'iconId',p_icon_id)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'map.icon.delete',p_occasion,
    v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT i.* INTO v_icon FROM public.icons i WHERE i.id=p_icon_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('icon',NULL));
  END IF;
  IF v_icon.unit IS NULL OR v_icon.unit IS DISTINCT FROM v_unit THEN
    RAISE insufficient_privilege USING MESSAGE='icon belongs to another unit or is legacy';
  END IF;
  SELECT count(*) INTO v_places FROM public.places p WHERE p.icon=p_icon_id;
  SELECT count(*) INTO v_paths FROM public.path_groups pg WHERE pg.icon=p_icon_id;
  SELECT count(*) INTO v_types FROM public.place_types pt WHERE pt.icon=p_icon_id;
  IF v_places+v_paths+v_types>0 THEN
    v_refs:=jsonb_build_object('places',v_places,'path_groups',v_paths,
      'place_types',v_types);
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'rejected',409,jsonb_build_object('icon',to_jsonb(v_icon),'refs',v_refs));
  END IF;
  DELETE FROM public.icons WHERE id=p_icon_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='icon'
    AND scope_type='unit' AND scope_id=v_unit AND aggregate_id=p_icon_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'map.icon.delete','map',
    jsonb_build_array(jsonb_build_object('entityType','icon','entityId',p_icon_id,
      'operation','delete','safeLabel',left(v_icon.link,240),
      'changedFields',jsonb_build_array('aggregate'))),'{}','[]','[]',
    jsonb_build_object('icon',NULL));
END; $$;
REVOKE ALL ON FUNCTION public.delete_icon_client_sync_v1(bigint,bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_icon_client_sync_v1(bigint,bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_information_command_data_v1(
  p_information_id bigint
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT to_jsonb(i)||jsonb_build_object('information_hidden',CASE
    WHEN ih.id IS NULL THEN NULL ELSE jsonb_build_object('id',ih.id,'data',ih.data) END)
  FROM public.information i LEFT JOIN public.information_hidden ih
    ON ih.id=i.information_hidden WHERE i.id=p_information_id;
$$;
REVOKE ALL ON FUNCTION public.get_information_command_data_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_information_editor_bundle_v1(
  p_occasion bigint,p_type text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_information jsonb;
BEGIN
  IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(public.get_information_command_data_v1(i.id)||
    jsonb_build_object('aggregate_version',COALESCE(v.version,0))
    ORDER BY i."order" NULLS LAST,i.id),'[]'::jsonb) INTO v_information
  FROM public.information i LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='information' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=i.id::text
  WHERE i.occasion=p_occasion AND (CASE WHEN p_type IS NULL
    THEN NULLIF(i.type,'') IS NULL ELSE i.type=p_type END);
  RETURN jsonb_build_object('code',200,'information',v_information);
END; $$;
REVOKE ALL ON FUNCTION public.get_information_editor_bundle_v1(bigint,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_information_editor_bundle_v1(bigint,text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_information_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,
  p_information jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_hidden_id bigint; v_old_hidden_id bigint;
  v_version bigint; v_begin jsonb; v_hash text; v_current jsonb;
  v_requested jsonb; v_entity jsonb; v_commit jsonb; v_public jsonb;
  v_response jsonb; v_is_publishable boolean; v_old_is_hidden boolean;
  v_new_is_hidden boolean; v_affects_public boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  IF p_information IS NULL OR jsonb_typeof(p_information)<>'object'
    OR octet_length(p_information::text)>786432
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_information) key WHERE key NOT IN
      ('id','title','description','type','isHidden','order','data','hiddenData'))
    OR NOT (p_information ? 'isHidden')
    OR length(COALESCE(p_information->>'title',''))>500
    OR length(COALESCE(p_information->>'type',''))>100
    OR octet_length(COALESCE(p_information->>'description',''))>524288
    OR octet_length(COALESCE((p_information->'data')::text,''))>131072
    OR octet_length(COALESCE((p_information->'hiddenData')::text,''))>65536
    OR ((p_information->>'type') IS DISTINCT FROM 'game'
      AND p_information->'hiddenData' IS DISTINCT FROM 'null'::jsonb) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid information aggregate';
  END IF;
  v_id:=(p_information->>'id')::bigint;
  v_new_is_hidden:=(p_information->>'isHidden')::boolean;
  v_requested:=jsonb_build_object('id',v_id,'title',p_information->>'title',
    'description',p_information->>'description','type',p_information->>'type',
    'isHidden',v_new_is_hidden,'order',(p_information->>'order')::bigint,
    'data',p_information->'data','hiddenData',p_information->'hiddenData');
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,
    'information',p_information)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.information.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.information i WHERE i.id=v_id AND i.occasion=p_occasion
      FOR UPDATE;
    IF NOT FOUND THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',404,jsonb_build_object('version',0,'information',NULL));
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('information','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='information' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    SELECT jsonb_build_object('id',i.id,'title',i.title,'description',i.description,
      'type',i.type,'isHidden',i.is_hidden,'order',i."order",'data',i.data,
      'hiddenData',ih.data),i.is_hidden,i.information_hidden
      INTO v_current,v_old_is_hidden,v_old_hidden_id
    FROM public.information i LEFT JOIN public.information_hidden ih
      ON ih.id=i.information_hidden WHERE i.id=v_id;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'conflict',409,jsonb_build_object('version',v_version,'information',
          public.get_information_command_data_v1(v_id)));
    END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new information must not have expected version';
  END IF;

  IF v_current IS NOT DISTINCT FROM v_requested THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',v_version,'information',
        public.get_information_command_data_v1(v_id)));
  END IF;

  IF p_information->>'type'='game' THEN
    IF v_old_hidden_id IS NULL THEN
      INSERT INTO public.information_hidden(data,occasion)
      VALUES (p_information->'hiddenData',p_occasion) RETURNING id INTO v_hidden_id;
    ELSE
      UPDATE public.information_hidden SET data=p_information->'hiddenData'
      WHERE id=v_old_hidden_id AND occasion=p_occasion RETURNING id INTO v_hidden_id;
      IF v_hidden_id IS NULL THEN
        RAISE invalid_parameter_value USING MESSAGE='cross-scope hidden information';
      END IF;
    END IF;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.information(title,description,type,is_hidden,"order",data,
      information_hidden,occasion)
    VALUES (p_information->>'title',p_information->>'description',
      p_information->>'type',v_new_is_hidden,(p_information->>'order')::bigint,
      p_information->'data',v_hidden_id,p_occasion) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('information','occasion',p_occasion,v_id::text,v_version);
  ELSE
    UPDATE public.information SET title=p_information->>'title',
      description=p_information->>'description',type=p_information->>'type',
      is_hidden=v_new_is_hidden,"order"=(p_information->>'order')::bigint,
      data=p_information->'data',information_hidden=v_hidden_id,
      updated_at=clock_timestamp() WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='information'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
    IF v_old_hidden_id IS NOT NULL AND v_hidden_id IS NULL THEN
      DELETE FROM public.information_hidden WHERE id=v_old_hidden_id
        AND occasion=p_occasion;
    END IF;
  END IF;
  v_entity:=public.get_information_command_data_v1(v_id)||
    jsonb_build_object('aggregate_version',v_version);
  v_affects_public:=NOT COALESCE(v_old_is_hidden,true) OR NOT v_new_is_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.information.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','information','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_information->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND v_affects_public THEN ARRAY['content_catalog']
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'information',v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.save_information_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_information_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_information_client_sync_v1(
  p_occasion bigint,p_information_id bigint,p_command_id uuid,
  p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_version bigint; v_hidden_id bigint;
  v_entity jsonb; v_begin jsonb; v_hash text; v_commit jsonb; v_public jsonb;
  v_response jsonb; v_is_publishable boolean; v_is_hidden boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'informationId',p_information_id,'expectedVersion',p_expected_version)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.information.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT public.get_information_command_data_v1(i.id),i.information_hidden,i.is_hidden
    INTO v_entity,v_hidden_id,v_is_hidden FROM public.information i
    WHERE i.id=p_information_id AND i.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',0,'information',NULL));
  END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('information','occasion',p_occasion,p_information_id::text,0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='information' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_information_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'conflict',409,jsonb_build_object('version',v_version,
        'information',v_entity));
  END IF;
  DELETE FROM public.information WHERE id=p_information_id;
  IF v_hidden_id IS NOT NULL THEN
    DELETE FROM public.information_hidden WHERE id=v_hidden_id AND occasion=p_occasion;
  END IF;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='information'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_information_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.information.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','information','entityId',p_information_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND NOT v_is_hidden THEN ARRAY['content_catalog']
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'information',NULL));
END; $$;
REVOKE ALL ON FUNCTION public.delete_information_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_information_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_news_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_news jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_entity jsonb; v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  IF p_news IS NULL OR jsonb_typeof(p_news)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_news) key
      WHERE key NOT IN ('id','message'))
    OR NOT (p_news ? 'message')
    OR octet_length(COALESCE(p_news->>'message','')) NOT BETWEEN 1 AND 524288 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid news';
  END IF;
  v_id:=(p_news->>'id')::bigint;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,
    'news',p_news)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.news.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    SELECT jsonb_build_object('id',n.id,'message',n.message) INTO v_current
    FROM public.news n WHERE n.id=v_id AND n.occasion=p_occasion FOR UPDATE;
    IF v_current IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',404,jsonb_build_object('version',0,'news',NULL));
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('news','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='news' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.news n WHERE n.id=v_id;
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'conflict',409,jsonb_build_object('version',v_version,'news',v_entity));
    END IF;
    IF v_current=jsonb_build_object('id',v_id,'message',p_news->>'message') THEN
      SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.news n WHERE n.id=v_id;
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'unchanged',200,jsonb_build_object('version',v_version,'news',v_entity));
    END IF;
    UPDATE public.news SET message=p_news->>'message',updated_at=clock_timestamp()
      WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='news'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    IF p_expected_version IS NOT NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='new news must not have expected version';
    END IF;
    INSERT INTO public.news(message,created_by,occasion)
    VALUES (p_news->>'message',v_actor,p_occasion) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('news','occasion',p_occasion,v_id::text,v_version);
  END IF;
  SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
    INTO v_entity FROM public.news n WHERE n.id=v_id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.news.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','news','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel','News','changedFields',jsonb_build_array('message'))),
    CASE WHEN v_is_publishable THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'news',v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.save_news_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_news_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

-- Creating a news item and requesting its push notification is one user
-- intent. The notification log is the existing transactional delivery outbox;
-- keeping both inserts here prevents a published item without its requested
-- notification (or the reverse).
CREATE OR REPLACE FUNCTION public.publish_news_client_sync_v1(
  p_occasion bigint,p_add_to_news boolean,p_news_message text,
  p_send_notification boolean,p_notification_heading text,
  p_notification_content text,p_recipients jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_organization bigint; v_begin jsonb; v_hash text;
  v_id bigint; v_version bigint:=0; v_entity jsonb; v_items jsonb:='[]'::jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT o.organization,NOT o.is_hidden INTO v_organization,v_is_publishable
    FROM public.occasions o WHERE o.id=p_occasion;
  IF v_organization IS NULL OR NOT COALESCE(p_add_to_news,false)
      AND NOT COALESCE(p_send_notification,false)
    OR p_add_to_news AND (p_news_message IS NULL
      OR octet_length(p_news_message) NOT BETWEEN 1 AND 524288)
    OR p_send_notification AND (p_notification_content IS NULL
      OR octet_length(p_notification_content)>65536
      OR octet_length(COALESCE(p_notification_heading,''))>2048
      OR p_recipients IS NOT NULL AND (jsonb_typeof(p_recipients)<>'array'
        OR jsonb_array_length(p_recipients)>5000
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_recipients) value
          WHERE jsonb_typeof(value)<>'string'
            OR octet_length(value#>>'{}')>512))) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid news publication'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'addToNews',p_add_to_news,'newsMessage',p_news_message,
    'sendNotification',p_send_notification,'notificationHeading',p_notification_heading,
    'notificationContent',p_notification_content,'recipients',p_recipients)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.news.publish',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF p_add_to_news THEN
    INSERT INTO public.news(message,created_by,occasion)
      VALUES (p_news_message,v_actor,p_occasion) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('news','occasion',p_occasion,v_id::text,v_version);
    SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.news n WHERE n.id=v_id;
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'entityType','news','entityId',v_id,'operation','insert','safeLabel','News',
      'changedFields',jsonb_build_array('message')));
  END IF;
  IF p_send_notification THEN
    INSERT INTO public.log_notifications
      (occasion,organization,user_id,"to",heading,content)
    VALUES (p_occasion,v_organization,v_actor,p_recipients,
      p_notification_heading,p_notification_content);
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'entityType','notification','entityId',NULL,'operation','publish',
      'safeLabel','Notification','changedFields',jsonb_build_array('delivery_request')));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.news.publish','content',v_items,
    CASE WHEN p_add_to_news AND v_is_publishable THEN ARRAY['content_catalog']
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'news',v_entity,
      'notificationQueued',p_send_notification));
END; $$;
REVOKE ALL ON FUNCTION public.publish_news_client_sync_v1(bigint,boolean,text,boolean,text,text,jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.publish_news_client_sync_v1(bigint,boolean,text,boolean,text,text,jsonb,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_news_client_sync_v1(
  p_occasion bigint,p_news_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_previous_id bigint; v_private_impacts jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'newsId',p_news_id,'expectedVersion',p_expected_version)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.news.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT to_jsonb(n) INTO v_entity FROM public.news n
    WHERE n.id=p_news_id AND n.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',0,'news',NULL));
  END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('news','occasion',p_occasion,p_news_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='news' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_news_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'conflict',409,jsonb_build_object('version',v_version,'news',v_entity));
  END IF;
  SELECT n.id INTO v_previous_id FROM public.news n
    WHERE n.occasion=p_occasion AND n.id<p_news_id ORDER BY n.id DESC LIMIT 1;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_news',
    'userId',un."user")),'[]'::jsonb) INTO v_private_impacts
  FROM public.user_news un JOIN public.occasion_users ou
    ON ou.occasion=p_occasion AND ou."user"=un."user"
  WHERE un.occasion=p_occasion AND un.news_id=p_news_id;
  IF v_previous_id IS NULL THEN
    DELETE FROM public.user_news WHERE occasion=p_occasion AND news_id=p_news_id;
  ELSE
    UPDATE public.user_news SET news_id=v_previous_id
      WHERE occasion=p_occasion AND news_id=p_news_id;
  END IF;
  DELETE FROM public.news WHERE id=p_news_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='news'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_news_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.news.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','news','entityId',p_news_id,'operation','delete',
      'safeLabel','News','changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    v_private_impacts,'[]',jsonb_build_object('version',v_version,'news',NULL));
END; $$;
REVOKE ALL ON FUNCTION public.delete_news_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_news_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

-- Speaker editor read model. A speaker owns its competence links; event links
-- remain part of the event aggregate and therefore expose the event version.
CREATE OR REPLACE FUNCTION public.get_speakers_editor_bundle_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_speakers jsonb; v_topics jsonb;
BEGIN
  IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(q.value ORDER BY q.sort_order,q.sort_title),'[]'::jsonb)
    INTO v_speakers FROM (
    SELECT s."order" sort_order,s.title sort_title,
      to_jsonb(s)||jsonb_build_object(
        'aggregate_version',COALESCE(v.version,0),
        'topics',COALESCE((SELECT jsonb_agg(l.topic ORDER BY l.topic)
          FROM public.speaker_topic_links l WHERE l.speaker=s.id),'[]'::jsonb),
        'events',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id',e.id,'title',e.title,'start_time',e.start_time,
          'end_time',e.end_time,'max_participants',e.max_participants,
          'occupied',(SELECT count(*) FROM public.event_users eu WHERE eu.event=e.id),
          'is_counseling_slot',COALESCE((e.data->>'is_counseling_slot')::boolean,false),
          'aggregate_version',COALESCE(ev.version,0)) ORDER BY e.start_time,e.id)
          FROM public.event_speakers es JOIN public.events e ON e.id=es.event
          LEFT JOIN public.client_aggregate_versions ev ON ev.aggregate_type='event'
            AND ev.scope_type='occasion' AND ev.scope_id=p_occasion
            AND ev.aggregate_id=e.id::text WHERE es.speaker=s.id),'[]'::jsonb)
      ) value
    FROM public.speakers s LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='speaker' AND v.scope_type='occasion'
      AND v.scope_id=p_occasion AND v.aggregate_id=s.id::text
    WHERE s.occasion=p_occasion
  ) q;
  SELECT COALESCE(jsonb_agg(to_jsonb(t)||jsonb_build_object(
      'aggregate_version',COALESCE(v.version,0)) ORDER BY t."order",t.title,t.id),
      '[]'::jsonb) INTO v_topics
  FROM public.speaker_topics t LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='speaker_topic' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=t.id::text
  WHERE t.occasion=p_occasion;
  RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
    'speakers',v_speakers,'speaker_topics',v_topics));
END; $$;
REVOKE ALL ON FUNCTION public.get_speakers_editor_bundle_v1(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_speakers_editor_bundle_v1(bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_event_editor_v1(
  p_occasion bigint,p_event bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event jsonb; v_version bigint;
BEGIN
  IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT public.get_event_command_data_v1(e.id),COALESCE(v.version,0)
    INTO v_event,v_version FROM public.events e
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event'
      AND v.scope_type='occasion' AND v.scope_id=p_occasion
      AND v.aggregate_id=e.id::text
    WHERE e.id=p_event AND e.occasion=p_occasion;
  IF v_event IS NULL THEN RETURN jsonb_build_object('code',404,'data',NULL); END IF;
  RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
    'version',v_version,'event',v_event));
END; $$;
REVOKE ALL ON FUNCTION public.get_event_editor_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_event_editor_v1(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_speaker_command_data_v1(p_speaker_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT to_jsonb(s)||jsonb_build_object('topics',COALESCE((
    SELECT jsonb_agg(l.topic ORDER BY l.topic) FROM public.speaker_topic_links l
    WHERE l.speaker=s.id),'[]'::jsonb)) FROM public.speakers s
  WHERE s.id=p_speaker_id;
$$;
REVOKE ALL ON FUNCTION public.get_speaker_command_data_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.save_speaker_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_speaker jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_requested jsonb; v_entity jsonb;
  v_topic_ids bigint[]; v_old_hidden boolean; v_new_hidden boolean;
  v_publishable boolean; v_content_impact boolean; v_program_impact boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  IF v_publishable IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='occasion not found'; END IF;
  IF p_speaker IS NULL OR jsonb_typeof(p_speaker)<>'object'
    OR octet_length(p_speaker::text)>786432
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_speaker) key WHERE key NOT IN
      ('id','title','subtitle','description','image','order','is_hidden','data','topics'))
    OR NOT (p_speaker ?& ARRAY['title','order','is_hidden','data','topics'])
    OR jsonb_typeof(p_speaker->'topics')<>'array'
    OR jsonb_array_length(p_speaker->'topics')>1000
    OR length(btrim(COALESCE(p_speaker->>'title',''))) NOT BETWEEN 1 AND 200
    OR octet_length(COALESCE(p_speaker->>'description',''))>524288
    OR octet_length(COALESCE((p_speaker->'data')::text,''))>131072 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid speaker aggregate';
  END IF;
  SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}')
    INTO v_topic_ids FROM jsonb_array_elements_text(p_speaker->'topics');
  IF cardinality(v_topic_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_topic_ids)))
    OR EXISTS (SELECT 1 FROM unnest(v_topic_ids) id LEFT JOIN public.speaker_topics t
      ON t.id=id AND t.occasion=p_occasion WHERE t.id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='speaker contains invalid topics';
  END IF;
  v_id:=(p_speaker->>'id')::bigint;
  v_new_hidden:=(p_speaker->>'is_hidden')::boolean;
  v_requested:=jsonb_build_object('id',v_id,'title',p_speaker->>'title',
    'subtitle',p_speaker->>'subtitle','description',p_speaker->>'description',
    'image',p_speaker->>'image','order',(p_speaker->>'order')::bigint,
    'is_hidden',v_new_hidden,'data',p_speaker->'data','topics',to_jsonb(v_topic_ids));
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'speaker',p_speaker)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.speakers s WHERE s.id=v_id AND s.occasion=p_occasion FOR UPDATE;
    IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'rejected',404,jsonb_build_object('version',0,'speaker',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='speaker' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    SELECT jsonb_build_object('id',s.id,'title',s.title,'subtitle',s.subtitle,
      'description',s.description,'image',s.image,'order',s."order",
      'is_hidden',s.is_hidden,'data',s.data,'topics',COALESCE((SELECT jsonb_agg(
        l.topic ORDER BY l.topic) FROM public.speaker_topic_links l
        WHERE l.speaker=s.id),'[]'::jsonb)),s.is_hidden
      INTO v_current,v_old_hidden FROM public.speakers s WHERE s.id=v_id;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'speaker',
          public.get_speaker_command_data_v1(v_id)||jsonb_build_object(
            'aggregate_version',v_version))); END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new speaker must not have expected version';
  END IF;
  IF v_current IS NOT DISTINCT FROM v_requested THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'speaker',
        public.get_speaker_command_data_v1(v_id)||jsonb_build_object(
          'aggregate_version',v_version)));
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.speakers(occasion,title,subtitle,description,image,"order",is_hidden,data)
    VALUES (p_occasion,p_speaker->>'title',p_speaker->>'subtitle',
      p_speaker->>'description',p_speaker->>'image',(p_speaker->>'order')::bigint,
      v_new_hidden,p_speaker->'data') RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker','occasion',p_occasion,v_id::text,v_version);
  ELSE
    UPDATE public.speakers SET title=p_speaker->>'title',subtitle=p_speaker->>'subtitle',
      description=p_speaker->>'description',image=p_speaker->>'image',
      "order"=(p_speaker->>'order')::bigint,is_hidden=v_new_hidden,data=p_speaker->'data'
      WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='speaker'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  END IF;
  DELETE FROM public.speaker_topic_links WHERE speaker=v_id;
  INSERT INTO public.speaker_topic_links(speaker,topic)
    SELECT v_id,id FROM unnest(v_topic_ids) id;
  v_entity:=public.get_speaker_command_data_v1(v_id)||
    jsonb_build_object('aggregate_version',v_version);
  v_program_impact:=v_old_hidden IS DISTINCT FROM v_new_hidden AND EXISTS (
    SELECT 1 FROM public.event_speakers es JOIN public.events e ON e.id=es.event
    WHERE es.speaker=v_id AND NOT e.is_hidden);
  v_content_impact:=NOT COALESCE(v_old_hidden,true) OR NOT v_new_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_speaker->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable THEN CASE WHEN v_content_impact
      THEN ARRAY['content_catalog'] ELSE '{}'::text[] END||CASE WHEN v_program_impact
      THEN ARRAY['program_catalog'] ELSE '{}'::text[] END ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'speaker',v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.save_speaker_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_speaker_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_speaker_client_sync_v1(
  p_occasion bigint,p_speaker_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_publishable boolean; v_hidden boolean; v_has_public_events boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'speakerId',p_speaker_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT public.get_speaker_command_data_v1(s.id),s.is_hidden INTO v_entity,v_hidden
    FROM public.speakers s WHERE s.id=p_speaker_id AND s.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'speaker',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('speaker','occasion',p_occasion,p_speaker_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='speaker' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_speaker_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'speaker',v_entity)); END IF;
  SELECT EXISTS (SELECT 1 FROM public.event_speakers es JOIN public.events e
    ON e.id=es.event WHERE es.speaker=p_speaker_id AND NOT e.is_hidden)
    INTO v_has_public_events;
  DELETE FROM public.speakers WHERE id=p_speaker_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='speaker'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_speaker_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker','entityId',p_speaker_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable THEN CASE WHEN NOT v_hidden THEN ARRAY['content_catalog']
      ELSE '{}'::text[] END||CASE WHEN NOT v_hidden
      AND v_has_public_events THEN ARRAY['program_catalog'] ELSE '{}'::text[] END
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'speaker',NULL));
END; $$;
REVOKE ALL ON FUNCTION public.delete_speaker_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_speaker_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_speaker_topic_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_topic jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_entity jsonb; v_publishable boolean;
  v_old_hidden boolean; v_new_hidden boolean; v_content_impact boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  IF p_topic IS NULL OR jsonb_typeof(p_topic)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_topic) key WHERE key NOT IN
      ('id','title','order','is_hidden')) OR NOT (p_topic ?& ARRAY['title','order','is_hidden'])
    OR length(btrim(COALESCE(p_topic->>'title',''))) NOT BETWEEN 1 AND 200 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid speaker topic'; END IF;
  v_id:=(p_topic->>'id')::bigint; v_new_hidden:=(p_topic->>'is_hidden')::boolean;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'topic',p_topic)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker_topic.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    SELECT to_jsonb(t),t.is_hidden INTO v_current,v_old_hidden FROM public.speaker_topics t
      WHERE t.id=v_id AND t.occasion=p_occasion FOR UPDATE;
    IF v_current IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'rejected',404,jsonb_build_object('version',0,'topic',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker_topic','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='speaker_topic' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'topic',v_current||
          jsonb_build_object('aggregate_version',v_version))); END IF;
    IF jsonb_build_object('id',v_id,'occasion',p_occasion,'title',v_current->>'title',
      'order',(v_current->>'order')::bigint,'is_hidden',(v_current->>'is_hidden')::boolean)
      = jsonb_build_object('id',v_id,'occasion',p_occasion,'title',p_topic->>'title',
      'order',(p_topic->>'order')::bigint,'is_hidden',v_new_hidden) THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
        jsonb_build_object('version',v_version,'topic',v_current||
          jsonb_build_object('aggregate_version',v_version))); END IF;
    UPDATE public.speaker_topics SET title=p_topic->>'title',
      "order"=(p_topic->>'order')::bigint,is_hidden=v_new_hidden,
      updated_at=clock_timestamp() WHERE id=v_id
      RETURNING to_jsonb(speaker_topics.*) INTO v_entity;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='speaker_topic'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    IF p_expected_version IS NOT NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='new topic must not have expected version'; END IF;
    INSERT INTO public.speaker_topics(occasion,title,"order",is_hidden)
    VALUES (p_occasion,p_topic->>'title',(p_topic->>'order')::bigint,v_new_hidden)
    RETURNING id,to_jsonb(speaker_topics.*) INTO v_id,v_entity;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('speaker_topic','occasion',p_occasion,v_id::text,v_version);
  END IF;
  v_entity:=v_entity||jsonb_build_object('aggregate_version',v_version);
  v_content_impact:=NOT COALESCE(v_old_hidden,true) OR NOT v_new_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker_topic.save','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker_topic','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_topic->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable AND v_content_impact THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'topic',v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.save_speaker_topic_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_speaker_topic_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_speaker_topic_client_sync_v1(
  p_occasion bigint,p_topic_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_publishable boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'topicId',p_topic_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.speaker_topic.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT to_jsonb(t) INTO v_entity FROM public.speaker_topics t
    WHERE t.id=p_topic_id AND t.occasion=p_occasion FOR UPDATE;
  IF v_entity IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'topic',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('speaker_topic','occasion',p_occasion,p_topic_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='speaker_topic' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_topic_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'topic',v_entity)); END IF;
  DELETE FROM public.speaker_topics WHERE id=p_topic_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='speaker_topic'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_topic_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.speaker_topic.delete','content',jsonb_build_array(jsonb_build_object(
      'entityType','speaker_topic','entityId',p_topic_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_publishable AND NOT (v_entity->>'is_hidden')::boolean
      THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,
    '[]','[]',jsonb_build_object('version',v_version,'topic',NULL));
END; $$;
REVOKE ALL ON FUNCTION public.delete_speaker_topic_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_speaker_topic_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_event_speakers_client_sync_v1(
  p_occasion bigint,p_event bigint,p_command_id uuid,p_expected_version bigint,
  p_speaker_ids bigint[]
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_current bigint[]; v_requested bigint[];
  v_publishable boolean; v_event_hidden boolean;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT COALESCE(array_agg(id ORDER BY id),'{}'::bigint[]) INTO v_requested
    FROM unnest(COALESCE(p_speaker_ids,'{}'::bigint[])) id;
  IF cardinality(v_requested)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_requested)))
    OR cardinality(v_requested)>1000 OR EXISTS (SELECT 1 FROM unnest(v_requested) id
      LEFT JOIN public.speakers s ON s.id=id AND s.occasion=p_occasion WHERE s.id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid event speakers'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'eventId',p_event,'expectedVersion',p_expected_version,
    'speakerIds',to_jsonb(v_requested))::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.event_speakers.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT e.is_hidden,NOT o.is_hidden INTO v_event_hidden,v_publishable
    FROM public.events e JOIN public.occasions o ON o.id=e.occasion
    WHERE e.id=p_event AND e.occasion=p_occasion FOR UPDATE OF e;
  IF v_event_hidden IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',404,jsonb_build_object('version',0,'eventId',p_event,
      'speakerIds','[]'::jsonb)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('event','occasion',p_occasion,p_event::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='event' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_event::text FOR UPDATE;
  SELECT COALESCE(array_agg(es.speaker ORDER BY es.speaker),'{}') INTO v_current
    FROM public.event_speakers es WHERE es.event=p_event;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'eventId',p_event,
        'speakerIds',to_jsonb(v_current))); END IF;
  IF v_current=v_requested THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',v_version,
      'eventId',p_event,'speakerIds',to_jsonb(v_current))); END IF;
  DELETE FROM public.event_speakers WHERE event=p_event;
  INSERT INTO public.event_speakers(event,speaker)
    SELECT p_event,id FROM unnest(v_requested) id;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='event'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_event::text
    RETURNING version INTO v_version;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'program.event_speakers.save','program',jsonb_build_array(jsonb_build_object(
      'entityType','event_speakers','entityId',p_event,'operation','update',
      'safeLabel','Event speakers','changedFields',jsonb_build_array('speakerIds'))),
    CASE WHEN v_publishable AND NOT v_event_hidden THEN ARRAY['program_catalog']
      ELSE '{}'::text[] END,'[]','[]',jsonb_build_object('version',v_version,
      'eventId',p_event,'speakerIds',to_jsonb(v_requested)));
END; $$;
REVOKE ALL ON FUNCTION public.save_event_speakers_client_sync_v1(bigint,bigint,uuid,bigint,bigint[])
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_event_speakers_client_sync_v1(bigint,bigint,uuid,bigint,bigint[])
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_group_command_data_v1(p_group bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object('id',g.id,'title',g.title,
    'description',g.description,'type',g.type,'data',g.data,'place',g.place,
    'placeData',(SELECT to_jsonb(p) FROM public.places p WHERE p.id=g.place),
    'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'userId',ug."user",'isAdmin',ug.is_admin,'is_admin',ug.is_admin,
      'user_info',jsonb_build_object('id',ui.id,'name',ui.name,'surname',ui.surname))
      ORDER BY ug."user") FROM public.user_groups ug JOIN public.user_info ui
      ON ui.id=ug."user" WHERE ug."group"=g.id),'[]'::jsonb))
  FROM public.user_group_info g WHERE g.id=p_group;
$$;
REVOKE ALL ON FUNCTION public.get_user_group_command_data_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_user_groups_editor_bundle_v1(
  p_occasion bigint,p_type text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_groups jsonb; v_places jsonb; v_game_definitions jsonb;
BEGIN
  IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(public.get_user_group_command_data_v1(g.id)||
    jsonb_build_object('aggregate_version',COALESCE(v.version,0))
    ORDER BY g.title,g.id),'[]'::jsonb) INTO v_groups
  FROM public.user_group_info g LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='user_group' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=g.id::text
  WHERE g.occasion=p_occasion AND (p_type IS NULL AND g.type IS NULL OR g.type=p_type);
  SELECT COALESCE(jsonb_agg(to_jsonb(p)||jsonb_build_object(
    'aggregate_version',COALESCE(v.version,0)) ORDER BY p."order" NULLS LAST,p.title),
    '[]'::jsonb) INTO v_places FROM public.places p
  LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=p.id::text
  WHERE p.occasion=p_occasion AND NOT p.is_hidden
    AND p.coordinates->'latLng'->>'lat' IS NOT NULL
    AND p.coordinates->'latLng'->>'lng' IS NOT NULL;
  IF p_type='game' THEN
    SELECT jsonb_object_agg(i.id,i.title) INTO v_game_definitions
    FROM public.information i WHERE i.occasion=p_occasion AND i.type='game';
  END IF;
  RETURN jsonb_build_object('groups',v_groups,'places',v_places,
    'game_definitions',v_game_definitions);
END; $$;
REVOKE ALL ON FUNCTION public.get_user_groups_editor_bundle_v1(bigint,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_groups_editor_bundle_v1(bigint,text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_user_group_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_group jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_requested jsonb; v_entity jsonb;
  v_participants jsonb; v_current_participants jsonb;
  v_old_users uuid[]; v_new_users uuid[];
  v_old_place bigint; v_old_private boolean:=false; v_place_id bigint;
  v_private_place jsonb; v_place_version bigint; v_private_impacts jsonb;
  v_current_place jsonb; v_requested_place jsonb; v_place_changed boolean:=false;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  v_id:=(p_group->>'id')::bigint;
  IF v_actor IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
    OR (v_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.user_groups ug
      JOIN public.user_group_info g ON g.id=ug."group"
      WHERE ug."group"=v_id AND ug."user"=v_actor AND ug.is_admin
        AND g.occasion=p_occasion))) THEN
    RAISE insufficient_privilege USING MESSAGE='group editor required';
  END IF;
  IF p_group IS NULL OR jsonb_typeof(p_group)<>'object'
    OR octet_length(p_group::text)>524288
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_group) key WHERE key NOT IN
      ('id','title','description','type','placeId','privatePlace','participants'))
    OR NOT (p_group ?& ARRAY['title','participants'])
    OR jsonb_typeof(p_group->'participants')<>'array'
    OR jsonb_array_length(p_group->'participants')>5000
    OR length(btrim(COALESCE(p_group->>'title',''))) NOT BETWEEN 1 AND 500
    OR octet_length(COALESCE(p_group->>'description',''))>262144 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group aggregate';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId',x.user_id,
    'isAdmin',x.is_admin) ORDER BY x.user_id),'[]'::jsonb),
    COALESCE(array_agg(x.user_id ORDER BY x.user_id),'{}'::uuid[])
    INTO v_participants,v_new_users
  FROM jsonb_to_recordset(p_group->'participants') x(user_id uuid,is_admin boolean);
  IF jsonb_array_length(p_group->'participants')<>cardinality(v_new_users)
    OR cardinality(v_new_users)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_new_users)))
    OR EXISTS (SELECT 1 FROM unnest(v_new_users) id LEFT JOIN public.occasion_users ou
      ON ou."user"=id AND ou.occasion=p_occasion WHERE ou."user" IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group participants';
  END IF;
  v_private_place:=p_group->'privatePlace';
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb AND (
    jsonb_typeof(v_private_place)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_private_place) key WHERE key NOT IN
      ('id','title','description','coordinates','order','icon'))
    OR length(btrim(COALESCE(v_private_place->>'title',''))) NOT BETWEEN 1 AND 500
    OR jsonb_typeof(v_private_place->'coordinates')<>'object'
    OR octet_length(v_private_place::text)>131072) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid private group place';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'group',p_group)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.group.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.user_group_info g WHERE g.id=v_id
      AND g.occasion=p_occasion FOR UPDATE;
    IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',404,jsonb_build_object('version',0,'group',NULL)); END IF;
    SELECT g.place,COALESCE(p.is_hidden AND p.type='group',false),
      public.get_user_group_command_data_v1(g.id)
      INTO v_old_place,v_old_private,v_current
    FROM public.user_group_info g LEFT JOIN public.places p ON p.id=g.place
    WHERE g.id=v_id;
    SELECT COALESCE(array_agg(ug."user" ORDER BY ug."user"),'{}'::uuid[]),
      COALESCE(jsonb_agg(jsonb_build_object('userId',ug."user",
        'isAdmin',ug.is_admin) ORDER BY ug."user"),'[]'::jsonb)
      INTO v_old_users,v_current_participants FROM public.user_groups ug
      WHERE ug."group"=v_id;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('user_group','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='user_group' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'group',v_current)); END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new group must not have expected version';
  END IF;
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb THEN
    v_place_id:=(v_private_place->>'id')::bigint;
    IF v_place_id IS NULL THEN
      INSERT INTO public.places(title,description,type,coordinates,is_hidden,"order",icon,occasion)
      VALUES (v_private_place->>'title',v_private_place->>'description','group',
        v_private_place->'coordinates',true,(v_private_place->>'order')::bigint,
        (v_private_place->>'icon')::bigint,p_occasion) RETURNING id INTO v_place_id;
      v_place_version:=1;
      v_place_changed:=true;
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES ('place','occasion',p_occasion,v_place_id::text,v_place_version);
    ELSE
      PERFORM 1 FROM public.places p WHERE p.id=v_place_id AND p.occasion=p_occasion
        AND p.type='group' AND p.is_hidden FOR UPDATE;
      IF NOT FOUND OR v_id IS NULL OR NOT v_old_private
        OR v_place_id IS DISTINCT FROM v_old_place THEN
        RAISE invalid_parameter_value USING MESSAGE='private place is not owned by group';
      END IF;
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES ('place','occasion',p_occasion,v_place_id::text,0) ON CONFLICT DO NOTHING;
      SELECT jsonb_build_object('id',p.id,'title',p.title,
        'description',p.description,'coordinates',p.coordinates,
        'order',p."order",'icon',p.icon) INTO v_current_place
      FROM public.places p WHERE p.id=v_place_id;
      v_requested_place:=jsonb_build_object('id',v_place_id,
        'title',v_private_place->>'title','description',v_private_place->>'description',
        'coordinates',v_private_place->'coordinates',
        'order',(v_private_place->>'order')::bigint,
        'icon',(v_private_place->>'icon')::bigint);
      v_place_changed:=v_current_place IS DISTINCT FROM v_requested_place;
      IF v_place_changed THEN
        UPDATE public.places SET title=v_private_place->>'title',
          description=v_private_place->>'description',coordinates=v_private_place->'coordinates',
          "order"=(v_private_place->>'order')::bigint,icon=(v_private_place->>'icon')::bigint
          WHERE id=v_place_id;
        UPDATE public.client_aggregate_versions SET version=version+1,
          updated_at=clock_timestamp() WHERE aggregate_type='place'
          AND scope_type='occasion' AND scope_id=p_occasion
          AND aggregate_id=v_place_id::text RETURNING version INTO v_place_version;
      ELSE
        SELECT version INTO v_place_version FROM public.client_aggregate_versions
        WHERE aggregate_type='place' AND scope_type='occasion'
          AND scope_id=p_occasion AND aggregate_id=v_place_id::text;
      END IF;
    END IF;
  ELSE
    v_place_id:=(p_group->>'placeId')::bigint;
    IF v_place_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.places p
      WHERE p.id=v_place_id AND p.occasion=p_occasion AND NOT p.is_hidden) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid shared group place';
    END IF;
  END IF;
  v_requested:=jsonb_build_object('id',v_id,'title',p_group->>'title',
    'description',p_group->>'description','type',p_group->>'type',
    'place',v_place_id,'participants',v_participants);
  IF v_current IS NOT NULL AND jsonb_build_object('id',v_id,
      'title',v_current->>'title','description',v_current->>'description',
      'type',v_current->>'type','place',(v_current->>'place')::bigint,
      'participants',v_current_participants)=v_requested
      AND NOT v_place_changed THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'group',v_current));
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.user_group_info(title,description,type,place,occasion)
    VALUES (p_group->>'title',p_group->>'description',p_group->>'type',v_place_id,p_occasion)
    RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('user_group','occasion',p_occasion,v_id::text,v_version);
  ELSE
    UPDATE public.user_group_info SET title=p_group->>'title',
      description=p_group->>'description',type=p_group->>'type',place=v_place_id
      WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='user_group'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  END IF;
  DELETE FROM public.user_groups WHERE "group"=v_id;
  INSERT INTO public.user_groups("user","group",is_admin)
    SELECT x.user_id,v_id,COALESCE(x.is_admin,false)
    FROM jsonb_to_recordset(p_group->'participants') x(user_id uuid,is_admin boolean);
  IF v_old_private AND v_old_place IS DISTINCT FROM v_place_id THEN
    IF EXISTS (SELECT 1 FROM public.user_group_info g WHERE g.id<>v_id
      AND g.place=v_old_place) THEN
      RAISE foreign_key_violation USING MESSAGE='private group place has another owner';
    END IF;
    DELETE FROM public.places WHERE id=v_old_place;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type='place'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_old_place::text;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts
  FROM (SELECT unnest(COALESCE(v_old_users,'{}'::uuid[])) id UNION
    SELECT unnest(v_new_users)) impacted;
  v_entity:=public.get_user_group_command_data_v1(v_id)||
    jsonb_build_object('aggregate_version',v_version);
  IF v_actor=ANY(COALESCE(v_old_users,'{}'::uuid[])||v_new_users) THEN
    v_actor_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.group.save','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_group->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_private_impacts,'[]',jsonb_build_object('version',v_version,'group',v_entity),
    '{}','[]','user',NULL,v_actor_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_user_group_client_sync_v1(
  p_occasion bigint,p_group_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_users uuid[]; v_place bigint; v_private_place boolean;
  v_private_impacts jsonb; v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'groupId',p_group_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.group.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.user_group_info g WHERE g.id=p_group_id
    AND g.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'group',NULL)); END IF;
  SELECT public.get_user_group_command_data_v1(g.id),g.place,
    COALESCE(p.is_hidden AND p.type='group',false)
    INTO v_entity,v_place,v_private_place
  FROM public.user_group_info g LEFT JOIN public.places p ON p.id=g.place
  WHERE g.id=p_group_id;
  SELECT COALESCE(array_agg(ug."user" ORDER BY ug."user"),'{}'::uuid[])
    INTO v_users FROM public.user_groups ug WHERE ug."group"=p_group_id;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('user_group','occasion',p_occasion,p_group_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='user_group' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_group_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'group',v_entity)); END IF;
  DELETE FROM public.user_groups WHERE "group"=p_group_id;
  DELETE FROM public.user_group_info WHERE id=p_group_id;
  IF v_private_place THEN
    DELETE FROM public.places WHERE id=v_place;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type='place'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_place::text;
  END IF;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group_id::text;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts FROM unnest(v_users) id;
  IF v_actor=ANY(v_users) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.group.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',p_group_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_private_impacts,'[]',jsonb_build_object('version',v_version,'group',NULL),
    '{}','[]','user',NULL,v_actor_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

-- Retain the released editor RPC as a thin facade over one domain handler.
ALTER FUNCTION public.save_occasion_user_for_edit(jsonb)
  RENAME TO save_occasion_user_for_edit_internal_v1;
REVOKE ALL ON FUNCTION public.save_occasion_user_for_edit_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.save_occasion_user_for_edit(input_data jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.save_occasion_user_for_edit_internal_v1(input_data);
$$;
REVOKE ALL ON FUNCTION public.save_occasion_user_for_edit(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_occasion_user_for_edit(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_user_command_data_v1(
  p_occasion bigint,p_user uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT to_jsonb(ou)||jsonb_build_object('profile',jsonb_build_object(
    'id',ui.id,'email',ui.email_readonly,'name',ui.name,'surname',ui.surname,
    'sex',ui.sex,'phone',ui.phone,'birthDate',ui.birth_date,'data',ui.data))
  FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user"
  WHERE ou.occasion=p_occasion AND ou."user"=p_user;
$$;
REVOKE ALL ON FUNCTION public.get_occasion_user_command_data_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_users_editor_bundle_v1(
  p_occasion bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result jsonb; v_users jsonb;
BEGIN
  v_result:=public.get_occasion_users_for_edit(p_occasion)::jsonb;
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN RETURN v_result; END IF;
  SELECT COALESCE(jsonb_agg(value||jsonb_build_object('aggregate_version',
    COALESCE(v.version,0))),'[]'::jsonb) INTO v_users
  FROM jsonb_array_elements(v_result#>'{data,occasion_users}') row
  LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=row.value->>'user';
  RETURN jsonb_set(v_result,'{data,occasion_users}',v_users);
END; $$;
REVOKE ALL ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_profile_client_sync_v1(
  p_occasion bigint,p_user uuid,p_command_id uuid,p_expected_version bigint,
  p_profile jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_before jsonb; v_after jsonb; v_result jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object'
    OR octet_length(p_profile::text)>262144
    OR (p_profile->>'occasion')::bigint IS DISTINCT FROM p_occasion
    OR (p_profile->>'user')::uuid IS DISTINCT FROM p_user THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid occasion user profile'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'userId',p_user,'expectedVersion',p_expected_version,
    'profile',p_profile)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'rejected',404,jsonb_build_object('version',0,'profile',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='occasion_user' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_user::text FOR UPDATE;
  v_before:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'profile',v_before)); END IF;
  v_result:=public.save_occasion_user_for_edit_internal_v1(p_profile);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),jsonb_build_object(
        'version',v_version,'profile',v_before,'message',v_result->>'message'));
  END IF;
  v_after:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF v_after IS NOT DISTINCT FROM v_before THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'profile',v_after)); END IF;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text
    RETURNING version INTO v_version;
  IF v_actor=p_user THEN v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',p_user,
    'payload',public.get_private_profile_payload_v1(p_occasion,p_user))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.save','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation','update',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('profile','rights','services'))),
    '{}',jsonb_build_array(jsonb_build_object('component','private_profile',
      'userId',p_user)),'[]',jsonb_build_object('version',v_version,'profile',v_after),
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb)
  TO authenticated;

ALTER FUNCTION public.update_user(jsonb) RENAME TO update_user_internal_v1;
REVOKE ALL ON FUNCTION public.update_user_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.update_user(input_data jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.update_user_internal_v1(input_data);
$$;
REVOKE ALL ON FUNCTION public.update_user(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_user(jsonb) TO authenticated;

ALTER FUNCTION public.add_user_to_occasion(bigint,uuid)
  RENAME TO add_user_to_occasion_internal_v1;
REVOKE ALL ON FUNCTION public.add_user_to_occasion_internal_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.add_user_to_occasion_client_sync_v1(
  p_occasion bigint,p_user uuid,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_before jsonb;
  v_after jsonb; v_result jsonb; v_version bigint; v_replacements jsonb:='[]';
BEGIN
  IF v_actor IS NULL OR p_user IS NULL OR NOT (
    v_actor=p_user OR public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion membership permission required';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'userId',p_user)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'profile.membership.ensure',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT to_jsonb(ou) INTO v_before FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=p_user FOR UPDATE;
  v_result:=public.add_user_to_occasion_internal_v1(p_occasion,p_user);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),v_result); END IF;
  SELECT to_jsonb(ou) INTO v_after FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=p_user;
  SELECT COALESCE(v.version,0) INTO v_version FROM (SELECT 1) seed
    LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=p_occasion AND v.aggregate_id=p_user::text;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'userId',p_user)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,1)
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp() RETURNING version INTO v_version;
  IF v_actor=p_user THEN v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',p_user,
    'payload',public.get_private_profile_payload_v1(p_occasion,p_user))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.membership.ensure','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation',
      CASE WHEN v_before IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel','Occasion membership','changedFields',jsonb_build_array(
        'membership','rights'))),'{}',jsonb_build_array(jsonb_build_object(
          'component','private_profile','userId',p_user)),'[]',
    jsonb_build_object('version',v_version,'userId',p_user),
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.add_user_to_occasion_client_sync_v1(
  bigint,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion_client_sync_v1(
  bigint,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.add_user_to_occasion(oc bigint,usr uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb;
BEGIN
  v_response:=public.add_user_to_occasion_client_sync_v1(
    oc,usr,extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',(v_response->>'code')::integer)
    ||COALESCE(v_response->'data','{}'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.add_user_to_occasion(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion(bigint,uuid)
  TO authenticated;

ALTER FUNCTION public.delete_unit_user(uuid,bigint)
  RENAME TO delete_unit_user_internal_v1;
REVOKE ALL ON FUNCTION public.delete_unit_user_internal_v1(uuid,bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_unit_user_client_sync_v1(
  p_user uuid,p_unit bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_before jsonb;
  v_after jsonb; v_result jsonb; v_commit public.client_commits%ROWTYPE;
  v_occasion bigint; v_revision bigint;
BEGIN
  IF v_actor IS NULL OR p_user IS NULL
    OR NOT public.get_is_manager_on_unit(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'unit',p_unit,'userId',p_user)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'profile.unit_access.delete',p_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT jsonb_build_object('unitUser',(SELECT to_jsonb(uu)
      FROM public.unit_users uu WHERE uu.unit=p_unit AND uu."user"=p_user),
    'occasionUsers',COALESCE((SELECT jsonb_agg(to_jsonb(ou) ORDER BY ou.occasion)
      FROM public.occasion_users ou JOIN public.occasions o ON o.id=ou.occasion
      WHERE o.unit=p_unit AND ou."user"=p_user),'[]'::jsonb)) INTO v_before;
  v_result:=public.delete_unit_user_internal_v1(p_user,p_unit);
  SELECT jsonb_build_object('unitUser',(SELECT to_jsonb(uu)
      FROM public.unit_users uu WHERE uu.unit=p_unit AND uu."user"=p_user),
    'occasionUsers',COALESCE((SELECT jsonb_agg(to_jsonb(ou) ORDER BY ou.occasion)
      FROM public.occasion_users ou JOIN public.occasions o ON o.id=ou.occasion
      WHERE o.unit=p_unit AND ou."user"=p_user),'[]'::jsonb)) INTO v_after;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('userId',p_user)); END IF;
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT p_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'profile.unit_access.delete','profile' FROM public.user_info ui
    WHERE ui.id=v_actor RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'unit_user',p_user::text,'delete','Unit access',
    ARRAY['rights']);
  FOR v_occasion IN SELECT ou.occasion FROM public.occasion_users ou
    JOIN public.occasions o ON o.id=ou.occasion
    WHERE o.unit=p_unit AND ou."user"=p_user ORDER BY ou.occasion LOOP
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('occasion_user','occasion',v_occasion,p_user::text,1)
    ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET
      version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
    INSERT INTO public.client_sync_private_scopes
      (component,occasion,user_id,source_revision)
    VALUES ('private_profile',v_occasion,p_user,1)
    ON CONFLICT (component,occasion,user_id) DO UPDATE SET
      source_revision=public.client_sync_private_scopes.source_revision+1,
      updated_at=now() RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
    VALUES (v_commit.commit_id,'private_profile','occasion',v_occasion,
      p_user,v_revision);
  END LOOP;
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object('userId',p_user),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit.commit_id,'replayed',false,'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.delete_unit_user_client_sync_v1(uuid,bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_unit_user_client_sync_v1(uuid,bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_unit_user(usr uuid,unit_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb;
BEGIN
  v_response:=public.delete_unit_user_client_sync_v1(
    usr,unit_id,extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',(v_response->>'code')::integer)
    ||COALESCE(v_response->'data','{}'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.delete_unit_user(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_unit_user(uuid,bigint) TO authenticated;

ALTER FUNCTION public.delete_user(uuid,bigint)
  RENAME TO delete_user_obsolete_v1;
REVOKE ALL ON FUNCTION public.delete_user_obsolete_v1(uuid,bigint)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.delete_user(usr uuid,oc bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.user_companions uc
    WHERE uc."user"=auth.uid() AND uc.companion=usr) THEN
    RETURN jsonb_build_object('code',410,
      'message','Use occasion membership or confirmed account deletion');
  END IF;
  v_response:=public.delete_companion_client_sync_v1(
    oc,usr,extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',(v_response->>'code')::integer)
    ||COALESCE(v_response->'data','{}'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.delete_user(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_user(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_occasion_user_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_profile jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_user uuid; v_begin jsonb; v_hash text;
  v_version bigint;
  v_result jsonb; v_profile jsonb; v_entity jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object'
    OR octet_length(p_profile::text)>262144
    OR (p_profile->>'occasion')::bigint IS DISTINCT FROM p_occasion
    OR p_profile->>'user' IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid new occasion user profile'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'profile',p_profile)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.create',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_result:=public.update_user_internal_v1(jsonb_build_object(
    'occasion',p_occasion,'user',NULL,'data',p_profile->'data'));
  IF COALESCE((v_result->>'code')::integer,500) NOT IN (200,201) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),jsonb_build_object(
        'version',0,'profile',NULL,'message',v_result->>'message')); END IF;
  v_user:=(v_result->>'user')::uuid;
  v_result:=public.add_user_to_occasion_internal_v1(p_occasion,v_user);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),jsonb_build_object(
        'version',0,'profile',NULL,'message',v_result->>'message')); END IF;
  v_profile:=p_profile||jsonb_build_object('user',v_user);
  v_result:=public.save_occasion_user_for_edit_internal_v1(v_profile);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),jsonb_build_object(
        'version',0,'profile',NULL,'message',v_result->>'message')); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,v_user::text,1)
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp() RETURNING version INTO v_version;
  SELECT public.get_occasion_user_command_data_v1(p_occasion,v_user) INTO v_entity;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.create','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',v_user,'operation','insert',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('profile','rights','services'))),
    '{}',jsonb_build_array(jsonb_build_object('component','private_profile',
    'userId',v_user)),'[]',jsonb_build_object('version',v_version,'userId',v_user,
      'profile',v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.create_occasion_user_client_sync_v1(bigint,uuid,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_occasion_user_client_sync_v1(bigint,uuid,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_occasion_user_client_sync_v1(
  p_occasion bigint,p_user uuid,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_profile jsonb; v_event_ids bigint[]; v_group_ids bigint[];
  v_private_impacts jsonb; v_publishable boolean;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'userId',p_user,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'profile',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='occasion_user' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_user::text FOR UPDATE;
  v_profile:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'profile',v_profile)); END IF;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
  FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
  LEFT JOIN public.event_users_saved es ON es.event=e.id
  WHERE e.occasion=p_occasion AND (eu."user"=p_user OR es."user"=p_user);
  SELECT COALESCE(array_agg(ug."group"),'{}'::bigint[]) INTO v_group_ids
  FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
  WHERE ug."user"=p_user AND g.occasion=p_occasion;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',members."user")),'[]'::jsonb) INTO v_private_impacts
  FROM public.user_groups members WHERE members."group"=ANY(v_group_ids)
    AND members."user"<>p_user;
  UPDATE public.news SET created_by=NULL WHERE created_by=p_user AND occasion=p_occasion;
  DELETE FROM public.user_groups WHERE "user"=p_user AND "group"=ANY(v_group_ids);
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(v_group_ids) id));
  DELETE FROM public.event_users WHERE "user"=p_user AND event=ANY(v_event_ids);
  DELETE FROM public.event_users_saved WHERE "user"=p_user AND event=ANY(v_event_ids);
  DELETE FROM public.user_news WHERE "user"=p_user AND occasion=p_occasion;
  DELETE FROM public.occasion_users WHERE "user"=p_user AND occasion=p_occasion;
  DELETE FROM public.client_sync_private_scopes WHERE occasion=p_occasion
    AND user_id=p_user;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_private_impacts) impact
    WHERE impact->>'userId'=v_actor::text) THEN
    v_actor_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation','delete',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('membership'))),
    CASE WHEN v_publishable AND cardinality(v_event_ids)>0 THEN ARRAY['live_public']
      ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,
    jsonb_build_object('version',v_version,'profile',NULL),
    '{}','[]','user',NULL,v_actor_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint)
  TO authenticated;

ALTER FUNCTION public.import_user_group_assignments(bigint,jsonb)
  RENAME TO import_user_group_assignments_internal_v1;
REVOKE ALL ON FUNCTION public.import_user_group_assignments_internal_v1(bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.import_user_group_assignments(
  p_occasion_id bigint,p_assignments jsonb
) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.import_user_group_assignments_internal_v1(
    p_occasion_id,p_assignments);
$$;
REVOKE ALL ON FUNCTION public.import_user_group_assignments(bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_user_group_assignments(bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.replace_group_assignments_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_assignments jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_group_ids bigint[]; v_impacted_users uuid[]; v_private_impacts jsonb;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='group import permission required'; END IF;
  IF p_assignments IS NULL OR jsonb_typeof(p_assignments)<>'array'
    OR jsonb_array_length(p_assignments)>10000
    OR octet_length(p_assignments::text)>2097152 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group assignments'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'assignments',p_assignments)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.groups.import',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    AND g.type IS NULL ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT ug."group"),'{}'::bigint[])
    INTO v_group_ids FROM public.user_groups ug JOIN public.user_group_info g
      ON g.id=ug."group" JOIN jsonb_to_recordset(p_assignments)
      x(user_id uuid,group_title text) ON x.user_id=ug."user"
    WHERE g.occasion=p_occasion AND g.type IS NULL;
  SELECT COALESCE(array_agg(DISTINCT members."user"),'{}'::uuid[])
    INTO v_impacted_users FROM public.user_groups members
    WHERE members."group"=ANY(v_group_ids);
  PERFORM public.import_user_group_assignments_internal_v1(
    p_occasion,p_assignments);
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_group_ids||COALESCE((
    SELECT array_agg(ug."group") FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    JOIN jsonb_to_recordset(p_assignments) x(user_id uuid,group_title text)
      ON x.user_id=ug."user" WHERE g.occasion=p_occasion AND g.type IS NULL),
    '{}'::bigint[])) id ORDER BY id) INTO v_group_ids;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_impacted_users||COALESCE((
    SELECT array_agg(members."user") FROM public.user_groups members
    WHERE members."group"=ANY(v_group_ids)),'{}'::uuid[])) id ORDER BY id)
    INTO v_impacted_users;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(v_group_ids) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts
  FROM unnest(v_impacted_users) id JOIN public.occasion_users ou
    ON ou.occasion=p_occasion AND ou."user"=id;
  IF v_actor=ANY(v_impacted_users) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.groups.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group_membership','entityId',NULL,'operation','import',
      'safeLabel','Group assignment import','changedFields',jsonb_build_array('memberships'))),
    '{}',v_private_impacts,'[]',jsonb_build_object(
      'assignments',jsonb_array_length(p_assignments)),
    '{}','[]','user',NULL,v_actor_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb)
  TO authenticated;

ALTER FUNCTION public.import_occasion_users_from_csv(bigint,jsonb,jsonb)
  RENAME TO import_occasion_users_from_csv_internal_v1;
REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv_internal_v1(bigint,jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv(
  p_occasion_id bigint,p_rows jsonb,p_delete_user_ids jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.import_occasion_users_from_csv_internal_v1(
    p_occasion_id,p_rows,p_delete_user_ids);
$$;
REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv(bigint,jsonb,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_occasion_users_from_csv(bigint,jsonb,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.import_profiles_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_rows jsonb,p_delete_user_ids jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_result jsonb; v_before_users uuid[]; v_after_users uuid[]; v_current_users uuid[];
  v_event_ids bigint[]; v_group_ids bigint[]; v_private_impacts jsonb;
  v_publishable boolean; v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  SELECT o.unit,NOT o.is_hidden INTO v_unit,v_publishable
    FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='profile import permission required'; END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array'
    OR p_delete_user_ids IS NULL OR jsonb_typeof(p_delete_user_ids)<>'array'
    OR jsonb_array_length(p_rows)>10000 OR jsonb_array_length(p_delete_user_ids)>10000
    OR octet_length(p_rows::text)+octet_length(p_delete_user_ids::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid profile import'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'rows',p_rows,'deleteUserIds',p_delete_user_ids)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.users.import',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
    FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
    LEFT JOIN public.event_users_saved es ON es.event=e.id
    WHERE e.occasion=p_occasion AND (eu."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR
      es."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))));
  SELECT COALESCE(array_agg(DISTINCT ug."group"),'{}'::bigint[]) INTO v_group_ids
    FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
    JOIN public.user_info ui ON ui.id=ug."user"
    WHERE g.occasion=p_occasion AND (ug."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR ug."user"=ANY(
      COALESCE((SELECT array_agg((row->>'user_id')::uuid)
        FROM jsonb_array_elements(p_rows) row
        WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(ui.email_readonly))=ANY(COALESCE((SELECT array_agg(
        lower(btrim(row#>>'{data,email}'))) FROM jsonb_array_elements(p_rows) row),
        '{}'::text[])));
  v_result:=public.import_occasion_users_from_csv_internal_v1(
    p_occasion,p_rows,p_delete_user_ids);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE data_exception USING MESSAGE=COALESCE(v_result->>'message','profile import failed');
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_after_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT ou."user" ORDER BY ou."user"),'{}'::uuid[])
    INTO v_current_users FROM public.occasion_users ou
    JOIN public.user_info ui ON ui.id=ou."user"
    WHERE ou.occasion=p_occasion AND (ou."user"=ANY(COALESCE((SELECT array_agg(
      (row->>'user_id')::uuid) FROM jsonb_array_elements(p_rows) row
      WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(COALESCE(ui.email_readonly,ou.data->>'email')))=ANY(COALESCE((
        SELECT array_agg(lower(btrim(row#>>'{data,email}')))
        FROM jsonb_array_elements(p_rows) row),'{}'::text[])) OR
      NOT ou."user"=ANY(v_before_users));
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_group_ids||COALESCE((
    SELECT array_agg(DISTINCT ug."group") FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    WHERE g.occasion=p_occasion AND ug."user"=ANY(v_current_users)),
    '{}'::bigint[])) id ORDER BY id) INTO v_group_ids;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_current_users||COALESCE((
    SELECT array_agg(DISTINCT ug."user") FROM public.user_groups ug
    WHERE ug."group"=ANY(v_group_ids)),'{}'::uuid[])) id
    JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id
    ORDER BY id) INTO v_current_users;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,id::text,1
    FROM unnest(v_current_users) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(v_group_ids) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  DELETE FROM public.client_aggregate_versions v WHERE v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=ANY(ARRAY(SELECT value FROM jsonb_array_elements_text(
      p_delete_user_ids)));
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',id)),'[]'::jsonb) INTO v_private_impacts
  FROM unnest(v_current_users) id;
  IF v_actor=ANY(v_current_users) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.users.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',NULL,'operation','import',
      'safeLabel','Profile CSV import','changedFields',jsonb_build_array('profiles','services','groups'))),
    CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    v_private_impacts,CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,v_result,'{}','[]','user',NULL,v_actor_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb)
  TO authenticated;

-- Ungranted implementation seam shared by the three map aggregate families.
-- Client code can only invoke the explicit intent wrappers declared below.
CREATE OR REPLACE FUNCTION public.mutate_map_entity_internal_v1(
  p_kind text,p_action text,p_occasion bigint,p_command_id uuid,
  p_expected_version bigint,p_entity_id bigint,p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint:=p_entity_id; v_version bigint;
  v_begin jsonb; v_hash text; v_current jsonb; v_requested jsonb;
  v_entity jsonb; v_commit jsonb; v_public jsonb; v_response jsonb;
  v_is_publishable boolean; v_old_hidden boolean; v_new_hidden boolean;
  v_affects_public boolean:=false; v_label text; v_entity_key text;
BEGIN
  IF p_kind NOT IN ('place','place_type','path') OR p_action NOT IN ('save','delete')
    OR v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;

  IF p_action='save' THEN
    IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
      OR octet_length(p_payload::text)>262144 THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid map aggregate';
    END IF;
    IF p_kind='place' THEN
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE key NOT IN
          ('id','title','description','type','coordinates','isHidden','order','icon'))
        OR NOT (p_payload ?& ARRAY['title','coordinates','isHidden'])
        OR length(p_payload->>'title') NOT BETWEEN 1 AND 500
        OR jsonb_typeof(p_payload->'coordinates')<>'object'
        OR jsonb_typeof(p_payload#>'{coordinates,latLng}')<>'object'
        OR jsonb_typeof(p_payload#>'{coordinates,latLng,lat}')<>'number'
        OR jsonb_typeof(p_payload#>'{coordinates,latLng,lng}')<>'number'
        OR (p_payload#>>'{coordinates,latLng,lat}')::double precision NOT BETWEEN -90 AND 90
        OR (p_payload#>>'{coordinates,latLng,lng}')::double precision NOT BETWEEN -180 AND 180 THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid place aggregate';
      END IF;
      v_id:=(p_payload->>'id')::bigint;
      v_requested:=jsonb_build_object('id',v_id,'title',p_payload->>'title',
        'description',p_payload->>'description','type',p_payload->>'type',
        'coordinates',p_payload->'coordinates','isHidden',(p_payload->>'isHidden')::boolean,
        'order',(p_payload->>'order')::bigint,'icon',(p_payload->>'icon')::bigint);
      v_entity_key:='place';
    ELSIF p_kind='place_type' THEN
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE key NOT IN
          ('id','code','title','icon','order','isHidden','isDefault'))
        OR NOT (p_payload ?& ARRAY['code','title','isHidden','isDefault'])
        OR length(p_payload->>'code') NOT BETWEEN 1 AND 100
        OR (p_payload->>'code') !~ '^[A-Za-z0-9_-]+$'
        OR length(p_payload->>'title') NOT BETWEEN 1 AND 500 THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid place type aggregate';
      END IF;
      v_id:=(p_payload->>'id')::bigint;
      v_requested:=jsonb_build_object('id',v_id,'code',p_payload->>'code',
        'title',p_payload->>'title','icon',(p_payload->>'icon')::bigint,
        'order',(p_payload->>'order')::bigint,
        'isHidden',(p_payload->>'isHidden')::boolean,
        'isDefault',(p_payload->>'isDefault')::boolean);
      v_entity_key:='placeType';
    ELSE
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE key NOT IN
          ('id','title','pathData','data','icon','isHidden','order'))
        OR NOT (p_payload ?& ARRAY['title','isHidden'])
        OR length(p_payload->>'title') NOT BETWEEN 1 AND 500
        OR (p_payload->'pathData' IS NOT NULL
          AND jsonb_typeof(p_payload->'pathData')<>'array')
        OR COALESCE(jsonb_array_length(p_payload->'pathData'),0)>500 THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid path aggregate';
      END IF;
      v_id:=(p_payload->>'id')::bigint;
      v_requested:=jsonb_build_object('id',v_id,'title',p_payload->>'title',
        'pathData',p_payload->'pathData','data',p_payload->'data',
        'icon',(p_payload->>'icon')::bigint,
        'isHidden',(p_payload->>'isHidden')::boolean,
        'order',(p_payload->>'order')::bigint);
      v_entity_key:='path';
    END IF;
  ELSE
    IF v_id IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='entity id required'; END IF;
    v_entity_key:=CASE p_kind WHEN 'place_type' THEN 'placeType' ELSE p_kind END;
  END IF;

  IF (p_payload->>'icon') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.icons i JOIN public.occasions o
      ON o.id=p_occasion AND i.organization=o.organization
    WHERE i.id=(p_payload->>'icon')::bigint AND (i.unit=o.unit OR i.unit IS NULL)
  ) THEN RAISE invalid_parameter_value USING MESSAGE='cross-scope map icon'; END IF;
  IF p_kind='path' AND p_action='save' AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(p_payload->'pathData','[]')) segment,
      LATERAL jsonb_array_elements(segment) node
    WHERE (jsonb_typeof(node)='number' AND NOT EXISTS (
      SELECT 1 FROM public.places p WHERE p.id=(node#>>'{}')::bigint
        AND p.occasion=p_occasion))
      OR (jsonb_typeof(node)='object' AND NOT (
        jsonb_typeof(node->'lat')='number' AND jsonb_typeof(node->'lng')='number'))
      OR jsonb_typeof(node) NOT IN ('number','object')
  ) THEN RAISE invalid_parameter_value USING MESSAGE='invalid or cross-scope path node'; END IF;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'kind',p_kind,'action',p_action,'occasion',p_occasion,'entityId',v_id,
    'expectedVersion',p_expected_version,'payload',p_payload)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'map.'||p_kind||'.'||p_action,p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_id IS NOT NULL THEN
    IF p_kind='place' THEN
      PERFORM 1 FROM public.places p WHERE p.id=v_id AND p.occasion=p_occasion FOR UPDATE;
      IF FOUND THEN SELECT jsonb_build_object('id',p.id,'title',p.title,
        'description',p.description,'type',p.type,'coordinates',p.coordinates,
        'isHidden',p.is_hidden,'order',p."order",'icon',p.icon),p.is_hidden,p.title
        INTO v_current,v_old_hidden,v_label FROM public.places p WHERE p.id=v_id; END IF;
    ELSIF p_kind='place_type' THEN
      PERFORM 1 FROM public.place_types t WHERE t.id=v_id AND t.occasion=p_occasion FOR UPDATE;
      IF FOUND THEN SELECT jsonb_build_object('id',t.id,'code',t.code,'title',t.title,
        'icon',t.icon,'order',t."order",'isHidden',t.is_hidden,'isDefault',t.is_default),
        t.is_hidden,t.title INTO v_current,v_old_hidden,v_label
        FROM public.place_types t WHERE t.id=v_id; END IF;
    ELSE
      PERFORM 1 FROM public.path_groups pg WHERE pg.id=v_id AND pg.occasion=p_occasion FOR UPDATE;
      IF FOUND THEN SELECT jsonb_build_object('id',pg.id,'title',pg.title,
        'pathData',pg.path_data,'data',pg.data,'icon',pg.icon,
        'isHidden',pg.is_hidden,'order',pg."order"),pg.is_hidden,pg.title
        INTO v_current,v_old_hidden,v_label FROM public.path_groups pg WHERE pg.id=v_id; END IF;
    END IF;
    IF v_current IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        CASE WHEN p_action='delete' THEN 'unchanged' ELSE 'rejected' END,
        CASE WHEN p_action='delete' THEN 200 ELSE 404 END,
        jsonb_build_object('version',0,v_entity_key,NULL));
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES (p_kind,'occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type=p_kind AND scope_type='occasion' AND scope_id=p_occasion
        AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      IF p_kind='place' THEN SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.places p WHERE p.id=v_id;
      ELSIF p_kind='place_type' THEN SELECT to_jsonb(t)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.place_types t WHERE t.id=v_id;
      ELSE SELECT to_jsonb(pg)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.path_groups pg WHERE pg.id=v_id; END IF;
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'conflict',409,jsonb_build_object('version',v_version,
          v_entity_key,v_entity));
    END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new map aggregate must not have expected version';
  END IF;

  IF p_action='save' AND v_current IS NOT DISTINCT FROM v_requested THEN
    IF p_kind='place' THEN SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.places p WHERE p.id=v_id;
    ELSIF p_kind='place_type' THEN SELECT to_jsonb(t)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.place_types t WHERE t.id=v_id;
    ELSE SELECT to_jsonb(pg)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.path_groups pg WHERE pg.id=v_id; END IF;
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',v_version,
        v_entity_key,v_entity));
  END IF;

  IF p_action='delete' THEN
    IF p_kind='place' AND (EXISTS (SELECT 1 FROM public.events e WHERE e.place=v_id)
      OR EXISTS (SELECT 1 FROM public.user_group_info g WHERE g.place=v_id)
      OR EXISTS (SELECT 1 FROM public.path_groups pg,
          LATERAL jsonb_array_elements(COALESCE(pg.path_data,'[]')) segment,
          LATERAL jsonb_array_elements(segment) node
        WHERE pg.occasion=p_occasion AND jsonb_typeof(node)='number'
          AND (node#>>'{}')::bigint=v_id)) THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',409,jsonb_build_object('version',v_version,
          v_entity_key,NULL));
    END IF;
    IF p_kind='place_type' AND EXISTS (SELECT 1 FROM public.places p
      WHERE p.occasion=p_occasion AND p.type=v_current->>'code') THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',409,jsonb_build_object('version',v_version,
          v_entity_key,NULL));
    END IF;
    IF p_kind='place' THEN DELETE FROM public.places WHERE id=v_id;
    ELSIF p_kind='place_type' THEN DELETE FROM public.place_types WHERE id=v_id;
    ELSE DELETE FROM public.path_groups WHERE id=v_id; END IF;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type=p_kind
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text;
    v_entity:=NULL;
    v_affects_public:=NOT v_old_hidden;
  ELSE
    v_new_hidden:=(p_payload->>'isHidden')::boolean;
    v_affects_public:=NOT COALESCE(v_old_hidden,true) OR NOT v_new_hidden;
    IF p_kind='place' THEN
      IF v_id IS NULL THEN INSERT INTO public.places
        (title,description,type,coordinates,is_hidden,occasion,"order",icon)
        VALUES (p_payload->>'title',p_payload->>'description',p_payload->>'type',
          p_payload->'coordinates',v_new_hidden,p_occasion,(p_payload->>'order')::bigint,
          (p_payload->>'icon')::bigint) RETURNING id INTO v_id;
      ELSE UPDATE public.places SET title=p_payload->>'title',description=p_payload->>'description',
        type=p_payload->>'type',coordinates=p_payload->'coordinates',is_hidden=v_new_hidden,
        "order"=(p_payload->>'order')::bigint,icon=(p_payload->>'icon')::bigint,
        updated_at=clock_timestamp() WHERE id=v_id; END IF;
    ELSIF p_kind='place_type' THEN
      IF v_id IS NULL THEN INSERT INTO public.place_types
        (occasion,code,title,icon,"order",is_hidden,is_default)
        VALUES (p_occasion,p_payload->>'code',p_payload->>'title',(p_payload->>'icon')::bigint,
          (p_payload->>'order')::bigint,v_new_hidden,(p_payload->>'isDefault')::boolean)
        RETURNING id INTO v_id;
      ELSE UPDATE public.place_types SET code=p_payload->>'code',title=p_payload->>'title',
        icon=(p_payload->>'icon')::bigint,"order"=(p_payload->>'order')::bigint,
        is_hidden=v_new_hidden,is_default=(p_payload->>'isDefault')::boolean,
        updated_at=clock_timestamp() WHERE id=v_id; END IF;
    ELSE
      IF v_id IS NULL THEN INSERT INTO public.path_groups
        (title,path_data,data,icon,is_hidden,occasion,"order")
        VALUES (p_payload->>'title',p_payload->'pathData',p_payload->'data',
          (p_payload->>'icon')::bigint,v_new_hidden,p_occasion,
          (p_payload->>'order')::bigint) RETURNING id INTO v_id;
      ELSE UPDATE public.path_groups SET title=p_payload->>'title',
        path_data=p_payload->'pathData',data=p_payload->'data',
        icon=(p_payload->>'icon')::bigint,is_hidden=v_new_hidden,
        "order"=(p_payload->>'order')::bigint WHERE id=v_id; END IF;
    END IF;
    IF v_version IS NULL THEN v_version:=1;
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES (p_kind,'occasion',p_occasion,v_id::text,v_version);
    ELSE UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type=p_kind
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version; END IF;
    IF p_kind='place' THEN SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',v_version),p.title
      INTO v_entity,v_label FROM public.places p WHERE p.id=v_id;
    ELSIF p_kind='place_type' THEN SELECT to_jsonb(t)||jsonb_build_object('aggregate_version',v_version),t.title
      INTO v_entity,v_label FROM public.place_types t WHERE t.id=v_id;
    ELSE SELECT to_jsonb(pg)||jsonb_build_object('aggregate_version',v_version),pg.title
      INTO v_entity,v_label FROM public.path_groups pg WHERE pg.id=v_id; END IF;
  END IF;

  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'map.'||p_kind||'.'||p_action,'map',jsonb_build_array(jsonb_build_object(
      'entityType',p_kind,'entityId',v_id,'operation',CASE WHEN p_action='delete'
        THEN 'delete' WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(v_label,240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND v_affects_public THEN ARRAY['map_catalog']
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',COALESCE(v_version,0),v_entity_key,v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.mutate_map_entity_internal_v1(text,text,bigint,uuid,bigint,bigint,jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.save_place_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_place jsonb
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.mutate_map_entity_internal_v1('place','save',p_occasion,
    p_command_id,p_expected_version,NULL,p_place); $$;
CREATE OR REPLACE FUNCTION public.delete_place_client_sync_v1(
  p_occasion bigint,p_place_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.mutate_map_entity_internal_v1('place','delete',p_occasion,
    p_command_id,p_expected_version,p_place_id,NULL); $$;
CREATE OR REPLACE FUNCTION public.save_place_type_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_place_type jsonb
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.mutate_map_entity_internal_v1('place_type','save',p_occasion,
    p_command_id,p_expected_version,NULL,p_place_type); $$;
CREATE OR REPLACE FUNCTION public.delete_place_type_client_sync_v1(
  p_occasion bigint,p_place_type_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.mutate_map_entity_internal_v1('place_type','delete',p_occasion,
    p_command_id,p_expected_version,p_place_type_id,NULL); $$;
CREATE OR REPLACE FUNCTION public.save_path_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_path jsonb
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.mutate_map_entity_internal_v1('path','save',p_occasion,
    p_command_id,p_expected_version,NULL,p_path); $$;
CREATE OR REPLACE FUNCTION public.delete_path_client_sync_v1(
  p_occasion bigint,p_path_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.mutate_map_entity_internal_v1('path','delete',p_occasion,
    p_command_id,p_expected_version,p_path_id,NULL); $$;

REVOKE ALL ON FUNCTION public.save_place_client_sync_v1(bigint,uuid,bigint,jsonb),
  public.delete_place_client_sync_v1(bigint,bigint,uuid,bigint),
  public.save_place_type_client_sync_v1(bigint,uuid,bigint,jsonb),
  public.delete_place_type_client_sync_v1(bigint,bigint,uuid,bigint),
  public.save_path_client_sync_v1(bigint,uuid,bigint,jsonb),
  public.delete_path_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_place_client_sync_v1(bigint,uuid,bigint,jsonb),
  public.delete_place_client_sync_v1(bigint,bigint,uuid,bigint),
  public.save_place_type_client_sync_v1(bigint,uuid,bigint,jsonb),
  public.delete_place_type_client_sync_v1(bigint,bigint,uuid,bigint),
  public.save_path_client_sync_v1(bigint,uuid,bigint,jsonb),
  public.delete_path_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.move_place_client_sync_v1(
  p_occasion bigint,p_place_id bigint,p_command_id uuid,p_expected_version bigint,
  p_lat double precision,p_lng double precision
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_place public.places%ROWTYPE; v_commit jsonb; v_public jsonb; v_response jsonb;
  v_is_publishable boolean; v_affects_public boolean;
BEGIN
  SELECT p.* INTO v_place FROM public.places p
    WHERE p.id=p_place_id AND p.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='place not found'; END IF;
  IF v_actor IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180
    OR NOT (public.get_is_editor_on_occasion(p_occasion) OR EXISTS (
      SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g
        ON g.id=ug."group" WHERE ug."user"=v_actor AND ug.is_admin
        AND g.occasion=p_occasion AND g.place=p_place_id
        AND v_place.type='group' AND v_place.is_hidden)) THEN
    RAISE insufficient_privilege USING MESSAGE='place move permission required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'placeId',p_place_id,'expectedVersion',p_expected_version,'lat',p_lat,'lng',p_lng)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'map.place.move',p_occasion,
    v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('place','occasion',p_occasion,p_place_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=p_occasion
      AND aggregate_id=p_place_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'conflict',409,jsonb_build_object('version',v_version,'place',
        to_jsonb(v_place)||jsonb_build_object('aggregate_version',v_version)));
  END IF;
  IF v_place.coordinates=jsonb_build_object('latLng',jsonb_build_object('lat',p_lat,'lng',p_lng)) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',v_version,'place',
        to_jsonb(v_place)||jsonb_build_object('aggregate_version',v_version)));
  END IF;
  UPDATE public.places SET coordinates=jsonb_build_object('latLng',
    jsonb_build_object('lat',p_lat,'lng',p_lng)),updated_at=clock_timestamp()
    WHERE id=p_place_id RETURNING * INTO v_place;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='place'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_place_id::text
    RETURNING version INTO v_version;
  v_affects_public:=NOT v_place.is_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'map.place.move','map',
    jsonb_build_array(jsonb_build_object('entityType','place','entityId',p_place_id,
      'operation','update','safeLabel',left(v_place.title,240),
      'changedFields',jsonb_build_array('coordinates'))),
    CASE WHEN v_is_publishable AND v_affects_public THEN ARRAY['map_catalog']
      ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'place',to_jsonb(v_place)||
      jsonb_build_object('aggregate_version',v_version)));
END; $$;
REVOKE ALL ON FUNCTION public.move_place_client_sync_v1(bigint,bigint,uuid,bigint,double precision,double precision)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.move_place_client_sync_v1(bigint,bigint,uuid,bigint,double precision,double precision)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_client_commits_v1(
  p_occasion bigint, p_before_time timestamptz DEFAULT NULL,
  p_before_id uuid DEFAULT NULL, p_limit integer DEFAULT 50,
  p_filters jsonb DEFAULT '{}'
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE WHEN NOT (public.get_is_manager_on_occasion(p_occasion)
      OR public.get_is_admin_on_occasion(p_occasion)) THEN jsonb_build_object('code',403)
    ELSE jsonb_build_object('code',200,'data',COALESCE((
      SELECT jsonb_agg(row_data ORDER BY occurred_at DESC, commit_id DESC) FROM (
        SELECT c.occurred_at,c.commit_id,jsonb_build_object(
          'commitId',c.commit_id,'occurredAt',c.occurred_at,'actorDisplay',c.actor_display,
          'actorKind',c.actor_kind,'source',c.source,'changeClass',c.change_class,
          'itemCount',(SELECT count(*) FROM public.client_commit_items ci WHERE ci.commit_id=c.commit_id),
          'components',(SELECT COALESCE(jsonb_agg(jsonb_build_object('component',cc.component,'revision',cc.resulting_revision,
            'publishedRevision',pub.published_revision,'publicationStatus',CASE WHEN pub.published_revision>=cc.resulting_revision THEN 'published' ELSE 'pending' END)),'[]')
            FROM public.client_commit_components cc LEFT JOIN LATERAL (SELECT max(cp.published_revision) published_revision
              FROM public.client_sync_publications cp WHERE cp.component=cc.component AND cp.scope_type=cc.scope_type AND cp.scope_id=cc.scope_id) pub ON true
            WHERE cc.commit_id=c.commit_id)
        ) row_data
        FROM public.client_commits c WHERE (c.occasion=p_occasion OR c.unit=(
          SELECT o.unit FROM public.occasions o WHERE o.id=p_occasion)
          OR c.organization=(SELECT o.organization FROM public.occasions o
            WHERE o.id=p_occasion))
          AND (p_before_time IS NULL OR (c.occurred_at,c.commit_id)<(p_before_time,p_before_id))
          AND (NOT p_filters ? 'source' OR c.source=p_filters->>'source')
          AND (NOT p_filters ? 'changeClass' OR c.change_class=p_filters->>'changeClass')
          AND (NOT p_filters ? 'actorKind' OR c.actor_kind=p_filters->>'actorKind')
          AND (NOT p_filters ? 'actor' OR COALESCE(c.actor_display,'') ILIKE '%'||(p_filters->>'actor')||'%')
          AND (NOT p_filters ? 'from' OR c.occurred_at >= (p_filters->>'from')::timestamptz)
          AND (NOT p_filters ? 'to' OR c.occurred_at < (p_filters->>'to')::timestamptz)
          AND (NOT p_filters ? 'component' OR EXISTS(SELECT 1 FROM public.client_commit_components fc
            WHERE fc.commit_id=c.commit_id AND fc.component=p_filters->>'component'))
        ORDER BY c.occurred_at DESC,c.commit_id DESC LIMIT LEAST(GREATEST(p_limit,1),200)
      ) page), '[]')) END;
$$;
REVOKE ALL ON FUNCTION public.get_client_commits_v1(bigint,timestamptz,uuid,integer,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_commits_v1(bigint,timestamptz,uuid,integer,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_client_commit_v1(p_commit_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = '' AS $$
  SELECT CASE WHEN c.commit_id IS NULL THEN jsonb_build_object('code',404)
    WHEN NOT (CASE WHEN c.occasion IS NOT NULL THEN
      public.get_is_manager_on_occasion(c.occasion)
        OR public.get_is_admin_on_occasion(c.occasion)
      WHEN c.unit IS NOT NULL THEN public.get_is_manager_on_unit(c.unit)
      ELSE public.get_is_admin_on_organization(c.organization) END) THEN jsonb_build_object('code',403)
    ELSE jsonb_build_object('code',200,'data',jsonb_build_object(
      'commitId',c.commit_id,'occurredAt',c.occurred_at,'actorDisplay',c.actor_display,
      'actorKind',c.actor_kind,'source',c.source,'changeClass',c.change_class,'reason',c.reason,
      'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('entityType',i.entity_type,'entityId',i.entity_id,'operation',i.operation,'safeLabel',i.safe_label,'changedFields',i.changed_fields) ORDER BY i.item_index),'[]') FROM public.client_commit_items i WHERE i.commit_id=c.commit_id),
      'components',(SELECT COALESCE(jsonb_agg(jsonb_build_object('component',cc.component,'scopeType',cc.scope_type,'scopeId',cc.scope_id,
        'revision',cc.resulting_revision,'publishedRevision',p.published_revision,
        'publicationStatus',CASE WHEN p.published_revision>=cc.resulting_revision THEN 'published' ELSE 'pending' END) ORDER BY cc.component),'[]')
        FROM public.client_commit_components cc LEFT JOIN LATERAL (SELECT max(cp.published_revision) published_revision
          FROM public.client_sync_publications cp WHERE cp.component=cc.component AND cp.scope_type=cc.scope_type AND cp.scope_id=cc.scope_id) p ON true
        WHERE cc.commit_id=c.commit_id))) END
  FROM (SELECT * FROM public.client_commits WHERE commit_id=p_commit_id) c
  RIGHT JOIN (SELECT 1) seed ON true;
$$;
REVOKE ALL ON FUNCTION public.get_client_commit_v1(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_commit_v1(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.claim_client_projection_dirty_v1(p_limit integer DEFAULT 200)
RETURNS TABLE(component text,scope_type text,scope_id bigint,entity_id bigint,source_revision bigint,claim_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_token uuid := gen_random_uuid();
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  RETURN QUERY WITH claimed AS (
    SELECT d.component,d.scope_type,d.scope_id,d.entity_id FROM public.client_projection_dirty_keys d
    WHERE d.claimed_at IS NULL OR d.claimed_at < now()-interval '2 minutes'
    ORDER BY d.dirty_since FOR UPDATE SKIP LOCKED LIMIT LEAST(p_limit,1000)
  ), updated AS (
    UPDATE public.client_projection_dirty_keys d SET claimed_at=now(),claim_token=v_token
    FROM claimed c WHERE (d.component,d.scope_type,d.scope_id,d.entity_id)=(c.component,c.scope_type,c.scope_id,c.entity_id)
    RETURNING d.*
  ) SELECT u.component,u.scope_type,u.scope_id,u.entity_id,u.source_revision,u.claim_token FROM updated u;
END; $$;
REVOKE ALL ON FUNCTION public.claim_client_projection_dirty_v1(integer) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.refresh_event_public_state_v1(p_occasion bigint,p_event_ids bigint[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  INSERT INTO public.event_public_state(occasion,event,participant_count,saved_count,remaining_capacity,revision,projected_at)
  SELECT e.occasion,e.id,COUNT(DISTINCT eu."user"),COUNT(DISTINCT es."user"),
    CASE WHEN e.max_participants IS NULL THEN NULL ELSE GREATEST(e.max_participants-COUNT(DISTINCT eu."user"),0) END,
    COALESCE(s.source_revision,0),now()
  FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
  LEFT JOIN public.event_users_saved es ON es.event=e.id
  LEFT JOIN public.client_sync_scopes s ON s.component='live_public' AND s.scope_type='occasion' AND s.scope_id=e.occasion
  WHERE e.occasion=p_occasion
    AND (cardinality(COALESCE(p_event_ids,'{}'::bigint[]))=0 OR e.id=ANY(p_event_ids))
  GROUP BY e.occasion,e.id,e.max_participants,s.source_revision
  ON CONFLICT (occasion,event) DO UPDATE SET participant_count=EXCLUDED.participant_count,
    saved_count=EXCLUDED.saved_count,remaining_capacity=EXCLUDED.remaining_capacity,
    revision=EXCLUDED.revision,projected_at=EXCLUDED.projected_at;
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_event_public_state_v1(bigint,bigint[]) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.refresh_cleaning_public_state_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  INSERT INTO public.cleaning_public_state
    (occasion,place,status,open_report_count,revision,projected_at)
  SELECT p.occasion,p.id,
    CASE COALESCE(max(CASE r.problem_type WHEN 'contamination' THEN 3 WHEN 'hygiene' THEN 2 WHEN 'paper' THEN 1 ELSE 0 END),0)
      WHEN 3 THEN 'contamination' WHEN 2 THEN 'hygiene' WHEN 1 THEN 'paper' ELSE 'green' END,
    count(r.id),COALESCE(s.source_revision,0),now()
  FROM public.places p LEFT JOIN public.cleaning_reports r ON r.place=p.id AND r.resolved_at IS NULL
  LEFT JOIN public.client_sync_scopes s ON s.component='live_public' AND s.scope_type='occasion' AND s.scope_id=p.occasion
  WHERE p.occasion=p_occasion AND p.type='toilet'
  GROUP BY p.occasion,p.id,s.source_revision
  ON CONFLICT (occasion,place) DO UPDATE SET status=EXCLUDED.status,
    open_report_count=EXCLUDED.open_report_count,revision=EXCLUDED.revision,
    projected_at=EXCLUDED.projected_at;
  DELETE FROM public.cleaning_public_state c WHERE c.occasion=p_occasion
    AND NOT EXISTS (SELECT 1 FROM public.places p WHERE p.id=c.place AND p.occasion=p_occasion AND p.type='toilet');
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_cleaning_public_state_v1(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_public_client_sync_component_v1(
  p_component text, p_scope_type text, p_scope_id bigint
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_revision bigint; v_payload jsonb; v_organization bigint; v_generated_at timestamptz;
BEGIN
  IF NOT public.is_service_role()
     AND NOT public.get_is_editor_on_occasion(p_scope_id) THEN
    RAISE insufficient_privilege USING MESSAGE='publisher or occasion editor required';
  END IF;
  IF p_scope_type <> 'occasion' OR NOT EXISTS (
    SELECT 1 FROM public.occasions WHERE id=p_scope_id AND NOT is_hidden
  ) THEN RAISE EXCEPTION 'scope is not publicly publishable'; END IF;
  SELECT source_revision,updated_at INTO v_revision,v_generated_at FROM public.client_sync_scopes
    WHERE component=p_component AND scope_type=p_scope_type AND scope_id=p_scope_id;
  v_revision := COALESCE(v_revision,0);

  CASE p_component
    WHEN 'occasion_config' THEN
      SELECT jsonb_build_object('id',o.id,'title',o.title,'startTime',o.start_time,
        'endTime',o.end_time,'isOpen',o.is_open,'features',o.features,'data',o.data,
        'services',o.services,'unitId',o.unit) INTO v_payload
      FROM public.occasions o WHERE o.id=p_scope_id AND NOT o.is_hidden;
    WHEN 'program_catalog' THEN
      SELECT jsonb_build_object(
        'events',COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id',e.id,'title',e.title,
          'startTime',e.start_time,'endTime',e.end_time,'maxParticipants',e.max_participants,
          'description',e.description,'placeId',e.place,'type',e.type,'data',e.data,
          'order',e."order",'isGroupEvent',e.is_group_event,'splitForMenWomen',e.split_for_men_women)) FILTER (WHERE e.id IS NOT NULL),'[]'),
        'eventGroups',(SELECT COALESCE(jsonb_agg(jsonb_build_object('parentId',eg.event_parent,'childId',eg.event_child) ORDER BY eg.event_parent,eg.event_child),'[]') FROM public.event_groups eg JOIN public.events ep ON ep.id=eg.event_parent JOIN public.events ec ON ec.id=eg.event_child WHERE ep.occasion=p_scope_id AND ec.occasion=p_scope_id AND NOT ep.is_hidden AND NOT ec.is_hidden),
        'eventRoles',(SELECT COALESCE(jsonb_agg(jsonb_build_object('eventId',er.event,'roleId',er.role) ORDER BY er.event,er.role),'[]') FROM public.event_roles er JOIN public.events e2 ON e2.id=er.event WHERE e2.occasion=p_scope_id AND NOT e2.is_hidden),
        'eventSpeakers',(SELECT COALESCE(jsonb_agg(jsonb_build_object('eventId',es.event,'speakerId',es.speaker) ORDER BY es.event,es.speaker),'[]') FROM public.event_speakers es JOIN public.events e3 ON e3.id=es.event JOIN public.speakers sp ON sp.id=es.speaker WHERE e3.occasion=p_scope_id AND NOT e3.is_hidden AND NOT sp.is_hidden)
      ) INTO v_payload FROM public.events e WHERE e.occasion=p_scope_id AND NOT e.is_hidden;
    WHEN 'map_catalog' THEN
      SELECT o.organization INTO v_organization FROM public.occasions o WHERE o.id=p_scope_id;
      WITH visible_places AS (
        SELECT p.*,COALESCE(v.version,0) aggregate_version FROM public.places p
        LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place'
          AND v.scope_type='occasion' AND v.scope_id=p_scope_id
          AND v.aggregate_id=p.id::text
        WHERE p.occasion=p_scope_id AND NOT p.is_hidden
      ), visible_types AS (
        SELECT pt.*,COALESCE(v.version,0) aggregate_version FROM public.place_types pt
        LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place_type'
          AND v.scope_type='occasion' AND v.scope_id=p_scope_id
          AND v.aggregate_id=pt.id::text
        WHERE pt.occasion=p_scope_id AND NOT pt.is_hidden
      ), visible_paths AS (
        SELECT pg.*,COALESCE(v.version,0) aggregate_version FROM public.path_groups pg
        LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='path'
          AND v.scope_type='occasion' AND v.scope_id=p_scope_id
          AND v.aggregate_id=pg.id::text
        WHERE pg.occasion=p_scope_id AND NOT pg.is_hidden
      ), icon_ids AS (
        SELECT icon FROM visible_places WHERE icon IS NOT NULL UNION
        SELECT icon FROM visible_types WHERE icon IS NOT NULL UNION
        SELECT icon FROM visible_paths WHERE icon IS NOT NULL
      ), missing AS (
        SELECT i.icon FROM icon_ids i LEFT JOIN public.icons x ON x.id=i.icon AND x.organization=v_organization
        WHERE x.id IS NULL
      )
      SELECT CASE WHEN EXISTS(SELECT 1 FROM missing) THEN NULL ELSE jsonb_build_object(
        'places',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'description',p.description,'type',p.type,'coordinates',p.coordinates,'order',p."order",'icon',p.icon,'aggregateVersion',p.aggregate_version) ORDER BY p."order",p.id),'[]') FROM visible_places p),
        'placeTypes',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pt.id,'code',pt.code,'title',pt.title,'icon',pt.icon,'order',pt."order",'isDefault',pt.is_default,'aggregateVersion',pt.aggregate_version) ORDER BY pt."order",pt.id),'[]') FROM visible_types pt),
        'paths',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pg.id,'title',pg.title,'pathData',pg.path_data,'data',pg.data,'icon',pg.icon,'order',pg."order",'aggregateVersion',pg.aggregate_version) ORDER BY pg."order",pg.id),'[]') FROM visible_paths pg),
        'icons',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',i.id,'link',i.link,'svg',i.data) ORDER BY i.id),'[]') FROM public.icons i JOIN icon_ids refs ON refs.icon=i.id)
      ) END INTO v_payload;
      IF v_payload IS NULL THEN RAISE EXCEPTION 'map_catalog has a dangling or foreign icon reference'; END IF;
    WHEN 'content_catalog' THEN
      SELECT jsonb_build_object(
        'information',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',i.id,'title',i.title,'description',i.description,'order',i."order",'type',i.type,'data',i.data,'aggregateVersion',COALESCE(v.version,0)) ORDER BY i."order",i.id),'[]') FROM public.information i LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='information' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=i.id::text WHERE i.occasion=p_scope_id AND NOT i.is_hidden),
        'news',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',n.id,'message',n.message,'createdAt',n.created_at,'updatedAt',n.updated_at,'aggregateVersion',COALESCE(v.version,0)) ORDER BY n.created_at,n.id),'[]') FROM public.news n LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='news' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=n.id::text WHERE n.occasion=p_scope_id),
        'speakers',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'title',s.title,'subtitle',s.subtitle,'description',s.description,'image',s.image,'order',s."order",'data',s.data,'aggregateVersion',COALESCE(v.version,0)) ORDER BY s."order",s.id),'[]') FROM public.speakers s LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=s.id::text WHERE s.occasion=p_scope_id AND NOT s.is_hidden),
        'topics',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'order',t."order",'aggregateVersion',COALESCE(v.version,0)) ORDER BY t."order",t.id),'[]') FROM public.speaker_topics t LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker_topic' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=t.id::text WHERE t.occasion=p_scope_id AND NOT t.is_hidden),
        'topicLinks',(SELECT COALESCE(jsonb_agg(jsonb_build_object('speakerId',l.speaker,'topicId',l.topic) ORDER BY l.speaker,l.topic),'[]') FROM public.speaker_topic_links l JOIN public.speakers s ON s.id=l.speaker JOIN public.speaker_topics t ON t.id=l.topic WHERE s.occasion=p_scope_id AND t.occasion=p_scope_id AND NOT s.is_hidden AND NOT t.is_hidden)
      ) INTO v_payload;
    WHEN 'unit_catalog' THEN
      SELECT jsonb_build_object('unit',jsonb_build_object('id',u.id,'title',u.title,'data',u.data,'features',u.features),
        'occasions',COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'title',o.title,'link',o.link,'startTime',o.start_time,'endTime',o.end_time,'description',o.description,'isOpen',o.is_open,'isPromoted',o.is_promoted) ORDER BY o.start_time,o.id) FILTER (WHERE o.id IS NOT NULL),'[]')) INTO v_payload
      FROM public.occasions current_o JOIN public.units u ON u.id=current_o.unit
      LEFT JOIN public.occasions o ON o.unit=u.id AND NOT o.is_hidden
      WHERE current_o.id=p_scope_id GROUP BY u.id;
    WHEN 'live_public' THEN
      SELECT jsonb_build_object(
        'events',(SELECT COALESCE(jsonb_agg(jsonb_build_object('eventId',s.event,'participantCount',s.participant_count,'savedCount',s.saved_count,'remainingCapacity',s.remaining_capacity) ORDER BY s.event),'[]') FROM public.event_public_state s JOIN public.events e ON e.id=s.event WHERE s.occasion=p_scope_id AND NOT e.is_hidden),
        'cleaning',(SELECT COALESCE(jsonb_agg(jsonb_build_object('placeId',s.place,'status',s.status,'openReportCount',s.open_report_count) ORDER BY s.place),'[]') FROM public.cleaning_public_state s WHERE s.occasion=p_scope_id)
      ) INTO v_payload;
    ELSE RAISE EXCEPTION 'unsupported public component %',p_component;
  END CASE;
  RETURN jsonb_build_object('protocol',1,'schema',1,'component',p_component,
    'scope',((SELECT organization FROM public.occasions WHERE id=p_scope_id))::text||'/'||p_scope_id::text,
    'revision',v_revision,'generatedAt',COALESCE(v_generated_at,'epoch'::timestamptz),'payload',v_payload);
END; $$;
REVOKE ALL ON FUNCTION public.get_public_client_sync_component_v1(text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_client_sync_component_v1(text,text,bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_client_projection_dirty_v1(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_event_public_state_v1(bigint,bigint[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_cleaning_public_state_v1(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.next_client_sync_release_revision_v1()
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  RETURN nextval('public.client_sync_release_revision_seq');
END;
$$;
REVOKE ALL ON FUNCTION public.next_client_sync_release_revision_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.next_client_sync_release_revision_v1() TO service_role;

CREATE OR REPLACE FUNCTION public.complete_client_sync_publication_v1(
  p_scope_type text,p_scope_id bigint,p_release_revision bigint,p_manifest jsonb,
  p_manifest_url text,p_manifest_sha256 text,p_manifest_bytes bigint,
  p_head_json jsonb,p_head_etag text,p_claim_tokens uuid[]
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_current bigint;
  v_component record;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT release_revision INTO v_current FROM public.client_sync_public_heads
    WHERE scope_type=p_scope_type AND scope_id=p_scope_id FOR UPDATE;
  IF v_current IS NOT NULL AND v_current >= p_release_revision THEN RETURN false; END IF;
  INSERT INTO public.client_sync_release_manifests
    (scope_type,scope_id,release_revision,manifest,artifact_url,sha256,byte_size)
  VALUES (p_scope_type,p_scope_id,p_release_revision,p_manifest,p_manifest_url,
    p_manifest_sha256,p_manifest_bytes) ON CONFLICT DO NOTHING;
  FOR v_component IN SELECT key,value FROM jsonb_each(p_manifest->'components') LOOP
    INSERT INTO public.client_sync_publications
      (component,scope_type,scope_id,published_revision,media_type,artifact_url,sha256,byte_size)
    VALUES (v_component.key,p_scope_type,p_scope_id,
      (v_component.value->>'revision')::bigint,v_component.value->>'mediaType',
      v_component.value->>'url',v_component.value->>'sha256',
      (v_component.value->>'bytes')::bigint)
    ON CONFLICT DO NOTHING;
  END LOOP;
  IF p_head_json->'live' IS NOT NULL THEN
    INSERT INTO public.client_sync_publications
      (component,scope_type,scope_id,published_revision,media_type,artifact_url,sha256,byte_size)
    VALUES ('live_public',p_scope_type,p_scope_id,
      (p_head_json#>>'{live,revision}')::bigint,p_head_json#>>'{live,mediaType}',
      p_head_json#>>'{live,url}',p_head_json#>>'{live,sha256}',
      (p_head_json#>>'{live,bytes}')::bigint)
    ON CONFLICT DO NOTHING;
  END IF;
  INSERT INTO public.client_sync_public_heads
    (scope_type,scope_id,release_revision,manifest_sha256,live_revision,live_sha256,head_etag,head_json)
  VALUES (p_scope_type,p_scope_id,p_release_revision,p_manifest_sha256,
    (p_head_json#>>'{live,revision}')::bigint,p_head_json#>>'{live,sha256}',p_head_etag,p_head_json)
  ON CONFLICT (scope_type,scope_id) DO UPDATE SET release_revision=EXCLUDED.release_revision,
    manifest_sha256=EXCLUDED.manifest_sha256,live_revision=EXCLUDED.live_revision,
    live_sha256=EXCLUDED.live_sha256,head_etag=EXCLUDED.head_etag,
    head_json=EXCLUDED.head_json,updated_at=now()
  WHERE public.client_sync_public_heads.release_revision < EXCLUDED.release_revision;
  DELETE FROM public.client_projection_dirty_keys WHERE claim_token=ANY(p_claim_tokens);
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.complete_client_sync_publication_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,text,uuid[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_client_sync_publication_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,text,uuid[]) TO service_role;

-- Publisher reads one compact checkpoint and reuses clean immutable descriptors.
-- The append-only commit ledger is deliberately absent from this path.
CREATE OR REPLACE FUNCTION public.get_client_sync_publication_state_v1(
  p_scope_type text,p_scope_id bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_scope text; v_head public.client_sync_public_heads%ROWTYPE; v_components jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF p_scope_type <> 'occasion' THEN RAISE EXCEPTION 'unsupported scope type'; END IF;
  SELECT o.organization::text||'/'||o.id::text INTO v_scope
  FROM public.occasions o WHERE o.id=p_scope_id AND NOT o.is_hidden;
  IF v_scope IS NULL THEN RAISE EXCEPTION 'scope is not publicly publishable'; END IF;
  SELECT * INTO v_head FROM public.client_sync_public_heads
    WHERE scope_type=p_scope_type AND scope_id=p_scope_id;
  WITH required(component) AS (VALUES ('occasion_config'),('program_catalog'),
    ('map_catalog'),('content_catalog'),('unit_catalog')),
  latest AS (
    SELECT DISTINCT ON (p.component) p.* FROM public.client_sync_publications p
    JOIN required r ON r.component=p.component
    WHERE p.scope_type=p_scope_type AND p.scope_id=p_scope_id
    ORDER BY p.component,p.published_revision DESC
  ) SELECT COALESCE(jsonb_object_agg(component,jsonb_build_object(
      'revision',published_revision,'mediaType',media_type,'url',artifact_url,
      'sha256',sha256,'bytes',byte_size)),'{}') INTO v_components FROM latest;
  RETURN jsonb_build_object('scope',v_scope,'components',v_components,
    'catalog',v_head.head_json->'catalog','live',v_head.head_json->'live',
    'headEtag',v_head.head_etag);
END; $$;
REVOKE ALL ON FUNCTION public.get_client_sync_publication_state_v1(text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_client_sync_publication_state_v1(text,bigint) TO service_role;

-- Catalog and live advance independently. One call records the exact merged R2
-- head and clears only claims whose class was successfully uploaded.
CREATE OR REPLACE FUNCTION public.complete_client_sync_publication_classes_v1(
  p_scope_type text,p_scope_id bigint,p_release_revision bigint,p_manifest jsonb,
  p_manifest_url text,p_manifest_sha256 text,p_manifest_bytes bigint,p_live jsonb,
  p_head_json jsonb,p_head_etag text,p_catalog_claim_tokens uuid[],p_live_claim_tokens uuid[]
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_head public.client_sync_public_heads%ROWTYPE; v_component record;
  v_next_catalog bigint := (p_head_json#>>'{catalog,revision}')::bigint;
  v_next_live bigint := (p_head_json#>>'{live,revision}')::bigint;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT * INTO v_head FROM public.client_sync_public_heads
    WHERE scope_type=p_scope_type AND scope_id=p_scope_id FOR UPDATE;
  IF FOUND AND (v_next_catalog < COALESCE(v_head.release_revision,-1)
      OR COALESCE(v_next_live,-1) < COALESCE(v_head.live_revision,-1)
      OR (v_next_catalog = v_head.release_revision
          AND v_next_live IS NOT DISTINCT FROM v_head.live_revision
          AND v_head.head_json IS DISTINCT FROM p_head_json)) THEN
    RETURN false;
  END IF;
  IF p_release_revision IS NOT NULL THEN
    IF p_manifest IS NULL OR p_manifest_sha256 IS NULL
       OR p_release_revision <> v_next_catalog THEN RAISE EXCEPTION 'invalid catalog completion'; END IF;
    INSERT INTO public.client_sync_release_manifests
      (scope_type,scope_id,release_revision,manifest,artifact_url,sha256,byte_size)
    VALUES (p_scope_type,p_scope_id,p_release_revision,p_manifest,p_manifest_url,
      p_manifest_sha256,p_manifest_bytes) ON CONFLICT DO NOTHING;
    FOR v_component IN SELECT key,value FROM jsonb_each(p_manifest->'components') LOOP
      INSERT INTO public.client_sync_publications
        (component,scope_type,scope_id,published_revision,media_type,artifact_url,sha256,byte_size)
      VALUES (v_component.key,p_scope_type,p_scope_id,
        (v_component.value->>'revision')::bigint,v_component.value->>'mediaType',
        v_component.value->>'url',v_component.value->>'sha256',(v_component.value->>'bytes')::bigint)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
  IF p_live IS NOT NULL THEN
    INSERT INTO public.client_sync_publications
      (component,scope_type,scope_id,published_revision,media_type,artifact_url,sha256,byte_size)
    VALUES ('live_public',p_scope_type,p_scope_id,(p_live->>'revision')::bigint,
      p_live->>'mediaType',p_live->>'url',p_live->>'sha256',(p_live->>'bytes')::bigint)
    ON CONFLICT DO NOTHING;
  END IF;
  INSERT INTO public.client_sync_public_heads
    (scope_type,scope_id,release_revision,manifest_sha256,live_revision,live_sha256,head_etag,head_json)
  VALUES (p_scope_type,p_scope_id,v_next_catalog,p_head_json#>>'{catalog,sha256}',
    v_next_live,p_head_json#>>'{live,sha256}',p_head_etag,p_head_json)
  ON CONFLICT (scope_type,scope_id) DO UPDATE SET
    release_revision=EXCLUDED.release_revision,manifest_sha256=EXCLUDED.manifest_sha256,
    live_revision=EXCLUDED.live_revision,live_sha256=EXCLUDED.live_sha256,
    head_etag=EXCLUDED.head_etag,head_json=EXCLUDED.head_json,updated_at=now();
  DELETE FROM public.client_projection_dirty_keys
    WHERE claim_token=ANY(COALESCE(p_catalog_claim_tokens,'{}')) AND component<>'live_public';
  DELETE FROM public.client_projection_dirty_keys
    WHERE claim_token=ANY(COALESCE(p_live_claim_tokens,'{}')) AND component='live_public';
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.complete_client_sync_publication_classes_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,jsonb,text,uuid[],uuid[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_client_sync_publication_classes_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,jsonb,text,uuid[],uuid[]) TO service_role;

-- Additive transition bootstrap. Released clients keep v217/v218 unchanged;
-- only the transition client asks for v219 and selects one mode for its context.
CREATE OR REPLACE FUNCTION public.get_app_config_v219(data_in jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_result jsonb; v_occasion bigint; v_enabled boolean := false;
BEGIN
  v_result := public.get_app_config_v218(data_in);
  v_occasion := (v_result#>>'{occasion,id}')::bigint;
  IF v_occasion IS NOT NULL THEN
    SELECT COALESCE((o.data->>'client_sync_v1')::boolean,false)
      AND NOT EXISTS (
        SELECT 1 FROM public.client_sync_component_sources s
        WHERE s.registry_version=(SELECT max(v.registry_version)
          FROM public.client_sync_component_sources v)
          AND NOT s.cutover_ready)
      INTO v_enabled
    FROM public.occasions o WHERE o.id=v_occasion;
  END IF;
  RETURN v_result || jsonb_build_object('client_sync_v1',v_enabled);
END; $$;
REVOKE ALL ON FUNCTION public.get_app_config_v219(jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_config_v219(jsonb) TO anon,authenticated;

-- Cleaning mutations keep their established validation/business rules in
-- ungranted handlers. The v1 commands add receipts, lock ordering and exact
-- revision/audit effects; released legacy names remain thin facades.
ALTER FUNCTION public.resolve_cleaning_place(bigint)
  RENAME TO resolve_cleaning_place_internal_v1;
ALTER FUNCTION public.set_cleaning_notifications_muted(bigint,boolean)
  RENAME TO set_cleaning_notifications_muted_internal_v1;
ALTER FUNCTION public.set_cleaning_reporter_blocked(bigint,uuid,boolean)
  RENAME TO set_cleaning_reporter_blocked_internal_v1;
REVOKE ALL ON FUNCTION public.resolve_cleaning_place_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.set_cleaning_notifications_muted_internal_v1(bigint,boolean)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.set_cleaning_reporter_blocked_internal_v1(bigint,uuid,boolean)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.resolve_cleaning_place(place_id bigint)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.resolve_cleaning_place_internal_v1(place_id);
$$;
CREATE OR REPLACE FUNCTION public.set_cleaning_notifications_muted(
  p_occasion bigint,p_muted boolean
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.set_cleaning_notifications_muted_internal_v1(p_occasion,p_muted);
$$;
CREATE OR REPLACE FUNCTION public.set_cleaning_reporter_blocked(
  p_occasion bigint,p_user uuid,p_blocked boolean
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.set_cleaning_reporter_blocked_internal_v1(
    p_occasion,p_user,p_blocked);
$$;

CREATE OR REPLACE FUNCTION public.report_cleaning_issue_client_sync_v1(
  p_place bigint,p_problem_type text,p_note text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_existing bigint; v_has_note boolean;
BEGIN
  SELECT p.occasion INTO v_occasion FROM public.places p WHERE p.id=p_place;
  IF v_actor IS NULL OR v_occasion IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='signed-in occasion participant required';
  END IF;
  v_has_note:=NULLIF(btrim(COALESCE(p_note,'')),'') IS NOT NULL;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'place',p_place,'problemType',p_problem_type,'note',p_note)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'cleaning.report',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.places p WHERE p.id=p_place FOR UPDATE;
  SELECT cr.id INTO v_existing FROM public.cleaning_reports cr
    WHERE cr.place=p_place AND cr.problem_type=p_problem_type
      AND cr.resolved_at IS NULL ORDER BY cr.created_at LIMIT 1 FOR UPDATE;
  v_result:=public.report_cleaning_issue(p_place,p_problem_type,p_note);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')||
      jsonb_build_object('message',v_result->>'message')); END IF;
  IF v_existing IS NOT NULL AND NOT v_has_note THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      v_result->'data'); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'cleaning.report','cleaning',jsonb_build_array(jsonb_build_object(
      'entityType','cleaning_report','entityId',v_result#>>'{data,id}',
      'operation',CASE WHEN v_existing IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel','Cleaning report','changedFields',CASE WHEN v_existing IS NULL
        THEN jsonb_build_array('place','problemType') ELSE jsonb_build_array('note') END)),
    CASE WHEN v_existing IS NULL THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    '[]',CASE WHEN v_existing IS NULL THEN jsonb_build_array(jsonb_build_object(
      'component','live_public','entityId',p_place)) ELSE '[]'::jsonb END,
    v_result->'data');
END; $$;
REVOKE ALL ON FUNCTION public.report_cleaning_issue_client_sync_v1(bigint,text,text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.report_cleaning_issue_client_sync_v1(bigint,text,text,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_cleaning_place_client_sync_v1(
  p_place bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_open integer;
BEGIN
  SELECT p.occasion INTO v_occasion FROM public.places p WHERE p.id=p_place;
  IF v_actor IS NULL OR v_occasion IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='cleaning crew required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'place',p_place)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'cleaning.resolve',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.places p WHERE p.id=p_place FOR UPDATE;
  PERFORM 1 FROM public.cleaning_reports cr
    WHERE cr.place=p_place AND cr.resolved_at IS NULL
    ORDER BY cr.id FOR UPDATE;
  SELECT count(*) INTO v_open FROM public.cleaning_reports cr
    WHERE cr.place=p_place AND cr.resolved_at IS NULL;
  v_result:=public.resolve_cleaning_place_internal_v1(p_place);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')||
      jsonb_build_object('message',v_result->>'message')); END IF;
  IF v_open=0 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,v_result->'data'); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'cleaning.resolve','cleaning',jsonb_build_array(jsonb_build_object(
      'entityType','cleaning_place','entityId',p_place,'operation','resolve',
      'safeLabel','Cleaning place','changedFields',jsonb_build_array('resolvedAt'))),
    ARRAY['live_public'],'[]',jsonb_build_array(jsonb_build_object(
      'component','live_public','entityId',p_place)),v_result->'data');
END; $$;
REVOKE ALL ON FUNCTION public.resolve_cleaning_place_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.resolve_cleaning_place_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_cleaning_notifications_muted_client_sync_v1(
  p_occasion bigint,p_muted boolean,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_current boolean; v_impacts jsonb; v_replacements jsonb;
BEGIN
  IF v_actor IS NULL THEN RAISE insufficient_privilege USING MESSAGE='sign in required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'muted',COALESCE(p_muted,false))::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'cleaning.notifications.set',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE((ou.data->>'cleaning_notifications_off')::boolean,false)
    INTO v_current FROM public.occasion_users ou WHERE ou.occasion=p_occasion
      AND ou."user"=v_actor FOR UPDATE;
  v_result:=public.set_cleaning_notifications_muted_internal_v1(p_occasion,p_muted);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')||
      jsonb_build_object('message',v_result->>'message')); END IF;
  IF v_current IS NOT DISTINCT FROM COALESCE(p_muted,false) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      v_result->'data'); END IF;
  v_impacts:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor));
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'cleaning.notifications.set','profile',jsonb_build_array(jsonb_build_object(
      'entityType','cleaning_preference','entityId',v_actor,'operation','update',
      'safeLabel','Cleaning notifications','changedFields',jsonb_build_array('muted'))),
    '{}',v_impacts,'[]',v_result->'data','{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.set_cleaning_notifications_muted_client_sync_v1(bigint,boolean,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_cleaning_notifications_muted_client_sync_v1(bigint,boolean,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_cleaning_reporter_blocked_client_sync_v1(
  p_occasion bigint,p_user uuid,p_blocked boolean,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_current boolean; v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL THEN RAISE insufficient_privilege USING MESSAGE='sign in required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'userId',p_user,'blocked',p_blocked)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'cleaning.reporter.set',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT ou.is_cleaning_blocked INTO v_current FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=p_user FOR UPDATE;
  v_result:=public.set_cleaning_reporter_blocked_internal_v1(
    p_occasion,p_user,p_blocked);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')||
      jsonb_build_object('message',v_result->>'message')); END IF;
  IF v_current IS NOT DISTINCT FROM p_blocked THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      v_result->'data'); END IF;
  v_impacts:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',p_user));
  IF p_user=v_actor THEN v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'cleaning.reporter.set','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation','update',
      'safeLabel','Cleaning reporter','changedFields',jsonb_build_array('blocked'))),
    '{}',v_impacts,'[]',v_result->'data','{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.set_cleaning_reporter_blocked_client_sync_v1(bigint,uuid,boolean,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_cleaning_reporter_blocked_client_sync_v1(bigint,uuid,boolean,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_resources_for_inventory_pool_v1(
  p_inventory_pool_id bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_occasion bigint; v_result jsonb;
BEGIN
  SELECT ip.occasion INTO v_occasion FROM public.inventory_pools ip
    WHERE ip.id=p_inventory_pool_id;
  IF v_occasion IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='inventory pool not found'; END IF;
  PERFORM public.check_is_editor_order_view_on_occasion(v_occasion);
  SELECT COALESCE(jsonb_agg(to_jsonb(r)||jsonb_build_object(
    'aggregate_version',COALESCE(v.version,0)) ORDER BY r.id),'[]'::jsonb)
    INTO v_result FROM public.resources r
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='resource'
      AND v.scope_type='occasion' AND v.scope_id=v_occasion
      AND v.aggregate_id=r.id::text
    WHERE r.inventory_pool=p_inventory_pool_id;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.get_resources_for_inventory_pool_v1(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_resources_for_inventory_pool_v1(bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_resource_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_resource jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_id bigint:=(p_resource->>'id')::bigint;
  v_pool bigint:=(p_resource->>'inventory_pool')::bigint; v_version bigint;
  v_begin jsonb; v_hash text; v_current jsonb; v_entity jsonb;
  v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_order_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  IF p_resource IS NULL OR jsonb_typeof(p_resource)<>'object'
    OR octet_length(p_resource::text)>131072
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_resource) key WHERE key NOT IN
      ('id','title','capacity','booking_rules','inventory_pool'))
    OR v_pool IS NULL OR length(btrim(COALESCE(p_resource->>'title',''))) NOT BETWEEN 1 AND 500
    OR (p_resource->>'capacity')::integer NOT BETWEEN 0 AND 1000000
    OR jsonb_typeof(COALESCE(p_resource->'booking_rules','{}'))<>'object' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid resource aggregate'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'resource',p_resource)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.resource.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.inventory_pools ip WHERE ip.id=v_pool
    AND ip.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='inventory pool is outside occasion'; END IF;
  IF v_id IS NOT NULL THEN
    SELECT to_jsonb(r) INTO v_current FROM public.resources r WHERE r.id=v_id
      AND r.occasion=p_occasion FOR UPDATE;
    IF v_current IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',404,jsonb_build_object('version',0,'resource',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('resource','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='resource' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'resource',v_current||
          jsonb_build_object('aggregate_version',v_version))); END IF;
    IF jsonb_build_object('title',v_current->>'title','capacity',(v_current->>'capacity')::integer,
      'booking_rules',COALESCE(v_current->'booking_rules','{}'),
      'inventory_pool',(v_current->>'inventory_pool')::bigint)=jsonb_build_object(
      'title',p_resource->>'title','capacity',(p_resource->>'capacity')::integer,
      'booking_rules',COALESCE(p_resource->'booking_rules','{}'),
      'inventory_pool',v_pool) THEN RETURN public.complete_client_mutation_outcome_v1(
        p_command_id,'unchanged',200,jsonb_build_object('version',v_version,
          'resource',v_current||jsonb_build_object('aggregate_version',v_version))); END IF;
    UPDATE public.resources SET title=p_resource->>'title',
      capacity=(p_resource->>'capacity')::integer,
      booking_rules=COALESCE(p_resource->'booking_rules','{}'),inventory_pool=v_pool,
      updated_at=clock_timestamp() WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='resource'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    IF p_expected_version IS NOT NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='new resource must not have expected version'; END IF;
    INSERT INTO public.resources(occasion,inventory_pool,title,capacity,booking_rules)
    VALUES (p_occasion,v_pool,p_resource->>'title',(p_resource->>'capacity')::integer,
      COALESCE(p_resource->'booking_rules','{}')) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('resource','occasion',p_occasion,v_id::text,v_version);
  END IF;
  PERFORM public.adjust_spot_capacity_for_pool(v_pool);
  SELECT to_jsonb(r)||jsonb_build_object('aggregate_version',v_version)
    INTO v_entity FROM public.resources r WHERE r.id=v_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=v_actor) THEN v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_inventory','userId',v_actor,
      'payload',public.get_user_inventory_for_occasion_v1(p_occasion))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'inventory.resource.save','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','resource','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_resource->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_impacts,'[]',jsonb_build_object('version',v_version,'resource',v_entity),
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_resource_client_sync_v1(
  p_occasion bigint,p_resource bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_pool bigint; v_version bigint; v_title text;
  v_begin jsonb; v_hash text; v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_order_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'resourceId',p_resource,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.resource.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT r.inventory_pool,r.title INTO v_pool,v_title FROM public.resources r
    WHERE r.id=p_resource AND r.occasion=p_occasion FOR UPDATE;
  IF v_pool IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'resource',NULL)); END IF;
  PERFORM 1 FROM public.inventory_pools ip WHERE ip.id=v_pool FOR UPDATE;
  PERFORM 1 FROM eshop.spots s WHERE s.resource=p_resource ORDER BY s.id FOR UPDATE;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('resource','occasion',p_occasion,p_resource::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='resource' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=p_resource::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'resourceId',p_resource)); END IF;
  IF EXISTS (SELECT 1 FROM eshop.spots s WHERE s.resource=p_resource
    AND s.order_product_ticket IS NOT NULL) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,
      jsonb_build_object('version',v_version,'resourceId',p_resource,
        'message','resource has reserved spots')); END IF;
  DELETE FROM eshop.spots WHERE resource=p_resource;
  DELETE FROM public.resources WHERE id=p_resource;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='resource'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_resource::text;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=v_actor) THEN v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_inventory','userId',v_actor,
      'payload',public.get_user_inventory_for_occasion_v1(p_occasion))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'inventory.resource.delete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','resource','entityId',p_resource,'operation','delete',
      'safeLabel',left(v_title,240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_impacts,'[]',jsonb_build_object('version',v_version,'resource',NULL),
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.delete_resource_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_resource_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_inventory_pool_client_sync_v1(
  p_occasion bigint,p_pool bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_title text; v_begin jsonb;
  v_hash text; v_reserved bigint; v_impacts jsonb;
  v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_order_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'poolId',p_pool,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.pool.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT ip.title INTO v_title FROM public.inventory_pools ip WHERE ip.id=p_pool
    AND ip.occasion=p_occasion FOR UPDATE;
  IF v_title IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'pool',NULL)); END IF;
  PERFORM 1 FROM public.inventory_contexts ic WHERE ic.inventory_pool=p_pool
    ORDER BY ic.id FOR UPDATE;
  PERFORM 1 FROM public.resources r WHERE r.inventory_pool=p_pool
    ORDER BY r.id FOR UPDATE;
  PERFORM 1 FROM eshop.spots s WHERE s.inventory_context IN (
    SELECT ic.id FROM public.inventory_contexts ic WHERE ic.inventory_pool=p_pool)
    OR s.resource IN (SELECT r.id FROM public.resources r WHERE r.inventory_pool=p_pool)
    ORDER BY s.id FOR UPDATE;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('inventory_pool','occasion',p_occasion,p_pool::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='inventory_pool' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=p_pool::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'poolId',p_pool)); END IF;
  SELECT count(*) INTO v_reserved FROM eshop.spots s
    WHERE s.order_product_ticket IS NOT NULL AND (s.inventory_context IN (
      SELECT ic.id FROM public.inventory_contexts ic WHERE ic.inventory_pool=p_pool)
      OR s.resource IN (SELECT r.id FROM public.resources r WHERE r.inventory_pool=p_pool));
  IF v_reserved>0 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',409,jsonb_build_object('version',v_version,
      'poolId',p_pool,'message','inventory pool has reserved spots')); END IF;
  DELETE FROM eshop.spots s WHERE s.order_product_ticket IS NULL AND (
    s.inventory_context IN (SELECT ic.id FROM public.inventory_contexts ic
      WHERE ic.inventory_pool=p_pool) OR s.resource IN (
      SELECT r.id FROM public.resources r WHERE r.inventory_pool=p_pool));
  DELETE FROM public.client_aggregate_versions v WHERE v.scope_type='occasion'
    AND v.scope_id=p_occasion AND ((v.aggregate_type='resource' AND v.aggregate_id IN (
      SELECT r.id::text FROM public.resources r WHERE r.inventory_pool=p_pool))
      OR (v.aggregate_type='inventory_pool' AND v.aggregate_id=p_pool::text));
  DELETE FROM public.resources WHERE inventory_pool=p_pool;
  DELETE FROM public.inventory_pools WHERE id=p_pool;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=v_actor) THEN v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_inventory','userId',v_actor,
      'payload',public.get_user_inventory_for_occasion_v1(p_occasion))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'inventory.pool.delete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','inventory_pool','entityId',p_pool,'operation','delete',
      'safeLabel',left(v_title,240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_impacts,'[]',jsonb_build_object('version',v_version,'pool',NULL),
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.delete_inventory_pool_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_inventory_pool_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

ALTER FUNCTION public.update_spot_assignments(jsonb)
  RENAME TO update_spot_assignments_internal_v1;
REVOKE ALL ON FUNCTION public.update_spot_assignments_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_spot_assignments_client_sync_v1(
  p_changes jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[]; v_spot_ids bigint[]; v_resource_ids bigint[];
BEGIN
  IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'array'
    OR jsonb_array_length(p_changes)=0 OR jsonb_array_length(p_changes)>1000
    OR octet_length(p_changes::text)>1048576 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid spot assignment batch'; END IF;
  SELECT ARRAY(SELECT DISTINCT value::bigint FROM jsonb_array_elements(p_changes) c
    CROSS JOIN LATERAL jsonb_each_text(c) e
    WHERE e.key IN ('old_spot_id','new_spot_id') AND nullif(e.value,'') IS NOT NULL),
    ARRAY(SELECT DISTINCT (c->>'resource_id')::bigint
      FROM jsonb_array_elements(p_changes) c)
    INTO v_spot_ids,v_resource_ids;
  SELECT min(r.occasion) INTO v_occasion FROM public.resources r
    WHERE r.id=ANY(v_resource_ids);
  IF v_actor IS NULL OR v_occasion IS NULL
    OR (SELECT count(DISTINCT r.occasion) FROM public.resources r
      WHERE r.id=ANY(v_resource_ids))<>1
    OR (SELECT count(*) FROM public.resources r WHERE r.id=ANY(v_resource_ids))
      <>cardinality(v_resource_ids)
    OR (SELECT count(*) FROM eshop.spots s WHERE s.id=ANY(v_spot_ids))
      <>cardinality(v_spot_ids)
    OR EXISTS (SELECT 1 FROM eshop.spots s WHERE s.id=ANY(v_spot_ids)
      AND s.occasion<>v_occasion)
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='inventory editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'changes',p_changes)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.spots.assign',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM eshop.spots s JOIN eshop.order_product_ticket opt
    ON opt.id=s.order_product_ticket JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE s.id=ANY(v_spot_ids);
  PERFORM public.update_spot_assignments_internal_v1(p_changes);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.spots.assign',jsonb_build_array(jsonb_build_object(
      'entityType','spot_assignment','entityId',NULL,'operation','update',
      'safeLabel','Spot assignments','changedFields',jsonb_build_array(
        'resource','resource_slot'))),v_users,jsonb_build_object(
          'changedCount',jsonb_array_length(p_changes)));
END; $$;
REVOKE ALL ON FUNCTION public.update_spot_assignments_client_sync_v1(jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_spot_assignments_client_sync_v1(jsonb,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_spot_assignments(p_changes jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.update_spot_assignments_client_sync_v1(
    p_changes,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.update_spot_assignments(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_spot_assignments(jsonb) TO authenticated;

ALTER FUNCTION public.update_product_inventory_contexts(bigint,jsonb)
  RENAME TO update_product_inventory_contexts_internal_v1;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts_internal_v1(bigint,jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts_client_sync_v1(
  p_product_id bigint,p_contexts jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[];
BEGIN
  SELECT p.occasion INTO v_occasion FROM eshop.products p WHERE p.id=p_product_id;
  IF v_actor IS NULL OR v_occasion IS NULL OR p_contexts IS NULL
    OR jsonb_typeof(p_contexts)<>'array' OR jsonb_array_length(p_contexts)>1000
    OR octet_length(p_contexts::text)>1048576
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_contexts) c
      LEFT JOIN public.inventory_contexts ic
        ON ic.id=(c->>'inventory_context_id')::bigint
      LEFT JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
      WHERE ip.occasion IS DISTINCT FROM v_occasion
        OR COALESCE((c->>'quantity')::integer,0)<0)
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='inventory editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'productId',p_product_id,'contexts',p_contexts)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.product.contexts',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt.product=p_product_id;
  PERFORM public.update_product_inventory_contexts_internal_v1(
    p_product_id,p_contexts);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.product.contexts',jsonb_build_array(jsonb_build_object(
      'entityType','product_inventory_context','entityId',p_product_id,
      'operation','update','safeLabel','Product inventory contexts',
      'changedFields',jsonb_build_array('contexts'))),v_users,
    jsonb_build_object('productId',p_product_id));
END; $$;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts_client_sync_v1(
  bigint,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_inventory_contexts_client_sync_v1(
  bigint,jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts(
  p_product_id bigint,p_contexts jsonb
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.update_product_inventory_contexts_client_sync_v1(
    p_product_id,p_contexts,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts(bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_inventory_contexts(bigint,jsonb)
  TO authenticated;

ALTER FUNCTION public.update_product(jsonb)
  RENAME TO update_product_internal_v1;
REVOKE ALL ON FUNCTION public.update_product_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_product_client_sync_v1(
  p_product jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_product bigint; v_occasion bigint;
  v_begin jsonb; v_hash text; v_users uuid[];
BEGIN
  IF p_product IS NULL OR jsonb_typeof(p_product)<>'object'
    OR octet_length(p_product::text)>524288 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid product aggregate'; END IF;
  v_product:=NULLIF(p_product->>'id','')::bigint;
  IF v_product IS NOT NULL THEN
    SELECT p.occasion INTO v_occasion FROM eshop.products p WHERE p.id=v_product;
  ELSE
    SELECT pt.occasion INTO v_occasion FROM eshop.product_types pt
      WHERE pt.id=NULLIF(p_product->>'product_type','')::bigint;
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'product',p_product)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.product.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_product IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
    FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
      ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
    WHERE opt.product=v_product;
  ELSE v_users:='{}'::uuid[]; END IF;
  v_product:=public.update_product_internal_v1(p_product);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.product.save',jsonb_build_array(jsonb_build_object(
      'entityType','product','entityId',v_product,'operation',
      CASE WHEN p_product->>'id' IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_product->>'title',240),'changedFields',jsonb_build_array(
        'configuration'))),v_users,jsonb_build_object('productId',v_product));
END; $$;
REVOKE ALL ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_product(p_input jsonb)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN (public.update_product_client_sync_v1(
    p_input,extensions.gen_random_uuid())->'data'->>'productId')::bigint;
END; $$;
REVOKE ALL ON FUNCTION public.update_product(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product(jsonb) TO authenticated;

ALTER FUNCTION public.update_form(jsonb)
  RENAME TO update_form_internal_v1;
REVOKE ALL ON FUNCTION public.update_form_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_form_client_sync_v1(
  p_form jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_form bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_result jsonb;
BEGIN
  IF p_form IS NULL OR jsonb_typeof(p_form)<>'object'
    OR octet_length(p_form::text)>4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid form aggregate'; END IF;
  v_occasion:=NULLIF(p_form->>'occasion','')::bigint;
  v_form:=NULLIF(p_form->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL OR v_form IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion)
    OR NOT EXISTS (SELECT 1 FROM public.forms f
      WHERE f.id=v_form AND f.occasion=v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'form',p_form)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.products p ON p.id=opt.product
  WHERE ou.occasion=v_occasion AND p.occasion=v_occasion;
  v_result:=public.update_form_internal_v1(p_form);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.save',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','update',
      'safeLabel',left(p_form->>'title',240),'changedFields',jsonb_build_array(
        'configuration','products'))),v_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_form(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN public.update_form_client_sync_v1(
    input_data,extensions.gen_random_uuid())->'data';
END; $$;
REVOKE ALL ON FUNCTION public.update_form(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form(jsonb) TO authenticated;

ALTER FUNCTION public.update_blueprint(jsonb)
  RENAME TO update_blueprint_internal_v1;
REVOKE ALL ON FUNCTION public.update_blueprint_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_blueprint_client_sync_v1(
  p_blueprint jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_blueprint bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_result jsonb;
BEGIN
  IF p_blueprint IS NULL OR jsonb_typeof(p_blueprint)<>'object'
    OR octet_length(p_blueprint::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid blueprint aggregate'; END IF;
  v_occasion:=NULLIF(p_blueprint->>'occasion','')::bigint;
  v_blueprint:=NULLIF(p_blueprint->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion)
    OR (v_blueprint IS NOT NULL AND NOT EXISTS (SELECT 1 FROM eshop.blueprints b
      WHERE b.id=v_blueprint AND b.occasion=v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'blueprint',p_blueprint)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.blueprint.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.spots s
    ON s.order_product_ticket=opt.id
  WHERE ou.occasion=v_occasion AND s.occasion=v_occasion;
  v_result:=public.update_blueprint_internal_v1(p_blueprint);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.blueprint.save',jsonb_build_array(jsonb_build_object(
      'entityType','blueprint','entityId',v_result->>'blueprint_id',
      'operation',CASE WHEN v_blueprint IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_blueprint->>'title',240),'changedFields',jsonb_build_array(
        'spots','configuration'))),v_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_blueprint(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN public.update_blueprint_client_sync_v1(
    input_data,extensions.gen_random_uuid())->'data';
END; $$;
REVOKE ALL ON FUNCTION public.update_blueprint(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_blueprint(jsonb) TO authenticated;

ALTER FUNCTION public.update_ticket_products_wsv2(bigint,jsonb)
  RENAME TO update_ticket_products_internal_v1;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_ticket_products_client_sync_v1(
  p_ticket bigint,p_products jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[]; v_result jsonb;
BEGIN
  SELECT t.occasion INTO v_occasion FROM eshop.tickets t WHERE t.id=p_ticket;
  IF v_actor IS NULL OR v_occasion IS NULL OR p_products IS NULL
    OR jsonb_typeof(p_products)<>'array' OR jsonb_array_length(p_products)>1000
    OR octet_length(p_products::text)>1048576
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'ticket',p_ticket,'products',p_products)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.ticket.products',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_users
    FROM public.occasion_users ou
    WHERE ou.occasion=v_occasion AND ou.ticket=p_ticket;
  v_result:=public.update_ticket_products_internal_v1(p_ticket,p_products);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.ticket.products',jsonb_build_array(jsonb_build_object(
      'entityType','ticket_products','entityId',p_ticket,'operation','update',
      'safeLabel','Ticket products','changedFields',jsonb_build_array(
        'products','allocations'))),v_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.update_ticket_products_client_sync_v1(
  bigint,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_ticket_products_client_sync_v1(
  bigint,jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id bigint,p_products jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN public.update_ticket_products_client_sync_v1(
    p_ticket_id,p_products,extensions.gen_random_uuid())->'data';
END; $$;
REVOKE ALL ON FUNCTION public.update_ticket_products_wsv2(bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_ticket_products_wsv2(bigint,jsonb)
  TO authenticated;

ALTER FUNCTION public.swap_spot_tickets(bigint,bigint)
  RENAME TO swap_spot_tickets_internal_v1;
REVOKE ALL ON FUNCTION public.swap_spot_tickets_internal_v1(bigint,bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.swap_spot_tickets_client_sync_v1(
  p_spot_1 bigint,p_spot_2 bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[];
BEGIN
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id IN (p_spot_1,p_spot_2);
  IF v_actor IS NULL OR p_spot_1 IS NULL OR p_spot_2 IS NULL
    OR p_spot_1=p_spot_2 OR v_occasion IS NULL
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id IN (p_spot_1,p_spot_2) AND s.occasion=v_occasion)<>2
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spot1',p_spot_1,'spot2',p_spot_2)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.spots.swap',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM eshop.spots s JOIN eshop.order_product_ticket opt
    ON opt.id=s.order_product_ticket JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE s.id IN (p_spot_1,p_spot_2);
  PERFORM public.swap_spot_tickets_internal_v1(p_spot_1,p_spot_2);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.spots.swap',jsonb_build_array(jsonb_build_object(
      'entityType','spot_assignment','entityId',NULL,'operation','update',
      'safeLabel','Spot ticket swap','changedFields',jsonb_build_array(
        'order_product_ticket','product'))),v_users,jsonb_build_object(
          'spotIds',jsonb_build_array(p_spot_1,p_spot_2)));
END; $$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets_client_sync_v1(
  bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets_client_sync_v1(
  bigint,bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.swap_spot_tickets(
  spot_id_1 bigint,spot_id_2 bigint
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.swap_spot_tickets_client_sync_v1(
    spot_id_1,spot_id_2,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets(bigint,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets(bigint,bigint)
  TO authenticated;

ALTER FUNCTION public.delete_order_221(bigint)
  RENAME TO delete_order_internal_v1;
REVOKE ALL ON FUNCTION public.delete_order_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_removed_users uuid[]; v_remaining_users uuid[];
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  SELECT o.occasion,oc.unit INTO v_occasion,v_unit FROM eshop.orders o
    JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_removed_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt."order"=p_order;
  PERFORM public.delete_order_internal_v1(p_order);
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=v_occasion
    AND s.user_id=ANY(v_removed_users);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed_users) id));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_remaining_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  IF cardinality(v_removed_users)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=v_occasion;
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,v_occasion,
    'inventory.order.delete',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order,'operation','delete',
      'safeLabel','Order','changedFields',jsonb_build_array(
        'tickets','membership','allocations'))),v_remaining_users,v_public,v_dirty,
    jsonb_build_object('orderId',p_order,'removedUsers',cardinality(v_removed_users)));
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_221(order_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.delete_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_221(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_221(bigint) TO authenticated;

ALTER FUNCTION public.create_ticket_order(jsonb)
  RENAME TO create_ticket_order_internal_v1;
REVOKE ALL ON FUNCTION public.create_ticket_order_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_ticket_order_confirmation_v1(
  p_command_id uuid,p_occasion bigint,p_order_payload jsonb,p_language text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_organization bigint; v_unit bigint;
BEGIN
  SELECT o.organization,o.unit INTO v_organization,v_unit
    FROM public.occasions o WHERE o.id=p_occasion;
  IF v_organization IS NULL OR p_command_id IS NULL OR p_order_payload IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order effect'; END IF;
  INSERT INTO public.queue_emails
    (target_time,code,data,organization,occasion,unit)
  VALUES (now(),'TICKET_ORDER_CONFIRMATION',jsonb_build_object(
    'command_id',p_command_id,'ticket_order',p_order_payload,
    'lang',COALESCE(NULLIF(p_language,''),'cs')),v_organization,p_occasion,v_unit)
  ON CONFLICT ((data->>'command_id'))
    WHERE code='TICKET_ORDER_CONFIRMATION' AND data ? 'command_id'
    DO NOTHING;
END; $$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_order_confirmation_v1(
  uuid,bigint,jsonb,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.claim_due_queue_emails_v1(p_limit integer DEFAULT 25)
RETURNS SETOF public.queue_emails LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = '' AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF p_limit IS NULL OR p_limit<1 OR p_limit>100 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid queue claim limit'; END IF;
  RETURN QUERY WITH candidates AS (
    SELECT q.id FROM public.queue_emails q
    WHERE q.target_time<=now()
      AND (q.processing_at IS NULL OR q.processing_at<now()-interval '10 minutes')
    ORDER BY q.target_time,q.id FOR UPDATE SKIP LOCKED LIMIT p_limit
  ) UPDATE public.queue_emails q SET processing_at=clock_timestamp(),
      attempt_count=q.attempt_count+1,last_error=NULL
    FROM candidates c WHERE q.id=c.id RETURNING q.*;
END; $$;
REVOKE ALL ON FUNCTION public.claim_due_queue_emails_v1(integer)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_due_queue_emails_v1(integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.release_queue_email_v1(
  p_task_id bigint,p_error text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  UPDATE public.queue_emails SET processing_at=NULL,
    last_error=left(COALESCE(p_error,'delivery failed'),1000)
    WHERE id=p_task_id;
END; $$;
REVOKE ALL ON FUNCTION public.release_queue_email_v1(bigint,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.release_queue_email_v1(bigint,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(
  p_order jsonb,p_command_id uuid,p_client_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_before_users uuid[]; v_actor_kind text;
BEGIN
  IF p_order IS NULL OR jsonb_typeof(p_order)<>'object'
    OR octet_length(p_order::text)>4194304 OR p_command_id IS NULL
    OR (v_actor IS NULL AND p_client_id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order command'; END IF;
  SELECT f.occasion INTO v_occasion FROM public.forms f
    WHERE f.key=NULLIF(p_order->>'form','')::uuid;
  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket order form not found'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'order',p_order)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,p_client_id,v_hash);
    v_actor_kind:='unknown';
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,v_actor,v_hash);
    v_actor_kind:='user';
  END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.create_ticket_order_internal_v1(p_order);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(
  jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(
  jsonb,uuid,uuid) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_ticket_order(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN public.create_ticket_order_client_sync_v1(input_data,
    extensions.gen_random_uuid(),COALESCE(auth.uid(),extensions.gen_random_uuid()))->'data';
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order(jsonb) TO anon,authenticated;

ALTER FUNCTION public.confirm_blueprint_order_change(bigint[],jsonb)
  RENAME TO confirm_blueprint_order_change_internal_v1;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_internal_v1(
  bigint[],jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_before_users uuid[];
BEGIN
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id=ANY(p_spot_ids);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_spot_ids)=0
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id=ANY(p_spot_ids) AND s.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spots',p_spot_ids,'input',p_input_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.prepare_replace',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.confirm_blueprint_order_change_internal_v1(
    p_spot_ids,p_input_data);
  IF COALESCE((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',400,v_result); END IF;
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.prepare_replace',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',NULL,
      'operation','update','safeLabel','Blueprint order replacement',
      'changedFields',jsonb_build_array('cancellations','allocations'))),
    v_before_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  bigint[],jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  bigint[],jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.replace_blueprint_order_client_sync_v1(
  p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_prepare jsonb; v_result jsonb; v_before_users uuid[];
BEGIN
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id=ANY(p_spot_ids);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_spot_ids)=0
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id=ANY(p_spot_ids) AND s.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spots',p_spot_ids,'input',p_input_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.replace',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  BEGIN
    v_prepare:=public.confirm_blueprint_order_change_internal_v1(
      p_spot_ids,p_input_data);
    IF COALESCE((v_prepare->>'success')::boolean,false) IS NOT TRUE THEN
      RAISE check_violation USING MESSAGE='replacement preparation rejected',
        DETAIL=v_prepare::text; END IF;
    v_result:=public.create_ticket_order_internal_v1(v_prepare->'orderDetails');
    IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
      RAISE check_violation USING MESSAGE='replacement order rejected',
        DETAIL=v_result::text; END IF;
  EXCEPTION WHEN check_violation THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',400,COALESCE(v_result,v_prepare,
        jsonb_build_object('message','order replacement rejected')));
  END;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,
    COALESCE(p_input_data->>'lang',v_prepare#>>'{orderDetails,lang}'));
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.replace',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Blueprint order replacement','changedFields',jsonb_build_array(
        'cancellations','tickets','products','allocations','membership'))),
    v_before_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.replace_blueprint_order_client_sync_v1(
  bigint[],jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_blueprint_order_client_sync_v1(
  bigint[],jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change(
  p_spot_ids bigint[],p_input_data jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN public.confirm_blueprint_order_change_client_sync_v1(
    p_spot_ids,p_input_data,extensions.gen_random_uuid())->'data';
END; $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change(bigint[],jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_blueprint_order_change(bigint[],jsonb)
  TO authenticated;

ALTER FUNCTION public.storno_tickets_bulk(bigint[])
  RENAME TO storno_tickets_bulk_internal_v1;
REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[])
  FROM PUBLIC,anon,authenticated;
ALTER FUNCTION public.update_order_and_tickets_to_storno_ws_221(bigint)
  RENAME TO update_order_and_tickets_to_storno_ws_internal_v1;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_ws_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_221(bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.internal_storno_tickets_221(bigint[])
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.storno_tickets_client_sync_v1(
  p_tickets bigint[],p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[];
BEGIN
  SELECT min(t.occasion) INTO v_occasion FROM eshop.tickets t
    WHERE t.id=ANY(p_tickets);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_tickets)=0
    OR (SELECT count(*) FROM eshop.tickets t
      WHERE t.id=ANY(p_tickets) AND t.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'tickets',p_tickets)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.tickets.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  PERFORM public.storno_tickets_bulk_internal_v1(p_tickets);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.tickets.cancel',
    jsonb_build_array(jsonb_build_object('entityType','ticket','entityId',NULL,
      'operation','update','safeLabel','Ticket cancellation',
      'changedFields',jsonb_build_array('state','membership','allocations'))),
    v_before_users,jsonb_build_object('ticketIds',to_jsonb(p_tickets)));
END; $$;
REVOKE ALL ON FUNCTION public.storno_tickets_client_sync_v1(bigint[],uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storno_tickets_client_sync_v1(bigint[],uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.storno_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[];
BEGIN
  SELECT o.occasion INTO v_occasion FROM eshop.orders o WHERE o.id=p_order;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  PERFORM public.update_order_and_tickets_to_storno_ws_internal_v1(p_order);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.cancel',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,
      'operation','update','safeLabel','Order cancellation',
      'changedFields',jsonb_build_array('state','tickets','membership','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order));
END; $$;
REVOKE ALL ON FUNCTION public.storno_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storno_order_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.storno_tickets_bulk(p_ticket_ids bigint[])
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.storno_tickets_client_sync_v1(
    p_ticket_ids,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.storno_tickets_bulk(bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storno_tickets_bulk(bigint[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_ws_221(
  order_id bigint
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.storno_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_ws_221(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_order_and_tickets_to_storno_ws_221(bigint)
  TO authenticated;

-- Form/product lifecycle implementations become ungranted domain handlers.
-- Released RPC names below are thin facades over receipt-backed commands.
ALTER FUNCTION public.create_form(bigint,text,text)
  RENAME TO create_form_internal_v1;
REVOKE ALL ON FUNCTION public.create_form_internal_v1(bigint,text,text)
  FROM PUBLIC,anon,authenticated;
ALTER FUNCTION public.create_form_ws(jsonb)
  RENAME TO create_form_ws_obsolete_v1;
REVOKE ALL ON FUNCTION public.create_form_ws_obsolete_v1(jsonb)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_form_client_sync_v1(
  p_occasion_link text,p_link text,p_title text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_form jsonb;
BEGIN
  SELECT o.id,o.unit INTO v_occasion,v_unit FROM public.occasions o
    WHERE o.link=p_occasion_link;
  IF v_actor IS NULL OR v_occasion IS NULL OR nullif(btrim(p_link),'') IS NULL
    OR length(p_link)>200 OR length(COALESCE(p_title,''))>500
    OR NOT (public.get_is_editor_on_unit(v_unit)
      OR public.get_is_editor_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'link',p_link,'title',p_title)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.create',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF EXISTS (SELECT 1 FROM public.forms f WHERE f.link=p_link) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',
      409,jsonb_build_object('message','Form link is already in use')); END IF;
  v_form:=public.create_form_internal_v1(v_occasion,p_link,p_title);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.create',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form->>'id','operation','insert',
      'safeLabel',left(p_title,240),'changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('form',v_form));
END; $$;
REVOKE ALL ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.create_form_ws(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb;
BEGIN
  IF input_data IS NULL OR jsonb_typeof(input_data)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(input_data) k
      WHERE k NOT IN ('occasion_link','link','title')) THEN
    RETURN jsonb_build_object('code',4000,'message','Invalid form input'); END IF;
  v_response:=public.create_form_client_sync_v1(input_data->>'occasion_link',
    input_data->>'link',input_data->>'title',extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',CASE WHEN v_response->>'status'='applied'
      THEN 201 ELSE (v_response->>'code')::integer END,
    'message',CASE WHEN v_response->>'status'='applied'
      THEN 'Form created successfully' ELSE v_response#>>'{data,message}' END,
    'data',v_response#>'{data,form}');
END; $$;
REVOKE ALL ON FUNCTION public.create_form_ws(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_form_ws(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_form(
  p_occasion_id bigint,p_link text,p_title text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.create_form_internal_v1(p_occasion_id,p_link,p_title);
$$;
REVOKE ALL ON FUNCTION public.create_form(bigint,text,text)
  FROM PUBLIC,anon,authenticated;

ALTER FUNCTION public.delete_form(bigint)
  RENAME TO delete_form_internal_v1;
REVOKE ALL ON FUNCTION public.delete_form_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;
ALTER FUNCTION public.delete_form_ws(bigint)
  RENAME TO delete_form_ws_obsolete_v1;
REVOKE ALL ON FUNCTION public.delete_form_ws_obsolete_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_form_client_sync_v1(
  p_form_id bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint; v_title text;
  v_key uuid; v_begin jsonb; v_hash text; v_responses integer;
BEGIN
  SELECT f.occasion,o.unit,f.title,f.key INTO v_occasion,v_unit,v_title,v_key
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    WHERE f.id=p_form_id FOR UPDATE OF f;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT (public.get_is_editor_on_unit(v_unit)
      OR public.get_is_editor_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'formId',p_form_id)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT count(*) INTO v_responses FROM eshop.orders ord
    WHERE ord.data->>'form'=v_key::text;
  IF v_responses>0 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',
      409,jsonb_build_object('message','Form has responses')); END IF;
  PERFORM public.delete_form_internal_v1(p_form_id);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.delete',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',p_form_id,'operation','delete',
      'safeLabel',left(v_title,240),'changedFields',jsonb_build_array(
        'configuration','fields'))),'{}'::uuid[],
    jsonb_build_object('formId',p_form_id));
END; $$;
REVOKE ALL ON FUNCTION public.delete_form_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_form_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_form_ws(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb;
BEGIN
  v_response:=public.delete_form_client_sync_v1(
    p_form_id,extensions.gen_random_uuid());
  RETURN jsonb_build_object('code',(v_response->>'code')::integer,
    'message',COALESCE(v_response#>>'{data,message}',
      'Form deleted successfully'));
END; $$;
REVOKE ALL ON FUNCTION public.delete_form_ws(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_form_ws(bigint) TO authenticated;

ALTER FUNCTION public.duplicate_form_to_occasion(bigint,text)
  RENAME TO duplicate_form_to_occasion_internal_v1;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_internal_v1(bigint,text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_client_sync_v1(
  p_source_form_id bigint,p_target_occasion_link text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_source_occasion bigint; v_source_unit bigint;
  v_target bigint; v_begin jsonb; v_hash text; v_form bigint;
BEGIN
  SELECT f.occasion,o.unit INTO v_source_occasion,v_source_unit
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    WHERE f.id=p_source_form_id;
  SELECT o.id INTO v_target FROM public.occasions o
    WHERE o.link=p_target_occasion_link;
  IF v_actor IS NULL OR v_source_occasion IS NULL OR v_target IS NULL
    OR NOT (public.get_is_editor_view_on_occasion(v_source_occasion)
      OR public.get_is_editor_view_on_unit(v_source_unit))
    OR NOT public.get_is_editor_on_occasion(v_target) THEN
    RAISE insufficient_privilege USING MESSAGE='form copy permission required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'sourceFormId',p_source_form_id,'targetOccasion',v_target)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.duplicate',v_target,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_form:=public.duplicate_form_to_occasion_internal_v1(
    p_source_form_id,p_target_occasion_link);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_target,
    'inventory.form.duplicate',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','insert',
      'safeLabel','Duplicated form','changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('formId',v_form));
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(
  bigint,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(
  bigint,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion(
  source_form_id bigint,target_occasion_link text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN (public.duplicate_form_to_occasion_client_sync_v1(source_form_id,
    target_occasion_link,extensions.gen_random_uuid())->'data'->>'formId')::bigint;
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion(bigint,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion(bigint,text)
  TO authenticated;

ALTER FUNCTION public.delete_product(bigint)
  RENAME TO delete_product_internal_v1;
REVOKE ALL ON FUNCTION public.delete_product_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_product_client_sync_v1(
  p_product_id bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_title text; v_orders integer;
BEGIN
  SELECT p.occasion,p.title INTO v_occasion,v_title FROM eshop.products p
    WHERE p.id=p_product_id FOR UPDATE;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'productId',p_product_id)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.product.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT count(*) INTO v_orders FROM eshop.order_product_ticket opt
    WHERE opt.product=p_product_id;
  IF v_orders>0 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',
      409,jsonb_build_object('message','Product is used by existing orders',
        'orderCount',v_orders)); END IF;
  PERFORM public.delete_product_internal_v1(p_product_id);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.product.delete',jsonb_build_array(jsonb_build_object(
      'entityType','product','entityId',p_product_id,'operation','delete',
      'safeLabel',left(v_title,240),'changedFields',jsonb_build_array(
        'product','inventoryContexts'))),'{}'::uuid[],
    jsonb_build_object('productId',p_product_id));
END; $$;
REVOKE ALL ON FUNCTION public.delete_product_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_product_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_product(p_product_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.delete_product_client_sync_v1(
    p_product_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_product(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_product(bigint) TO authenticated;

-- These routines are implementation details reached only from the canonical
-- aggregate commands above. PostgreSQL's default PUBLIC EXECUTE grant would
-- otherwise expose alternate mutation roots.
REVOKE ALL ON FUNCTION public.apply_allocations(bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.assign_spot_to_resource(bigint,bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.adjust_spot_capacity_for_pool(bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public._swap_spots_update_ticket(bigint,bigint,bigint)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public._swap_spots_generate_product_json(bigint,bigint)
  FROM PUBLIC,anon,authenticated;

ALTER FUNCTION public.apply_planned_changes()
  RENAME TO apply_planned_changes_obsolete_v1;
REVOKE ALL ON FUNCTION public.apply_planned_changes_obsolete_v1()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.apply_planned_changes_client_sync_v1()
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_change eshop.planned_changes%ROWTYPE; v_occasion bigint;
  v_impacts jsonb; v_changed integer;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  FOR v_change IN SELECT pc.* FROM eshop.planned_changes pc
    WHERE pc.change_time<=now() AND NOT pc.applied
    ORDER BY pc.change_time,pc.id FOR UPDATE SKIP LOCKED LOOP
    v_changed:=0; v_occasion:=NULL; v_impacts:='[]'::jsonb;
    IF v_change.change_type='products.price' THEN
      UPDATE eshop.products p SET price=v_change.new_value::numeric
      WHERE p.id=v_change.subject_id
        AND p.price IS DISTINCT FROM v_change.new_value::numeric
      RETURNING p.occasion INTO v_occasion;
      GET DIAGNOSTICS v_changed=ROW_COUNT;
    ELSIF v_change.change_type='products.is_hidden' THEN
      UPDATE eshop.products p SET is_hidden=v_change.new_value::boolean
      WHERE p.id=v_change.subject_id
        AND p.is_hidden IS DISTINCT FROM v_change.new_value::boolean
      RETURNING p.occasion INTO v_occasion;
      GET DIAGNOSTICS v_changed=ROW_COUNT;
    ELSIF v_change.change_type='forms.is_open' THEN
      UPDATE public.forms f SET is_open=v_change.new_value::boolean
      WHERE f.id=v_change.subject_id
        AND f.is_open IS DISTINCT FROM v_change.new_value::boolean;
    ELSE
      RAISE warning 'Unknown planned change type %',v_change.change_type;
    END IF;
    IF v_changed>0 AND v_occasion IS NOT NULL THEN
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'component','private_inventory','userId',ou."user")),'[]'::jsonb)
        INTO v_impacts
      FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
        ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
      WHERE opt.product=v_change.subject_id;
      PERFORM public.record_client_sync_commit_v1(v_occasion,
        'inventory.product.planned','inventory',jsonb_build_array(
          jsonb_build_object('entityType','product','entityId',v_change.subject_id,
            'operation','update','safeLabel','Scheduled product change',
            'changedFields',jsonb_build_array(split_part(
              v_change.change_type,'.',2)))),'{}',v_impacts,'[]','service',
        'planned_change:'||v_change.id::text);
    END IF;
    UPDATE eshop.planned_changes SET applied=true WHERE id=v_change.id;
  END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.apply_planned_changes_client_sync_v1()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.apply_planned_changes_client_sync_v1()
  TO service_role;
CREATE OR REPLACE FUNCTION public.apply_planned_changes()
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.apply_planned_changes_client_sync_v1();
$$;
REVOKE ALL ON FUNCTION public.apply_planned_changes()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.apply_planned_changes() TO service_role;

ALTER FUNCTION public.delete_service_item(bigint,text,text,boolean)
  RENAME TO delete_service_item_internal_v1;
REVOKE ALL ON FUNCTION public.delete_service_item_internal_v1(
  bigint,text,text,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_service_item_client_sync_v1(
  p_occasion bigint,p_type text,p_code text,p_force boolean,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_users uuid[];
BEGIN
  IF v_actor IS NULL OR p_force IS NULL OR p_type NOT IN ('food','accommodation')
    OR nullif(btrim(p_code),'') IS NULL OR length(p_code)>100
    OR NOT public.get_is_manager_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'type',p_type,'code',p_code,
    'force',p_force)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.service.delete',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND (
    (p_force AND ou.services->p_type->>p_code IS NOT NULL
      AND ou.services->p_type->>p_code<>'none') OR
    (NOT p_force AND (ou.services->p_type->>p_code IS NULL
      OR ou.services->p_type->>p_code='none')));
  v_result:=public.delete_service_item_internal_v1(
    p_occasion,p_type,p_code,p_force);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),v_result); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion','occasion',p_occasion,p_occasion::text,1)
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  RETURN public.complete_private_profile_mutation_v1(p_command_id,p_occasion,
    'occasion.service.delete',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_service','entityId',p_code,'operation','delete',
      'safeLabel',p_code,'changedFields',jsonb_build_array('services'))),
    v_users,ARRAY['occasion_config'],'[]',v_result);
END; $$;
REVOKE ALL ON FUNCTION public.delete_service_item_client_sync_v1(
  bigint,text,text,boolean,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_service_item_client_sync_v1(
  bigint,text,text,boolean,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_service_item(
  oc bigint,type text,code text,force boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN public.delete_service_item_client_sync_v1(
    oc,type,code,force,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_service_item(bigint,text,text,boolean)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_service_item(bigint,text,text,boolean)
  TO authenticated;

ALTER FUNCTION public.import_users_from_tickets_ws(bigint)
  RENAME TO import_users_from_tickets_ws_internal_v1;
REVOKE ALL ON FUNCTION public.import_users_from_tickets_ws_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.import_users_from_tickets_client_sync_v1(
  p_occasion bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before_users uuid[];
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'profile.tickets.import',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  v_result:=public.import_users_from_tickets_ws_internal_v1(p_occasion);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,p_occasion,'profile.tickets.import',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',NULL,'operation','import',
      'safeLabel','Ticket profile import','changedFields',jsonb_build_array(
        'profile','ticket','membership'))),v_before_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.import_users_from_tickets_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_users_from_tickets_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.import_users_from_tickets_ws(p_occasion_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN public.import_users_from_tickets_client_sync_v1(
    p_occasion_id,extensions.gen_random_uuid())->'data';
END; $$;
REVOKE ALL ON FUNCTION public.import_users_from_tickets_ws(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_users_from_tickets_ws(bigint)
  TO authenticated;

ALTER FUNCTION public.update_occasion_203(jsonb)
  RENAME TO update_occasion_internal_v1;
REVOKE ALL ON FUNCTION public.update_occasion_internal_v1(jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.update_occasion_203(input_data jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.update_occasion_internal_v1(input_data);
END; $$;
REVOKE ALL ON FUNCTION public.update_occasion_203(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion_203(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_for_edit_v1(p_link text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_occasion bigint; v_result jsonb;
BEGIN
  SELECT o.id INTO v_occasion FROM public.occasions o WHERE o.link=p_link;
  IF v_occasion IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='occasion not found'; END IF;
  IF NOT (public.get_is_editor_view_on_occasion(v_occasion)
    OR public.get_is_manager_on_occasion(v_occasion)
    OR public.get_is_admin_on_occasion(v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required'; END IF;
  SELECT to_jsonb(o)||jsonb_build_object('aggregate_version',COALESCE(v.version,0))
    INTO v_result FROM public.occasions o
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion'
      AND v.scope_type='occasion' AND v.scope_id=o.id AND v.aggregate_id=o.id::text
    WHERE o.id=v_occasion;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.get_occasion_for_edit_v1(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_for_edit_v1(text) TO authenticated;

ALTER FUNCTION public.update_unit(bigint,text,jsonb) RENAME TO update_unit_internal_v1;
REVOKE ALL ON FUNCTION public.update_unit_internal_v1(bigint,text,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.update_unit(
  p_unit_id bigint,p_title text,p_data jsonb
) RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.update_unit_internal_v1(p_unit_id,p_title,p_data);
$$;
REVOKE ALL ON FUNCTION public.update_unit(bigint,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_unit(bigint,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_unit_edit_data_v1(
  p_unit bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result jsonb; v_version bigint;
BEGIN
  IF auth.uid() IS NULL OR NOT public.get_is_manager_on_unit(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_result:=public.get_unit_edit_data(p_unit);
  SELECT COALESCE(v.version,0) INTO v_version
    FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='unit' AND v.scope_type='unit'
      AND v.scope_id=p_unit AND v.aggregate_id=p_unit::text;
  RETURN jsonb_set(v_result,'{unit}',(v_result->'unit')||
    jsonb_build_object('aggregate_version',v_version));
END; $$;
REVOKE ALL ON FUNCTION public.get_unit_edit_data_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_edit_data_v1(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_unit_client_sync_v1(
  p_unit bigint,p_command_id uuid,p_expected_version bigint,p_unit_data jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_version bigint;
  v_before jsonb; v_after jsonb; v_commit public.client_commits%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_manager_on_unit(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  IF p_unit_data IS NULL OR jsonb_typeof(p_unit_data)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_unit_data) key
      WHERE key NOT IN ('id','title','data'))
    OR (p_unit_data->>'id')::bigint IS DISTINCT FROM p_unit
    OR nullif(btrim(p_unit_data->>'title'),'') IS NULL
    OR length(p_unit_data->>'title')>30
    OR jsonb_typeof(COALESCE(p_unit_data->'data','{}'::jsonb))<>'object'
    OR octet_length(p_unit_data::text)>262144 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid unit aggregate'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'unit',p_unit,'expectedVersion',p_expected_version,
    'data',p_unit_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,'unit.config.save',
    p_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT jsonb_build_object('id',u.id,'title',u.title,'data',u.data)
    INTO v_before FROM public.units u WHERE u.id=p_unit FOR UPDATE;
  IF v_before IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',404,jsonb_build_object('version',0,'unit',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('unit','unit',p_unit,p_unit::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='unit' AND scope_type='unit'
      AND scope_id=p_unit AND aggregate_id=p_unit::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'unit',v_before||
        jsonb_build_object('aggregate_version',v_version))); END IF;
  v_after:=jsonb_build_object('id',p_unit,'title',p_unit_data->>'title',
    'data',COALESCE(p_unit_data->'data','{}'::jsonb));
  IF v_before=v_after THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',v_version,
      'unit',v_before||jsonb_build_object('aggregate_version',v_version))); END IF;
  PERFORM public.update_unit_internal_v1(
    p_unit,p_unit_data->>'title',COALESCE(p_unit_data->'data','{}'::jsonb));
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='unit' AND scope_type='unit'
    AND scope_id=p_unit AND aggregate_id=p_unit::text RETURNING version INTO v_version;
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT p_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'unit.config.save','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'unit',p_unit::text,'update',
    left(p_unit_data->>'title',240),ARRAY['configuration']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,p_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object('version',v_version,
      'unit',v_after||jsonb_build_object('aggregate_version',v_version)),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit.commit_id,'replayed',false,'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.save_unit_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_unit_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

ALTER FUNCTION public.duplicate_occasion(bigint)
  RENAME TO duplicate_occasion_internal_v1;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_unit bigint; v_title text; v_new bigint;
  v_begin jsonb; v_hash text; v_commit public.client_commits%ROWTYPE;
BEGIN
  SELECT o.unit,o.title INTO v_unit,v_title FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_actor IS NULL OR v_unit IS NULL OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'occasion.duplicate',v_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_new:=public.duplicate_occasion_internal_v1(p_occasion);
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT v_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'occasion.duplicate','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'occasion',v_new::text,'create',
    left(COALESCE(v_title,'')||' (Copy)',240),ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object('occasionId',v_new),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit.commit_id,'replayed',false,'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_response jsonb;
BEGIN
  v_response:=public.duplicate_occasion_client_sync_v1(
    oc,extensions.gen_random_uuid());
  RETURN (v_response->'data'->>'occasionId')::bigint;
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint) TO authenticated;

ALTER FUNCTION public.delete_occasion(bigint)
  RENAME TO delete_occasion_internal_v1;
REVOKE ALL ON FUNCTION public.delete_occasion_internal_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_occasion_client_sync_v1(
  p_occasion bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_unit bigint; v_title text; v_begin jsonb;
  v_hash text; v_commit public.client_commits%ROWTYPE;
BEGIN
  SELECT o.unit,o.title INTO v_unit,v_title FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  IF v_actor IS NULL OR v_unit IS NULL OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'occasion.delete',v_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.delete_occasion_internal_v1(p_occasion);
  DELETE FROM public.client_sync_scopes WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  DELETE FROM public.client_projection_dirty_keys WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  DELETE FROM public.client_aggregate_versions WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  DELETE FROM public.client_sync_public_heads WHERE scope_type='occasion'
    AND scope_id=p_occasion;
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT v_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'occasion.delete','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'occasion',p_occasion::text,'delete',
    left(v_title,240),ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object('occasionId',p_occasion),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit.commit_id,'replayed',false,'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.delete_occasion_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_occasion(oc bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM public.delete_occasion_client_sync_v1(oc,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_occasion_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_config jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_old_hidden boolean; v_new_hidden boolean;
  v_old_unit bigint; v_new_unit bigint; v_fanout_units bigint[]:='{}';
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  IF p_config IS NULL OR jsonb_typeof(p_config)<>'object'
    OR octet_length(p_config::text)>1048576
    OR (p_config->>'id')::bigint IS DISTINCT FROM p_occasion
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_config) key WHERE key NOT IN
      ('id','start_time','end_time','is_open','is_hidden','is_promoted','link','title',
       'description','data','services','organization','unit','features','form_link',
       'has_orders','stats')) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid occasion aggregate'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'config',p_config)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'occasion.config.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT o.is_hidden,o.unit INTO v_old_hidden,v_old_unit FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',404,jsonb_build_object('version',0,'occasion',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion','occasion',p_occasion,p_occasion::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='occasion' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=p_occasion::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    SELECT to_jsonb(o)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.occasions o WHERE o.id=p_occasion;
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'occasion',v_entity)); END IF;
  PERFORM public.update_occasion_internal_v1(p_config);
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='occasion'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text
    RETURNING version INTO v_version;
  SELECT to_jsonb(o)||jsonb_build_object('aggregate_version',v_version)
    INTO v_entity FROM public.occasions o WHERE o.id=p_occasion;
  v_new_hidden:=(v_entity->>'is_hidden')::boolean;
  v_new_unit:=(v_entity->>'unit')::bigint;
  IF NOT v_old_hidden THEN v_fanout_units:=array_append(v_fanout_units,v_old_unit); END IF;
  IF NOT v_new_hidden AND v_new_unit IS DISTINCT FROM v_old_unit THEN
    v_fanout_units:=array_append(v_fanout_units,v_new_unit);
  ELSIF NOT v_new_hidden AND v_old_hidden THEN
    v_fanout_units:=array_append(v_fanout_units,v_new_unit);
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'occasion.config.save','configuration',jsonb_build_array(jsonb_build_object(
      'entityType','occasion','entityId',p_occasion,'operation','update',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('configuration'))),
    CASE WHEN v_old_hidden AND NOT v_new_hidden THEN ARRAY[
      'occasion_config','program_catalog','map_catalog','content_catalog',
      'live_public'] ELSE ARRAY['occasion_config'] END,
    '[]','[]',jsonb_build_object('version',v_version,'occasion',v_entity),
    CASE WHEN NOT v_new_hidden THEN ARRAY['occasion_config'] ELSE '{}'::text[] END,
    '[]','user',NULL,'[]',v_fanout_units);
END; $$;
REVOKE ALL ON FUNCTION public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.create_occasion_client_sync_v1(
  p_command_id uuid,p_config jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_unit bigint; v_organization bigint;
  v_occasion bigint; v_begin jsonb; v_hash text; v_commit public.client_commits%ROWTYPE;
  v_entity jsonb;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config)<>'object'
    OR octet_length(p_config::text)>1048576
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_config) key WHERE key NOT IN
      ('id','start_time','end_time','is_open','is_hidden','is_promoted','link','title',
       'description','data','services','organization','unit','features','form_link',
       'has_orders','stats'))
    OR p_config->>'id' IS NOT NULL OR nullif(btrim(p_config->>'link'),'') IS NULL
    OR nullif(btrim(p_config->>'title'),'') IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid occasion aggregate'; END IF;
  v_unit:=NULLIF(p_config->>'unit','')::bigint;
  v_organization:=NULLIF(p_config->>'organization','')::bigint;
  IF v_actor IS NULL OR v_unit IS NULL OR v_organization IS NULL
    OR NOT EXISTS (SELECT 1 FROM public.units u
      WHERE u.id=v_unit AND u.organization=v_organization)
    OR NOT (public.get_is_manager_on_unit(v_unit)
      OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(p_config::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'occasion.create',v_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF EXISTS (SELECT 1 FROM public.occasions o
    WHERE o.organization=v_organization AND o.link=p_config->>'link') THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',
      409,jsonb_build_object('message','Occasion link is already in use')); END IF;
  PERFORM public.update_occasion_internal_v1(p_config);
  SELECT o.id,to_jsonb(o)||jsonb_build_object('aggregate_version',1)
    INTO v_occasion,v_entity FROM public.occasions o
    WHERE o.organization=v_organization AND o.link=p_config->>'link';
  IF v_occasion IS NULL THEN
    RAISE data_exception USING MESSAGE='occasion create returned no aggregate'; END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion','occasion',v_occasion,v_occasion::text,1);
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT v_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'occasion.create','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'occasion',v_occasion::text,'insert',
    left(v_entity->>'title',240),ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object(
      'occasionId',v_occasion,'occasion',v_entity),
    'mutation',jsonb_build_object('commandId',p_command_id,
      'receiptId',p_command_id,'commitId',v_commit.commit_id,'replayed',false,
      'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.create_occasion_client_sync_v1(uuid,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_occasion_client_sync_v1(uuid,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_occasion_203(input_data jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_occasion bigint; v_version bigint;
BEGIN
  v_occasion:=NULLIF(input_data->>'id','')::bigint;
  IF v_occasion IS NULL THEN
    PERFORM public.create_occasion_client_sync_v1(
      extensions.gen_random_uuid(),input_data);
    RETURN;
  END IF;
  SELECT COALESCE(v.version,0) INTO v_version
    FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='occasion' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=v_occasion::text;
  PERFORM public.save_occasion_client_sync_v1(v_occasion,
    extensions.gen_random_uuid(),v_version,input_data);
END; $$;
REVOKE ALL ON FUNCTION public.update_occasion_203(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion_203(jsonb) TO authenticated;

ALTER FUNCTION public.create_service_item(bigint,text,text,text,bigint)
  RENAME TO create_service_item_internal_v1;
ALTER FUNCTION public.update_service_item(bigint,text,text,text,bigint)
  RENAME TO update_service_item_internal_v1;
ALTER FUNCTION public.game_update_settings(bigint,timestamptz,timestamptz)
  RENAME TO game_update_settings_internal_v1;
REVOKE ALL ON FUNCTION public.create_service_item_internal_v1(
  bigint,text,text,text,bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.update_service_item_internal_v1(
  bigint,text,text,text,bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.game_update_settings_internal_v1(
  bigint,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_service_item_client_sync_v1(
  p_occasion bigint,p_type text,p_code text,p_title text,p_reference bigint,
  p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before jsonb; v_after jsonb;
BEGIN
  IF v_actor IS NULL OR p_type NOT IN ('food','accommodation')
    OR nullif(btrim(p_code),'') IS NULL OR length(p_code)>100
    OR length(COALESCE(p_title,''))>500
    OR NOT public.get_is_manager_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'type',p_type,'code',p_code,'title',p_title,
    'reference',p_reference)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.service.create',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT o.services INTO v_before FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  v_result:=public.create_service_item_internal_v1(
    p_occasion,p_type,p_code,p_title,p_reference);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      400,v_result); END IF;
  SELECT o.services INTO v_after FROM public.occasions o WHERE o.id=p_occasion;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,v_result); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'occasion.service.create','configuration',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_service','entityId',p_code,'operation','insert',
      'safeLabel',left(p_title,240),'changedFields',jsonb_build_array('services'))),
    ARRAY['occasion_config'],'[]','[]',v_result);
END; $$;
REVOKE ALL ON FUNCTION public.create_service_item_client_sync_v1(
  bigint,text,text,text,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_service_item_client_sync_v1(
  bigint,text,text,text,bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_service_item_client_sync_v1(
  p_occasion bigint,p_type text,p_code text,p_title text,p_reference bigint,
  p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before jsonb; v_after jsonb;
BEGIN
  IF v_actor IS NULL OR p_type NOT IN ('food','accommodation')
    OR nullif(btrim(p_code),'') IS NULL OR length(p_code)>100
    OR length(COALESCE(p_title,''))>500
    OR NOT public.get_is_manager_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'type',p_type,'code',p_code,'title',p_title,
    'reference',p_reference)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.service.update',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT o.services INTO v_before FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  v_result:=public.update_service_item_internal_v1(
    p_occasion,p_type,p_code,p_title,p_reference);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      404,v_result); END IF;
  SELECT o.services INTO v_after FROM public.occasions o WHERE o.id=p_occasion;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,v_result); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'occasion.service.update','configuration',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_service','entityId',p_code,'operation','update',
      'safeLabel',left(p_title,240),'changedFields',jsonb_build_array('services'))),
    ARRAY['occasion_config'],'[]','[]',v_result);
END; $$;
REVOKE ALL ON FUNCTION public.update_service_item_client_sync_v1(
  bigint,text,text,text,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_service_item_client_sync_v1(
  bigint,text,text,text,bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.game_update_settings_client_sync_v1(
  p_occasion bigint,p_start timestamptz,p_end timestamptz,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before jsonb; v_after jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'start',p_start,'end',p_end)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'occasion.game.settings',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT o.data INTO v_before FROM public.occasions o
    WHERE o.id=p_occasion FOR UPDATE;
  v_result:=public.game_update_settings_internal_v1(p_occasion,p_start,p_end);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      400,v_result); END IF;
  SELECT o.data INTO v_after FROM public.occasions o WHERE o.id=p_occasion;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,v_result); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'occasion.game.settings','configuration',jsonb_build_array(jsonb_build_object(
      'entityType','game_settings','entityId',p_occasion,'operation','update',
      'safeLabel','Game settings','changedFields',jsonb_build_array('data.game'))),
    ARRAY['occasion_config'],'[]','[]',v_result);
END; $$;
REVOKE ALL ON FUNCTION public.game_update_settings_client_sync_v1(
  bigint,timestamptz,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.game_update_settings_client_sync_v1(
  bigint,timestamptz,timestamptz,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_service_item(
  oc bigint,type text,code text,title text,reference bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN RETURN public.create_service_item_client_sync_v1(
  oc,type,code,title,reference,extensions.gen_random_uuid())->'data'; END; $$;
CREATE OR REPLACE FUNCTION public.update_service_item(
  oc bigint,type text,code text,new_title text,new_reference bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN RETURN public.update_service_item_client_sync_v1(
  oc,type,code,new_title,new_reference,extensions.gen_random_uuid())->'data'; END; $$;
CREATE OR REPLACE FUNCTION public.game_update_settings(
  oc bigint,new_start_time timestamptz,new_end_time timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
BEGIN RETURN public.game_update_settings_client_sync_v1(
  oc,new_start_time,new_end_time,extensions.gen_random_uuid())->'data'; END; $$;
REVOKE ALL ON FUNCTION public.create_service_item(bigint,text,text,text,bigint)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.update_service_item(bigint,text,text,text,bigint)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.game_update_settings(bigint,timestamptz,timestamptz)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_service_item(bigint,text,text,text,bigint)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_service_item(bigint,text,text,text,bigint)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_update_settings(bigint,timestamptz,timestamptz)
  TO authenticated;

ALTER FUNCTION public.sync_source_via_http(text)
  RENAME TO sync_source_via_http_internal_v1;
REVOKE ALL ON FUNCTION public.sync_source_via_http_internal_v1(text)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.sync_source_via_http_client_sync_v1(
  p_source_name text
) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_organization bigint; v_before jsonb; v_after jsonb; v_result text;
  v_changed bigint[]; v_deleted bigint[]; v_units bigint[]; v_commit public.client_commits%ROWTYPE;
  v_occasion bigint; v_unit bigint; v_revision bigint;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF nullif(btrim(p_source_name),'') IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='one external source is required'; END IF;
  PERFORM 1 FROM public.external_sync_sources s
    WHERE s.source_name=p_source_name FOR UPDATE;
  SELECT min(m.target_org_id),array_agg(DISTINCT m.target_unit_id ORDER BY m.target_unit_id)
    INTO v_organization,v_units FROM public.external_sync_maps m
    WHERE m.source_name=p_source_name;
  IF v_organization IS NULL OR EXISTS (SELECT 1 FROM public.external_sync_maps m
      WHERE m.source_name=p_source_name AND m.target_org_id<>v_organization) THEN
    RAISE invalid_parameter_value USING MESSAGE='external source must map to one organization';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'unit',o.unit,
    'row',to_jsonb(o)-'updated_at') ORDER BY o.id),'[]'::jsonb) INTO v_before
    FROM public.occasions o WHERE o.external_source=p_source_name;
  v_result:=public.sync_source_via_http_internal_v1(p_source_name);
  IF v_result LIKE 'Error:%' THEN
    RAISE external_routine_exception USING MESSAGE=v_result; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'unit',o.unit,
    'row',to_jsonb(o)-'updated_at') ORDER BY o.id),'[]'::jsonb) INTO v_after
    FROM public.occasions o WHERE o.external_source=p_source_name;
  IF v_before=v_after THEN RETURN v_result; END IF;
  SELECT ARRAY(SELECT COALESCE(a.id,b.id) FROM
    jsonb_to_recordset(v_after) a(id bigint,unit bigint,row jsonb)
    FULL JOIN jsonb_to_recordset(v_before) b(id bigint,unit bigint,row jsonb)
      ON a.id=b.id WHERE a.row IS DISTINCT FROM b.row ORDER BY 1)
    INTO v_changed;
  SELECT ARRAY(SELECT b.id FROM jsonb_to_recordset(v_before)
    b(id bigint,unit bigint,row jsonb) WHERE NOT EXISTS (
      SELECT 1 FROM jsonb_to_recordset(v_after) a(id bigint,unit bigint,row jsonb)
      WHERE a.id=b.id) ORDER BY b.id) INTO v_deleted;
  SELECT ARRAY(SELECT DISTINCT unit_id FROM (
    SELECT unit unit_id FROM jsonb_to_recordset(v_before)
      b(id bigint,unit bigint,row jsonb) WHERE id=ANY(v_changed)
    UNION SELECT unit FROM jsonb_to_recordset(v_after)
      a(id bigint,unit bigint,row jsonb) WHERE id=ANY(v_changed)
  ) units WHERE unit_id IS NOT NULL ORDER BY unit_id) INTO v_units;
  INSERT INTO public.client_commits
    (organization,actor_id,actor_display,actor_kind,source,change_class,reason)
  VALUES (v_organization,NULL,NULL,'service','occasion.external_sync',
    'configuration','external source '||p_source_name) RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'external_source',p_source_name,'sync',
    left(p_source_name,240),ARRAY['occasions']);
  FOREACH v_occasion IN ARRAY v_changed LOOP
    IF v_occasion=ANY(COALESCE(v_deleted,'{}'::bigint[])) THEN
      DELETE FROM public.client_projection_dirty_keys
        WHERE scope_type='occasion' AND scope_id=v_occasion;
      DELETE FROM public.client_sync_scopes
        WHERE scope_type='occasion' AND scope_id=v_occasion;
      DELETE FROM public.client_sync_private_scopes WHERE occasion=v_occasion;
      CONTINUE;
    END IF;
    INSERT INTO public.client_sync_scopes
      (component,scope_type,scope_id,source_revision)
    VALUES ('occasion_config','occasion',v_occasion,1)
    ON CONFLICT (component,scope_type,scope_id) DO UPDATE SET
      source_revision=public.client_sync_scopes.source_revision+1,updated_at=now()
    RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
    VALUES (v_commit.commit_id,'occasion_config','occasion',v_occasion,NULL,v_revision);
  END LOOP;
  FOREACH v_unit IN ARRAY COALESCE(v_units,'{}'::bigint[]) LOOP
    PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,v_unit);
  END LOOP;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.sync_source_via_http_client_sync_v1(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sync_source_via_http_client_sync_v1(text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.sync_source_via_http(
  p_target_source_name text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_source text; v_result text:='';
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  FOR v_source IN SELECT s.source_name FROM public.external_sync_sources s
    WHERE p_target_source_name IS NULL OR s.source_name=p_target_source_name
    ORDER BY s.source_name LOOP
    v_result:=v_result||CASE WHEN v_result='' THEN '' ELSE E'\n' END||
      public.sync_source_via_http_client_sync_v1(v_source);
  END LOOP;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.sync_source_via_http(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sync_source_via_http(text) TO service_role;

ALTER FUNCTION public.create_counseling_slots(bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer)
  RENAME TO create_counseling_slots_internal_v1;
ALTER FUNCTION public.delete_empty_counseling_slots(bigint,timestamptz)
  RENAME TO delete_empty_counseling_slots_internal_v1;
REVOKE ALL ON FUNCTION public.create_counseling_slots_internal_v1(bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.delete_empty_counseling_slots_internal_v1(bigint,timestamptz)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.create_counseling_slots(
  p_speaker bigint,p_start timestamptz,p_end timestamptz,p_slot_minutes integer,
  p_place bigint DEFAULT NULL,p_capacity integer DEFAULT 1,p_title text DEFAULT NULL,
  p_break_minutes integer DEFAULT 0
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.create_counseling_slots_internal_v1(p_speaker,p_start,p_end,
    p_slot_minutes,p_place,p_capacity,p_title,p_break_minutes);
$$;
CREATE OR REPLACE FUNCTION public.delete_empty_counseling_slots(
  p_speaker bigint,p_from timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.delete_empty_counseling_slots_internal_v1(p_speaker,p_from);
$$;

CREATE OR REPLACE FUNCTION public.create_counseling_slots_client_sync_v1(
  p_speaker bigint,p_start timestamptz,p_end timestamptz,p_slot_minutes integer,
  p_place bigint,p_capacity integer,p_title text,p_break_minutes integer,
  p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_ids bigint[];
BEGIN
  SELECT s.occasion INTO v_occasion FROM public.speakers s WHERE s.id=p_speaker;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('speaker',p_speaker,
    'start',p_start,'end',p_end,'slotMinutes',p_slot_minutes,'place',p_place,
    'capacity',p_capacity,'title',p_title,'breakMinutes',p_break_minutes)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.counseling.create',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.speakers s WHERE s.id=p_speaker FOR UPDATE;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_speaker);
  v_result:=public.create_counseling_slots_internal_v1(p_speaker,p_start,p_end,
    p_slot_minutes,p_place,p_capacity,p_title,p_break_minutes);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')); END IF;
  SELECT COALESCE(array_agg(value::bigint),'{}'::bigint[]) INTO v_ids
    FROM jsonb_array_elements_text(v_result#>'{data,event_ids}');
  IF cardinality(v_ids)=0 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,v_result->'data'); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'event','occasion',v_occasion,id::text,1 FROM unnest(v_ids) id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'program.counseling.create','program',jsonb_build_array(jsonb_build_object(
      'entityType','counseling_slot','entityId',NULL,'operation','insert',
      'safeLabel','Counseling slots','changedFields',jsonb_build_array('events','speakers'))),
    ARRAY['program_catalog','content_catalog'],'[]','[]',v_result->'data');
END; $$;
REVOKE ALL ON FUNCTION public.create_counseling_slots_client_sync_v1(bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_counseling_slots_client_sync_v1(bigint,timestamptz,timestamptz,integer,bigint,integer,text,integer,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_empty_counseling_slots_client_sync_v1(
  p_speaker bigint,p_from timestamptz,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_ids bigint[]; v_users uuid[]; v_impacts jsonb;
  v_publishable boolean;
BEGIN
  SELECT s.occasion,NOT o.is_hidden INTO v_occasion,v_publishable
    FROM public.speakers s JOIN public.occasions o ON o.id=s.occasion
    WHERE s.id=p_speaker;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('speaker',p_speaker,
    'from',p_from)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'program.counseling.delete_empty',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.speakers s WHERE s.id=p_speaker FOR UPDATE;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_speaker);
  SELECT COALESCE(array_agg(e.id ORDER BY e.id),'{}'::bigint[]) INTO v_ids
    FROM public.events e JOIN public.event_speakers es ON es.event=e.id
    WHERE es.speaker=p_speaker AND (e.data->>'is_counseling_slot')::boolean IS TRUE
      AND (p_from IS NULL OR e.start_time>=p_from)
      AND NOT EXISTS (SELECT 1 FROM public.event_users eu WHERE eu.event=e.id);
  PERFORM 1 FROM public.events e WHERE e.id=ANY(v_ids) ORDER BY e.id FOR UPDATE;
  PERFORM 1 FROM public.event_users_saved eus WHERE eus.event=ANY(v_ids)
    ORDER BY eus.event,eus."user" FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT eus."user"),'{}'::uuid[]) INTO v_users
    FROM public.event_users_saved eus WHERE eus.event=ANY(v_ids);
  v_result:=public.delete_empty_counseling_slots_internal_v1(p_speaker,p_from);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      COALESCE((v_result->>'code')::integer,400),COALESCE(v_result->'data','{}')); END IF;
  IF cardinality(v_ids)=0 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,v_result->'data'); END IF;
  DELETE FROM public.client_aggregate_versions v WHERE v.aggregate_type='event'
    AND v.scope_type='occasion' AND v.scope_id=v_occasion
    AND v.aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(v_ids) id));
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_program',
    'userId',id)),'[]'::jsonb) INTO v_impacts FROM unnest(v_users) id
    JOIN public.occasion_users ou ON ou.occasion=v_occasion AND ou."user"=id;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'program.counseling.delete_empty','program',jsonb_build_array(jsonb_build_object(
      'entityType','counseling_slot','entityId',NULL,'operation','delete',
      'safeLabel','Empty counseling slots','changedFields',jsonb_build_array('events'))),
    CASE WHEN v_publishable THEN ARRAY['program_catalog','content_catalog','live_public']
      ELSE '{}'::text[] END,v_impacts,CASE WHEN v_publishable THEN COALESCE((
      SELECT jsonb_agg(jsonb_build_object('component','live_public','entityId',id))
      FROM unnest(v_ids) id),'[]'::jsonb) ELSE '[]'::jsonb END,v_result->'data');
END; $$;
REVOKE ALL ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(bigint,timestamptz,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_empty_counseling_slots_client_sync_v1(bigint,timestamptz,uuid)
  TO authenticated;

ALTER FUNCTION public.game_guess(bigint,text) RENAME TO game_guess_internal_v1;
REVOKE ALL ON FUNCTION public.game_guess_internal_v1(bigint,text)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.game_guess(check_point_id bigint,guess text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.game_guess_internal_v1(check_point_id,guess);
$$;
REVOKE ALL ON FUNCTION public.game_guess(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.game_guess(bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.game_guess_client_sync_v1(
  p_checkpoint bigint,p_guess text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_group bigint;
  v_begin jsonb; v_hash text; v_result jsonb; v_before jsonb; v_after jsonb;
  v_version bigint; v_impacts jsonb; v_replacements jsonb;
  v_domain_code integer;
BEGIN
  SELECT ih.occasion INTO v_occasion FROM public.information i
    JOIN public.information_hidden ih ON ih.id=i.information_hidden
    WHERE i.id=p_checkpoint;
  IF v_actor IS NULL OR v_occasion IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='occasion participant required'; END IF;
  SELECT ug."group" INTO v_group FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    WHERE ug."user"=v_actor AND g.occasion=v_occasion AND g.type='game'
    ORDER BY g.id LIMIT 1;
  IF v_group IS NULL THEN RAISE insufficient_privilege USING MESSAGE='game group required'; END IF;
  IF p_guess IS NULL OR length(p_guess)>2000 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid game guess'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'checkpoint',p_checkpoint,'guess',p_guess)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.game.guess',
    v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT g.data INTO v_before FROM public.user_group_info g WHERE g.id=v_group FOR UPDATE;
  v_result:=public.game_guess_internal_v1(p_checkpoint,p_guess);
  v_domain_code:=COALESCE((v_result->>'code')::integer,500);
  IF v_domain_code<>200 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',CASE WHEN v_domain_code BETWEEN 4030 AND 4039 THEN 403
      WHEN v_domain_code BETWEEN 4040 AND 4049 THEN 404 ELSE 400 END,
    jsonb_build_object('domainCode',v_domain_code,'message',v_result->>'message'));
  END IF;
  SELECT g.data INTO v_after FROM public.user_group_info g WHERE g.id=v_group;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('user_group','occasion',v_occasion,v_group::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='user_group' AND scope_type='occasion'
      AND scope_id=v_occasion AND aggregate_id=v_group::text FOR UPDATE;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('domainCode',200,'correct',true,'version',v_version)); END IF;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_group::text
    RETURNING version INTO v_version;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',ug."user")),'[]'::jsonb) INTO v_impacts FROM public.user_groups ug
    WHERE ug."group"=v_group;
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(v_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'profile.game.guess','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',v_group,'operation','update',
      'safeLabel','Game checkpoint','changedFields',jsonb_build_array('game'))),
    '{}',v_impacts,'[]',jsonb_build_object('domainCode',200,'correct',true,
      'version',v_version),'{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.game_guess_client_sync_v1(bigint,text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.game_guess_client_sync_v1(bigint,text,uuid)
  TO authenticated;

-- Feedback supports both authenticated users and a stable anonymous device
-- identity. The legacy contracts remain thin facades; v1 owns receipts,
-- exactly-one audit, and authenticated private-feedback revisions.
ALTER FUNCTION public.submit_event_feedback(bigint,text,text,uuid)
  RENAME TO submit_event_feedback_internal_v1;
REVOKE ALL ON FUNCTION public.submit_event_feedback_internal_v1(bigint,text,text,uuid)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.submit_event_feedback(
  p_event bigint,p_rating text,p_note text DEFAULT NULL,p_client_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.submit_event_feedback_internal_v1(
    p_event,p_rating,p_note,p_client_id);
$$;
REVOKE ALL ON FUNCTION public.submit_event_feedback(bigint,text,text,uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback(bigint,text,text,uuid)
  TO anon,authenticated,service_role;

ALTER FUNCTION public.delete_event_feedback(bigint,uuid)
  RENAME TO delete_event_feedback_internal_v1;
REVOKE ALL ON FUNCTION public.delete_event_feedback_internal_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.delete_event_feedback(
  p_event bigint,p_client_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.delete_event_feedback_internal_v1(p_event,p_client_id);
$$;
REVOKE ALL ON FUNCTION public.delete_event_feedback(bigint,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_event_feedback(bigint,uuid)
  TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_event_feedback_command_data_v1(
  p_feedback bigint
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object('id',f.id,'event',f.event,'rating',f.rating,
    'note',f.note,'created_at',f.created_at,'updated_at',f.updated_at)
  FROM public.event_feedback f WHERE f.id=p_feedback;
$$;
REVOKE ALL ON FUNCTION public.get_event_feedback_command_data_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.submit_event_feedback_client_sync_v1(
  p_occasion bigint,p_event bigint,p_rating text,p_note text,p_client_id uuid,
  p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_client uuid; v_begin jsonb; v_hash text;
  v_result jsonb; v_before public.event_feedback%ROWTYPE;
  v_after public.event_feedback%ROWTYPE; v_private_impacts jsonb:='[]'::jsonb;
  v_replacements jsonb:='[]'::jsonb; v_operation text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.events e
    WHERE e.id=p_event AND e.occasion=p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='feedback event outside occasion'; END IF;
  v_client:=CASE WHEN v_actor IS NULL THEN p_client_id ELSE NULL END;
  IF v_actor IS NULL AND v_client IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='anonymous client id required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'event',p_event,'rating',p_rating,'note',p_note,
    'clientId',v_client)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'feedback.submit',p_occasion,v_client,v_hash);
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,'feedback.submit',
      p_occasion,v_actor,v_hash);
  END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.events e WHERE e.id=p_event FOR UPDATE;
  IF v_actor IS NULL THEN
    SELECT * INTO v_before FROM public.event_feedback f
      WHERE f.event=p_event AND f."user" IS NULL AND f.client_id=v_client
      FOR UPDATE;
  ELSE
    SELECT * INTO v_before FROM public.event_feedback f
      WHERE f.event=p_event AND f."user"=v_actor FOR UPDATE;
  END IF;
  v_result:=public.submit_event_feedback_internal_v1(
    p_event,p_rating,p_note,v_client);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,400) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,
      jsonb_build_object('message',v_result->>'message'));
  END IF;
  SELECT * INTO STRICT v_after FROM public.event_feedback f
    WHERE f.id=(v_result#>>'{data,id}')::bigint;
  IF v_before.id IS NOT NULL AND v_before.rating IS NOT DISTINCT FROM v_after.rating
      AND v_before.note IS NOT DISTINCT FROM v_after.note
      AND v_before.data IS NOT DISTINCT FROM v_after.data THEN
    UPDATE public.event_feedback SET updated_at=v_before.updated_at
      WHERE id=v_after.id;
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('feedback',public.get_event_feedback_command_data_v1(v_after.id)));
  END IF;
  v_operation:=CASE WHEN v_before.id IS NULL THEN 'insert' ELSE 'update' END;
  IF v_actor IS NOT NULL AND EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=v_actor) THEN
    v_private_impacts:=jsonb_build_array(jsonb_build_object(
      'component','private_feedback','userId',v_actor));
    v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_feedback','userId',v_actor,
      'payload',public.get_private_feedback_payload_v1(p_occasion,v_actor)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'feedback.submit','feedback',jsonb_build_array(jsonb_build_object(
      'entityType','event_feedback','entityId',v_after.id,'operation',v_operation,
      'safeLabel','Event feedback','changedFields',jsonb_build_array('rating','note'))),
    '{}',v_private_impacts,'[]',jsonb_build_object(
      'feedback',public.get_event_feedback_command_data_v1(v_after.id)),
    '{}','[]',CASE WHEN v_actor IS NULL THEN 'unknown' ELSE 'user' END,NULL,
    v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.submit_event_feedback_client_sync_v1(bigint,bigint,text,text,uuid,uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback_client_sync_v1(bigint,bigint,text,text,uuid,uuid)
  TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_event_feedback_client_sync_v1(
  p_occasion bigint,p_event bigint,p_client_id uuid,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_client uuid; v_begin jsonb; v_hash text;
  v_before public.event_feedback%ROWTYPE; v_result jsonb;
  v_private_impacts jsonb:='[]'::jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.events e
    WHERE e.id=p_event AND e.occasion=p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='feedback event outside occasion'; END IF;
  v_client:=CASE WHEN v_actor IS NULL THEN p_client_id ELSE NULL END;
  IF v_actor IS NULL AND v_client IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='anonymous client id required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'event',p_event,'clientId',v_client)::text,
    'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'feedback.delete',p_occasion,v_client,v_hash);
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,'feedback.delete',
      p_occasion,v_actor,v_hash);
  END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.events e WHERE e.id=p_event FOR UPDATE;
  IF v_actor IS NULL THEN
    SELECT * INTO v_before FROM public.event_feedback f
      WHERE f.event=p_event AND f."user" IS NULL AND f.client_id=v_client
      FOR UPDATE;
  ELSE
    SELECT * INTO v_before FROM public.event_feedback f
      WHERE f.event=p_event AND f."user"=v_actor FOR UPDATE;
  END IF;
  IF v_before.id IS NULL THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('deleted',false)); END IF;
  v_result:=public.delete_event_feedback_internal_v1(p_event,v_client);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,400) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,
      jsonb_build_object('message',v_result->>'message'));
  END IF;
  IF v_actor IS NOT NULL AND EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=v_actor) THEN
    v_private_impacts:=jsonb_build_array(jsonb_build_object(
      'component','private_feedback','userId',v_actor));
    v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_feedback','userId',v_actor,
      'payload',public.get_private_feedback_payload_v1(p_occasion,v_actor)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'feedback.delete','feedback',jsonb_build_array(jsonb_build_object(
      'entityType','event_feedback','entityId',v_before.id,'operation','delete',
      'safeLabel','Event feedback','changedFields',jsonb_build_array('aggregate'))),
    '{}',v_private_impacts,'[]',jsonb_build_object('deleted',true),
    '{}','[]',CASE WHEN v_actor IS NULL THEN 'unknown' ELSE 'user' END,NULL,
    v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.delete_event_feedback_client_sync_v1(bigint,bigint,uuid,uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_event_feedback_client_sync_v1(bigint,bigint,uuid,uuid)
  TO anon,authenticated;

-- Companion creation retains the established auth-user provisioning handler,
-- but puts a bounded, idempotent command and private-profile revision around
-- it. The old signature remains a compatibility facade only.
ALTER FUNCTION public.create_companion_in_organization(bigint,bigint,uuid,text)
  RENAME TO create_companion_in_organization_internal_v1;
REVOKE ALL ON FUNCTION public.create_companion_in_organization_internal_v1(bigint,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.create_companion_in_organization(
  org bigint,oc bigint,usr uuid,c_name text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.create_companion_in_organization_internal_v1(org,oc,usr,c_name);
$$;
REVOKE ALL ON FUNCTION public.create_companion_in_organization(bigint,bigint,uuid,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_companion_in_organization(bigint,bigint,uuid,text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.create_companion_client_sync_v1(
  p_occasion bigint,p_name text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_organization bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_before uuid[]; v_companion uuid; v_replacements jsonb;
BEGIN
  IF v_actor IS NULL OR nullif(btrim(p_name),'') IS NULL
    OR octet_length(p_name)>512 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid companion'; END IF;
  SELECT o.organization INTO v_organization FROM public.occasions o
    JOIN public.occasion_users ou ON ou.occasion=o.id AND ou."user"=v_actor
    WHERE o.id=p_occasion;
  IF v_organization IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='occasion participant required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'name',p_name)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.create',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-owner:'||v_actor::text||':'||p_occasion::text,0));
  SELECT COALESCE(array_agg(uc.companion),'{}'::uuid[]) INTO v_before
    FROM public.user_companions uc WHERE uc."user"=v_actor;
  v_result:=public.create_companion_in_organization_internal_v1(
    v_organization,p_occasion,v_actor,p_name);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer=403 THEN 403 ELSE 400 END,
      jsonb_build_object('companion',NULL,'domainCode',v_result->'code'));
  END IF;
  SELECT uc.companion INTO v_companion FROM public.user_companions uc
    WHERE uc."user"=v_actor AND NOT uc.companion=ANY(v_before)
    ORDER BY uc.companion LIMIT 1;
  IF v_companion IS NULL THEN
    RAISE EXCEPTION 'companion handler did not create a companion'; END IF;
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.companion.create','profile',jsonb_build_array(jsonb_build_object(
      'entityType','companion','entityId',v_companion,'operation','insert',
      'safeLabel','Companion','changedFields',jsonb_build_array('name'))),
    '{}',jsonb_build_array(jsonb_build_object('component','private_profile',
      'userId',v_actor)),'[]',jsonb_build_object('companion',jsonb_build_object(
        'id',v_companion,'name',p_name,'event_ids','[]'::jsonb)),
    '{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.create_companion_client_sync_v1(bigint,text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_companion_client_sync_v1(bigint,text,uuid)
  TO authenticated;

-- The legacy delete handler contains no receipt/revision protocol. Keep its
-- released name for old clients; v1 uses the closed companion-specific command.
CREATE OR REPLACE FUNCTION public.delete_companion_client_sync_v1(
  p_occasion bigint,p_companion uuid,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_event_ids bigint[];
  v_group_ids bigint[]; v_private_impacts jsonb; v_replacements jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR p_companion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid companion delete'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_companions uc
    JOIN public.occasion_users ou ON ou."user"=uc.companion AND ou.occasion=p_occasion
    WHERE uc."user"=v_actor AND uc.companion=p_companion) THEN
    RAISE insufficient_privilege USING MESSAGE='companion owner required'; END IF;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou."user"=p_companion AND ou.occasion<>p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='cross-occasion companion requires manual cleanup'; END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'companion',p_companion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-owner:'||v_actor::text||':'||p_occasion::text,0));
  PERFORM 1 FROM public.user_info ui WHERE ui.id=p_companion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('companion',NULL)); END IF;
  SELECT COALESCE(array_agg(DISTINCT event_id ORDER BY event_id),'{}'::bigint[])
    INTO v_event_ids FROM (
      SELECT eu.event event_id FROM public.event_users eu JOIN public.events e
        ON e.id=eu.event WHERE eu."user"=p_companion AND e.occasion=p_occasion
      UNION SELECT es.event FROM public.event_users_saved es JOIN public.events e
        ON e.id=es.event WHERE es."user"=p_companion AND e.occasion=p_occasion
    ) affected;
  SELECT COALESCE(array_agg(ug."group" ORDER BY ug."group"),'{}'::bigint[])
    INTO v_group_ids FROM public.user_groups ug JOIN public.user_group_info g
      ON g.id=ug."group" WHERE ug."user"=p_companion AND g.occasion=p_occasion;
  PERFORM 1 FROM public.events e WHERE e.id=ANY(v_event_ids) ORDER BY e.id FOR UPDATE;
  PERFORM 1 FROM public.user_group_info g WHERE g.id=ANY(v_group_ids) ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',impacted.user_id)),'[]'::jsonb) INTO v_private_impacts FROM (
      SELECT v_actor user_id UNION SELECT ug."user" FROM public.user_groups ug
        WHERE ug."group"=ANY(v_group_ids) AND ug."user"<>p_companion
    ) impacted JOIN public.occasion_users ou ON ou.occasion=p_occasion
      AND ou."user"=impacted.user_id;
  UPDATE public.news SET created_by=NULL WHERE created_by=p_companion;
  DELETE FROM public.user_groups WHERE "user"=p_companion;
  DELETE FROM public.event_users WHERE "user"=p_companion;
  DELETE FROM public.user_news WHERE "user"=p_companion;
  DELETE FROM public.event_users_saved WHERE "user"=p_companion;
  DELETE FROM public.occasion_users WHERE "user"=p_companion;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_companion::text;
  DELETE FROM public.user_reset_token WHERE "user"=p_companion;
  DELETE FROM public.user_companions WHERE "user"=p_companion OR companion=p_companion;
  DELETE FROM public.user_info WHERE id=p_companion;
  DELETE FROM auth.identities WHERE user_id=p_companion;
  DELETE FROM auth.users WHERE id=p_companion;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(v_group_ids) id));
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.companion.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','companion','entityId',p_companion,'operation','delete',
      'safeLabel','Companion','changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND cardinality(v_event_ids)>0
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_is_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',event_id)) FROM unnest(v_event_ids) event_id),
      '[]'::jsonb) ELSE '[]'::jsonb END,
    jsonb_build_object('companion',NULL),'{}','[]','user',NULL,v_replacements);
END; $$;
REVOKE ALL ON FUNCTION public.delete_companion_client_sync_v1(bigint,uuid,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_companion_client_sync_v1(bigint,uuid,uuid)
  TO authenticated;

-- Exclusivity is authoritative decision state for attendance rather than a
-- cached projection. It still uses one guarded command so a v1 client cannot
-- expose a partially replaced group/event relation set.
CREATE OR REPLACE FUNCTION public.get_exclusive_group_command_data_v1(
  p_group bigint
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id',g.id,
    'title',g.title,
    'exclusive_events',COALESCE((SELECT jsonb_agg(
      jsonb_build_object('event',ee.event) ORDER BY ee.event)
      FROM public.exclusive_events ee WHERE ee."group"=g.id),'[]'::jsonb),
    'aggregate_version',COALESCE(v.version,0))
  FROM public.exclusive_groups g
  LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='exclusive_group' AND v.scope_type='occasion'
    AND v.scope_id=g.occasion AND v.aggregate_id=g.id::text
  WHERE g.id=p_group;
$$;
REVOKE ALL ON FUNCTION public.get_exclusive_group_command_data_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_exclusive_groups_for_edit_v1(
  p_occasion bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(public.get_exclusive_group_command_data_v1(g.id)
    ORDER BY g.title,g.id),'[]'::jsonb) INTO v_result
  FROM public.exclusive_groups g WHERE g.occasion=p_occasion;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.get_exclusive_groups_for_edit_v1(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_exclusive_groups_for_edit_v1(bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_exclusive_group_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_group jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_entity jsonb; v_event_ids bigint[];
  v_requested jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  IF p_group IS NULL OR jsonb_typeof(p_group)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_group) key
      WHERE key NOT IN ('id','title','events'))
    OR nullif(btrim(p_group->>'title'),'') IS NULL
    OR octet_length(p_group->>'title')>2048
    OR jsonb_typeof(p_group->'events')<>'array'
    OR jsonb_array_length(p_group->'events')>500
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_group->'events') value
      WHERE jsonb_typeof(value)<>'number') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid exclusive group'; END IF;
  SELECT COALESCE(array_agg(value::text::bigint ORDER BY value::text::bigint),
    '{}'::bigint[]) INTO v_event_ids FROM jsonb_array_elements(p_group->'events');
  IF cardinality(v_event_ids)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_event_ids))) THEN
    RAISE invalid_parameter_value USING MESSAGE='duplicate exclusive event'; END IF;
  v_id:=(p_group->>'id')::bigint;
  IF v_id IS NULL AND p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new group must not have expected version'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'expectedVersion',p_expected_version,
    'group',p_group)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'schedule.exclusive_group.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_event_ids) event_id WHERE NOT EXISTS (
    SELECT 1 FROM public.events e WHERE e.id=event_id AND e.occasion=p_occasion)) THEN
    RAISE invalid_parameter_value USING MESSAGE='exclusive event outside occasion'; END IF;
  PERFORM 1 FROM public.events e WHERE e.id=ANY(v_event_ids) ORDER BY e.id FOR UPDATE;
  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.exclusive_groups g WHERE g.id=v_id
      AND g.occasion=p_occasion FOR UPDATE;
    IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',404,jsonb_build_object('version',0,'group',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('exclusive_group','occasion',p_occasion,v_id::text,0)
    ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='exclusive_group' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    v_current:=public.get_exclusive_group_command_data_v1(v_id);
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'group',v_current)); END IF;
    v_requested:=jsonb_build_object('id',v_id,'title',p_group->>'title',
      'exclusive_events',COALESCE((SELECT jsonb_agg(jsonb_build_object('event',event_id)
        ORDER BY event_id) FROM unnest(v_event_ids) event_id),'[]'::jsonb),
      'aggregate_version',v_version);
    IF v_current=v_requested THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'unchanged',200,jsonb_build_object(
        'version',v_version,'group',v_current)); END IF;
    UPDATE public.exclusive_groups SET title=p_group->>'title' WHERE id=v_id;
    DELETE FROM public.exclusive_events WHERE "group"=v_id;
    INSERT INTO public.exclusive_events("group",event)
      SELECT v_id,event_id FROM unnest(v_event_ids) event_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='exclusive_group'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    INSERT INTO public.exclusive_groups(title,occasion)
      VALUES (p_group->>'title',p_occasion) RETURNING id INTO v_id;
    INSERT INTO public.exclusive_events("group",event)
      SELECT v_id,event_id FROM unnest(v_event_ids) event_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('exclusive_group','occasion',p_occasion,v_id::text,v_version);
  END IF;
  v_entity:=public.get_exclusive_group_command_data_v1(v_id);
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'schedule.exclusive_group.save','schedule_constraints',
    jsonb_build_array(jsonb_build_object('entityType','exclusive_group',
      'entityId',v_id,'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_group->>'title',240),
      'changedFields',jsonb_build_array('title','events'))),
    '{}','[]','[]',jsonb_build_object('version',v_version,'group',v_entity));
END; $$;
REVOKE ALL ON FUNCTION public.save_exclusive_group_client_sync_v1(bigint,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_exclusive_group_client_sync_v1(bigint,uuid,bigint,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_exclusive_group_client_sync_v1(
  p_occasion bigint,p_group_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'groupId',p_group_id,
    'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'schedule.exclusive_group.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.exclusive_groups g WHERE g.id=p_group_id
    AND g.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'group',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('exclusive_group','occasion',p_occasion,p_group_id::text,0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='exclusive_group' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_group_id::text FOR UPDATE;
  v_entity:=public.get_exclusive_group_command_data_v1(p_group_id);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'group',v_entity)); END IF;
  DELETE FROM public.exclusive_events WHERE "group"=p_group_id;
  DELETE FROM public.exclusive_groups WHERE id=p_group_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='exclusive_group'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group_id::text;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'schedule.exclusive_group.delete','schedule_constraints',
    jsonb_build_array(jsonb_build_object('entityType','exclusive_group',
      'entityId',p_group_id,'operation','delete','safeLabel',left(v_entity->>'title',240),
      'changedFields',jsonb_build_array('aggregate'))),
    '{}','[]','[]',jsonb_build_object('version',v_version,'group',NULL));
END; $$;
REVOKE ALL ON FUNCTION public.delete_exclusive_group_client_sync_v1(bigint,bigint,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_exclusive_group_client_sync_v1(bigint,bigint,uuid,bigint)
  TO authenticated;

RESET statement_timeout;
RESET lock_timeout;
