import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { prepareAccountEmail } from "../_shared/emailQueueClient.ts";
import type { DeliverEmailInput } from "../_shared/emailDelivery.ts";
import type { AccessDependencies } from "./handler.ts";
async function rpc(client: ReturnType<typeof createUserClient>, name: string, args: Record<string, unknown>) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}
export const memberAccessDependencies: AccessDependencies = {
  preview: (authorization, commandId, request) => rpc(createUserClient(authorization), "preview_member_access", { p_command_id: commandId, p_request: request }),
  prepare: input => prepareAccountEmail(input as DeliverEmailInput),
  stage: args => rpc(supabaseAdmin, "stage_member_access_email", args),
  commit: (authorization, commandId, request, preparation) => rpc(createUserClient(authorization), "manage_member_access", { p_command_id: commandId, p_request: request, p_preparation: preparation }),
  token: () => [...crypto.getRandomValues(new Uint8Array(32))].map(b => b.toString(16).padStart(2, "0")).join(""),
};
