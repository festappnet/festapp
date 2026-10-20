BEGIN;

ALTER TABLE public.occasion_users ADD COLUMN IF NOT EXISTS is_receptionist boolean NOT NULL DEFAULT false;

create table if not exists public.reception_registrations (
  occasion bigint not null,
  "user" uuid not null,
  created_by uuid not null,
  command_id uuid not null,
  request_hash text not null,
  created_at timestamptz not null default now(),
  status text not null default 'active' check (status in ('active', 'cancelled')),
  cancelled_by uuid null,
  cancelled_at timestamptz null,
  auth_revoked_at timestamptz null,
  constraint reception_registrations_pkey primary key (occasion, "user"),
  constraint reception_registrations_command_key unique (occasion, created_by, command_id),
  constraint reception_registrations_occasion_fkey foreign key (occasion) references public.occasions(id),
  constraint reception_registrations_user_fkey foreign key ("user") references public.user_info(id),
  constraint reception_registrations_created_by_fkey foreign key (created_by) references public.user_info(id),
  constraint reception_registrations_cancelled_by_fkey foreign key (cancelled_by) references public.user_info(id)
) tablespace pg_default;

alter table public.reception_registrations enable row level security;

create table if not exists public.user_login_qr_credentials (
  occasion bigint not null,
  "user" uuid not null,
  token_hash text not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  rotated_at timestamptz null,
  revoked_at timestamptz null,
  last_used_at timestamptz null,
  use_count bigint not null default 0,
  constraint user_login_qr_credentials_pkey primary key (occasion, "user"),
  constraint user_login_qr_credentials_hash_key unique (token_hash),
  constraint user_login_qr_credentials_membership_fkey foreign key (occasion, "user")
    references public.occasion_users(occasion, "user") on delete cascade,
  constraint user_login_qr_credentials_created_by_fkey foreign key (created_by) references public.user_info(id),
  constraint user_login_qr_credentials_hash_check check (token_hash ~ '^[0-9a-f]{64}$')
) tablespace pg_default;

alter table public.user_login_qr_credentials enable row level security;

create table if not exists public.reception_rate_limits (
  actor uuid not null,
  operation text not null,
  bucket timestamptz not null,
  count integer not null default 1,
  primary key (actor, operation, bucket)
);

alter table public.reception_rate_limits enable row level security;

revoke all on table public.reception_registrations,
  public.user_login_qr_credentials, public.reception_rate_limits
from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_is_receptionist_on_occasion(oc bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT COALESCE((SELECT ou.is_receptionist
    FROM public.occasion_users ou
    WHERE ou."user"=auth.uid() AND ou.occasion=oc),false);
$$;

REVOKE ALL ON FUNCTION public.get_is_receptionist_on_occasion(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_is_receptionist_on_occasion(bigint) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_can_use_reception(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE o.id=p_occasion
      AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),
        '$[*] ? (@.code == "reception" && @.is_enabled == true)')
  ) AND (
    public.get_is_receptionist_on_occasion(p_occasion)
    OR public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
  );
$$;

REVOKE ALL ON FUNCTION public.get_can_use_reception(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_can_use_reception(bigint) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reception_rate_limit_v1(p_operation text,p_limit integer DEFAULT 30)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_count integer; v_bucket timestamptz:=date_trunc('minute',now());
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  INSERT INTO public.reception_rate_limits(actor,operation,bucket,count)
  VALUES(auth.uid(),p_operation,v_bucket,1)
  ON CONFLICT(actor,operation,bucket) DO UPDATE SET count=public.reception_rate_limits.count+1
  RETURNING count INTO v_count;
  RETURN v_count<=p_limit;
END $$;

CREATE OR REPLACE FUNCTION public.get_reception_registration_options_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_services jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN
    RETURN jsonb_build_object('code',403,'message','reception_unavailable');
  END IF;
  SELECT COALESCE(o.services,'{}'::jsonb) INTO v_services FROM public.occasions o WHERE o.id=p_occasion;
  RETURN jsonb_build_object('code',200,'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',g.id,'title',g.title) ORDER BY g.title)
    FROM public.user_group_info g WHERE g.occasion=p_occasion AND g.type IS NULL),'[]'::jsonb),
    'accommodations',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.item->>'code','title',x.item->>'title','placeTitle',p.title) ORDER BY x.ordinality)
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_services->'accommodation')='array' THEN v_services->'accommodation' ELSE '[]'::jsonb END)
      WITH ORDINALITY x(item,ordinality) LEFT JOIN public.places p ON p.occasion=p_occasion AND p.id=CASE WHEN x.item->>'reference' ~ '^[0-9]+$' THEN (x.item->>'reference')::bigint END),'[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.create_reception_user_v1(p_occasion bigint,p_command_id uuid,p_profile jsonb,p_group_id bigint DEFAULT NULL,p_accommodation_code text DEFAULT NULL,p_confirm_same_name boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_org bigint; v_user uuid; v_hash text; v_existing public.reception_registrations%rowtype;
  v_name text:=btrim(p_profile->>'name'); v_surname text:=btrim(p_profile->>'surname'); v_email text:=lower(btrim(p_profile->>'email'));
  v_sex text:=p_profile->>'sex'; v_matches jsonb; v_services jsonb:='{}'::jsonb; v_catalog jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('create',20) THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_profile) k WHERE k NOT IN('name','surname','email','sex','phone','birthDate'))
  THEN RETURN jsonb_build_object('code',400,'message','invalid_profile_fields'); END IF;
  IF COALESCE(v_name,'')='' OR COALESCE(v_surname,'')='' OR COALESCE(v_email,'')='' OR position('@' IN v_email)<=1 OR v_sex NOT IN('male','female','unspecified')
  THEN RETURN jsonb_build_object('code',400,'message','required_profile_fields'); END IF;
  v_hash:=encode(digest(jsonb_build_object('profile',p_profile,'group',p_group_id,'accommodation',p_accommodation_code)::text,'sha256'),'hex');
  SELECT * INTO v_existing FROM public.reception_registrations WHERE occasion=p_occasion AND created_by=v_actor AND command_id=p_command_id;
  IF FOUND THEN
    IF v_existing.request_hash<>v_hash THEN RETURN jsonb_build_object('code',409,'message','command_conflict'); END IF;
    SELECT ui.email_readonly INTO v_email FROM public.user_info ui WHERE ui.id=v_existing."user";
    RETURN jsonb_build_object('code',200,'userId',v_existing."user",'email',v_email,'replayed',true);
  END IF;
  SELECT o.organization,COALESCE(o.services,'{}'::jsonb) INTO v_org,v_catalog FROM public.occasions o WHERE o.id=p_occasion FOR SHARE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reception-email:'||v_org::text||':'||v_email,0));
  IF EXISTS(SELECT 1 FROM public.user_info ui WHERE ui.organization=v_org AND lower(btrim(ui.email_readonly))=v_email) THEN
    RETURN jsonb_build_object('code',409,'message','email_already_exists');
  END IF;
  SELECT COALESCE(jsonb_agg(candidate),'[]'::jsonb) INTO v_matches FROM (
    SELECT jsonb_build_object('name',ui.name,'surname',ui.surname,'sex',ui.sex,
      'birthYear',CASE WHEN ui.birth_date IS NULL THEN NULL ELSE extract(year FROM ui.birth_date)::int END,
      'email',CASE WHEN position('@' IN ui.email_readonly)>2 THEN left(ui.email_readonly,1)||'***@'||split_part(ui.email_readonly,'@',2) ELSE '***' END,
      'onOccasion',EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=ui.id)) candidate
    FROM public.user_info ui WHERE ui.organization=v_org AND public.f_unaccent(btrim(ui.name))=public.f_unaccent(v_name)
      AND public.f_unaccent(btrim(ui.surname))=public.f_unaccent(v_surname) ORDER BY ui.created_at NULLS LAST LIMIT 10) q;
  IF jsonb_array_length(v_matches)>0 AND NOT p_confirm_same_name THEN RETURN jsonb_build_object('code',409,'message','same_name_confirmation_required','candidates',v_matches); END IF;
  IF p_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.user_group_info g WHERE g.id=p_group_id AND g.occasion=p_occasion AND g.type IS NULL FOR SHARE)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_group'); END IF;
  IF p_accommodation_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_catalog->'accommodation')='array' THEN v_catalog->'accommodation' ELSE '[]'::jsonb END) x WHERE x->>'code'=p_accommodation_code)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_accommodation'); END IF;
  v_user:=public.create_user_in_organization_with_data_pure(v_org,v_email,v_email,encode(gen_random_bytes(32),'hex'),p_profile-'email');
  IF p_accommodation_code IS NOT NULL THEN v_services:=jsonb_build_object('accommodation',jsonb_build_object(p_accommodation_code,'paid')); END IF;
  INSERT INTO public.occasion_users(occasion,"user",data,services) VALUES(p_occasion,v_user,p_profile,v_services);
  IF p_group_id IS NOT NULL THEN INSERT INTO public.user_groups("user","group",is_admin) VALUES(v_user,p_group_id,false); END IF;
  INSERT INTO public.reception_registrations(occasion,"user",created_by,command_id,request_hash) VALUES(p_occasion,v_user,v_actor,p_command_id,v_hash);
  RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,'replayed',false);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('code',409,'message','email_or_command_conflict');
END $$;

CREATE OR REPLACE FUNCTION public.issue_reception_login_qr_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_token text; v_hash text; v_actor uuid:=auth.uid();
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('issue',30) THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.reception_registrations r WHERE r.occasion=p_occasion AND r."user"=p_user AND r.status='active' AND (r.created_by=v_actor AND r.created_at>now()-interval '30 minutes' OR public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion))) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  v_token:=translate(encode(gen_random_bytes(32),'base64'),E'+/=\n','-_'); v_hash:=encode(digest(v_token,'sha256'),'hex');
  INSERT INTO public.user_login_qr_credentials(occasion,"user",token_hash,created_by) VALUES(p_occasion,p_user,v_hash,v_actor)
  ON CONFLICT(occasion,"user") DO UPDATE SET token_hash=excluded.token_hash,created_by=excluded.created_by,rotated_at=now(),revoked_at=NULL,last_used_at=NULL,use_count=0;
  RETURN jsonb_build_object('code',200,'payload','festapp-login:v1:'||p_occasion::text||':'||v_token);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_reception_login_qr_v1(p_occasion bigint,p_token_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_user uuid; v_email text;
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
  SELECT c."user",(o.organization::text||'+'||au.email_readonly) INTO v_user,v_email
  FROM public.user_login_qr_credentials c JOIN public.occasion_users ou ON (ou.occasion,ou."user")=(c.occasion,c."user")
  JOIN public.user_info au ON au.id=c."user" JOIN public.occasions o ON o.id=c.occasion
  WHERE c.occasion=p_occasion AND c.token_hash=p_token_hash AND c.revoked_at IS NULL
    AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),'$[*] ? (@.code == "reception" && @.is_enabled == true)') FOR UPDATE OF c;
  IF v_user IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('userId',v_user,'authEmail',v_email);
END $$;

CREATE OR REPLACE FUNCTION public.mark_reception_login_qr_used_v1(p_occasion bigint,p_token_hash text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
  UPDATE public.user_login_qr_credentials c SET last_used_at=now(),use_count=use_count+1
  FROM public.occasion_users ou,public.occasions o
  WHERE c.occasion=p_occasion AND c.token_hash=p_token_hash AND c.revoked_at IS NULL
    AND (ou.occasion,ou."user")=(c.occasion,c."user") AND o.id=c.occasion
    AND jsonb_path_exists(COALESCE(o.features,'[]'::jsonb),'$[*] ? (@.code == "reception" && @.is_enabled == true)');
END $$;

CREATE OR REPLACE FUNCTION public.cancel_reception_registration_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_r public.reception_registrations%rowtype; v_actor uuid:=auth.uid();
BEGIN
  SELECT * INTO v_r FROM public.reception_registrations WHERE occasion=p_occasion AND "user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','registration_unavailable'); END IF;
  IF NOT public.get_can_use_reception(p_occasion) OR NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR (v_r.created_by=v_actor AND (v_r.status='cancelled' OR v_r.created_at>now()-interval '30 minutes'))) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  IF v_r.status='cancelled' THEN RETURN jsonb_build_object('code',200,'status',CASE WHEN v_r.auth_revoked_at IS NULL THEN 'domain_blocked_auth_revocation_pending' ELSE 'cancelled' END,'targetUser',p_user); END IF;
  UPDATE public.reception_registrations SET status='cancelled',cancelled_by=v_actor,cancelled_at=now() WHERE occasion=p_occasion AND "user"=p_user;
  PERFORM public.delete_occasion_user(p_user,p_occasion);
  RETURN jsonb_build_object('code',200,'status','domain_blocked_auth_revocation_pending','targetUser',p_user);
END $$;

CREATE OR REPLACE FUNCTION public.mark_reception_auth_revoked_v1(p_occasion bigint,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'not_authorized'; END IF;
UPDATE public.reception_registrations SET auth_revoked_at=now() WHERE occasion=p_occasion AND "user"=p_user AND status='cancelled'; END $$;

CREATE OR REPLACE FUNCTION public.get_my_recent_reception_registrations_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
SELECT CASE WHEN public.get_can_use_reception(p_occasion) THEN COALESCE(jsonb_agg(jsonb_build_object('userId',r."user",'name',ui.name,'surname',ui.surname,'email',ui.email_readonly,'createdAt',r.created_at,'qrUsed',c.last_used_at IS NOT NULL) ORDER BY r.created_at DESC),'[]'::jsonb) ELSE '[]'::jsonb END
FROM public.reception_registrations r JOIN public.user_info ui ON ui.id=r."user" LEFT JOIN public.user_login_qr_credentials c ON (c.occasion,c."user")=(r.occasion,r."user")
WHERE r.occasion=p_occasion AND r.created_by=auth.uid() AND r.status='active' AND r.created_at>now()-interval '30 minutes'; $$;

REVOKE ALL ON FUNCTION public.reception_rate_limit_v1(text,integer),public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text),public.mark_reception_auth_revoked_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_reception_login_qr_v1(bigint,text),public.mark_reception_login_qr_used_v1(bigint,text),public.mark_reception_auth_revoked_v1(bigint,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_reception_registration_options_v1(bigint),public.create_reception_user_v1(bigint,uuid,jsonb,bigint,text,boolean),public.issue_reception_login_qr_v1(bigint,uuid),public.cancel_reception_registration_v1(bigint,uuid),public.get_my_recent_reception_registrations_v1(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.save_occasion_user_for_edit_internal_v1(input_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion bigint := (input_data->>'occasion')::bigint;
    v_user uuid := (input_data->>'user')::uuid;
    v_unit bigint;
    v_data jsonb := CASE WHEN jsonb_typeof(input_data->'data') = 'object'
                         THEN input_data->'data' ELSE '{}'::jsonb END;
    v_services jsonb := CASE WHEN jsonb_typeof(input_data->'services') = 'object'
                             THEN input_data->'services' ELSE '{}'::jsonb END;
    v_catalog jsonb;
    v_existing_services jsonb;
    v_code text;
BEGIN
    SELECT o.unit,
           CASE WHEN jsonb_typeof(o.services) = 'object'
                THEN o.services ELSE '{}'::jsonb END
      INTO v_unit, v_catalog
      FROM public.occasions o
     WHERE o.id = v_occasion;

    IF v_unit IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion not found');
    END IF;

    -- Keep the write boundary at occasion management level. In particular,
    -- a unit editor must not gain the ability to assign manager/editor flags
    -- through this SECURITY DEFINER function.
    IF NOT public.get_is_manager_on_occasion(v_occasion)
       AND NOT public.get_is_admin_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Not authorized to update occasion users');
    END IF;

    SELECT CASE WHEN jsonb_typeof(ou.services) = 'object'
                THEN ou.services ELSE '{}'::jsonb END
      INTO v_existing_services
      FROM public.occasion_users ou
     WHERE ou.occasion = v_occasion AND ou."user" = v_user;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion user not found');
    END IF;

    -- Every assigned accommodation code must still exist in this occasion's
    -- catalog. This keeps the grid select and persisted service data aligned.
    FOR v_code IN
        SELECT key FROM jsonb_each(
            CASE WHEN jsonb_typeof(v_services->'accommodation') = 'object'
                 THEN v_services->'accommodation' ELSE '{}'::jsonb END
        )
    LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(
                  CASE WHEN jsonb_typeof(v_catalog->'accommodation') = 'array'
                       THEN v_catalog->'accommodation' ELSE '[]'::jsonb END
              ) item
             WHERE item->>'code' = v_code
        ) AND NOT COALESCE((
            -- Historical assignments can outlive a removed catalog item.
            -- Preserve such a code on unrelated edits, but never allow a new
            -- unknown code to be introduced.
            jsonb_typeof(v_existing_services->'accommodation') = 'object'
            AND (v_existing_services->'accommodation') ? v_code
        ), false) THEN
            RETURN jsonb_build_object('code', 400, 'message', 'Unknown accommodation code: ' || v_code);
        END IF;
    END LOOP;

    UPDATE public.user_info
       SET data = COALESCE(user_info.data, '{}'::jsonb)
                  || public.get_user_profile_data_patch(v_data),
           name = COALESCE(v_data->>'name', user_info.name),
           surname = COALESCE(v_data->>'surname', user_info.surname),
           sex = COALESCE(v_data->>'sex', user_info.sex),
           phone = CASE
               WHEN v_data ? 'phone' THEN v_data->>'phone'
               ELSE user_info.phone
           END,
           birth_date = CASE
               WHEN v_data ? 'birthDate'
                   THEN NULLIF(v_data->>'birthDate', '')::date
               ELSE user_info.birth_date
           END
     WHERE id = v_user;

    UPDATE public.occasion_users
       SET data = v_data,
           -- A grid may edit only one service family. Merge top-level service
           -- keys so changing accommodation never erases food (and vice versa).
           -- An explicitly supplied empty object still clears that family.
           services = COALESCE(occasion_users.services, '{}'::jsonb) || v_services,
           role = CASE WHEN input_data ? 'role' THEN (input_data->>'role')::int ELSE role END,
           is_editor = COALESCE((input_data->>'is_editor')::boolean, is_editor),
           is_editor_view = COALESCE((input_data->>'is_editor_view')::boolean, is_editor_view),
           is_editor_order = COALESCE((input_data->>'is_editor_order')::boolean, is_editor_order),
           is_editor_order_view = COALESCE((input_data->>'is_editor_order_view')::boolean, is_editor_order_view),
           is_cleaning_crew = COALESCE((input_data->>'is_cleaning_crew')::boolean, is_cleaning_crew),
           is_cleaning_blocked = COALESCE((input_data->>'is_cleaning_blocked')::boolean, is_cleaning_blocked),
           is_receptionist = COALESCE((input_data->>'is_receptionist')::boolean, is_receptionist),
           is_approver = COALESCE((input_data->>'is_approver')::boolean, is_approver),
           is_approved = COALESCE((input_data->>'is_approved')::boolean, is_approved),
           is_manager = COALESCE((input_data->>'is_manager')::boolean, is_manager)
     WHERE occasion = v_occasion AND "user" = v_user;

    RETURN jsonb_build_object('code', 200, 'message', 'Occasion user updated');
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$;

CREATE OR REPLACE FUNCTION public.save_occasion_user_for_edit(input_data jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.save_occasion_user_for_edit_internal_v1(input_data);
$$;

CREATE OR REPLACE FUNCTION public.get_occasion_users_for_edit(
    p_occasion_id BIGINT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    users_data JSON;
    forms_data JSON;
    services_data JSONB;
    org_id BIGINT;
BEGIN
    -- 0. Retrieve the Organization ID
    -- We need this to check against the organization_users table later
    SELECT organization INTO org_id
    FROM public.occasions
    WHERE id = p_occasion_id;

    -- Authorization check: Ensure the user has editor rights for the occasion.
    IF (SELECT get_is_editor_view_on_occasion(p_occasion_id)) <> TRUE AND (SELECT get_is_editor_order_view_on_occasion(p_occasion_id)) <> TRUE THEN
        RETURN json_build_object('code', 403, 'message', 'User is not authorized to view this occasion''s data');
    END IF;

    -- 1. Get all users associated with the occasion. Resolve order and group
    -- metadata once for the whole occasion instead of running correlated
    -- subqueries for every user.
    WITH visible_users AS MATERIALIZED (
        SELECT ou.*
        FROM public.occasion_users ou
        LEFT JOIN public.organization_users org_u
          ON org_u."user" = ou."user"
         AND org_u.organization = org_id
        WHERE ou.occasion = p_occasion_id
          AND org_u.is_hidden IS NOT TRUE
    ),
    order_info AS (
        SELECT DISTINCT ON (opt.ticket)
            opt.ticket,
            o.data->>'form' AS form_id,
            o.created_at
        FROM visible_users vu
        JOIN eshop.order_product_ticket opt ON opt.ticket = vu.ticket
        JOIN eshop.orders o ON o.id = opt."order"
        ORDER BY opt.ticket, opt.id
    ),
    standard_groups AS (
        SELECT
            ug."user",
            string_agg(ugi.title, ', ' ORDER BY ugi.title) AS titles
        FROM visible_users vu
        JOIN public.user_groups ug ON ug."user" = vu."user"
        JOIN public.user_group_info ugi ON ugi.id = ug."group"
        WHERE ugi.occasion = p_occasion_id
          AND ugi.type IS NULL
        GROUP BY ug."user"
    ),
    companion_owners AS (
        SELECT uc.companion, uc."user" AS owner_id, uc.origin,
               concat_ws(' ', owner_info.name, owner_info.surname) AS owner_name
        FROM public.user_companions uc
        JOIN public.user_info owner_info ON owner_info.id = uc."user"
        WHERE uc.occasion = p_occasion_id
    )
    SELECT json_agg(row_to_json(user_row))
    INTO users_data
    FROM (
        SELECT
            vu.occasion,
            vu.created_at,
            vu."user",
            vu.is_editor,
            vu.is_manager,
            vu.is_approved,
            vu.is_approver,
            -- Occasion data remains authoritative for event-specific fields.
            -- Overlay only the dedicated global profile columns; user_info.data
            -- also contains historical occasion fields and must not leak across
            -- events. A LEFT JOIN preserves legacy occasion rows without a
            -- matching user_info record.
            COALESCE(vu.data, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
                'email', ui.email_readonly,
                'name', ui.name,
                'surname', ui.surname,
                'sex', ui.sex,
                'phone', COALESCE(ui.phone, ui.data->>'phone'),
                'birthDate', COALESCE(
                    to_char(ui.birth_date, 'YYYY-MM-DD'),
                    ui.data->>'birthDate'
                )
            )) AS data,
            vu.role,
            vu.services,
            vu.is_editor_view,
            vu.is_editor_order,
            vu.is_editor_order_view,
            vu.is_cleaning_crew,
            vu.is_cleaning_blocked,
            vu.is_receptionist,
            vu.ticket,
            order_info.form_id,
            order_info.created_at AS order_created_at,
            au.last_sign_in_at,
            standard_groups.titles AS group_title,
            companion_owners.owner_id AS companion_owner_id,
            companion_owners.owner_name AS companion_owner_name,
            companion_owners.origin AS companion_origin
        FROM visible_users vu
        LEFT JOIN public.user_info ui ON ui.id = vu."user"
        LEFT JOIN auth.users au ON au.id = vu."user"
        LEFT JOIN order_info ON order_info.ticket = vu.ticket
        LEFT JOIN standard_groups ON standard_groups."user" = vu."user"
        LEFT JOIN companion_owners ON companion_owners.companion = vu."user"
    ) user_row;

    -- 2. Get all forms associated with the occasion, selecting only the specified fields.
    SELECT json_agg(
        json_build_object(
            'key', f.key,
            'type', f.type,
            'id', f.id,
            'title', f.title,
            'link', f.link
        )
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = p_occasion_id;

    -- 3. Return the service catalog in the same RPC response. Both the Users
    -- and Stay tabs need these options to render editable accommodation/food
    -- columns; keeping them here avoids extra requests and PostgREST's 1000-row
    -- cap on direct occasion_users queries.
    SELECT catalog.services || jsonb_build_object(
        'accommodation',
        COALESCE((
            SELECT jsonb_agg(
                service_item.item || jsonb_build_object('place_title', p.title)
                ORDER BY service_item.position
            )
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(catalog.services->'accommodation') = 'array'
                        THEN catalog.services->'accommodation'
                    ELSE '[]'::jsonb
                END
            ) WITH ORDINALITY AS service_item(item, position)
            LEFT JOIN public.places p
              ON p.id = CASE
                  WHEN service_item.item->>'reference' ~ '^[0-9]+$'
                      THEN (service_item.item->>'reference')::bigint
                  ELSE NULL
              END
             AND p.occasion = p_occasion_id
        ), '[]'::jsonb)
    )
    INTO services_data
    FROM (
        SELECT CASE
            WHEN jsonb_typeof(o.services) = 'object' THEN o.services
            ELSE '{}'::jsonb
        END AS services
        FROM public.occasions o
        WHERE o.id = p_occasion_id
    ) catalog;

    -- Assemble the final JSON object without reparsing the complete roster as
    -- JSONB. Both the Users and Stay tabs consume this same bundle.
    RETURN json_build_object(
        'code', 200,
        'message', 'Occasion users and forms retrieved successfully.',
        'data', json_build_object(
            'occasion_users', COALESCE(users_data, '[]'::json),
            'forms',          COALESCE(forms_data, '[]'::json),
            'services',       COALESCE(services_data, '{}'::jsonb)
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_private_profile_payload_v1(
  p_occasion bigint,p_user uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'user',(SELECT jsonb_build_object('id',u.id,'email',u.email_readonly,
      'name',u.name,'surname',u.surname,'sex',u.sex,'phone',u.phone,
      'birthDate',u.birth_date,'data',u.data) FROM public.user_info u
      WHERE u.id=p_user),
    'occasion',(SELECT jsonb_build_object('role',ou.role,'services',ou.services,
      'data',ou.data,'isCleaningBlocked',ou.is_cleaning_blocked,
      'isCleaningCrew',ou.is_cleaning_crew,'isReceptionist',ou.is_receptionist) FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_user),
    'companions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',ui.id,'name',ui.name,'surname',COALESCE(ui.surname,''),
      'group_title',COALESCE(groups.titles,''),'origin',uc.origin,
      'can_owner_delete',uc.origin='self_created',
      'services',COALESCE(companion_membership.services,'{}'::jsonb),
      'event_ids',COALESCE((SELECT jsonb_agg(eu.event ORDER BY eu.event)
        FROM public.event_users eu JOIN public.events e ON e.id=eu.event
        WHERE eu."user"=ui.id AND e.occasion=p_occasion),'[]'::jsonb))
      ORDER BY ui.name,ui.surname,ui.id)
      FROM public.user_companions uc
      JOIN public.user_info ui ON ui.id=uc.companion
      JOIN public.occasion_users companion_membership
        ON companion_membership.occasion=uc.occasion
       AND companion_membership."user"=uc.companion
      LEFT JOIN LATERAL (SELECT string_agg(ugi.title,', ' ORDER BY ugi.title) titles
        FROM public.user_groups ug JOIN public.user_group_info ugi ON ugi.id=ug."group"
        WHERE ug."user"=uc.companion AND ugi.occasion=p_occasion
          AND ugi.type IS NULL) groups ON true
      WHERE uc.occasion=p_occasion AND uc."user"=p_user),'[]'::jsonb),
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

UPDATE public.client_sync_component_sources
SET tracked_columns = array_append(tracked_columns, 'is_receptionist'),
    canonical_writers = array_append(canonical_writers, 'save_occasion_user_for_edit')
WHERE registry_version=1 AND component='private_profile'
  AND source_relation='public.occasion_users'::regclass
  AND NOT ('is_receptionist'=ANY(tracked_columns));

COMMIT;
