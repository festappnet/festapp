-- Application clients no longer delete these rows directly: image metadata is
-- removed through remove_image_records after the canonical asset operation;
-- notification lifecycle belongs to SQL/its trusted delivery worker. Leaving
-- DELETE grants beside historical permissive policies bypasses those owners.
-- Read contracts, service jobs and all other table/column grants stay intact.
REVOKE DELETE ON public.images, public.log_notifications FROM PUBLIC, anon, authenticated;
