export type SafeContext = Record<string, string | number | boolean | null>;
export type EventTicket = {
    eventId: string;
    buffered: boolean;
};
export type EventReceipt = {
    eventId: string;
    recorded: true;
    replayed: boolean;
    incidentId?: string;
    revision?: number;
};
export type FlushResult = {
    receipts: EventReceipt[];
    pending: number;
    dropped: number;
    status: 'flushed' | 'partial' | 'unavailable' | 'disabled';
};
export type Config = {
    baseUrl?: string;
    token?: string;
    service: string;
    release: string;
    enabled?: boolean;
    fetch?: typeof fetch;
    maxBuffer?: number;
    diagnostic?: (code: string) => void;
};
export interface Monitoring {
    reportError(error: unknown, options: {
        code: string;
        operation: string;
        context?: SafeContext;
    }): EventTicket;
    raiseIssue(key: string, options: {
        code: string;
        summary: string;
        severity: 'warning' | 'critical';
        context?: SafeContext;
    }): EventTicket;
    resolveIssue(key: string, proof: {
        incidentId: string;
        expectedRevision: number;
        evidence: SafeContext;
    }): EventTicket;
    heartbeat(checkId: string, result: {
        status: 'ok' | 'failed';
        code?: string;
        context?: SafeContext;
    }): EventTicket;
    flush(options?: {
        timeoutMs?: number;
    }): Promise<FlushResult>;
    close(options?: {
        timeoutMs?: number;
    }): Promise<FlushResult>;
}
export declare function createMonitoring(config: Config): Monitoring;
