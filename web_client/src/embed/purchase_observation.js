// Keep observation time stable across helper heartbeats; state changes get a new time.
export function purchaseObservation(win) {
    let previous, capturedAt;
    return value => {
        const key = JSON.stringify(value);
        if (key !== previous) { previous = key; capturedAt = new Date(win.Date?.now?.() ?? Date.now()).toISOString(); }
        return {...value, capturedAt};
    };
}
export function auditDecision(value) {
    try {
        const date = Object.prototype.toString.call(value) === '[object Date]' ? value.getTime() : typeof value === 'number' ? value : Date.parse(value);
        return Number.isFinite(date) ? {decidedAt:new Date(date).toISOString()} : {};
    } catch { return {}; }
}
