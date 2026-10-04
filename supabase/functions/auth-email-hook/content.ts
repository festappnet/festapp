const actions: Record<string, string> = {
  signup: "Confirm your account",
  invite: "You have been invited",
  magiclink: "Sign in",
  recovery: "Reset your password",
  email_change: "Confirm your email address",
  reauthentication: "Confirm your identity",
};
function escape(value: string) {
  return value.replace(
    /[&<>"']/g,
    (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]!),
  );
}
export function authEmailContent(
  data: Record<string, unknown>,
  publicAuthUrl: string,
) {
  const action = String(data.email_action_type ?? "");
  if (
    !actions[action] || typeof data.token !== "string" ||
    !/^[a-zA-Z0-9]+$/.test(data.token)
  ) throw new Error("invalid_auth_email");
  const base = new URL(publicAuthUrl);
  if (base.protocol !== "https:" || base.username || base.password) {
    throw new Error("invalid_auth_public_url");
  }
  let html = `<p>${escape(actions[action])}</p><p><strong>${
    escape(data.token)
  }</strong></p>`;
  if (action !== "reauthentication") {
    if (typeof data.token_hash !== "string" || !data.token_hash) {
      throw new Error("missing_auth_proof");
    }
    const link = new URL("/auth/v1/verify", base);
    link.searchParams.set("token", data.token_hash);
    link.searchParams.set("type", action);
    if (typeof data.redirect_to === "string" && data.redirect_to) {
      link.searchParams.set("redirect_to", data.redirect_to);
    }
    html += `<p><a href="${escape(link.href)}">${
      escape(actions[action])
    }</a></p>`;
  }
  return { id: null, subject: `Festapp - ${actions[action]}`, html };
}
export function authEmailRecipients(
  user: Record<string, unknown>,
  data: Record<string, unknown>,
) {
  const action = data.email_action_type;
  if (action === "email_change") {
    if (typeof user.new_email !== "string" || !user.new_email) {
      throw new Error("missing_new_email");
    }
    const recipients: Array<
      { to: string; data: Record<string, unknown>; suffix: string }
    > = [{
      to: user.new_email,
      data: {
        ...data,
        token: data.token_new ?? data.token,
        token_hash: data.token_hash,
      },
      suffix: "new",
    }];
    if (
      data.token_new && data.token_hash_new && typeof user.email === "string" &&
      user.email
    ) {
      recipients.push({
        to: user.email,
        data: { ...data, token_hash: data.token_hash_new },
        suffix: "current",
      });
    }
    return recipients;
  }
  if (typeof user.email !== "string" || !user.email) {
    throw new Error("missing_auth_recipient");
  }
  return [{ to: user.email, data, suffix: "current" }];
}
