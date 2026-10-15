// Shared by the browser and the generated edge worker. Missing dates remain visible.
export function classifyOccasions(occasions, now = Date.now()) {
    const groups = { present: [], upcoming: [], past: [], undated: [] };
    const time = value => value == null || value === '' ? NaN : new Date(value).getTime();
    for (const occasion of occasions) {
        const start = time(occasion.start_time);
        const end = time(occasion.end_time);
        if (Number.isFinite(end) && end < now) groups.past.push(occasion);
        else if (Number.isFinite(start) && start > now) groups.upcoming.push(occasion);
        else if (Number.isFinite(start) && Number.isFinite(end) && start <= now && end >= now) groups.present.push(occasion);
        else groups.undated.push(occasion);
    }
    groups.upcoming.sort((a, b) => time(a.start_time) - time(b.start_time));
    groups.past.sort((a, b) => time(b.end_time) - time(a.end_time));
    return groups;
}

// An invalid response is an unavailable catalogue, never a confirmed empty list.
export function extractPublicOccasions(data) {
    const occasions = Array.isArray(data) ? data : data?.occasions ?? data?.data?.occasions;
    if (!Array.isArray(occasions)) throw new Error('Invalid public catalogue response');
    return occasions;
}
