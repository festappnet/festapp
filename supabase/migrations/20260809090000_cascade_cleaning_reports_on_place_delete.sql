-- Cleaning reports are owned by their toilet place. The canonical map delete
-- command already rejects places referenced by events, groups, and paths, but
-- it previously reached DELETE for a toilet and then failed with an unhandled
-- cleaning_reports_place_fkey violation as soon as that toilet had history.
-- Match cleaning_public_state and remove the owned report history atomically
-- when an editor deliberately deletes the toilet.
ALTER TABLE public.cleaning_reports
  DROP CONSTRAINT cleaning_reports_place_fkey;

ALTER TABLE public.cleaning_reports
  ADD CONSTRAINT cleaning_reports_place_fkey
  FOREIGN KEY (place)
  REFERENCES public.places (id)
  ON DELETE CASCADE;
