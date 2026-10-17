-- Canonical sources: database/functions/security/data_security_reads.sql

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
