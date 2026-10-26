/**
 * R2 upload and list helpers via S3-compatible API.
 */

import {
  S3Client,
  PutObjectCommand,
  ListObjectsV2Command,
  HeadObjectCommand,
} from '@aws-sdk/client-s3';

/**
 * Create an S3-compatible client configured for Cloudflare R2.
 *
 * @param {object} env - Environment variables
 * @param {string} env.CF_ACCOUNT_ID - Cloudflare account ID
 * @param {string} env.R2_ACCESS_KEY_ID - R2 API token access key
 * @param {string} env.R2_SECRET_ACCESS_KEY - R2 API token secret key
 * @returns {S3Client}
 */
export function createR2Client(env) {
  return new S3Client({
    region: 'auto',
    endpoint: `https://${env.CF_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    },
  });
}

/**
 * Upload a file to R2.
 *
 * @param {S3Client} r2 - R2 client
 * @param {string} bucket - R2 bucket name
 * @param {string} key - Object key (path)
 * @param {Buffer} body - File contents
 * @param {string} contentType - MIME type
 */
export async function uploadToR2(r2, bucket, key, body, contentType) {
  await r2.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: body,
      ContentType: contentType,
    })
  );
}

/**
 * Count all objects in an R2 bucket using pagination.
 *
 * @param {S3Client} r2 - R2 client
 * @param {string} bucket - R2 bucket name
 * @returns {Promise<{count: number, keys: string[]}>}
 */
export async function countR2Objects(r2, bucket) {
  const keys = [];
  let continuationToken = undefined;

  while (true) {
    const response = await r2.send(
      new ListObjectsV2Command({
        Bucket: bucket,
        ContinuationToken: continuationToken,
      })
    );

    if (response.Contents) {
      for (const obj of response.Contents) {
        keys.push(obj.Key);
      }
    }

    if (!response.IsTruncated) break;
    continuationToken = response.NextContinuationToken;
  }

  return { count: keys.length, keys };
}

/**
 * Check if an object exists in R2 and return its size.
 *
 * @param {S3Client} r2 - R2 client
 * @param {string} bucket - R2 bucket name
 * @param {string} key - Object key
 * @returns {Promise<{exists: boolean, size?: number}>}
 */
export async function headR2Object(r2, bucket, key) {
  try {
    const response = await r2.send(
      new HeadObjectCommand({
        Bucket: bucket,
        Key: key,
      })
    );
    return { exists: true, size: response.ContentLength };
  } catch (err) {
    if (err.name === 'NotFound' || err.$metadata?.httpStatusCode === 404) {
      return { exists: false };
    }
    throw err;
  }
}
