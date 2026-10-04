import { emailRpc } from "../_shared/emailQueueClient.ts";
import { feedbackHandler } from "./handler.ts";
Deno.serve(
  feedbackHandler({
    topic: Deno.env.get("EMAIL_SNS_TOPIC_ARN") ?? "",
    rpc: emailRpc,
  }),
);
