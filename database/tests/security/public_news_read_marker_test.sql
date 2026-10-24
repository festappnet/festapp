BEGIN;
DO $$
DECLARE org bigint; other_org bigint; oc bigint; hidden_oc bigint; reader uuid:=gen_random_uuid(); foreign_user uuid:=gen_random_uuid();
 news_id bigint; old_news bigint; hidden_news bigint; command uuid:=gen_random_uuid(); response jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Public news regression') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other news tenant') RETURNING id INTO other_org;
 INSERT INTO public.occasions(organization,title,link,is_open,is_hidden,start_time,end_time)
 VALUES(org,'Public news',gen_random_uuid()::text,true,false,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,title,link,is_open,is_hidden,start_time,end_time)
 VALUES(org,'Private news',gen_random_uuid()::text,false,true,now(),now()+interval '1 day') RETURNING id INTO hidden_oc;
 INSERT INTO auth.users(id) VALUES(reader),(foreign_user);
 INSERT INTO public.user_info(id,organization) VALUES(reader,org),(foreign_user,other_org);
 INSERT INTO public.news(occasion,message) VALUES(oc,'Older') RETURNING id INTO old_news;
 INSERT INTO public.news(occasion,message) VALUES(oc,'Public announcement') RETURNING id INTO news_id;
 INSERT INTO public.news(occasion,message) VALUES(hidden_oc,'Private') RETURNING id INTO hidden_news;
 PERFORM set_config('request.jwt.claim.sub',reader::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_eq(jsonb_array_length(public.get_news_for_context_v1(oc)),2,'visitor can see news');
 response:=public.mark_news_read_client_sync_v1(oc,news_id,command);
 PERFORM assert_eq((response->>'code')::int,200,'public visitor without membership can record own read');
 PERFORM assert_eq((public.get_news_read_state_v1(oc)->>'newsId')::bigint,news_id,'visitor can read own marker');
 PERFORM assert_eq((SELECT count(*) FROM public.occasion_users WHERE occasion=oc AND "user"=reader),0::bigint,'reading does not join occasion');
 PERFORM assert_eq((SELECT views FROM public.get_news_with_views(oc) WHERE id=news_id),1::bigint,'view count includes public visitor');
 response:=public.mark_news_read_client_sync_v1(oc,news_id,command);
 PERFORM assert_eq((response#>>'{mutation,receiptId}')::uuid,command,'same command returns original receipt');
 PERFORM assert_eq((SELECT count(*) FROM public.user_news WHERE occasion=oc AND "user"=reader),1::bigint,'replay does not duplicate marker');
 response:=public.mark_news_read_client_sync_v1(oc,old_news,gen_random_uuid());
 PERFORM assert_eq((public.get_news_read_state_v1(oc)->>'newsId')::bigint,news_id,'delayed old read never decreases marker');
 response:=public.mark_news_read_client_sync_v1(hidden_oc,hidden_news,gen_random_uuid());
 PERFORM assert_eq((response->>'code')::int,403,'private news remains protected');
 UPDATE public.occasions SET is_open=false,is_hidden=true WHERE id=oc;
 response:=public.mark_news_read_client_sync_v1(oc,news_id,command);
 PERFORM assert_eq((response->>'code')::int,403,'receipt cannot bypass revoked access');
 UPDATE public.occasions SET is_open=true,is_hidden=false WHERE id=oc;
 PERFORM set_config('request.jwt.claim.sub',foreign_user::text,true);
 response:=public.mark_news_read_client_sync_v1(oc,news_id,gen_random_uuid());
 PERFORM assert_eq((response->>'code')::int,403,'other tenant identity cannot write marker');
 PERFORM set_config('request.jwt.claim.sub','',true);
 response:=public.mark_news_read_client_sync_v1(oc,news_id,gen_random_uuid());
 PERFORM assert_eq((response->>'code')::int,403,'anonymous identity cannot write marker');
END $$;
ROLLBACK;
