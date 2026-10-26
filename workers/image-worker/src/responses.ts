export function jsonResponse(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
}

export function errorResponse(status: number, code: string, message: string, retryable = false): Response {
  return jsonResponse({ error: { code, message, retryable } }, status);
}
