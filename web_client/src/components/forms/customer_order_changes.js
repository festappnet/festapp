import { LocalizationService } from "../../services/localization_service.js";
const text = (key) => LocalizationService.tr(`CustomerSelfService.${key}`);
const node = (host, tag, value = "", attrs = {}) => {
  const el = document.createElement(tag);
  el.textContent = value;
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  host.append(el);
  return el;
};
const button = (host, label, action) => {
  const b = node(host, "button", text(label), { type: "button" });
  b.onclick = action;
  return b;
};
export function takeCustomerChangeToken(win = globalThis.window) {
  const token = win?.__festappCustomerChangeToken;
  if (win) delete win.__festappCustomerChangeToken;
  return token || null;
}
export async function customerChangeCall(client, body) {
  const { data, error } = await client.functions.invoke(
    "customer-order-changes",
    { body, timeout: 20000 },
  );
  if (error || ![200, 202].includes(data?.code)) {
    let status = data?.code;
    try {
      if (error?.context?.json) status = (await error.context.json()).code;
    } catch { /* A transport failure has no proven result. */ }
    throw Object.assign(
      new Error(
        status === 409 ? "conflict" : status === 422 ? "invalid" : status === 403 ? "unavailable" : "failed",
      ),
      { status },
    );
  }
  return data;
}
export function renderCustomerOrderChanges(
  host,
  data,
  scope,
  client,
  onRefresh,
) {
  if (!scope || !client) return;
  const ticketLabel = id => {
    const person = data.people.find(p => String(p.id) === String(id));
    const items = (data.orders || []).flatMap(o => o.items || []).filter(i => String(i.ticketId) === String(id));
    return [person?.label || `${text("ticket")} ${id}`, ...items.map(i => [i.title,i.spotGroupTitle,i.spotTitle].filter(Boolean).join(" / "))].join(" - ");
  };
  const actions = (data.allowedActions || []).filter((a) => a.enabled);
  const requests = data.changeRequests || [];
  let session = host._customerChangeSession;
  const token = takeCustomerChangeToken();
  if (token) {
    session = host._customerChangeSession = {
      token,
      commandId: crypto.randomUUID(),
    };
  }
  if (!actions.length && !requests.length && !session) return;
  const panel = node(host, "section", "", {
    class: "overview-customer-changes",
    "aria-labelledby": "customer-changes-title",
  });
  node(panel, "h2", text("title"), { id: "customer-changes-title" });
  const locale = LocalizationService.currentLocale;
  node(panel, "a", text("help"), {
    href: locale === "cs" ? "/napoveda/zakaznicka-samoobsluha/" : "/help/customer-self-service/",
    target: "_blank", rel: "noopener noreferrer",
  });
  const status = node(panel, "p", "", {
    role: "status",
    "aria-live": "polite",
  });
  const work = node(panel, "div");
  const report = (error) => {
    status.textContent = text(["conflict", "invalid", "unavailable"].includes(error?.message) ? error.message : "failed");
    status.setAttribute("role", "alert");
  };
  const end = () => {
    work.replaceChildren();
    delete host.dataset.customerEditing;
  };
  const busy = async (b, fn) => {
    if (b.disabled) return;
    b.disabled = true;
    b.setAttribute("aria-busy", "true");
    try {
      await fn();
    } catch (e) {
      report(e);
    } finally {
      b.disabled = false;
      b.removeAttribute("aria-busy");
    }
  };
  async function challenge(operation, payload, b) {
    await busy(b, async () => {
      await customerChangeCall(client, {
        action: "challenge",
        token: scope.token,
        orderId: scope.orderId,
        operation,
        payload,
      });
      status.textContent = text("linkSent");
      end();
    });
  }
  function open(action) {
    end();
    host.dataset.customerEditing = "true";
    status.textContent = "";
    const form = node(work, "form");
    node(form, "h3", text(action.operation));
    const inputs = [];
    const addField = (field, ticketId, value) => {
      const group = node(form, "div", "", { class: "customer-change-field" });
      const id = `customer-field-${ticketId ?? "order"}-${field.id}`;
      node(group, "label", field.title, { for: id });
      let input;
      if (field.type === "select_one") {
        input = node(group, "select", "", { id });
        node(input, "option", "", { value: "" });
        for (const option of field.options || []) {
          node(input, "option", option.title ?? option.label ?? option.value, {
            value: option.value,
          });
        }
      } else {input = node(group, "input", "", {
          id,
          type: field.type === "phone" ? "tel" : "text",
          maxlength: "4000",
          autocomplete: "off",
        });}
      input.value = value ?? "";
      input.required = field.required === true;
      inputs.push({ input, field, ticketId, old: input.value });
    };
    if (action.operation === "edit") {
      for (const field of action.fields || []) {
        if (field.ticket) {
          for (const value of field.values || []) {
            const person = data.people.find((p) => p.id === value.ticketId);
            node(form, "p", person?.label || `${value.ticketId}`);
            addField(field, value.ticketId, value.value);
          }
        } else addField(field, null, field.value);
      }
    }
    const selectedTickets = [];
    if (action.operation === "cancel" && action.tickets?.length) {
      const group = node(form, "fieldset");
      node(group, "legend", text("selectTickets"));
      for (const ticket of action.tickets) {
        const label = node(group, "label");
        const input = node(label, "input", "", {type:"checkbox"});
        input.checked = true;
        node(label, "span", ticketLabel(ticket.id));
        selectedTickets.push({id:ticket.id,input});
      }
    }
    let target, reason;
    if (action.operation === "move") {
      const id = "customer-target";
      node(form, "label", text("target"), { for: id });
      target = node(form, "select", "", { id, required: "" });
      node(target, "option", "", { value: "" });
      for (const t of action.targets || []) {
        const date = t.startsAt
          ? new Date(t.startsAt).toLocaleString(
            LocalizationService.currentLocale,
          )
          : "";
        node(
          target,
          "option",
          `${t.title || ""}${date ? ` - ${date}` : ""}${t.automatic ? "" : ` (${text("manual")})`}`,
          { value: String(t.formId) },
        );
      }
    }
    if (action.operation !== "edit") {
      node(
        form,
        "label",
        text(action.reasonRequired ? "reasonRequired" : "reason"),
        { for: "customer-reason" },
      );
      reason = node(form, "textarea", "", {
        id: "customer-reason",
        maxlength: "2000",
        rows: "3",
      });
      reason.required = action.reasonRequired === true;
    }
    const submit = node(form, "button", text("sendLink"), { type: "submit" });
    button(form, "close", end);
    form.onsubmit = (event) => {
      event.preventDefault();
      if (!form.reportValidity()) return;
      let payload = {};
      if (action.operation === "edit") {
        payload = { order: {}, tickets: {} };
        for (const entry of inputs) {
          if (entry.input.value === entry.old) continue;
          if (entry.ticketId == null) {
            payload.order[entry.field.id] = entry.input.value;
          } else {(payload.tickets[entry.ticketId] ??= {})[entry.field.id] =
              entry.input.value;}
        }
        if (
          !Object.keys(payload.order).length &&
          !Object.keys(payload.tickets).length
        ) {
          status.textContent = text("noChanges");
          return;
        }
      } else {
        payload = { reason: reason.value.trim() };
        if (selectedTickets.length) {
          payload.ticketIds = selectedTickets.filter(t => t.input.checked).map(t => t.id);
          if (!payload.ticketIds.length) { status.textContent = text("selectOneTicket"); return; }
        }
        if (target) payload.targetFormId = Number(target.value);
      }
      challenge(action.operation, payload, submit);
    };
    form.querySelector("input,select,textarea,button")?.focus();
  }
  if (actions.length && !session) {
    node(panel, "p", text("intro"));
    const controls = node(panel, "div", "", {
      class: "overview-admission-actions",
    });
    for (const action of actions) {
      button(controls, action.operation, () => open(action));
    }
  } else if (!session) node(panel, "p", text("noActions"));
  if (requests.length) {
    node(panel, "h3", text("requests"));
    const list = node(panel, "ul");
    for (const request of requests) {
      const item = node(list, "li");
      node(item, "p", `${text(request.operation)}: ${text(request.status)}`);
      if (request.ticketIds?.length) node(panel, "p", request.ticketIds.map(ticketLabel).join(", "));
      if (request.reason) node(item, "p", request.reason);
      if (request.response) {
        node(item, "p", `${text("response")}: ${request.response}`);
      }
      if (request.canWithdraw) {
        const b = button(
          item,
          "withdraw",
          () => challenge("withdraw", { requestId: request.id }, b),
        );
      }
    }
  }
  if (session) {
    host.dataset.customerEditing = "true";
    async function preview() {
      work.replaceChildren();
      status.textContent = text("busy");
      try {
        if (!session.proposal) {
          const source = await customerChangeCall(client, {
            action: "resolve",
            token: session.token,
            commandId: session.commandId,
          });
          if (source.orderId !== scope.orderId) throw new Error("unavailable");
          session.proposal = source;
        }
        const proposal = session.proposal;
        const impact = await customerChangeCall(client, {
          action: "preview",
          token: session.token,
          operation: proposal.operation,
          payload: proposal.payload,
          commandId: session.commandId,
        });
        if (!panel.isConnected) return;
        status.textContent = "";
        node(work, "h3", text("preview"));
        node(work, "p", text("review"));
        node(
          work,
          "p",
          text(impact.partial ? `${impact.effect}_selected` :
            ["edit", "move", "withdraw", "cancel"].includes(impact.effect)
              ? `${impact.effect}_effect`
              : impact.effect,
          ),
        );
        if (proposal.operation === "cancel" && impact.partial) {
          node(work, "p", text("remainingTickets"));
          const list = node(work, "ul");
          for (const id of impact.ticketIds || []) node(list, "li", ticketLabel(id));
        }
        if (proposal.operation === "edit") {
          for (
            const [fieldId, value] of Object.entries(
              proposal.payload.order || {},
            )
          ) {
            const f = actions.find((a) => a.operation === "edit")?.fields?.find(
              (f) => String(f.id) === fieldId,
            );
            node(work, "p", `${f?.title || fieldId}: ${value}`);
          }
          for (
            const [ticketId, fields] of Object.entries(
              proposal.payload.tickets || {},
            )
          ) {
            node(
              work,
              "h4",
              data.people.find((p) => String(p.id) === ticketId)?.label ||
                ticketId,
            );
            for (const [fieldId, value] of Object.entries(fields)) {
              const f = actions.find((a) => a.operation === "edit")?.fields
                ?.find((f) => String(f.id) === fieldId);
              node(work, "p", `${f?.title || fieldId}: ${value}`);
            }
          }
        }
        if (impact.refundAmount > 0) {
          node(
            work,
            "p",
            `${text("amount")}: ${
              new Intl.NumberFormat(LocalizationService.currentLocale, {
                style: "currency",
                currency: impact.currency,
              }).format(impact.refundAmount)
            }`,
          );
        }
        if (impact.target) {
          node(
            work,
            "p",
            `${text("target")}: ${
              [impact.target.title, impact.target.startsAt
                ? new Date(impact.target.startsAt).toLocaleString(
                  LocalizationService.currentLocale,
                )
                : null].filter(Boolean).join(" - ")
            }`,
          );
          node(work, "p", text("difference"));
          for (const ticket of impact.target.tickets || []) {
            for (const item of ticket.products || []) {
              node(
                work,
                "p",
                `${item.title}: ${item.price} ${item.currency_code}`,
              );
            }
          }
        }
        if (proposal.payload.reason) {
          node(work, "p", `${text("reason")}: ${proposal.payload.reason}`);
        }
        const confirm = button(
          work,
          impact.effect.startsWith("request_")
            ? "confirmRequest"
            : impact.effect.startsWith("cancel")
            ? "confirmCancel"
            : "confirm",
          () =>
            busy(confirm, async () => {
              try {
                await customerChangeCall(client, {
                  action: "command",
                  token: session.token,
                  operation: proposal.operation,
                  payload: proposal.payload,
                  commandId: session.commandId,
                  fingerprint: impact.fingerprint,
                });
                delete host._customerChangeSession;
                end();
                status.textContent = text("success");
                await onRefresh();
              } catch (error) {
                if (error.status === 409) {
                  confirm.remove();
                  session.commandId = crypto.randomUUID();
                  button(work, "refreshPreview", preview);
                }
                throw error;
              }
            }),
        );
        button(work, "close", () => {
          delete host._customerChangeSession;
          end();
        });
        confirm.focus();
      } catch (error) {
        report(error);
        button(work, "refreshPreview", preview);
      }
    }
    preview();
  }
}
