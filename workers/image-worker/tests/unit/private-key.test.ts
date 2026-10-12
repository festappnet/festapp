import { describe, expect, it } from 'vitest';
import { isPrivateKey } from '../../src/private-key';

describe('private key contract', () => {
  it.each(['private/', 'private/../secret', 'private/a%2fb', 'private/file?name=x', 'private/file#fragment', 42, null])('rejects invalid key %s', (key) => {
    expect(isPrivateKey(key)).toBe(false);
  });
  it('retains legacy canonical keys', () => {
    expect(isPrivateKey('private/236/export-1.pdf')).toBe(true);
  });
});
