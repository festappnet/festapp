export function translatePlatformLinks(
  platforms: Array<{ platform: string; link: string }>,
  lang: string
): string {
  const translations: Record<string, Record<string, string>> = {
    cs: {
      droid: "Stáhnout pro Android",
      ios: "Stáhnout pro iOS",
      web: "Otevřít na webu",
    },
    en: {
      droid: "Get Android App",
      ios: "Get iOS App",
      web: "Open Web App",
    },
  };

  const t = translations[lang] || translations["en"]; // Fallback to English if translation is unavailable

  return platforms
    .map(
      (platform) => `
        <p>
          <a target="_blank" rel="noopener noreferrer" href="${platform.link}">
            ${t[platform.platform.toLowerCase()] || platform.platform}
          </a>
        </p>
      `
    )
    .join("");
}

