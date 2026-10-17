----------------------------------------------------------------
-- public.email_templates
----------------------------------------------------------------


----------------------------------------------------------------
-- public.event_groups
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable delete for editors" ON public.event_groups;
CREATE POLICY "Enable delete for editors" ON public.event_groups
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_groups.event_parent))));

DROP POLICY IF EXISTS "Enable update for editors" ON public.event_groups;
CREATE POLICY "Enable update for editors" ON public.event_groups
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_groups.event_parent))))
WITH CHECK (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_groups.event_parent))));

DROP POLICY IF EXISTS "Enable select for editors" ON public.event_groups;
CREATE POLICY "Enable select for editors" ON public.event_groups
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_groups.event_parent))));

DROP POLICY IF EXISTS "Enable read for all" ON public.event_groups;
CREATE POLICY "Enable read for all" ON public.event_groups
AS PERMISSIVE FOR SELECT
TO public
USING (true);

DROP POLICY IF EXISTS "Enable insert for editors" ON public.event_groups;
CREATE POLICY "Enable insert for editors" ON public.event_groups
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_groups.event_parent))));

----------------------------------------------------------------
-- public.event_roles
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable update for editors" ON public.event_roles;
CREATE POLICY "Enable update for editors" ON public.event_roles
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_roles.event))))
WITH CHECK (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_roles.event))));

DROP POLICY IF EXISTS "Enable select for editors" ON public.event_roles;
CREATE POLICY "Enable select for editors" ON public.event_roles
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_roles.event))));

DROP POLICY IF EXISTS "Enable insert for editors" ON public.event_roles;
CREATE POLICY "Enable insert for editors" ON public.event_roles
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_roles.event))));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.event_roles;
CREATE POLICY "Enable delete for editors" ON public.event_roles
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT events.occasion
   FROM events
  WHERE (events.id = event_roles.event))));

----------------------------------------------------------------
-- public.event_users
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable read for all" ON public.event_users;
CREATE POLICY "Enable read for all" ON public.event_users
AS PERMISSIVE FOR SELECT
TO public
USING (true);

DROP POLICY IF EXISTS "Enable all on own record" ON public.event_users;
CREATE POLICY "Enable all on own record" ON public.event_users
AS PERMISSIVE FOR ALL
TO authenticated
USING ((auth.uid() = "user"))
WITH CHECK ((auth.uid() = "user"));

----------------------------------------------------------------
-- public.event_users_saved
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable all on own record" ON public.event_users_saved;
CREATE POLICY "Enable all on own record" ON public.event_users_saved
AS PERMISSIVE FOR ALL
TO authenticated
USING ((auth.uid() = "user"))
WITH CHECK ((auth.uid() = "user"));

----------------------------------------------------------------
-- public.events
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for editors" ON public.events;
CREATE POLICY "Enable select for editors" ON public.events
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.events;
CREATE POLICY "Enable delete for editors" ON public.events
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable insert for editors" ON public.events;
CREATE POLICY "Enable insert for editors" ON public.events
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable read for all" ON public.events;
CREATE POLICY "Enable read for all" ON public.events
AS PERMISSIVE FOR SELECT
TO public
USING (get_is_event_allowed(id));

DROP POLICY IF EXISTS "Enable update for editors" ON public.events;
CREATE POLICY "Enable update for editors" ON public.events
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

----------------------------------------------------------------
-- public.exclusive_events
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable delete for editors" ON public.exclusive_events;
CREATE POLICY "Enable delete for editors" ON public.exclusive_events
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT exclusive_groups.occasion
   FROM exclusive_groups
  WHERE (exclusive_groups.id = exclusive_events."group"))));

DROP POLICY IF EXISTS "Enable update for editors" ON public.exclusive_events;
CREATE POLICY "Enable update for editors" ON public.exclusive_events
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT exclusive_groups.occasion
   FROM exclusive_groups
  WHERE (exclusive_groups.id = exclusive_events."group"))))
WITH CHECK (get_is_editor_on_occasion(( SELECT exclusive_groups.occasion
   FROM exclusive_groups
  WHERE (exclusive_groups.id = exclusive_events."group"))));

DROP POLICY IF EXISTS "Enable select to all auth" ON public.exclusive_events;
CREATE POLICY "Enable select to all auth" ON public.exclusive_events
AS PERMISSIVE FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Enable select for editors" ON public.exclusive_events;

DROP POLICY IF EXISTS "Enable insert for editors" ON public.exclusive_events;
CREATE POLICY "Enable insert for editors" ON public.exclusive_events
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(( SELECT exclusive_groups.occasion
   FROM exclusive_groups
  WHERE (exclusive_groups.id = exclusive_events."group"))));

----------------------------------------------------------------
-- public.exclusive_groups
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for editors" ON public.exclusive_groups;

DROP POLICY IF EXISTS "Enable select to all auth" ON public.exclusive_groups;
CREATE POLICY "Enable select to all auth" ON public.exclusive_groups
AS PERMISSIVE FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Enable update for editors" ON public.exclusive_groups;
CREATE POLICY "Enable update for editors" ON public.exclusive_groups
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable insert for editors" ON public.exclusive_groups;
CREATE POLICY "Enable insert for editors" ON public.exclusive_groups
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.exclusive_groups;
CREATE POLICY "Enable delete for editors" ON public.exclusive_groups
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

----------------------------------------------------------------
-- public.form_fields
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for editors" ON public.form_fields;
CREATE POLICY "Enable select for editors" ON public.form_fields
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(( SELECT forms.occasion
   FROM forms
  WHERE (forms.id = form_fields.form))));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.form_fields;
CREATE POLICY "Enable delete for editors" ON public.form_fields
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT forms.occasion
   FROM forms
  WHERE (forms.id = form_fields.form))));

DROP POLICY IF EXISTS "Enable insert for editors" ON public.form_fields;
CREATE POLICY "Enable insert for editors" ON public.form_fields
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(( SELECT forms.occasion
   FROM forms
  WHERE (forms.id = form_fields.form))));

DROP POLICY IF EXISTS "Enable read for editor_view" ON public.form_fields;
CREATE POLICY "Enable read for editor_view" ON public.form_fields
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(( SELECT forms.occasion
   FROM forms
  WHERE (forms.id = form_fields.form))));

DROP POLICY IF EXISTS "Enable update for editors" ON public.form_fields;
CREATE POLICY "Enable update for editors" ON public.form_fields
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT forms.occasion
   FROM forms
  WHERE (forms.id = form_fields.form))))
WITH CHECK (get_is_editor_on_occasion(( SELECT forms.occasion
   FROM forms
  WHERE (forms.id = form_fields.form))));

----------------------------------------------------------------
-- public.forms
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable insert for editors" ON public.forms;
CREATE POLICY "Enable insert for editors" ON public.forms
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable select for editors" ON public.forms;
CREATE POLICY "Enable select for editors" ON public.forms
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable update for editors" ON public.forms;
CREATE POLICY "Enable update for editors" ON public.forms
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.forms;
CREATE POLICY "Enable delete for editors" ON public.forms
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable read for editor_view" ON public.forms;
CREATE POLICY "Enable read for editor_view" ON public.forms
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

----------------------------------------------------------------
-- public.icons
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for all" ON public.icons;
CREATE POLICY "Enable select for all" ON public.icons
AS PERMISSIVE FOR SELECT
TO public
USING (true);

----------------------------------------------------------------
-- public.images
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for editors" ON public.images;
DROP POLICY IF EXISTS "Enable delete for editors" ON public.images;
DROP POLICY IF EXISTS "Enable insert for editors" ON public.images;
DROP POLICY IF EXISTS "Enable update for editors" ON public.images;

DROP POLICY IF EXISTS "Enable all for unit editors" ON public.images;
CREATE POLICY "Enable all for unit editors" ON public.images
AS PERMISSIVE FOR ALL
TO authenticated
USING (get_is_editor_on_unit((select unit from occasions where id = occasion)))
WITH CHECK (get_is_editor_on_unit((select unit from occasions where id = occasion)));

DROP POLICY IF EXISTS "Enable all for editors" ON public.images;
CREATE POLICY "Enable all for editors" ON public.images
AS PERMISSIVE FOR ALL
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

----------------------------------------------------------------
-- public.information
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable delete for editors" ON public.information;
CREATE POLICY "Enable delete for editors" ON public.information
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable all for unit editors" ON public.information;
CREATE POLICY "Enable all for unit editors" ON public.information
AS PERMISSIVE FOR ALL
TO authenticated
USING (get_is_editor_on_unit(unit))
WITH CHECK (get_is_editor_on_unit(unit));

DROP POLICY IF EXISTS "Enable update for editors" ON public.information;
CREATE POLICY "Enable update for editors" ON public.information
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable select for editors" ON public.information;
CREATE POLICY "Enable select for editors" ON public.information
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable read for all" ON public.information;
CREATE POLICY "Enable read for all" ON public.information
AS PERMISSIVE FOR SELECT
TO public
USING (true);

DROP POLICY IF EXISTS "Enable insert for editors" ON public.information;
CREATE POLICY "Enable insert for editors" ON public.information
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

----------------------------------------------------------------
-- public.information_hidden
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for editors" ON public.information_hidden;
CREATE POLICY "Enable select for editors" ON public.information_hidden
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.information_hidden;
CREATE POLICY "Enable delete for editors" ON public.information_hidden
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable insert for editors" ON public.information_hidden;
CREATE POLICY "Enable insert for editors" ON public.information_hidden
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable update for editors" ON public.information_hidden;
CREATE POLICY "Enable update for editors" ON public.information_hidden
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

----------------------------------------------------------------
-- public.log_notifications
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable insert for editors" ON public.log_notifications;
CREATE POLICY "Enable insert for editors" ON public.log_notifications
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.log_notifications;
CREATE POLICY "Enable delete for editors" ON public.log_notifications
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable update for editors" ON public.log_notifications;
CREATE POLICY "Enable update for editors" ON public.log_notifications
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable select for editors" ON public.log_notifications;
CREATE POLICY "Enable select for editors" ON public.log_notifications
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

----------------------------------------------------------------
-- public.news
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable insert for editors" ON public.news;
CREATE POLICY "Enable insert for editors" ON public.news
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable read for all" ON public.news;
CREATE POLICY "Enable read for all" ON public.news
AS PERMISSIVE FOR SELECT
TO public
USING (true);

DROP POLICY IF EXISTS "Enable update for editors" ON public.news;
CREATE POLICY "Enable update for editors" ON public.news
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable select for editors" ON public.news;
CREATE POLICY "Enable select for editors" ON public.news
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.news;
CREATE POLICY "Enable delete for editors" ON public.news
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

----------------------------------------------------------------
-- public.occasion_users
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select on own record" ON public.occasion_users;
CREATE POLICY "Enable select on own record" ON public.occasion_users
AS PERMISSIVE FOR SELECT
TO authenticated
USING ((auth.uid() = "user"));

DROP POLICY IF EXISTS "Enable all for managers" ON public.occasion_users;
CREATE POLICY "Enable all for managers" ON public.occasion_users
AS PERMISSIVE FOR ALL
TO authenticated
USING ((get_is_manager_on_occasion(occasion) OR get_is_admin_on_occasion(occasion)))
WITH CHECK ((get_is_manager_on_occasion(occasion) OR get_is_admin_on_occasion(occasion)));

DROP POLICY IF EXISTS "Enable read for editors" ON public.occasion_users;
CREATE POLICY "Enable read for editors" ON public.occasion_users
AS PERMISSIVE FOR SELECT
TO public
USING (get_is_editor_view_on_occasion(occasion));

----------------------------------------------------------------
-- public.occasions
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable all for admins" ON public.occasions;
CREATE POLICY "Enable all for admins" ON public.occasions
AS PERMISSIVE FOR ALL
TO authenticated
USING (get_is_admin_on_organization(organization))
WITH CHECK (get_is_admin_on_organization(organization));


----------------------------------------------------------------
-- public.places
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable update for editors" ON public.places;
CREATE POLICY "Enable update for editors" ON public.places
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));


DROP POLICY IF EXISTS "Enable insert for editors" ON public.places;
CREATE POLICY "Enable insert for editors" ON public.places
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.places;
CREATE POLICY "Enable delete for editors" ON public.places
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable select for editors" ON public.places;
CREATE POLICY "Enable select for editors" ON public.places
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

----------------------------------------------------------------
-- public.place_types
--   Per-occasion place categories: public read, editor write.
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable read for all" ON public.place_types;
CREATE POLICY "Enable read for all" ON public.place_types
AS PERMISSIVE FOR SELECT
TO public
USING (true);

DROP POLICY IF EXISTS "Enable insert for editors" ON public.place_types;
CREATE POLICY "Enable insert for editors" ON public.place_types
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable update for editors" ON public.place_types;
CREATE POLICY "Enable update for editors" ON public.place_types
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.place_types;
CREATE POLICY "Enable delete for editors" ON public.place_types
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

----------------------------------------------------------------
-- public.cleaning_reports
--   Writes go exclusively through SECURITY DEFINER RPCs
--   (report_cleaning_issue / resolve_cleaning_place); the cleaning crew
--   reads via get_cleaning_reports. Direct SELECT is limited to editors.
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for editors" ON public.cleaning_reports;
CREATE POLICY "Enable select for editors" ON public.cleaning_reports
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

----------------------------------------------------------------
-- public.role_info
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for auth" ON public.role_info;
CREATE POLICY "Enable select for auth" ON public.role_info
AS PERMISSIVE FOR SELECT
TO authenticated
USING (true);

----------------------------------------------------------------
-- public.user_group_info
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable insert for editors" ON public.user_group_info;
CREATE POLICY "Enable insert for editors" ON public.user_group_info
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable delete for editors" ON public.user_group_info;
CREATE POLICY "Enable delete for editors" ON public.user_group_info
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable update for editors" ON public.user_group_info;
CREATE POLICY "Enable update for editors" ON public.user_group_info
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(occasion))
WITH CHECK (get_is_editor_on_occasion(occasion));


DROP POLICY IF EXISTS "Enable select for editors" ON public.user_group_info;
CREATE POLICY "Enable select for editors" ON public.user_group_info
AS PERMISSIVE FOR SELECT
TO authenticated
USING (get_is_editor_view_on_occasion(occasion));

----------------------------------------------------------------
-- public.user_groups
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable delete for editors" ON public.user_groups;
CREATE POLICY "Enable delete for editors" ON public.user_groups
AS PERMISSIVE FOR DELETE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT user_group_info.occasion
   FROM user_group_info
  WHERE (user_group_info.id = user_groups."group"))));

DROP POLICY IF EXISTS "Enable update for editors" ON public.user_groups;
CREATE POLICY "Enable update for editors" ON public.user_groups
AS PERMISSIVE FOR UPDATE
TO authenticated
USING (get_is_editor_on_occasion(( SELECT user_group_info.occasion
   FROM user_group_info
  WHERE (user_group_info.id = user_groups."group"))))
WITH CHECK (get_is_editor_on_occasion(( SELECT user_group_info.occasion
   FROM user_group_info
  WHERE (user_group_info.id = user_groups."group"))));



DROP POLICY IF EXISTS "Enable insert for editors" ON public.user_groups;
CREATE POLICY "Enable insert for editors" ON public.user_groups
AS PERMISSIVE FOR INSERT
TO authenticated
WITH CHECK (get_is_editor_on_occasion(( SELECT user_group_info.occasion
   FROM user_group_info
  WHERE (user_group_info.id = user_groups."group"))));

----------------------------------------------------------------
-- public.user_info
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable all on own record" ON public.user_info;
CREATE POLICY "Enable all on own record" ON public.user_info
AS PERMISSIVE FOR ALL
TO authenticated
USING ((auth.uid() = id))
WITH CHECK ((auth.uid() = id));

----------------------------------------------------------------
-- public.user_news
----------------------------------------------------------------



----------------------------------------------------------------
-- public.path_groups
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for all" ON public.path_groups;
CREATE POLICY "Enable select for all" ON public.path_groups
  AS PERMISSIVE FOR SELECT
  TO public
  USING (true);

DROP POLICY IF EXISTS "Enable update for editors" ON public.path_groups;
CREATE POLICY "Enable update for editors" ON public.path_groups
  AS PERMISSIVE FOR UPDATE
  TO authenticated
  USING (get_is_editor_on_occasion(occasion))
  WITH CHECK (get_is_editor_on_occasion(occasion));

DROP POLICY IF EXISTS "Enable insert for editors" ON public.path_groups;
CREATE POLICY "Enable insert for editors" ON public.path_groups
  AS PERMISSIVE FOR INSERT
  TO authenticated
  WITH CHECK (get_is_editor_on_occasion(occasion));



----------------------------------------------------------------
-- public.speakers (writes only via SECURITY DEFINER RPCs)
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for all" ON public.speakers;
CREATE POLICY "Enable select for all" ON public.speakers
AS PERMISSIVE FOR SELECT
TO public
USING (true);

----------------------------------------------------------------
-- public.speaker_topics (writes only via SECURITY DEFINER RPCs)
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for all" ON public.speaker_topics;
CREATE POLICY "Enable select for all" ON public.speaker_topics
AS PERMISSIVE FOR SELECT
TO public
USING (true);

----------------------------------------------------------------
-- public.speaker_topic_links (writes only via SECURITY DEFINER RPCs)
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for all" ON public.speaker_topic_links;
CREATE POLICY "Enable select for all" ON public.speaker_topic_links
AS PERMISSIVE FOR SELECT
TO public
USING (true);

----------------------------------------------------------------
-- public.event_speakers (writes only via SECURITY DEFINER RPCs)
----------------------------------------------------------------

DROP POLICY IF EXISTS "Enable select for all" ON public.event_speakers;
CREATE POLICY "Enable select for all" ON public.event_speakers
AS PERMISSIVE FOR SELECT
TO public
USING (true);

-- Canonical scoped data-security policies and grants.
-- Narrow compatibility reads. All writes belong to existing domain commands.
CREATE OR REPLACE FUNCTION public.can_read_group_data_security_v1(p_group bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS (
 SELECT 1 FROM public.user_group_info g WHERE g.id=p_group AND (
   public.get_is_editor_view_on_occasion(g.occasion) OR EXISTS (
   SELECT 1 FROM public.user_groups ug WHERE ug."group"=g.id AND ug."user"=auth.uid())));
$$;
REVOKE ALL ON FUNCTION public.can_read_group_data_security_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_group_data_security_v1(bigint) TO authenticated,service_role;

DROP POLICY IF EXISTS "Enable select to all auth" ON public.user_group_info;
DROP POLICY IF EXISTS "Enable select to all auth" ON public.user_groups;
DROP POLICY IF EXISTS "Enable select for editors" ON public.user_groups;
DROP POLICY IF EXISTS data_security_group_info_read ON public.user_group_info;
CREATE POLICY data_security_group_info_read ON public.user_group_info FOR SELECT TO authenticated
 USING(public.can_read_group_data_security_v1(id));
DROP POLICY IF EXISTS data_security_group_members_read ON public.user_groups;
CREATE POLICY data_security_group_members_read ON public.user_groups FOR SELECT TO authenticated
 USING(public.can_read_group_data_security_v1("group"));
REVOKE ALL ON public.user_group_info,public.user_groups FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.user_group_info,public.user_groups TO authenticated;

DROP POLICY IF EXISTS "select for all" ON public.user_news;
DROP POLICY IF EXISTS "Enable all on own record" ON public.user_news;
DROP POLICY IF EXISTS "Enable all for editors" ON public.user_news;
DROP POLICY IF EXISTS data_security_own_news_read ON public.user_news;
CREATE POLICY data_security_own_news_read ON public.user_news FOR SELECT TO authenticated
 USING("user"=auth.uid() AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=user_news.occasion AND ou."user"=auth.uid()));
REVOKE ALL ON public.user_news FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.user_news TO authenticated;
-- News DML must not bypass command receipts/revisions on non-sync occasions.
REVOKE INSERT,UPDATE,DELETE ON public.news FROM PUBLIC,anon,authenticated;

DROP POLICY IF EXISTS "Enable read for all" ON public.places;
CREATE POLICY "Enable read for all" ON public.places FOR SELECT TO public
 USING(is_hidden IS DISTINCT FROM true AND type IS DISTINCT FROM 'group');
-- Group locations, including malformed public group rows, are scoped by the DTO.
DROP POLICY IF EXISTS "Enable read for all" ON public.occasions;
DROP POLICY IF EXISTS data_security_occasion_context_read ON public.occasions;
CREATE POLICY data_security_occasion_context_read ON public.occasions FOR SELECT TO authenticated
 USING(public.get_is_editor_view_on_occasion(id) OR public.get_is_manager_on_occasion(id)
 OR EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=occasions.id AND ou."user"=auth.uid()));
REVOKE SELECT ON public.occasions FROM PUBLIC,anon;

DROP POLICY IF EXISTS "Enable select for managers and admins" ON public.email_templates;
REVOKE SELECT ON public.email_templates FROM PUBLIC,anon,authenticated;

ALTER FUNCTION public.can_read_group_data_security_v1(bigint) OWNER TO postgres;

-- Public news remains a catalog; hidden/closed occasion content is scoped.
CREATE OR REPLACE FUNCTION public.can_read_news_data_security_v1(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.occasions o WHERE o.id=p_occasion AND (
   (o.is_hidden IS FALSE AND o.is_open IS TRUE) OR
   auth.uid() IS NOT NULL AND (public.get_is_editor_view_on_occasion(o.id)
   OR public.get_is_manager_on_occasion(o.id) OR public.get_is_admin_on_occasion(o.id)
   OR EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=o.id AND ou."user"=auth.uid()))));
$$;
REVOKE ALL ON FUNCTION public.can_read_news_data_security_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.can_read_news_data_security_v1(bigint) TO anon,authenticated,service_role;
ALTER FUNCTION public.can_read_news_data_security_v1(bigint) OWNER TO postgres;
DROP POLICY IF EXISTS data_security_news_context_read ON public.news;
CREATE POLICY data_security_news_context_read ON public.news AS RESTRICTIVE FOR SELECT TO public
 USING(public.can_read_news_data_security_v1(occasion));
