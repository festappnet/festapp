export const CSM_INSTALLATION_GENERATION = "csm_ostrava_2026_v1";

export interface NotificationPayloadInput {
  appId: string;
  defaultUrl: string;
  occasionLink: string;
  targetPath: string;
  recipient?: string | string[] | null;
  heading: string;
  content: string;
}

export function buildNotificationPayload(input: NotificationPayloadInput) {
  const notificationIcon = new URL(
    "/notification-icon-256x256.png",
    input.defaultUrl,
  ).toString();
  const webIcons = {
    chrome_web_icon: notificationIcon,
    firefox_icon: notificationIcon,
  };

  if (input.recipient) {
    return {
      app_id: input.appId,
      web_url:
        `${input.defaultUrl}/#/${input.occasionLink}/${input.targetPath}`,
      include_aliases: { external_id: Array.isArray(input.recipient) ? input.recipient : [input.recipient] },
      target_channel: "push",
      headings: { en: input.heading },
      contents: { en: input.content },
      ...webIcons,
    };
  }

  return {
    app_id: input.appId,
    filters: [
      {
        field: "tag",
        key: "app_generation",
        relation: "=",
        value: CSM_INSTALLATION_GENERATION,
      },
      { operator: "AND" },
      {
        field: "tag",
        key: "occasion",
        relation: "=",
        value: input.occasionLink,
      },
    ],
    headings: { en: input.heading },
    contents: { en: input.content },
    ...webIcons,
  };
}
