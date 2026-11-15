import { AuthError } from '../_shared/authError.ts';

type Stage = 'parse' | 'authorize' | 'reconcile';
type Failure = {stage: Stage; kind: string};

/** Only fixed categories enter logs. Never serialize errors, request bodies or credentials. */
function failureKind(error: unknown): string {
  if (error instanceof AuthError) return 'authorization';
  if (error instanceof TypeError) return 'type_error';
  if (error instanceof SyntaxError) return 'syntax_error';
  if (error instanceof DOMException && error.name === 'AbortError') return 'aborted';
  if (error instanceof DOMException && error.name === 'TimeoutError') return 'timeout';
  return 'unavailable';
}

export function syncTicketWalletHandler(dependencies: {
  authorize: (params: {requestSecret: string}) => Promise<unknown>;
  reconcile: () => Promise<unknown>;
  report?: (failure: Failure) => void;
}) {
  return async (req: Request): Promise<Response> => {
    const headers = {'Cache-Control': 'no-store'};
    if (req.method !== 'POST') return new Response(null, {status: 405, headers});
    let stage: Stage = 'parse';
    try {
      const body = await req.json();
      if (!body.requestSecret) return Response.json({error: 'unauthorized'}, {status: 401, headers});
      stage = 'authorize';
      await dependencies.authorize({requestSecret: body.requestSecret});
      stage = 'reconcile';
      return Response.json(await dependencies.reconcile(), {headers});
    } catch (error) {
      try {
        const failure = {stage, kind: failureKind(error)};
        if (dependencies.report) dependencies.report(failure);
        else console.error('wallet_sync_failure', failure);
      } catch { /* Diagnostics must never alter the application response. */ }
      return Response.json({error: 'wallet_sync_unavailable'}, {status: 503, headers});
    }
  };
}
