export type Contact = { id: string; email: string; message: string };
type Forward = (contact: Contact) => Promise<"accepted" | "conflict">;

const idPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const emailPattern =
  /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$/;
const byteLimit = 8192;

async function readContact(request: Request): Promise<Contact> {
  const reader = request.body?.getReader();
  if (!reader) throw new Error("invalid");
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let text = "";
  let bytes = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > byteLimit) throw new Error("invalid");
      text += decoder.decode(value, { stream: true });
    }
    const value = JSON.parse(text + decoder.decode());
    if (
      typeof value?.id !== "string" || !idPattern.test(value.id) ||
      typeof value.email !== "string" || typeof value.message !== "string"
    ) {
      throw new Error("invalid");
    }
    const email = value.email.trim();
    const message = value.message.trim();
    if (
      email.length > 254 || !emailPattern.test(email) || !message.length ||
      message.length > 1000
    ) throw new Error("invalid");
    return { id: value.id, email, message };
  } finally {
    await reader.cancel().catch(() => undefined);
  }
}

export function organizerContactHandler(
  forward: Forward,
  origin = "https://vstupenky.online",
) {
  return async (request: Request): Promise<Response> => {
    const headers = {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "content-type",
      "Cache-Control": "no-store",
      "Vary": "Origin",
    };
    const result = (status: number) => new Response(null, { headers, status });
    if (request.headers.get("origin") !== origin) return result(403);
    if (request.method === "OPTIONS") return result(204);
    if (request.method !== "POST") return result(405);
    if (
      request.headers.get("content-type")?.split(";")[0].trim() !==
        "application/json"
    ) return result(415);

    let contact: Contact;
    try {
      contact = await readContact(request);
    } catch {
      return result(400);
    }
    try {
      return result(await forward(contact) === "accepted" ? 202 : 409);
    } catch (error) {
      if ((error as { code?: string })?.code === "PT429") return result(429);
      return result(503);
    }
  };
}
