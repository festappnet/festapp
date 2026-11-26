export function getMinimalisticDateRange(
  start: Date,
  end: Date,
  locale: string = "cs",
  timeZone?: string
): string {
  const full = new Intl.DateTimeFormat(locale, {
    timeZone,
    year: "numeric",
    month: "short",
    day: "numeric",
  });
  const civil = new Intl.DateTimeFormat("en", {
    timeZone,
    year: "numeric",
    month: "numeric",
    day: "numeric",
  });
  const fullEnd = full.format(end);
  if (civil.format(start) === civil.format(end)) return fullEnd;

  if (locale.toLowerCase().startsWith("en") &&
      typeof full.formatRange === "function" && start <= end) {
    return full.formatRange(start, end)
      .replace(/[\u2009\u202f]/g, " ").replace(/\u2013/g, "-");
  }

  const startParts = civil.formatToParts(start);
  const endParts = civil.formatToParts(end);
  const samePart = (type: "year" | "month") =>
    startParts.find(part => part.type === type)?.value ===
    endParts.find(part => part.type === type)?.value;
  let minimalStart: string;
  if (samePart("year")) {
    if (samePart("month")) {
      minimalStart = new Intl.DateTimeFormat(locale, { day: "numeric", timeZone }).format(start);
    } else {
      minimalStart = new Intl.DateTimeFormat(locale, {
        timeZone,
        day: "numeric",
        month: "short",
      }).format(start);
    }
  } else {
    minimalStart = full.format(start);
  }
  return `${minimalStart} - ${fullEnd}`;
}

