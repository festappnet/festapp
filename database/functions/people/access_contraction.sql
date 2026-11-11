-- This RPC was consumed only by the old server-side setup producer, now moved
-- to executeMemberAccess. No application/client uses this sealed-content RPC.
DROP FUNCTION IF EXISTS public.enqueue_occasion_setup_invitation(uuid,text,text,jsonb,text,text);
