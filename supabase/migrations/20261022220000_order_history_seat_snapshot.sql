-- Patch only the nullable-record check. Preserve the installed finalizer and
-- its existing feature dependencies, privileges and admission safeguards.
BEGIN;
DO $$
DECLARE definition text;
 old_check constant text:='IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN';
 new_check constant text:='IF spot_id IS NOT NULL AND spot_product.id IS NOT NULL THEN';
BEGIN
 definition:=pg_get_functiondef('public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean)'::regprocedure);
 IF position(old_check IN definition)>0 THEN
  IF (length(definition)-length(replace(definition,old_check,'')))/length(old_check)<>1 THEN
   RAISE EXCEPTION 'Unexpected finalizer seat-check shape';
  END IF;
  EXECUTE replace(definition,old_check,new_check);
 ELSIF position(new_check IN definition)=0 THEN
  RAISE EXCEPTION 'Expected finalizer seat check not found';
 END IF;
END $$;
COMMIT;
