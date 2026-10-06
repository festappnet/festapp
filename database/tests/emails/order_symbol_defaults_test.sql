DO $$
DECLARE c text; t record;
BEGIN
 FOREACH c IN ARRAY ARRAY['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_STORNO','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER'] LOOP
  SELECT * INTO t FROM public.email_templates WHERE code=c AND organization IS NULL AND unit IS NULL AND occasion IS NULL ORDER BY id LIMIT 1;
  PERFORM assert_not_null(t.id,'global default exists');
  PERFORM assert_true(t.subject LIKE '%{{orderSymbol}}%','default subject includes identity');
  PERFORM assert_true(t.html LIKE '%{{orderSymbol}}%' OR t.html LIKE '%{{fullOrder}}%','default body includes identity');
 END LOOP;
END $$;
