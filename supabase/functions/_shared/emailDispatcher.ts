export type DispatchRow = {
  message_id: string;
  attempt_id: string;
  lease_token: string;
  prepared: unknown;
  skipped?: boolean;
};
export type DispatcherDependencies = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<any>;
  prepare: (
    row: any,
  ) => Promise<{ prepared: unknown; postAction: Record<string, unknown> }>;
  seal: (value: unknown) => Promise<unknown>;
  gateway: (row: DispatchRow) => Promise<void>;
  now: () => number;
};
/** One bounded worker; gateway owns begin and all provider outcomes. */
export async function drainEmails(
  d: DispatcherDependencies,
  budgetMs = 35_000,
) {
  const started = d.now();
  let claimed = 0;
  await d.rpc("apply_email_post_actions");
  await d.rpc("reconcile_email_events");
  while (d.now() - started < budgetMs) {
    const row: DispatchRow | null = await d.rpc("claim_email");
    if (!row) {
      const due = await d.rpc("get_next_email_due");
      const remaining = due ? Date.parse(due) - d.now() : Infinity;
      if (
        remaining > 0 && remaining <= 2500 &&
        d.now() - started + remaining < budgetMs
      ) {
        await new Promise((resolve) => setTimeout(resolve, remaining));
        continue;
      }
      break;
    }
    if (row.skipped) continue;
    claimed++;
    try {
      if (!row.prepared) {
        let timer: ReturnType<typeof setTimeout> | undefined;
        const timeout = new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error("preparation_timeout")),
            Math.min(30000, Math.max(1, budgetMs - (d.now() - started))),
          );
        });
        let snapshot: Awaited<ReturnType<typeof d.prepare>>;
        try {
          snapshot = await Promise.race([d.prepare(row), timeout]);
        } finally {
          clearTimeout(timer);
        }
        row.prepared = await d.seal(snapshot.prepared);
        await d.rpc("prepare_email", {
          p_message: row.message_id,
          p_token: row.lease_token,
          p_prepared: row.prepared,
          p_post_action: snapshot.postAction,
        });
      }
    } catch {
      await d.rpc("finish_email_attempt", {
        p_attempt: row.attempt_id,
        p_token: row.lease_token,
        p_outcome: "preparation_failed",
        p_error: "preparation_failed",
      });
      continue;
    }
    // An HTTP failure cannot prove whether gateway began/sent. Leave its fenced lease for recovery.
    try {
      await d.gateway(row);
    } catch {
      break;
    }
    await d.rpc("apply_email_post_actions", { p_message: row.message_id });
  }
  if (claimed > 0) await d.rpc("wake_email_worker");
  return { claimed };
}
