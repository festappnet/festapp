import { describe, expect, it } from 'vitest';
import {
  assertControlHost,
  ProjectResolutionError,
  projectRegistry,
  resolveControlProject,
  resolveProjectByHostname,
  resolveProjectById,
} from '../../src/project-registry';
import type { Env } from '../../src/types';

const publicDefault = { name: 'public-default' } as unknown as R2Bucket;
const privateDefault = { name: 'private-default' } as unknown as R2Bucket;
const publicA = { name: 'public-a' } as unknown as R2Bucket;
const privateA = { name: 'private-a' } as unknown as R2Bucket;
const publicAkh = { name: 'public-akh' } as unknown as R2Bucket;
const env = {
  IMAGES_BUCKET: publicDefault,
  IMAGES_BUCKET_A: publicA,
  IMAGES_PRIVATE_BUCKET: privateDefault,
  IMAGES_PRIVATE_BUCKET_A: privateA,
  IMAGES_BUCKET_AKHWEB: publicAkh,
  SUPABASE_URL: 'https://default.supabase.co',
  SUPABASE_ANON_KEY: 'default-key',
  SUPABASE_URL_A: 'https://a.supabase.co',
  SUPABASE_ANON_KEY_A: 'a-key',
  SUPABASE_URL_AKHWEB: 'https://akh.supabase.co',
  SUPABASE_ANON_KEY_AKHWEB: 'akh-key',
} as Env;

describe('project registry', () => {
  it('registers the inventory-proven projects with explicit contracts', () => {
    expect(projectRegistry(env).map((project) => project.id)).toEqual(['default', 'a', 'akhweb']);
    expect(resolveProjectById(env, 'default').privateBucket).toBe(privateDefault);
    expect(resolveProjectById(env, 'a').publicBucket).toBe(publicA);
    expect(resolveProjectByHostname(env, 'a.img.festapp.net').id).toBe('a');
    expect(resolveProjectByHostname(env, 'akh.img.festapp.net').id).toBe('akhweb');
    expect(resolveProjectById(env, 'akhweb').publicBucket).toBe(publicAkh);
    expect(resolveProjectById(env, 'akhweb').authContract).toBe('akhweb');
  });
  it('fails closed for unknown project and host', () => {
    expect(() => resolveProjectById(env, 'b')).toThrow(ProjectResolutionError);
    expect(() => resolveProjectByHostname(env, 'unknown.example')).toThrow(ProjectResolutionError);
  });
  it('allows only a canonical legacy Supabase URL and ignores caller credentials', () => {
    expect(resolveControlProject(env, { legacySupabaseUrl: 'https://a.supabase.co' }).id).toBe('a');
    expect(() => resolveControlProject(env, { legacySupabaseUrl: 'https://evil.supabase.co' })).toThrow(ProjectResolutionError);
    expect(() => resolveControlProject(env, {})).toThrow(ProjectResolutionError);
  });
  it('rejects a public control hostname that belongs to another project', () => {
    expect(() => assertControlHost(resolveProjectById(env, 'a'), 'https://img.festapp.net/upload'))
      .toThrow(ProjectResolutionError);
    expect(() => assertControlHost(resolveProjectById(env, 'a'), 'https://image-api.festapp.net/upload'))
      .not.toThrow();
  });
});
