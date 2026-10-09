/** The same object key must be used by upload, read, delete and S3 signing. */
export function isPrivateKey(key: unknown): key is string {
  return typeof key === 'string' && key.length <= 1024 &&
    /^private\/[A-Za-z0-9._/-]+$/.test(key) && !key.includes('..');
}
