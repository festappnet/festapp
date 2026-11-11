import { createUserClient } from "../_shared/supabaseUtil.ts";
import { createInvitationHandler } from "./handler.ts";
import { executeMemberAccess } from "../manage-member-access/handler.ts";
import { memberAccessDependencies } from "../manage-member-access/dependencies.ts";
Deno.serve(createInvitationHandler({
 async preview(authorization, draftId) {
  const { data, error } = await createUserClient(authorization).rpc("preview_occasion_setup_invitations", { p_id: draftId, p_emails: null });
  if (error) throw new Error("scope_denied");
  return data;
 },
 execute: (authorization, command, request) => executeMemberAccess(memberAccessDependencies, authorization, command, request),
}));
