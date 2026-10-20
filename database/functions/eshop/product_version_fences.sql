-- The service cron entrypoint is apply_planned_changes[_client_sync_v1], with version/publication effects.
REVOKE ALL ON FUNCTION public.apply_planned_changes_obsolete_v1() FROM PUBLIC,anon,authenticated,service_role;
-- Direct DML bypasses original editor revisions. Activate only after old-DML clients upgrade.
REVOKE INSERT,UPDATE,DELETE ON eshop.products,eshop.product_types,eshop.product_inventory_contexts FROM anon,authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.forms,public.form_fields,eshop.blueprints,eshop.spots FROM anon,authenticated;
REVOKE ALL ON FUNCTION public.create_form(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
