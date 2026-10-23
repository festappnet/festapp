export type ProjectId = 'default' | 'a' | 'akhweb' | 'slunovrat';

export interface Env {
  IMAGE_PROCESSING_SERVICE_SECRET?: string;
  ASSET_CLEANUP_SERVICE_SECRET?: string;
  TICKET_FONT_SERVICE_SECRET?: string;
  TICKET_BATCH_SERVICE_SECRET?: string;
  IMAGE_READ_MISS_BUDGET?: { limit(input: { key: string }): Promise<{ success: boolean }> };
  IMAGES_BUCKET: R2Bucket;
  IMAGES_BUCKET_AKHWEB: R2Bucket;
  IMAGES_PRIVATE_BUCKET: R2Bucket;
  IMAGES?: any;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  SUPABASE_URL_A: string;
  SUPABASE_ANON_KEY_A: string;
  SUPABASE_URL_AKHWEB: string;
  SUPABASE_ANON_KEY_AKHWEB: string;
  SUPABASE_URL_SLUNOVRAT?: string;
  SUPABASE_ANON_KEY_SLUNOVRAT?: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  CF_ACCOUNT_ID: string;
  CF_ZONE_ID: string;
  CF_CACHE_PURGE_TOKEN: string;
  CONTROL_ALLOWED_ORIGINS: string;
}
