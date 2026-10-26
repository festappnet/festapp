DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=991001) OR
    NOT EXISTS(SELECT 1 FROM public.units WHERE id=991001 AND organization=991001) OR
    NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=991001 AND unit=991001 AND organization=991001) THEN
  RAISE EXCEPTION 'upgrade lost entity identities'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=991001 AND occasion=991001 AND payment_info=991001 AND state='ordered' AND price=100) OR
    NOT EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=991001 AND variable_symbol=987654321 AND amount=100 AND paid=0) THEN
  RAISE EXCEPTION 'upgrade changed order/payment identity or reference'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.email_messages WHERE id=991001 AND workflow_state='pending' AND recipient='fixture@example.invalid' AND accepted_at IS NULL AND delivered_at IS NULL) THEN
  RAISE EXCEPTION 'upgrade changed pending email identity or invented a receipt'; END IF;
 IF (SELECT count(*) FROM public.log_emails WHERE occasion=991001 AND template='baseline upgrade audit')<>1 THEN
  RAISE EXCEPTION 'upgrade changed email audit'; END IF;
END $$;
