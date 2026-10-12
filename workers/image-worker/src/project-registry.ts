import type { Env, ProjectId } from './types';

export interface ProjectConfig {
  id: ProjectId;
  supabaseUrl: string;
  anonKey: string;
  publicBucket: R2Bucket;
  privateBucket: R2Bucket;
  publicBucketName: string;
  privateBucketName: string;
  publicHostname: string;
  authContract: 'festapp' | 'akhweb';
  publicKeyPrefixes: readonly string[];
  supportsPrivate: boolean;
  persistsImageRecords: boolean;
}

export class ProjectResolutionError extends Error {
  readonly code = 'UNKNOWN_PROJECT';
}

export function projectRegistry(env: Env): readonly ProjectConfig[] {
  return [
    { id: 'default', supabaseUrl: env.SUPABASE_URL, anonKey: env.SUPABASE_ANON_KEY,
      publicBucket: env.IMAGES_BUCKET, privateBucket: env.IMAGES_PRIVATE_BUCKET,
      publicBucketName: 'festapp-images', privateBucketName: 'festapp-images-private',
      publicHostname: 'img.festapp.net', authContract: 'festapp',
      publicKeyPrefixes: ['images/'], supportsPrivate: true, persistsImageRecords: true },
    { id: 'a', supabaseUrl: env.SUPABASE_URL_A, anonKey: env.SUPABASE_ANON_KEY_A,
      publicBucket: env.IMAGES_BUCKET_A, privateBucket: env.IMAGES_PRIVATE_BUCKET_A,
      publicBucketName: 'festapp-images-a', privateBucketName: 'festapp-images-a-private',
      publicHostname: 'a.img.festapp.net', authContract: 'festapp',
      publicKeyPrefixes: ['images/'], supportsPrivate: true, persistsImageRecords: true },
    { id: 'akhweb', supabaseUrl: env.SUPABASE_URL_AKHWEB, anonKey: env.SUPABASE_ANON_KEY_AKHWEB,
      publicBucket: env.IMAGES_BUCKET_AKHWEB, privateBucket: env.IMAGES_BUCKET_AKHWEB,
      publicBucketName: 'festapp-images-akhweb', privateBucketName: 'festapp-images-akhweb',
      publicHostname: 'akh.img.festapp.net', authContract: 'akhweb',
      publicKeyPrefixes: ['images/', 'blog/', 'content/'], supportsPrivate: false,
      persistsImageRecords: false },
  ];
}

function requireConfigured(project: ProjectConfig | undefined): ProjectConfig {
  if (!project) throw new ProjectResolutionError('Unknown image project');
  if (!project.supabaseUrl || !project.anonKey || !project.publicBucket || !project.privateBucket) {
    throw new ProjectResolutionError(`Image project ${project.id} is not fully configured`);
  }
  return project;
}

export function resolveProjectById(env: Env, projectId: string | null | undefined): ProjectConfig {
  return requireConfigured(projectRegistry(env).find((project) => project.id === projectId));
}

export function resolveProjectByHostname(env: Env, hostname: string): ProjectConfig {
  return requireConfigured(projectRegistry(env).find((project) => project.publicHostname === hostname));
}

/** Temporary measured-adoption alias. Caller-supplied credentials are ignored. */
export function resolveLegacyProjectBySupabaseUrl(env: Env, value: string): ProjectConfig {
  let origin: string;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.pathname !== '/' || url.search || url.hash) throw new Error();
    origin = url.origin;
  } catch {
    throw new ProjectResolutionError('Invalid Supabase project URL');
  }
  return requireConfigured(projectRegistry(env).find((project) => project.supabaseUrl === origin));
}

export function resolveControlProject(
  env: Env,
  input: { projectId?: string | null; legacySupabaseUrl?: string | null },
): ProjectConfig {
  if (input.projectId) return resolveProjectById(env, input.projectId);
  if (input.legacySupabaseUrl) return resolveLegacyProjectBySupabaseUrl(env, input.legacySupabaseUrl);
  throw new ProjectResolutionError('Missing projectId');
}

export function assertControlHost(project: ProjectConfig, requestUrl: string): void {
  const hostname = new URL(requestUrl).hostname;
  if (hostname !== 'image-api.festapp.net' && hostname !== project.publicHostname) {
    throw new ProjectResolutionError('Control hostname does not match project');
  }
}
