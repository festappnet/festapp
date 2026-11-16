-- Review records attest exact effective templates, never editable payment tokens.
CREATE TABLE IF NOT EXISTS eshop.payment_template_reviews (
 occasion_id bigint PRIMARY KEY REFERENCES public.occasions(id) ON DELETE CASCADE,
 revision text NOT NULL,reviewed_by uuid NOT NULL,reviewed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.payment_template_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_template_reviews FROM PUBLIC,anon,authenticated,service_role;
-- Monotonic per-occasion epoch prevents A-B-A content changes from reviving a
-- prepared snapshot, without invalidating another organizer's templates.
CREATE TABLE IF NOT EXISTS eshop.payment_template_epochs (
 occasion_id bigint PRIMARY KEY REFERENCES public.occasions(id) ON DELETE CASCADE,
 revision bigint NOT NULL DEFAULT 0
);
ALTER TABLE eshop.payment_template_epochs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_template_epochs FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.payment_template_audit_internal(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE oc public.occasions; code text; resolved jsonb; evidence jsonb:='[]'; blockers jsonb:='[]'; part text; content text; v_revision text;
BEGIN
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=p_occasion;
 FOREACH code IN ARRAY ARRAY['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_STORNO'] LOOP
  resolved:=public.get_email_template_and_wrapper(code,jsonb_build_object('occasion',oc.id,'unit',oc.unit,'organization',oc.organization));
  evidence:=evidence||jsonb_build_array(jsonb_build_object('code',code,'resolved',resolved));
  FOREACH part IN ARRAY ARRAY['template','wrapper'] LOOP
   content:=coalesce(resolved#>>ARRAY[part,'html'],'')||' '||coalesce(resolved#>>ARRAY[part,'subject'],'');
   -- A conservative aid, not a claim to understand arbitrary authored HTML.
   IF content ~* '(\{\{\s*(iban|accountNumber|variableSymbol)\s*\}\}|qr-payment|SPD\*|BCD[[:space:]]|[A-Z]{2}[0-9]{2}[[:space:]]?([A-Z0-9][[:space:]]?){11,30}|[0-9]{2,10}/[0-9]{4})' THEN
    blockers:=blockers||jsonb_build_array(jsonb_build_object('code',code,'location',part,'templateId',resolved#>ARRAY[part,'id'],'reason','authored_bank_instructions'));
   END IF;
  END LOOP;
 END LOOP;
 v_revision:=encode(extensions.digest(jsonb_build_object('templates',evidence,'epoch',coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=oc.id),0))::text,'sha256'),'hex');
 RETURN jsonb_build_object('revision',v_revision,'blockers',blockers,'compatible',jsonb_array_length(blockers)=0,
  'reviewed',EXISTS(SELECT 1 FROM eshop.payment_template_reviews WHERE occasion_id=oc.id AND payment_template_reviews.revision=v_revision));
END $$;
REVOKE ALL ON FUNCTION public.payment_template_audit_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_payment_template_audit(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint;
BEGIN
 SELECT occasion INTO oc FROM public.forms WHERE id=p_form;
 IF oc IS NULL OR NOT public.can_read_occasion_email_templates(oc) THEN RAISE insufficient_privilege; END IF;
 RETURN public.payment_template_audit_internal(oc)||jsonb_build_object('canReview',public.can_write_occasion_email_templates(oc));
END $$;
CREATE OR REPLACE FUNCTION public.review_payment_templates(p_form bigint,p_revision text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; audit jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.forms WHERE id=p_form;
 IF oc IS NULL OR NOT public.can_write_occasion_email_templates(oc) THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('payment-template-review:'||oc,0));
 audit:=public.payment_template_audit_internal(oc);
 IF p_revision IS DISTINCT FROM audit->>'revision' THEN RAISE EXCEPTION 'PAYMENT_TEMPLATE_REVIEW_STALE'; END IF;
 IF audit->'compatible' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_TEMPLATE_BANK_CONTENT_REQUIRES_REPAIR'; END IF;
 INSERT INTO eshop.payment_template_reviews(occasion_id,revision,reviewed_by) VALUES(oc,p_revision,auth.uid())
 ON CONFLICT(occasion_id) DO UPDATE SET revision=excluded.revision,reviewed_by=excluded.reviewed_by,reviewed_at=clock_timestamp();
 RETURN public.payment_template_audit_internal(oc);
END $$;
REVOKE ALL ON FUNCTION public.get_payment_template_audit(bigint),public.review_payment_templates(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_payment_template_audit(bigint),public.review_payment_templates(bigint,text) TO authenticated;

-- Explicit authoring boundary, called before hierarchy/row locks. No persistent
-- application trigger: command owners attest writes in the same transaction.
CREATE OR REPLACE FUNCTION public.payment_template_write_scope_internal(p_context jsonb,p_invalidate boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE org bigint;
BEGIN
 IF p_context IS NULL OR jsonb_typeof(p_context)<>'object' THEN
  RAISE invalid_parameter_value USING MESSAGE='Template write scope required'; END IF;
 FOR org IN SELECT o.id FROM public.organizations o WHERE
  CASE WHEN p_context->>'occasion' IS NOT NULL THEN EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=(p_context->>'occasion')::bigint AND oc.organization=o.id)
   WHEN p_context->>'unit' IS NOT NULL THEN EXISTS(SELECT 1 FROM public.units u WHERE u.id=(p_context->>'unit')::bigint AND u.organization=o.id)
   WHEN p_context->>'organization' IS NOT NULL THEN o.id=(p_context->>'organization')::bigint
   ELSE true END ORDER BY o.id LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('payment-policy:'||org,0));
  IF p_invalidate THEN
   INSERT INTO eshop.payment_template_epochs(occasion_id,revision)
   SELECT oc.id,1 FROM public.occasions oc WHERE oc.organization=org AND
    CASE WHEN p_context->>'occasion' IS NOT NULL THEN oc.id=(p_context->>'occasion')::bigint
     WHEN p_context->>'unit' IS NOT NULL THEN oc.unit=(p_context->>'unit')::bigint
     ELSE true END
   ON CONFLICT(occasion_id) DO UPDATE SET revision=payment_template_epochs.revision+1;
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.payment_template_write_scope_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
-- Retire the earlier local candidate; no installed migration is rewritten.
DROP TRIGGER IF EXISTS payment_template_policy_fence ON public.email_templates;
DROP TRIGGER IF EXISTS payment_template_policy_fence ON public.email_wrappers;
DROP FUNCTION IF EXISTS public.payment_template_policy_fence_internal();
-- All supported runtime authors use the checked definer commands above.
-- Direct API table writes cannot bypass the explicit fence/epoch owner.
REVOKE INSERT,UPDATE,DELETE ON public.email_templates,public.email_wrappers FROM PUBLIC,anon,authenticated,service_role;
