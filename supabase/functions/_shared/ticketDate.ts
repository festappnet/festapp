export function getMinimalisticDateRange(
  start: Date,
  end: Date,
  locale: string = "cs",
  timeZone?: string
): string {
  if (locale.toLowerCase().startsWith('en')) {
    return new Intl.DateTimeFormat(locale, {timeZone, year:'numeric', month:'short', day:'numeric'})
      .formatRange(start, end).replace(/[\u2009\u202f]/g, ' ').replace(/\u2013/g, '-');
  }
  const fullEnd = new Intl.DateTimeFormat(locale, {
    timeZone,
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(end);
  const civil = (date: Date) => new Intl.DateTimeFormat('en', {year:'numeric',month:'numeric',timeZone}).formatToParts(date);
  const part = (date: Date, type: string) => civil(date).find(p => p.type === type)?.value;
  let minimalStart: string;
  if (part(start, 'year') === part(end, 'year')) {
    if (part(start, 'month') === part(end, 'month')) {
      minimalStart = new Intl.DateTimeFormat(locale, { day: "numeric", timeZone }).format(start);
    } else {
      minimalStart = new Intl.DateTimeFormat(locale, {
        timeZone,
        day: "numeric",
        month: "short",
      }).format(start);
    }
  } else {
    minimalStart = new Intl.DateTimeFormat(locale, {
      timeZone,
    year: "numeric",
      month: "short",
      day: "numeric",
    }).format(start);
  }
  return `${minimalStart} - ${fullEnd}`;
}

