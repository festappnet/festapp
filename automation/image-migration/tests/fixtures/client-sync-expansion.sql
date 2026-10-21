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

CREATE OR REPLACE FUNCTION public.require_service_role()
RETURNS void LANGUAGE plpgsql STABLE SET search_path = '' AS $$
BEGIN
  IF NOT public.is_service_role() THEN
    RAISE insufficient_privilege USING MESSAGE='service role required';
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.require_client_sync_service_role_v1()
RETURNS void LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT public.require_service_role();
$$;

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
