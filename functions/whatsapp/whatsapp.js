/**
 * Thin fetch-based client for the WhatsApp Cloud API (Graph API).
 * No SDK dependency — Node 22 has global `fetch` built in.
 */

const {
  WHATSAPP_TOKEN,
  WHATSAPP_PHONE_NUMBER_ID,
  WHATSAPP_GRAPH_VERSION,
} = require("./config");
const {TEMPLATES} = require("./templates");

/** Digits only; a bare 10-digit number gets 91 prepended. */
function normalizePhone(raw) {
  if (!raw) return null;
  const digits = String(raw).replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length === 10) return `91${digits}`;
  return digits;
}

function _graphUrl() {
  const ver = WHATSAPP_GRAPH_VERSION.value();
  const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value();
  return `https://graph.facebook.com/${ver}/${phoneNumberId}/messages`;
}

/** 429 or any 5xx is worth retrying; everything else (400s) is not. */
function _isRetryable(status) {
  return status === 429 || (status >= 500 && status < 600);
}

async function _post(body) {
  const token = WHATSAPP_TOKEN.value();
  try {
    const resp = await fetch(_graphUrl(), {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    const data = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      return {
        ok: false,
        retryable: _isRetryable(resp.status),
        status: resp.status,
        error: data?.error || data,
      };
    }
    const messageId = data?.messages?.[0]?.id || null;
    return {ok: true, messageId};
  } catch (e) {
    // Network-level failure — treat as retryable.
    return {ok: false, retryable: true, error: String(e?.message || e)};
  }
}

/**
 * Sends an approved template message.
 * @param {string} to E.164/normalized recipient phone (digits only, no '+').
 * @param {string} key Template key from templates.js.
 * @param {string[]} params Ordered body param values, matching template.params.
 * @param {string} lang Language code (e.g. "en").
 * @param {string} refId Used to build quick-reply button payloads "ACTION:refId".
 */
async function sendTemplate(to, key, params, lang, refId) {
  const tpl = TEMPLATES[key];
  if (!tpl) return {ok: false, retryable: false, error: `Unknown template: ${key}`};

  const components = [
    {
      type: "body",
      parameters: params.map((p) => ({type: "text", text: String(p)})),
    },
  ];

  if (tpl.buttons && tpl.buttons.length) {
    tpl.buttons.forEach((btn, index) => {
      components.push({
        type: "button",
        sub_type: "quick_reply",
        index: String(index),
        parameters: [
          {type: "payload", payload: `${btn.action}:${refId}`},
        ],
      });
    });
  }

  return _post({
    messaging_product: "whatsapp",
    to,
    type: "template",
    template: {
      name: key,
      language: {code: lang},
      components,
    },
  });
}

/** Free-form text — only usable within Meta's 24h customer-service window. */
async function sendText(to, body) {
  return _post({
    messaging_product: "whatsapp",
    to,
    type: "text",
    text: {body, preview_url: false},
  });
}

/** Marks an inbound message read (blue ticks) — best-effort, errors swallowed. */
async function markRead(messageId) {
  try {
    const token = WHATSAPP_TOKEN.value();
    const ver = WHATSAPP_GRAPH_VERSION.value();
    const phoneNumberId = WHATSAPP_PHONE_NUMBER_ID.value();
    await fetch(`https://graph.facebook.com/${ver}/${phoneNumberId}/messages`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        status: "read",
        message_id: messageId,
      }),
    });
  } catch (_) {
    // Non-critical.
  }
}

module.exports = {normalizePhone, sendTemplate, sendText, markRead};
