import type { ProjectConfig } from './project-registry';

/** Physical identity only; SQL authorization always receives the original URL.
 * Historical a keys occupy their own namespace, even when default has the same
 * key with different bytes. AKH keys and its separate bucket stay unchanged.
 */
export function assetKey(project: Pick<ProjectConfig, 'id'>, key: string): string {
  return project.id === 'a' ? `imports/a/${key}` : key;
}
