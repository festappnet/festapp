-- Rollout gate: upgrade direct-DML clients before activating this migration.
-- RPC SECURITY DEFINER owners remain the only application mutation boundary.
REVOKE INSERT,UPDATE,DELETE ON public.exclusive_groups,public.exclusive_events,
 public.news,public.user_news FROM anon,authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.path_groups,public.place_types FROM anon,authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.events,public.event_groups,public.event_roles,public.event_speakers,public.event_users,public.event_users_saved FROM anon,authenticated;
