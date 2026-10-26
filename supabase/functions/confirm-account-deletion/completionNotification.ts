export type CompletionNotification = {
  to: string;
  templateCode: "ACCOUNT_DELETION_COMPLETE";
  context: { organization: number };
  substitutions: { appName: string };
};

type CompletionJob = {
  completionEmail?: unknown;
  organization: number;
  appName: string;
};

export async function sendCompletionNotification(
  job: CompletionJob,
  deliver: (message: CompletionNotification) => Promise<unknown>,
): Promise<boolean> {
  if (typeof job.completionEmail !== "string" || !job.completionEmail) {
    return false;
  }
  await deliver({
    to: job.completionEmail,
    templateCode: "ACCOUNT_DELETION_COMPLETE",
    context: { organization: job.organization },
    substitutions: { appName: job.appName },
  });
  return true;
}
