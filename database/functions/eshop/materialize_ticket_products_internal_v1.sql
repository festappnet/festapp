-- Private product materializer. Callers normalize selection, lock capacity/products,
-- and determine ticket identity first. It never creates an order or a ticket.
CREATE OR REPLACE FUNCTION public.materialize_ticket_products_internal_v1(
 order_id bigint,form_id bigint,ticket_id bigint,ticket_data jsonb,spot_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE
 is_editor boolean; occasion_id bigint; spot_data record; spot_product record; spot_id bigint;
 ticket_note text; product_id bigint; ordered_count bigint; field_item jsonb;
 products_array bigint[] := '{}'; product_data record; ticket_products jsonb;
 order_product_ticket_id bigint; first_currency_code text; calculated_price numeric := 0;
 v_product_deposit numeric; v_total_deposit numeric := 0; now timestamptz := clock_timestamp();
BEGIN
 SELECT occasion INTO STRICT occasion_id FROM public.forms WHERE id=form_id;
 is_editor:=coalesce(public.can_write_orders(occasion_id),false);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=order_id AND form=form_id AND occasion=occasion_id)
 OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=ticket_id AND occasion=occasion_id AND state='ordered') THEN
  RAISE EXCEPTION 'TICKET_MATERIALIZATION_SCOPE_MISMATCH'; END IF;
            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT s.* INTO spot_data
                FROM eshop.spots s
                JOIN public.forms f ON f.id=form_id AND f.blueprint=s.blueprint AND f.occasion=s.occasion
                JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=f.blueprint
                WHERE s.id = (ticket_data->>'spot')::BIGINT
                  AND s.occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings b WHERE b.spot=spot_data.id AND b.blocked) OR spot_data.product IS NULL THEN
                    RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (spot_secret::text)::UUID;
                IF (NOT coalesce(is_editor,false) AND
                     (spot_secret IS NULL OR spot_data.secret IS NULL
                      OR spot_data.secret IS DISTINCT FROM spot_secret
                      OR spot_data.secret_expiration_time IS NULL
                      OR spot_data.secret_expiration_time <= clock_timestamp()))
                   OR (coalesce(is_editor,false) AND spot_data.secret IS NOT NULL
                       AND spot_data.secret_expiration_time > clock_timestamp()
                       AND spot_data.secret IS DISTINCT FROM spot_secret) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden)
                  AND NOT EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(form_id) offered
                    WHERE offered.product=product_data.id AND offered.has_capacity) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product.id IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, secret = NULL, secret_expiration_time = NULL, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;


 RETURN jsonb_build_object('products',ticket_products,'price',calculated_price,
  'deposit',v_total_deposit,'currency_code',first_currency_code,'spot',spot_id,'note',ticket_note);
END $$;
REVOKE ALL ON FUNCTION public.materialize_ticket_products_internal_v1(bigint,bigint,bigint,jsonb,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
