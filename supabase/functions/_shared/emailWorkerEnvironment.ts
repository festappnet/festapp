/** SES credentials belong only to the authenticated queue worker. */
export function emailWorkerEnvironment(
  service: string,
  environment: Record<string, string>,
): Array<[string, string]> {
  return Object.entries(environment).filter(([name]) =>
    service === "process-email-queue" || !name.startsWith("EMAIL_SES_")
  );
}
