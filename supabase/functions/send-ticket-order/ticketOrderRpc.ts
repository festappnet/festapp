import { abuseLimitDetails } from "../_shared/abuseLimit.ts";

type RpcError = { code?: string; message?: string; details?: string };
type RpcClient = {
  rpc(name: string, parameters: Record<string, unknown>): PromiseLike<{
    data: unknown;
    error: RpcError | null;
  }>;
};

/** Preserve definitive admission rejections across both authorization paths. */
export async function executeTicketOrderRpc(
  client: RpcClient,
  name: string,
  parameters: Record<string, unknown>,
) {
  const { data, error } = await client.rpc(name, parameters);
  if (!error) {
    const order = data !== null && typeof data === "object" && "data" in data
      ? data.data ?? data
      : data;
    return { envelope: data, order, error: null };
  }
  if (error.code !== "PT429") {
    return {
      envelope: null,
      order: { code: 500, message: error.message },
      error,
    };
  }
  return { envelope: null, error, order: abuseLimitDetails(error.details) };
}
