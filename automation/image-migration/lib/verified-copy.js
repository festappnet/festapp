import { createHash } from 'node:crypto';
import { Transform } from 'node:stream';

/** Provider-independent streaming copy. create() MUST be conditional create;
 * an existing destination is read and hash-checked, never overwritten. A receipt
 * is durable only after source completion and an independent destination read.
 */
export async function copyVerifiedAsset(asset, { openSource, destination, persistReceipt }) {
  if (asset.issues?.length || !/^[a-f0-9]{64}$/.test(asset.source.sha256) ||
      !Number.isSafeInteger(asset.source.size) || asset.source.size < 0) {
    throw new Error('unresolved_source_manifest');
  }
  const { bucket, key } = asset.destination;
  if (!['public','private'].includes(asset.visibility) ||
      (asset.visibility === 'private') !== (bucket === 'festapp-images-private')) {
    throw new Error('visibility_destination_mismatch');
  }
  if (!['festapp-images', 'festapp-images-private'].includes(bucket) || !key ||
      key.startsWith('/') || key.split('/').some(part => part === '..' || part === '.')) {
    throw new Error('invalid_destination');
  }
  const verify = async () => {
    const object = await destination.read(bucket, key);
    if (!object) throw new Error('destination_missing');
    let size = 0;
    const hash = createHash('sha256');
    for await (const chunk of object.stream) { size += chunk.length; hash.update(chunk); }
    const sha256 = hash.digest('hex');
    if (size !== asset.source.size || sha256 !== asset.source.sha256 || object.contentType !== asset.contentType) {
      throw new Error('destination_conflict');
    }
    return {size, sha256};
  };
  let resumed = false;
  if (await destination.exists(bucket, key)) {
    resumed = true;
  } else {
    const source = await openSource(asset);
    let size = 0;
    const digest = createHash('sha256');
    const checked = new Transform({
      transform(chunk, _encoding, done) {
        size += chunk.length;
        if (size > asset.source.size) return done(new Error('source_changed'));
        digest.update(chunk); done(null, chunk);
      },
      flush(done) {
        if (size !== asset.source.size || digest.digest('hex') !== asset.source.sha256) return done(new Error('source_changed'));
        done();
      },
    });
    source.stream.on('error', error => checked.destroy(error));
    source.stream.pipe(checked);
    // Observe completion immediately, including when a conditional write loses
    // a race before the destination adapter consumes the complete source.
    const completed = Promise.resolve(source.done).then(() => null, error => error);
    try {
      await destination.create(bucket, key, checked, {
        contentLength: asset.source.size, contentType: asset.contentType,
        sha256: asset.source.sha256, ifNoneMatch: '*',
      });
      const error = await completed;
      if (error) throw error;
    } catch (error) {
      checked.destroy(); source.stream.destroy();
      await completed;
      // A concurrent creator is accepted only after identical-byte/MIME proof.
      if (error?.code !== 'PRECONDITION_FAILED') throw error;
      resumed = true;
    }
  }
  const verified = await verify();
  const receipt = { version: 1, identity: asset.identity, destination: asset.destination,
    ...verified, contentType: asset.contentType, verifiedAt: new Date().toISOString(), resumed };
  await persistReceipt(receipt);
  return receipt;
}
