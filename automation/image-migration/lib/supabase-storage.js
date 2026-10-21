/**
 * Supabase Storage list and download helpers.
 * Recursively lists all files in a bucket and downloads individual files.
 */

/**
 * Recursively list all files in a Supabase Storage bucket.
 * Files have an `id` property; folders do not — use this to distinguish.
 *
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase
 * @param {string} bucket - Bucket name (e.g. 'public-files')
 * @param {string} [prefix=''] - Folder prefix for recursion
 * @returns {Promise<string[]>} Array of full file paths (relative to bucket root)
 */
export async function listAllFiles(supabase, bucket, prefix = '') {
  const PAGE_SIZE = 100;
  const allFiles = [];
  let offset = 0;

  while (true) {
    const { data, error } = await supabase.storage
      .from(bucket)
      .list(prefix, { limit: PAGE_SIZE, offset });

    if (error) {
      throw new Error(`Failed to list ${bucket}/${prefix}: ${error.message}`);
    }

    if (!data || data.length === 0) break;

    for (const item of data) {
      const fullPath = prefix ? `${prefix}/${item.name}` : item.name;

      if (item.id) {
        // It's a file
        allFiles.push(fullPath);
      } else {
        // It's a folder — recurse
        const nested = await listAllFiles(supabase, bucket, fullPath);
        allFiles.push(...nested);
      }
    }

    if (data.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }

  return allFiles;
}

/**
 * Download a single file from Supabase Storage.
 *
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase
 * @param {string} bucket - Bucket name
 * @param {string} path - File path within the bucket
 * @returns {Promise<Buffer>} File contents as a Buffer
 */
export async function downloadFile(supabase, bucket, path) {
  const { data, error } = await supabase.storage
    .from(bucket)
    .download(path);

  if (error) {
    throw new Error(`Failed to download ${bucket}/${path}: ${error.message}`);
  }

  return Buffer.from(await data.arrayBuffer());
}
