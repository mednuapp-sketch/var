#!/usr/bin/env node
/**
 * One-time/idempotent setup: creates every template in whatsapp/templates.js
 * on the WhatsApp Business Account via the Graph API, skipping any that
 * already exist by name.
 *
 * Reads WHATSAPP_TOKEN and WHATSAPP_WABA_ID from the environment — this
 * script does NOT read functions/.env or Cloud Functions secrets itself; run
 * it with those two exported in your shell first (see the checklist in the
 * PR/chat this shipped with). Never hardcode the token here.
 *
 * Usage: npm run templates:create
 */

const path = require("path");
const {TEMPLATES} = require(path.join(__dirname, "..", "whatsapp", "templates"));

const GRAPH_VERSION = process.env.WHATSAPP_GRAPH_VERSION || "v25.0";
const WABA_ID = process.env.WHATSAPP_WABA_ID;
const TOKEN = process.env.WHATSAPP_TOKEN;
const DEFAULT_LANG = process.env.WHATSAPP_DEFAULT_LANG || "en";

function _fail(msg) {
  console.error(`create-templates: ${msg}`);
  process.exit(1);
}

async function _listExistingNames() {
  const url = `https://graph.facebook.com/${GRAPH_VERSION}/${WABA_ID}/message_templates?fields=name&limit=200`;
  let resp;
  try {
    resp = await fetch(url, {headers: {Authorization: `Bearer ${TOKEN}`}});
  } catch (e) {
    // Node's fetch (undici) hides the actual network error behind a generic
    // "fetch failed" TypeError — the real cause (DNS failure, connection
    // refused, TLS error, proxy interference) is on e.cause.
    const cause = e && e.cause ? ` — cause: ${e.cause.code || e.cause.message || e.cause}` : "";
    _fail(`network request to graph.facebook.com failed: ${e.message}${cause}`);
  }
  const data = await resp.json();
  if (!resp.ok) {
    _fail(`failed to list existing templates: ${JSON.stringify(data)}`);
  }
  return new Set((data.data || []).map((t) => t.name));
}

function _buildComponents(key, tpl) {
  const bodyExample = {body_text: [tpl.example.map(String)]};
  const components = [
    {
      type: "BODY",
      text: tpl.body,
      example: bodyExample,
    },
    {
      type: "FOOTER",
      text: tpl.footer,
    },
  ];

  if (tpl.buttons && tpl.buttons.length) {
    components.push({
      type: "BUTTONS",
      buttons: tpl.buttons.map((b) => ({
        type: "QUICK_REPLY",
        text: b.text,
      })),
    });
  }

  return components;
}

async function _createTemplate(key, tpl) {
  const url = `https://graph.facebook.com/${GRAPH_VERSION}/${WABA_ID}/message_templates`;
  const body = {
    name: key,
    language: DEFAULT_LANG,
    category: tpl.category,
    components: _buildComponents(key, tpl),
  };
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const data = await resp.json();
  if (!resp.ok) {
    console.error(`  ✗ ${key}: ${JSON.stringify(data.error || data)}`);
    return false;
  }
  console.log(`  ✓ ${key} (id: ${data.id})`);
  return true;
}

async function main() {
  if (!TOKEN) _fail("WHATSAPP_TOKEN is not set in the environment.");
  if (!WABA_ID) _fail("WHATSAPP_WABA_ID is not set in the environment.");

  console.log(`create-templates: listing existing templates on WABA ${WABA_ID}...`);
  const existing = await _listExistingNames();
  console.log(`create-templates: ${existing.size} existing template(s) found.`);

  const missing = Object.entries(TEMPLATES).filter(([key]) => !existing.has(key));
  if (missing.length === 0) {
    console.log("create-templates: nothing to do, all templates already exist.");
    return;
  }

  console.log(`create-templates: creating ${missing.length} missing template(s)...`);
  let failures = 0;
  for (const [key, tpl] of missing) {
    const ok = await _createTemplate(key, tpl);
    if (!ok) failures++;
  }

  if (failures > 0) {
    console.error(`create-templates: ${failures} template(s) failed to create — see above.`);
    process.exit(1);
  }
  console.log("create-templates: done. Templates are now pending Meta review before they can be sent.");
}

main().catch((e) => _fail(e?.stack || String(e)));
