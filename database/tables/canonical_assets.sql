-- Exact migrated identity and original ownership; no FK to auth.users: account
-- cleanup runs after Auth deletion and must not lose the durable owner binding.
ALTER TABLE public.account_deletion_requests ADD COLUMN assets_prepared boolean NOT NULL DEFAULT false;
CREATE TABLE public.canonical_assets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 bucket text NOT NULL CHECK(bucket IN ('festapp-images','festapp-images-private')),
 object_key text NOT NULL,
 sha256 text NOT NULL CHECK(sha256 ~ '^[0-9a-f]{64}$'),
 bytes bigint NOT NULL CHECK(bytes>=0),
 content_type text NOT NULL CHECK(length(content_type)>0),
 visibility text NOT NULL CHECK(visibility IN ('public','private')),
 owner_id text,
 source_bucket text NOT NULL,
 source_key text,
 source_storage_record jsonb NOT NULL CHECK(jsonb_typeof(source_storage_record)='object'),
 verified_at timestamptz NOT NULL,
 deleted_at timestamptz,
 UNIQUE(bucket,object_key), UNIQUE(source_bucket,source_key),
 CHECK(deleted_at IS NOT NULL OR (source_key IS NOT NULL AND
   owner_id IS NOT DISTINCT FROM source_storage_record->>'owner_id')),
 CHECK((bucket='festapp-images')=(visibility='public')),
 CHECK(object_key ~ '^(assets|images)/storage/[A-Za-z0-9_-]+/[a-f0-9]{20}/[a-f0-9]{64}/[a-f0-9]{64}$'
   OR object_key ~ '^ticket-fonts/sha256/[a-f0-9]{64}\.(ttf|woff)$'),
 CHECK(CASE WHEN object_key LIKE 'ticket-fonts/%' THEN owner_id IS NULL
   AND bucket='festapp-images-private' ELSE right(object_key,64)=sha256 END)
);
ALTER TABLE public.canonical_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.canonical_assets FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.canonical_asset_cutover (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 active boolean NOT NULL DEFAULT false,
 inventory_sha256 text CHECK(inventory_sha256 ~ '^[0-9a-f]{64}$'),
 CHECK(NOT active OR inventory_sha256 IS NOT NULL)
);
INSERT INTO public.canonical_asset_cutover(singleton) VALUES(true);
REVOKE ALL ON public.canonical_asset_cutover FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.account_deletion_assets (
 request_id uuid NOT NULL REFERENCES public.account_deletion_requests(id),
 asset_id uuid NOT NULL REFERENCES public.canonical_assets(id),
 deleted_at timestamptz,
 PRIMARY KEY(request_id,asset_id)
);
ALTER TABLE public.account_deletion_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_deletion_assets FROM PUBLIC,anon,authenticated,service_role;
