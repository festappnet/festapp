export interface SupabaseAuth {
  supabaseUrl: string;
  anonKey: string;
}

/**
 * Extract and validate the Bearer token format from the Authorization header.
 * Actual JWT verification is delegated to Supabase PostgREST via RPC calls.
 */
export function extractBearerToken(authHeader: string): string {
  const token = authHeader.replace('Bearer ', '');
  if (!token || token === authHeader) {
    throw new Error('Missing bearer token');
  }
  return token;
}

/**
 * Check if a user has editor permission via the check_upload_permission RPC.
 *
 * Uses the user's own JWT for auth context (auth.uid() in the RPC function)
 * and the anon key as the apikey. No service role key needed.
 *
 * This implicitly verifies the JWT: if the token is invalid, Supabase
 * PostgREST returns 401, and we treat that as permission denied.
 */
export async function checkEditorPermission(
  userJwt: string,
  occasionId: number,
  auth: SupabaseAuth
): Promise<boolean> {
  const response = await fetch(
    `${auth.supabaseUrl}/rest/v1/rpc/check_upload_permission`,
    {
      method: 'POST',
      headers: {
        'apikey': auth.anonKey,
        'Authorization': `Bearer ${userJwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_occasion_id: occasionId }),
    }
  );
  if (!response.ok) return false;
  return (await response.json()) === true;
}

/**
 * Check if a user has editor permission on a specific unit via RPC.
 */
export async function checkUnitEditorPermission(
  userJwt: string,
  unitId: number,
  auth: SupabaseAuth
): Promise<boolean> {
  const response = await fetch(
    `${auth.supabaseUrl}/rest/v1/rpc/check_upload_permission`,
    {
      method: 'POST',
      headers: {
        'apikey': auth.anonKey,
        'Authorization': `Bearer ${userJwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_unit_id: unitId }),
    }
  );
  if (!response.ok) return false;
  return (await response.json()) === true;
}

/**
 * Check if a user is an editor on any occasion.
 */
export async function checkIsEditorOnAnyOccasion(
  userJwt: string,
  auth: SupabaseAuth
): Promise<boolean> {
  const response = await fetch(
    `${auth.supabaseUrl}/rest/v1/rpc/get_is_editor_on_any_occasion`,
    {
      method: 'POST',
      headers: {
        'apikey': auth.anonKey,
        'Authorization': `Bearer ${userJwt}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    }
  );
  if (!response.ok) return false;
  return (await response.json()) === true;
}

/** Check the independent AKH role model through its authenticated-only RPC. */
export async function checkAkhEventManagerPermission(
  userJwt: string,
  auth: SupabaseAuth,
): Promise<boolean> {
  const response = await fetch(`${auth.supabaseUrl}/rest/v1/rpc/get_can_manage_images`, {
    method: 'POST',
    headers: {
      apikey: auth.anonKey,
      Authorization: `Bearer ${userJwt}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  });
  if (!response.ok) return false;
  return (await response.json()) === true;
}

export async function authorizeImageDeletion(
  userJwt: string,
  links: string[],
  auth: SupabaseAuth,
): Promise<string[]> {
  const response = await fetch(`${auth.supabaseUrl}/rest/v1/rpc/authorize_image_deletion`, {
    method: 'POST',
    headers: {
      apikey: auth.anonKey,
      Authorization: `Bearer ${userJwt}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_links: links }),
  });
  if (!response.ok) return [];
  const body = await response.json() as Array<{ link: string }> | string[];
  return body.map((item) => typeof item === 'string' ? item : item.link);
}

export async function removeImageRecords(
  userJwt: string,
  links: string[],
  auth: SupabaseAuth,
): Promise<boolean> {
  const response = await fetch(`${auth.supabaseUrl}/rest/v1/rpc/remove_image_records`, {
    method: 'POST',
    headers: {
      apikey: auth.anonKey,
      Authorization: `Bearer ${userJwt}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_links: links }),
  });
  return response.ok;
}
