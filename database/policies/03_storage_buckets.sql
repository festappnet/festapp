-- images-temp bucket: insert only if not exists
INSERT INTO storage.buckets (id, name, public, owner, avif_autodetection)
VALUES ('images-temp', 'images-temp', false, null, false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Temp Images Policy" ON storage.objects;
CREATE POLICY "Temp Images Policy" ON storage.objects
AS PERMISSIVE FOR ALL
TO authenticated
USING (get_is_editor_on_any_occasion() AND bucket_id = 'images-temp')
WITH CHECK (get_is_editor_on_any_occasion() AND bucket_id = 'images-temp');

-- editor-files bucket: insert only if not exists
INSERT INTO storage.buckets (id, name, public, owner, avif_autodetection)
VALUES ('editor-files', 'editor-files', false, null, false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Temp Images Policy" ON storage.objects;
CREATE POLICY "Temp Images Policy" ON storage.objects
AS PERMISSIVE FOR ALL
TO authenticated
USING (get_is_editor_on_any_occasion() AND bucket_id = 'editor-files')
WITH CHECK (get_is_editor_on_any_occasion() AND bucket_id = 'editor-files');

-- public-files bucket: insert only if not exists
INSERT INTO storage.buckets (id, name, public, owner, avif_autodetection)
VALUES ('public-files', 'public-files', true, null, false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Public Images Policy" ON storage.objects;
CREATE POLICY "Public Images Policy" ON storage.objects
AS PERMISSIVE FOR ALL
TO authenticated
USING (get_is_editor_on_any_occasion() AND bucket_id = 'public-files')
WITH CHECK (bucket_id = 'public-files');
