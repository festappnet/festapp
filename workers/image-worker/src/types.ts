export type ProjectId = 'default' | 'a' | 'akhweb';

export interface Env {
  IMAGES_BUCKET: R2Bucket;
  IMAGES_BUCKET_A: R2Bucket;
  IMAGES_BUCKET_AKHWEB: R2Bucket;
  IMAGES_PRIVATE_BUCKET: R2Bucket;
  IMAGES_PRIVATE_BUCKET_A: R2Bucket;
  IMAGES?: any;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_URL_A: string;
  SUPABASE_ANON_KEY_A: string;
  SUPABASE_URL_AKHWEB: string;
  SUPABASE_ANON_KEY_AKHWEB: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  CF_ACCOUNT_ID: string;
  CF_ZONE_ID: string;
  CF_CACHE_PURGE_TOKEN: string;
  CONTROL_ALLOWED_ORIGINS: string;
  PRIVATE_MIGRATION_FALLBACK?: string;
}
