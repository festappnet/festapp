import { createUserClient } from "../_shared/supabaseUtil.ts";
import { prepareAccountEmail } from "../_shared/emailQueueClient.ts";
import { createInvitationHandler, type InvitationPreview } from "./handler.ts";

Deno.serve(createInvitationHandler({
  async preview(authorization, draftId) {
    const { data, error } = await createUserClient(authorization).rpc(
      "preview_occasion_setup_invitations",
      {
        p_id: draftId,
        p_emails: null,
      },
    );
    if (error) throw new Error("invitation_access_denied");
    return data as InvitationPreview;
  },
  prepare: prepareAccountEmail,
  async enqueue(authorization, args) {
    const { data, error } = await createUserClient(authorization).rpc(
      "enqueue_occasion_setup_invitation",
      args,
    );
    if (error) throw new Error("invitation_enqueue_failed");
    return data;
  },
  token: () =>
    [...crypto.getRandomValues(new Uint8Array(32))].map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join(""),
}));
