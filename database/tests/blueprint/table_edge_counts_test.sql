BEGIN;
DO $$
DECLARE rules jsonb:=public.blueprint_contract_metadata_internal()->'seating'; invalid jsonb;
BEGIN
 PERFORM public.blueprint_validate_leaves_internal('{"edgeCounts":[0,8,1,8]}',rules);
 PERFORM public.blueprint_validate_leaves_internal('{"edgeCounts":[0,0,0,0]}',rules);
 PERFORM public.blueprint_validate_leaves_internal('{"width":32,"gap":4}',rules);
 FOR invalid IN SELECT * FROM jsonb_array_elements('[[],[1,2,3],[1,2,3,4,5],[0,0,-1,0],[0,0,20001,0],[0,0,1.5,0],[0,0,"1",0],[0,0,null,0],null,{}]') LOOP
  BEGIN
   PERFORM public.blueprint_validate_leaves_internal(jsonb_build_object('edgeCounts',invalid),rules);
   RAISE EXCEPTION 'Invalid table edge counts accepted: %',invalid;
  EXCEPTION WHEN check_violation THEN NULL;
  END;
 END LOOP;
END $$;
ROLLBACK;
