-- Patch semantics belong to explicit RPC boundaries. A table-wide merge
-- trigger cannot distinguish an omitted import field from an intentional key
-- deletion in another workflow (for example clearing cleaning block audit
-- metadata), so remove the previously deployed compatibility trigger.
DROP TRIGGER IF EXISTS preserve_occasion_user_state_on_update
ON public.occasion_users;

DROP FUNCTION IF EXISTS public.preserve_occasion_user_state_on_update();
