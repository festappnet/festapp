export function getMinimalisticDateRange(
  start: Date,
  end: Date,
  locale: string = "cs"
): string {
  const fullEnd = new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(end);
  let minimalStart: string;
  if (start.getFullYear() === end.getFullYear()) {
    if (start.getMonth() === end.getMonth()) {
      minimalStart = new Intl.DateTimeFormat(locale, { day: "numeric" }).format(start);
    } else {
      minimalStart = new Intl.DateTimeFormat(locale, {
        day: "numeric",
        month: "short",
      }).format(start);
    }
  } else {
    minimalStart = new Intl.DateTimeFormat(locale, {
      year: "numeric",
      month: "short",
      day: "numeric",
    }).format(start);
  }
  return `${minimalStart} - ${fullEnd}`;
}

