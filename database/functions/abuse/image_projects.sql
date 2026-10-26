-- Immutable imported provenance, not a tenant supplied filename convention.
-- Canonical/new organizations belong to default; imported organizations retain
-- their original R2 project. Never infer private ownership from the object key.
CREATE TABLE public.image_project_imports(organization bigint PRIMARY KEY, project text NOT NULL CHECK(project IN ('a','slunovrat')));
ALTER TABLE public.image_project_imports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.image_project_imports FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN
 IF to_regclass('festapp_merge.id_mappings') IS NOT NULL AND to_regclass('festapp_merge.import_runs') IS NOT NULL THEN
  EXECUTE $adopt$INSERT INTO public.image_project_imports
   SELECT DISTINCT m.target_id::bigint,r.source_alias FROM festapp_merge.id_mappings m
   JOIN festapp_merge.import_runs r USING(run_id)
   WHERE m.source_table='public.organizations' AND r.source_alias IN ('a','slunovrat')$adopt$;
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.get_image_project_access_v1(p_project text,p_occasion bigint DEFAULT NULL,p_unit bigint DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE org bigint;
BEGIN
 IF auth.uid() IS NULL OR p_project IS NULL OR p_project NOT IN ('default','a','slunovrat') OR (p_occasion IS NOT NULL AND p_unit IS NOT NULL) THEN RETURN false; END IF;
 IF p_occasion IS NOT NULL OR p_unit IS NOT NULL THEN
  IF public.check_upload_permission(p_occasion,p_unit) IS NOT TRUE THEN RETURN false; END IF;
  IF p_occasion IS NOT NULL THEN SELECT organization INTO org FROM public.occasions WHERE id=p_occasion;
  ELSE SELECT organization INTO org FROM public.units WHERE id=p_unit; END IF;
  RETURN org IS NOT NULL AND coalesce((SELECT project FROM public.image_project_imports WHERE organization=org),'default')=p_project;
 END IF;
 -- Historical private files are intentionally shared among project editors.
 -- Backend consolidation must never broaden that contract across projects.
 IF p_project='slunovrat' THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM public.occasions o
  WHERE coalesce((SELECT project FROM public.image_project_imports WHERE organization=o.organization),'default')=p_project
   AND public.get_is_editor_on_occasion(o.id));
END $$;
REVOKE ALL ON FUNCTION public.get_image_project_access_v1(text,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_image_project_access_v1(text,bigint,bigint) TO authenticated;
