-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); audit jsonb; clean_revision text; wrapper bigint;
BEGIN
 INSERT INTO public.email_wrappers(occasion,html) VALUES((x->>'occasion')::bigint,'<div>{{content}}<p>IBAN CZ6508000000192000145399</p></div>') RETURNING id INTO wrapper;
 SET LOCAL ROLE authenticated;
 audit:=public.get_payment_template_audit((x->>'form')::bigint);
 PERFORM assert_false((audit->>'compatible')::boolean,'effective custom wrapper fixed bank instructions are detected');
 BEGIN PERFORM public.review_payment_templates((x->>'form')::bigint,audit->>'revision'); RAISE EXCEPTION 'incompatible wrapper was approved';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_TEMPLATE_BANK_CONTENT_REQUIRES_REPAIR' THEN RAISE; END IF; END;
 RESET ROLE;
 UPDATE public.email_wrappers SET html='<div>{{content}}</div>' WHERE id=wrapper;
 SET LOCAL ROLE authenticated;
 audit:=public.get_payment_template_audit((x->>'form')::bigint);
 PERFORM assert_true((audit->>'compatible')::boolean,'repaired wrapper is compatible');
 clean_revision:=audit->>'revision';
 audit:=public.review_payment_templates((x->>'form')::bigint,clean_revision);
 PERFORM assert_true((audit->>'reviewed')::boolean,'review binds the exact current revision');
 RESET ROLE;
 INSERT INTO public.email_templates(occasion,code,subject,html) VALUES((x->>'occasion')::bigint,'TICKET_ORDER_CONFIRMATION','Potvrzení','<p>{{accountNumber}}</p>');
 SET LOCAL ROLE authenticated;
 audit:=public.get_payment_template_audit((x->>'form')::bigint);
 PERFORM assert_false((audit->>'reviewed')::boolean,'body changes invalidate the previous wrapper/body review');
 PERFORM assert_false((audit->>'compatible')::boolean,'bank variable in effective body is incompatible for gateway');
 BEGIN PERFORM public.review_payment_templates((x->>'form')::bigint,clean_revision); RAISE EXCEPTION 'stale template revision approved';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_TEMPLATE_REVIEW_STALE' THEN RAISE; END IF; END;
 RESET ROLE;
 PERFORM assert_false(has_table_privilege('authenticated','eshop.payment_template_reviews','UPDATE'),'review storage is private');
END $$;
