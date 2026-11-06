import {describe, expect, it} from 'vitest';
import {startLocalUploadRuntime} from '../integration/local-upload-runtime';

describe('image integration fixture target guard', () => {
  it('rejects a remote database before creating a user or worker', async () => {
    await expect(startLocalUploadRuntime('postgresql://db.example.invalid/postgres', 'http://127.0.0.1:55481', 'fixture'))
      .rejects.toThrow('disposable loopback backend');
  });
  it('rejects a production API even with a local database', async () => {
    await expect(startLocalUploadRuntime('postgresql://127.0.0.1:55482/postgres', 'https://api.festapp.net', 'fixture'))
      .rejects.toThrow('disposable loopback backend');
  });
  it('requires explicit local fixture configuration instead of falling back', async () => {
    await expect(startLocalUploadRuntime('', '', '')).rejects.toThrow('are required');
  });
});
