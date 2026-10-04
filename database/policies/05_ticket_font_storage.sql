INSERT INTO storage.buckets(id,name,public,file_size_limit)
VALUES ('ticket-fonts','ticket-fonts',false,8388608)
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=8388608;
-- Restrictive policy prevents even unrelated broad permissive client policies
-- from exposing font bytes. Service role bypasses RLS.
DROP POLICY IF EXISTS ticket_fonts_private ON storage.objects;
CREATE POLICY ticket_fonts_private ON storage.objects AS RESTRICTIVE
FOR ALL TO anon,authenticated
USING (bucket_id <> 'ticket-fonts') WITH CHECK (bucket_id <> 'ticket-fonts');
