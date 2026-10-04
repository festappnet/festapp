import { enqueueAndAwaitEmail } from "../_shared/emailQueueClient.ts";
import {
  accountDeletionCors,
  deleteAccountStorageObjects,
  deleteOneSignalUser,
  jsonResponse,
  sha256,
} from "../_shared/accountDeletion.ts";
import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { parseOrganizationBranding } from "../_shared/organizationBranding.ts";
import { loadOrganizationNotificationConfig } from "../_shared/organizationNotificationConfig.ts";
import { sendCompletionNotification } from "./completionNotification.ts";

async function inspect(token: string) {
  if (token.length < 40 || token.length > 200) return { status: "invalid" };
  const { data, error } = await supabaseAdmin.rpc(
    "inspect_account_deletion_token",
    {
      p_token_hash: await sha256(token),
    },
  );
  return error ? { status: "invalid" } : data;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: accountDeletionCors });
  }
  if (request.method === "GET") {
    const state = await inspect(
      new URL(request.url).searchParams.get("token") || "",
    );
    const status = state.status === "expired"
      ? 410
      : state.status === "valid"
      ? 200
      : 400;
    return jsonResponse(state, status);
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  let token = "";
  try {
    const body = await request.json();
    if (!body || Object.keys(body).some((key) => key !== "token")) {
      throw new Error();
    }
    token = typeof body.token === "string" ? body.token : "";
  } catch {
    return jsonResponse({ error: "invalid" }, 400);
  }
  if (token.length < 40 || token.length > 200) {
    return jsonResponse({ error: "invalid" }, 400);
  }

  const { data: job, error: claimError } = await supabaseAdmin.rpc(
    "claim_account_deletion",
    {
      p_token_hash: await sha256(token),
    },
  );
  if (claimError || job?.status === "invalid") {
    return jsonResponse({ error: "invalid" }, 400);
  }
  if (job?.status === "expired") return jsonResponse({ error: "expired" }, 410);
  if (job?.status === "already_completed") {
    return jsonResponse({ status: "already_completed" });
  }

  const requestId = job.requestId as string;
  const userId = job.userId as string;
  const organization = Number(job.organization);

  if (!job.publicDeleted) {
    const { error } = await supabaseAdmin.rpc(
      "cleanup_account_deletion_domain",
      { p_request_id: requestId },
    );
    if (error) {
      await supabaseAdmin.rpc("update_account_deletion_job", {
        p_request_id: requestId,
        p_error_class: "public_cleanup",
      });
      return jsonResponse({ status: "processing" }, 503);
    }
  }

  if (!job.authDeleted) {
    const { error } = await supabaseAdmin.auth.admin.deleteUser(userId, false);
    if (error && error.status !== 404) {
      await supabaseAdmin.rpc("update_account_deletion_job", {
        p_request_id: requestId,
        p_error_class: "auth_delete",
      });
      return jsonResponse({ status: "processing" }, 503);
    }
    await supabaseAdmin.rpc("update_account_deletion_job", {
      p_request_id: requestId,
      p_auth_deleted: true,
    });
  }

  try {
    await deleteAccountStorageObjects(requestId, {
      getBatch: async (id, limit) => {
        const { data, error } = await supabaseAdmin.rpc(
          "get_account_deletion_storage_batch",
          {
            p_request_id: id,
            p_limit: limit,
          },
        );
        if (error) throw error;
        return data;
      },
      remove: async (bucketId, names) => {
        const { error } = await supabaseAdmin.storage.from(bucketId).remove(
          names,
        );
        if (error) throw error;
      },
    });
  } catch {
    await supabaseAdmin.rpc("update_account_deletion_job", {
      p_request_id: requestId,
      p_error_class: "storage_delete",
    });
    return jsonResponse({ status: "processing" }, 503);
  }

  if (!job.onesignalDeleted) {
    try {
      const localVendorMock =
        Deno.env.get("ACCOUNT_DELETION_LOCAL_VENDOR_MOCK") === "true" &&
        /^(http:\/\/(127\.0\.0\.1|localhost|kong)(:|\/))/.test(
          Deno.env.get("SUPABASE_URL") || "",
        );
      if (!localVendorMock) {
        const config = await loadOrganizationNotificationConfig(
          supabaseAdmin,
          organization,
        );
        await deleteOneSignalUser(
          config.appId,
          config.restApiKey,
          userId,
        );
      }
    } catch (error) {
      await supabaseAdmin.rpc("update_account_deletion_job", {
        p_request_id: requestId,
        p_error_class: error instanceof Error
          ? error.message.slice(0, 64)
          : "onesignal_delete",
      });
      return jsonResponse({ status: "processing" }, 503);
    }
  }

  const { data: finalState, error: finalError } = await supabaseAdmin.rpc(
    "update_account_deletion_job",
    {
      p_request_id: requestId,
      p_onesignal_deleted: true,
      p_error_class: null,
    },
  );
  if (finalError || finalState?.status !== "completed") {
    return jsonResponse({ status: "processing" }, 503);
  }

  try {
    const { data: organizationRow, error: organizationError } =
      await supabaseAdmin
        .from("organizations").select("data").eq("id", organization).single();
    if (organizationError) throw organizationError;
    const branding = parseOrganizationBranding(organizationRow?.data);
    await sendCompletionNotification({
      completionEmail: job.completionEmail,
      organization,
      appName: branding.appName,
    }, (message) =>
      enqueueAndAwaitEmail({
        ...message,
        from: `${branding.appName} | Festapp <${
          Deno.env.get("DEFAULT_EMAIL") || ""
        }>`,
      }));
  } catch {
    console.error("Deletion completed; completion notification failed");
  }
  return jsonResponse({ status: "completed" });
});
