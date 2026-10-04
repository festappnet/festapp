-- Access goes through authorized editor RPCs and the service scheduler only.
REVOKE ALL ON TABLE eshop.planned_changes FROM anon,authenticated;
REVOKE ALL ON SEQUENCE eshop.planned_changes_id_seq FROM anon,authenticated;

-- Internal validation shared by immediate writes and scheduled application.
CREATE OR REPLACE FUNCTION public.validate_product_price(p_price numeric, p_data jsonb, p_currency text)
RETURNS void LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_deposit numeric; v_digits integer;
BEGIN
  -- Match ISO currency minor units, including currencies without cents.
  v_digits := CASE WHEN p_currency IN ('JPY','KRW','VND','CLP','ISK','BIF','DJF','GNF','KMF','PYG','RWF','UGX','VUV','XAF','XOF','XPF') THEN 0
    WHEN p_currency IN ('BHD','IQD','JOD','KWD','LYD','OMR','TND') THEN 3 ELSE 2 END;
  -- Current products.price is numeric(10,2); never schedule an unrepresentable target.
  v_digits := least(v_digits,2);
  IF p_price IS NULL OR p_price::text IN ('NaN','Infinity','-Infinity') OR p_price < 0 OR p_price > 99999999.99
    OR p_price <> round(p_price,v_digits) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='INVALID_PRODUCT_PRICE';
  END IF;
  v_deposit := NULLIF(p_data->'deposit'->>'amount','')::numeric;
  IF v_deposit > 0 AND v_deposit >= p_price THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='DEPOSIT_AMOUNT_TOO_HIGH';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.validate_product_price(numeric,jsonb,text) FROM PUBLIC,anon,authenticated;

-- Caller holds the product lock before inspecting plans (also used by form saves).
CREATE OR REPLACE FUNCTION public.validate_product_price_update(p_id bigint, p_price numeric, p_data jsonb, p_currency text)
RETURNS void LANGUAGE plpgsql SET search_path = public, extensions AS $$
DECLARE v_product eshop.products%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_product FROM eshop.products WHERE id=p_id FOR UPDATE;
  PERFORM public.validate_product_price(p_price,p_data,p_currency);
  IF p_currency IS DISTINCT FROM v_product.currency_code AND EXISTS (
    SELECT 1 FROM eshop.planned_changes WHERE subject_id=p_id AND change_type='products.price' AND NOT applied
  ) THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='CANCEL_PRICE_CHANGES_BEFORE_CURRENCY_CHANGE'; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.validate_product_price_update(bigint,numeric,jsonb,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.save_product_price_change(
  p_product_id bigint, p_price numeric, p_change_time timestamptz,
  p_change_id bigint DEFAULT NULL, p_expected_revision bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_product eshop.products%ROWTYPE; v_change eshop.planned_changes%ROWTYPE; v_occasion bigint;
BEGIN
  SELECT p.* INTO STRICT v_product FROM eshop.products p WHERE p.id=p_product_id FOR UPDATE;
  SELECT pt.occasion INTO STRICT v_occasion FROM eshop.product_types pt WHERE pt.id=v_product.product_type;
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.occasions o JOIN public.user_info ui
    ON ui.organization=o.organization WHERE o.id=v_occasion AND ui.id=auth.uid()) THEN
    RAISE insufficient_privilege USING MESSAGE='ORDER_EDITOR_REQUIRED'; END IF;
  PERFORM public.check_is_editor_order_on_occasion(v_occasion);
  IF v_product.occasion IS DISTINCT FROM v_occasion THEN RAISE EXCEPTION 'PRODUCT_OCCASION_MISMATCH'; END IF;
  PERFORM public.validate_product_price(p_price,v_product.data,v_product.currency_code);
  IF p_change_time IS NULL OR NOT isfinite(p_change_time) OR p_change_time <= clock_timestamp() THEN
    RAISE invalid_parameter_value USING MESSAGE='FUTURE_TIME_REQUIRED'; END IF;
  IF p_change_id IS NULL THEN
    IF p_expected_revision IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='INVALID_REVISION'; END IF;
    INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
    VALUES ('products.price',p_product_id,p_price::text,p_change_time,v_occasion) RETURNING * INTO v_change;
  ELSE
    SELECT * INTO v_change FROM eshop.planned_changes WHERE id=p_change_id FOR UPDATE;
    IF NOT FOUND OR v_change.subject_id<>p_product_id OR v_change.change_type<>'products.price'
      OR v_change.applied OR v_change.revision IS DISTINCT FROM p_expected_revision THEN
      RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
    UPDATE eshop.planned_changes SET new_value=p_price::text,change_time=p_change_time,
      occasion=v_occasion,revision=revision+1,failed_at=NULL,failure_code=NULL,
      wave_id=CASE WHEN change_time=p_change_time THEN wave_id ELSE NULL END
      WHERE id=p_change_id RETURNING * INTO v_change;
  END IF;
  RETURN to_jsonb(v_change);
END; $$;
REVOKE ALL ON FUNCTION public.save_product_price_change(bigint,numeric,timestamptz,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_product_price_change(bigint,numeric,timestamptz,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_product_price_change(p_product_id bigint,p_change_id bigint,p_expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_occasion bigint; v_change eshop.planned_changes%ROWTYPE;
BEGIN
  SELECT pt.occasion INTO STRICT v_occasion FROM eshop.products p JOIN eshop.product_types pt
    ON pt.id=p.product_type WHERE p.id=p_product_id FOR UPDATE OF p;
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.occasions o JOIN public.user_info ui
    ON ui.organization=o.organization WHERE o.id=v_occasion AND ui.id=auth.uid()) THEN
    RAISE insufficient_privilege USING MESSAGE='ORDER_EDITOR_REQUIRED'; END IF;
  PERFORM public.check_is_editor_order_on_occasion(v_occasion);
  SELECT * INTO v_change FROM eshop.planned_changes WHERE id=p_change_id FOR UPDATE;
  IF NOT FOUND OR v_change.subject_id<>p_product_id OR v_change.change_type<>'products.price'
    OR v_change.applied OR v_change.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE serialization_failure USING MESSAGE='PRICE_CHANGE_CONFLICT'; END IF;
  DELETE FROM eshop.planned_changes WHERE id=p_change_id;
END; $$;
REVOKE ALL ON FUNCTION public.cancel_product_price_change(bigint,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_product_price_change(bigint,bigint,bigint) TO authenticated;
