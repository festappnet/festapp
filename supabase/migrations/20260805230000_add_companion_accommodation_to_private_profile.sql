CREATE OR REPLACE FUNCTION public.get_private_profile_payload_v1(
  p_occasion bigint,p_user uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'user',(SELECT jsonb_build_object('id',u.id,'email',u.email_readonly,
      'name',u.name,'surname',u.surname,'sex',u.sex,'phone',u.phone,
      'birthDate',u.birth_date,'data',u.data) FROM public.user_info u
      WHERE u.id=p_user),
    'occasion',(SELECT jsonb_build_object('role',ou.role,'services',ou.services,
      'data',ou.data,'isCleaningBlocked',ou.is_cleaning_blocked,
      'isCleaningCrew',ou.is_cleaning_crew) FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_user),
    'companions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',ui.id,'name',ui.name,'surname',COALESCE(ui.surname,''),
      'group_title',COALESCE(groups.titles,''),'origin',uc.origin,
      'can_owner_delete',uc.origin='self_created',
      'services',COALESCE(companion_membership.services,'{}'::jsonb),
      'event_ids',COALESCE((SELECT jsonb_agg(eu.event ORDER BY eu.event)
        FROM public.event_users eu JOIN public.events e ON e.id=eu.event
        WHERE eu."user"=ui.id AND e.occasion=p_occasion),'[]'::jsonb))
      ORDER BY ui.name,ui.surname,ui.id)
      FROM public.user_companions uc
      JOIN public.user_info ui ON ui.id=uc.companion
      JOIN public.occasion_users companion_membership
        ON companion_membership.occasion=uc.occasion
       AND companion_membership."user"=uc.companion
      LEFT JOIN LATERAL (SELECT string_agg(ugi.title,', ' ORDER BY ugi.title) titles
        FROM public.user_groups ug JOIN public.user_group_info ugi ON ugi.id=ug."group"
        WHERE ug."user"=uc.companion AND ugi.occasion=p_occasion
          AND ugi.type IS NULL) groups ON true
      WHERE uc.occasion=p_occasion AND uc."user"=p_user),'[]'::jsonb),
    'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',g.id,'title',g.title,'description',g.description,'type',g.type,
      'data',g.data,'place',g.place,'isAdmin',mine.is_admin,
      'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'userId',members."user",'isAdmin',members.is_admin,
        'name',ui.name,'surname',ui.surname) ORDER BY members."user")
        FROM public.user_groups members JOIN public.user_info ui
          ON ui.id=members."user" WHERE members."group"=g.id),'[]'::jsonb),
      'placeData',(SELECT to_jsonb(p) FROM public.places p WHERE p.id=g.place))
      ORDER BY g.id) FROM public.user_groups mine JOIN public.user_group_info g
        ON g.id=mine."group" WHERE mine."user"=p_user
        AND g.occasion=p_occasion),'[]'::jsonb));
$$;

REVOKE ALL ON FUNCTION public.get_private_profile_payload_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
