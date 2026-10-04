import { assert, assertEquals } from "jsr:@std/assert@1";
import pg from "npm:pg@8.17.1";
import { authEmailHandler } from "../../supabase/functions/auth-email-hook/handler.ts";
import { renderEmail } from "../../supabase/functions/_shared/emailDelivery.ts";
import {
  openEmail,
  sealEmail,
} from "../../supabase/functions/_shared/emailPayload.ts";
const enabled = Deno.env.get("EMAIL_NATIVE_REHEARSAL") === "1";
Deno.test({
  name:
    "pinned GoTrue recovery uses signed durable hook and fails closed on DB outage",
  ignore: !enabled,
  fn: async () => {
    const database = "postgresql://postgres:postgres@127.0.0.1:55434/postgres";
    const client = new pg.Client({ connectionString: database });
    await client.connect();
    const secret = btoa("local-native-hook-fixture-key-1234"),
      jwtSecret = "local-native-auth-jwt-fixture-key-at-least-32-characters";
    const name = `festapp-email-auth-${crypto.randomUUID()}`;
    let user: string | undefined;
    let available = false;
    let callbacks = 0;
    const previousKey = Deno.env.get("EMAIL_PAYLOAD_KEY");
    Deno.env.set("EMAIL_PAYLOAD_KEY", btoa("a".repeat(32)));
    const handler = authEmailHandler({
      secret,
      publicAuthUrl: "https://api.example.invalid",
      prepare: async (input) => ({
        p_sealed: await sealEmail(
          await renderEmail(input, async () => ({ template: input.template })),
        ),
        p_content_hash: "rendered-fixture",
      }),
      rpc: async (method, args) => {
        if (method === "get_auth_email_context") {
          return (await client.query(
            "SELECT public.get_auth_email_context($1) value",
            [args.p_user],
          )).rows[0].value;
        }
        if (!available) throw new Error("functional database outage");
        assertEquals(method, "enqueue_prepared_email");
        callbacks++;
        return (await client.query(
          "SELECT public.enqueue_prepared_email($1,$2,$3,$4,$5,$6,$7,$8) value",
          [
            args.p_kind,
            args.p_context,
            args.p_recipient,
            args.p_sealed,
            args.p_dedupe,
            args.p_content_hash,
            args.p_code,
            args.p_expires,
          ],
        )).rows[0].value;
      },
    });
    const server = Deno.serve({
      hostname: "0.0.0.0",
      port: 0,
      onListen: () => {},
    }, handler);
    const command = async (args: string[]) => {
      const result = await new Deno.Command("docker", {
        args,
        stdout: "piped",
        stderr: "piped",
      }).output();
      if (!result.success) {
        throw new Error(
          `docker operation failed: ${
            new TextDecoder().decode(result.stderr).slice(0, 500)
          }`,
        );
      }
      return new TextDecoder().decode(result.stdout).trim();
    };
    function b64(value: Uint8Array) {
      return btoa(String.fromCharCode(...value)).replace(/=/g, "").replace(
        /\+/g,
        "-",
      ).replace(/\//g, "_");
    }
    const jwtHead = b64(
        new TextEncoder().encode(JSON.stringify({ alg: "HS256", typ: "JWT" })),
      ),
      jwtBody = b64(
        new TextEncoder().encode(
          JSON.stringify({
            role: "service_role",
            iss: "supabase",
            aud: "authenticated",
            exp: Math.floor(Date.now() / 1000) + 600,
          }),
        ),
      );
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(jwtSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const jwt = `${jwtHead}.${jwtBody}.${
      b64(
        new Uint8Array(
          await crypto.subtle.sign(
            "HMAC",
            key,
            new TextEncoder().encode(`${jwtHead}.${jwtBody}`),
          ),
        ),
      )
    }`;
    try {
      assertEquals(
        (await client.query("SELECT paused FROM public.email_capacity")).rows[0]
          .paused,
        true,
      );
      await command([
        "run",
        "--detach",
        "--name",
        name,
        "--publish",
        "127.0.0.1::9999",
        "--env",
        "GOTRUE_API_HOST=0.0.0.0",
        "--env",
        "GOTRUE_API_PORT=9999",
        "--env",
        "API_EXTERNAL_URL=https://api.example.invalid",
        "--env",
        "GOTRUE_SITE_URL=https://app.example.invalid",
        "--env",
        "GOTRUE_DB_DRIVER=postgres",
        "--env",
        "GOTRUE_DB_DATABASE_URL=postgresql://supabase_auth_admin:postgres@host.docker.internal:55434/postgres?sslmode=disable",
        "--env",
        `GOTRUE_JWT_SECRET=${jwtSecret}`,
        "--env",
        "GOTRUE_EXTERNAL_EMAIL_ENABLED=true",
        "--env",
        "GOTRUE_MAILER_AUTOCONFIRM=false",
        "--env",
        "GOTRUE_MAILER_SECURE_EMAIL_CHANGE_ENABLED=true",
        "--env",
        "GOTRUE_HOOK_SEND_EMAIL_ENABLED=true",
        "--env",
        `GOTRUE_HOOK_SEND_EMAIL_URI=http://host.docker.internal:${server.addr.port}`,
        "--env",
        `GOTRUE_HOOK_SEND_EMAIL_SECRETS=v1,whsec_${secret}`,
        "--env",
        "GOTRUE_SMTP_MAX_FREQUENCY=0s",
        "supabase/gotrue:v2.189.0@sha256:cce6c1d00352f22ee7634066012830f69636c157017ea166634c48dbb58eefb7",
      ]);
      const port = (await command(["port", name, "9999/tcp"])).split(":").at(
          -1,
        ),
        origin = `http://127.0.0.1:${port}`;
      let healthy = false;
      for (let i = 0; i < 100; i++) {
        try {
          const response = await fetch(`${origin}/health`);
          healthy = response.ok;
          await response.text();
          if (healthy) break;
        } catch {}
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      if (!healthy) {
        throw new Error(
          "pinned Auth unhealthy: " +
            (await command(["logs", name])).slice(-1500),
        );
      }
      const email = `native-${crypto.randomUUID()}@example.invalid`;
      const created = await fetch(`${origin}/admin/users`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jwt}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email,
          password: "fixture-only-password",
          email_confirm: true,
        }),
      });
      const data = await created.json();
      assertEquals(created.status, 200);
      user = data.id;
      await client.query(
        "INSERT INTO public.user_info(id,organization,name) VALUES($1,1,$2) ON CONFLICT(id) DO UPDATE SET organization=1",
        [user, "Native email fixture"],
      );
      const recover = () =>
        fetch(`${origin}/recover`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email }),
        });
      const failure = await recover();
      await failure.text();
      assert(
        failure.status >= 400,
        "Auth does not claim success before durable enqueue",
      );
      assertEquals(callbacks, 0);
      available = true;
      const success = await recover();
      await success.text();
      assertEquals(success.status, 200);
      assertEquals(callbacks, 1);
      const rows = (await client.query(
        "SELECT workflow_state,tracking_policy,prepared::text payload FROM public.email_messages WHERE recipient_user=$1 AND message_kind='gotrue'",
        [user],
      )).rows;
      assertEquals(rows.length, 1);
      assertEquals(rows[0].workflow_state, "pending");
      assertEquals(rows[0].tracking_policy, "disabled");
      assert(!rows[0].payload.includes("href"));
      assert(rows[0].payload.includes("ciphertext"));

      const login = await fetch(`${origin}/token?grant_type=password`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password: "fixture-only-password" }),
      });
      const session = await login.json();
      assertEquals(login.status, 200);
      const nextEmail = `changed-${crypto.randomUUID()}@example.invalid`;
      const changed = await fetch(`${origin}/user`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ email: nextEmail }),
      });
      await changed.text();
      assertEquals(changed.status, 200);
      assertEquals(
        callbacks,
        3,
        "secure email change records two independent proofs",
      );
      const changeRows = (await client.query(
        "SELECT recipient,prepared FROM public.email_messages WHERE recipient_user=$1 AND message_kind='gotrue' ORDER BY id DESC LIMIT 2",
        [user],
      )).rows;
      assertEquals(
        changeRows.map((r: any) => r.recipient).sort(),
        [email, nextEmail].sort(),
      );
      for (const row of changeRows) {
        const body = await openEmail<{ html: string }>(row.prepared);
        const href = body.html.match(/href="([^"]+)"/)?.[1];
        assert(href);
        const link = new URL(href.replaceAll("&amp;", "&"));
        assertEquals(link.searchParams.get("type"), "email_change");
        const verified = await fetch(`${origin}/verify?${link.searchParams}`, {
          redirect: "manual",
        });
        await verified.text();
        assert([302, 303].includes(verified.status));
        assert(
          !verified.headers.get("location")?.includes("error="),
          "each recipient receives the correct native proof",
        );
      }
      assertEquals(
        (await client.query("SELECT email FROM auth.users WHERE id=$1", [user]))
          .rows[0].email,
        nextEmail,
        "both mapped links complete native email change",
      );
    } finally {
      try {
        await command(["rm", "--force", name]);
      } catch {}
      await server.shutdown();
      if (user) {
        await client.query(
          "DELETE FROM public.email_messages WHERE recipient_user=$1",
          [user],
        );
        await client.query("DELETE FROM public.user_info WHERE id=$1", [user]);
        await client.query("DELETE FROM auth.users WHERE id=$1", [user]);
      }
      await client.end();
      if (previousKey === undefined) Deno.env.delete("EMAIL_PAYLOAD_KEY");
      else Deno.env.set("EMAIL_PAYLOAD_KEY", previousKey);
    }
  },
});
