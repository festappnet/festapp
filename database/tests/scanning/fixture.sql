-- Only loaded into explicitly isolated local test databases by scanner harnesses.
CREATE OR REPLACE FUNCTION public.scanner_test_fixture(p_count integer DEFAULT 2)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; un bigint; oc bigint; fm bigint; product bigint; tid bigint; oid bigint; h bigint; ids bigint[]:='{}'; i integer;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Scanner isolated fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Scanner fixture',org) RETURNING id INTO un;
 INSERT INTO public.occasions_hidden(secret) VALUES('TEST_'||gen_random_uuid()) RETURNING id INTO h;
 INSERT INTO public.occasions(title,organization,unit,occasion_hidden,features,link,start_time,end_time) VALUES('Testovací akce skeneru',org,un,h,'[]','scanner-test-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO oc;
 UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',oc,NULL,true) WHERE id=oc;
 INSERT INTO public.forms(occasion,title) VALUES(oc,'Scanner fixture') RETURNING id INTO fm;
 INSERT INTO eshop.products(occasion,title,price) VALUES(oc,'Vstup do hlavního sálu',100) RETURNING id INTO product;
 FOR i IN 1..p_count LOOP
  INSERT INTO eshop.tickets(occasion,ticket_symbol,state) VALUES(oc,'SCANNER-'||oc||'-'||i,'sent') RETURNING id INTO tid;
  INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data) VALUES(oc,fm,'sent',public.generate_order_symbol(),i,jsonb_build_object('tickets',jsonb_build_array(jsonb_build_object('id',tid,'name','Alexandra','surname','Novotná')))) RETURNING id INTO oid;
  INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(oid,product,tid);ids:=array_append(ids,tid);
 END LOOP;
 INSERT INTO public.scanner_settings(occasion_id,config) VALUES(oc,public.scanner_default_settings_internal(oc));
 RETURN jsonb_build_object('occasion',oc,'form',fm,'tickets',ids,'scan_code',(SELECT secret FROM public.occasions_hidden WHERE id=h));
END $$;
