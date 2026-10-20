DO $$
DECLARE c text; t record; v_count integer; v_variants integer;
BEGIN
 FOREACH c IN ARRAY ARRAY['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_STORNO','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER'] LOOP
  SELECT count(*), count(DISTINCT (subject,html)) INTO v_count,v_variants
  FROM public.email_templates WHERE code=c AND organization IS NULL AND unit IS NULL AND occasion IS NULL;
  PERFORM assert_true(v_count > 0,'global default exists: ' || c);
  PERFORM assert_eq(v_variants,1,'all imported globals must resolve to identical content: ' || c);
  FOR t IN SELECT * FROM public.email_templates WHERE code=c
    AND organization IS NULL AND unit IS NULL AND occasion IS NULL LOOP
   PERFORM assert_true(t.subject LIKE '%{{orderSymbol}}%','default subject includes identity');
   PERFORM assert_true(t.html LIKE '%{{orderSymbol}}%' OR t.html LIKE '%{{fullOrder}}%','default body includes identity');
   PERFORM assert_false(t.html LIKE '%XYZ%','global content must not contain example organizer/site');
   IF c <> 'TICKET_ORDER_STORNO' THEN
    PERFORM assert_true(t.html LIKE '%{{balanceReasoning}}%','payment state must use the dynamic block: ' || c);
   END IF;
   IF c IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_REMINDER') THEN
    PERFORM assert_true(t.html LIKE '%{{fullOrder}}%','order messages retain the full order: ' || c);
   END IF;
   IF c = 'TICKET_ORDER_CONFIRMATION' THEN
    PERFORM assert_false(t.html ~ '\{\{(amount|accountNumber|variableSymbol|deadline)\}\}',
      'confirmation must not prescribe payment independently of the balance state');
   END IF;
   IF c = 'TICKET_ORDER_UPDATE' THEN
    PERFORM assert_true(t.html LIKE '%{{changeOverview}}%','update retains the change summary');
   END IF;
  END LOOP;
 END LOOP;
END $$;
