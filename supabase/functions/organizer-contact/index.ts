import { emailRpc } from "../_shared/emailQueueClient.ts";
import { contactIntent } from "./contact_intent.ts";
import { organizerContactHandler } from "./handler.ts";

Deno.serve(organizerContactHandler(async (contact) => {
  const from = Deno.env.get("DEFAULT_EMAIL");
  if (!from) throw new Error("contact_sender_unavailable");
  const receipt = await emailRpc(
    "enqueue_organizer_contact_v1",
    await contactIntent(contact, from),
  );
  if (receipt === "accepted" || receipt === "conflict") return receipt;
  throw new Error("contact_receipt_unavailable");
}));
