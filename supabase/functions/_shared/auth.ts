import {
  canManageOccasionUsers,
  createUserClient,
  getSupabaseUser,
  isUserEditorOrder,
  supabaseAdmin,
} from "./supabaseUtil.ts";

import { AuthError } from './authError.ts';
export { AuthError } from './authError.ts';

interface AuthParams {
  requestSecret?: string;
  authorizationHeader?: string | null;
  occasionId?: number;
  permission?: "editorOrder" | "manageUsers" | "readOrder";
}

interface AuthResult {
  user: any | null; // Returns the Supabase user object if authenticated via header, else null
}

/**
 * Authorizes a request by checking for a valid secret or editor permissions.
 * Throws an AuthError if authorization fails.
 * @param {AuthParams} params - The authorization parameters.
 * @returns Promise<AuthResult> - Contains the user object if applicable.
 */
export async function authorizeRequest({
  requestSecret,
  authorizationHeader,
  occasionId,
  permission = "editorOrder",
}: AuthParams): Promise<AuthResult> {
  if (occasionId && permission !== "readOrder") {
    const {data: demo, error} = await supabaseAdmin.rpc("is_demo_occasion", {p_occasion: occasionId});
    if (error || demo === true) throw new AuthError("Demo event is read only", 403);
  }
  // Path 1: Authorization via request secret (for cron jobs, etc.)
  if (requestSecret) {
    const { data: secretValid, error: secretError } = await supabaseAdmin.rpc(
      "check_request_secret",
      { p_secret: requestSecret },
    );
    if (secretError || !secretValid) {
      throw new AuthError("Invalid request secret", 403);
    }
    return { user: null }; // Authorized as system/admin, no specific user context
  }

  // Path 2: Authorization via user token and editor role on a specific occasion
  if (authorizationHeader && occasionId) {
    const userResponse = await getSupabaseUser(authorizationHeader);

    // getSupabaseUser throws if unauthorized, but we double check existence
    if (!userResponse || !userResponse.user) {
      throw new AuthError("Unauthorized", 401);
    }

    const userId = userResponse.user.id;
    // Note: Passing BigInt(occasionId) assuming occasionId comes in as number but DB expects BigInt context
    if (permission === "readOrder") {
      const {data: readable,error} = await createUserClient(authorizationHeader)
        .rpc("get_is_editor_order_view_on_occasion", {oc: occasionId.toString()});
      if (error || readable !== true) throw new AuthError("Forbidden",403);
      return {user: userResponse.user};
    }
    const userIsEditor = permission === "manageUsers"
      ? await canManageOccasionUsers(authorizationHeader, BigInt(occasionId))
      : await isUserEditorOrder(userId, BigInt(occasionId));

    if (!userIsEditor) {
      throw new AuthError("Forbidden: Not an editor", 403);
    }

    return { user: userResponse.user }; // Success with User Context
  }

  // If neither valid path's parameters are met, fail the request.
  throw new AuthError("Invalid authorization credentials provided", 401);
}
