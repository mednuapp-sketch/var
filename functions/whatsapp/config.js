/**
 * Single source of truth for every collection/field/status name the WhatsApp
 * module touches, plus the secret/param definitions it needs. Nothing else
 * in this module should hardcode a Firestore collection or field name —
 * import it from here so a schema rename only needs one edit.
 */

const {defineSecret, defineString} = require("firebase-functions/params");

// ── Region ────────────────────────────────────────────────────────────────
// Every other function in this codebase has no explicit region (defaults to
// us-central1) — this module is the first to opt into asia-south1, since
// WhatsApp traffic and the patient/doctor base are India-only.
const REGION = "asia-south1";

// ── Secrets (set via `firebase functions:secrets:set`, never in code) ──────
const WHATSAPP_TOKEN = defineSecret("WHATSAPP_TOKEN");
const WHATSAPP_APP_SECRET = defineSecret("WHATSAPP_APP_SECRET");
const WHATSAPP_VERIFY_TOKEN = defineSecret("WHATSAPP_VERIFY_TOKEN");

// ── Params (non-secret, safe to keep in functions/.env) ─────────────────────
const WHATSAPP_PHONE_NUMBER_ID = defineString("WHATSAPP_PHONE_NUMBER_ID");
const WHATSAPP_GRAPH_VERSION = defineString("WHATSAPP_GRAPH_VERSION", {default: "v25.0"});
const WHATSAPP_DEFAULT_LANG = defineString("WHATSAPP_DEFAULT_LANG", {default: "en"});

// ── Collections ───────────────────────────────────────────────────────────
const COLLECTIONS = {
  users: "users",
  doctors: "doctors",
  appointments: "appointments",
  orders: "orders",
  serviceRequests: "service_requests",
  payments: "payments",
  settlements: "settlements",
  scheduledReminders: "scheduled_reminders",
  whatsappLogs: "whatsapp_logs",
};

// ── Provider-role registry ───────────────────────────────────────────────
// Every partner profile collection a `settlements` payout could belong to.
// `greeting` is the literal word (if any) the payout template's fixed text
// expects before the recipient's name — only the doctor template has one
// ("Hello Dr. {{1}}"); every other role uses the role-neutral partner
// template (see templates.js's `mednu_partner_payout_processed` — an
// addition beyond the original 12, needed because Meta templates are fixed
// text and "Hello Dr. {{1}}" is wrong for a pharmacy/lab/etc. partner).
const PROVIDER_ROLES = [
  {key: "doctor", collection: COLLECTIONS.doctors, payoutTemplate: "mednu_doctor_payout_processed"},
  {key: "lab", collection: "lab_profiles", payoutTemplate: "mednu_partner_payout_processed"},
  {key: "pharmacy", collection: "pharmacy_profiles", payoutTemplate: "mednu_partner_payout_processed"},
  {key: "ambulance", collection: "ambulance_profiles", payoutTemplate: "mednu_partner_payout_processed"},
  {key: "caregiver", collection: "caregiver_profiles", payoutTemplate: "mednu_partner_payout_processed"},
  {key: "physiotherapist", collection: "physiotherapist_profiles", payoutTemplate: "mednu_partner_payout_processed"},
  {key: "counsellor", collection: "counsellor_profiles", payoutTemplate: "mednu_partner_payout_processed"},
  {key: "nutritionist", collection: "nutritionist_profiles", payoutTemplate: "mednu_partner_payout_processed"},
];

// ── Status values actually written in this app (see Step 0 research) ───────
// `appointments.status` — NOT pending/confirmed/rejected/doctor_on_the_way:
// payment capture writes 'booked' directly; there is no approval step.
const APPOINTMENT_STATUS = {
  booked: "booked",
  cancelled: "cancelled",
  completed: "completed",
};

// `orders.status` (medicine delivery — functions/index.js _PHARMACY_VALID_TRANSITIONS)
const ORDER_STATUS = {
  pending: "pending",
  prescriptionRequired: "prescription_required",
  verified: "verified",
  packed: "packed",
  outForDelivery: "out_for_delivery",
  delivered: "delivered",
  cancelled: "cancelled",
};
const ORDER_STATUS_LABEL = {
  pending: "placed",
  prescription_required: "awaiting prescription review",
  verified: "confirmed",
  packed: "packed",
  out_for_delivery: "out for delivery",
  delivered: "delivered",
  cancelled: "cancelled",
};

// `service_requests.status` for type in (diagnostics, lab_test) — mirrored
// from diagnostic_bookings by _LAB_TO_SERVICE_REQUEST_STATUS.
const LAB_SERVICE_REQUEST_TYPES = ["diagnostics", "lab_test"];
const LAB_STATUS_LABEL = {
  pending: "requested",
  accepted: "accepted",
  assigned: "technician assigned",
  sample_collected: "sample collected",
  in_progress: "being processed",
  report_ready: "ready",
  completed: "completed",
  cancelled: "cancelled",
  rejected: "declined",
};
const LAB_REPORT_READY_STATUS = "report_ready";

// `payments.status` (standalone payments collection — NOT captured/paid/success)
const PAYMENT_STATUS = {
  completed: "completed",
};

// `settlements.status`
const SETTLEMENT_STATUS = {
  pending: "pending",
  approved: "approved",
  paid: "paid",
  held: "held",
};

module.exports = {
  REGION,
  WHATSAPP_TOKEN,
  WHATSAPP_APP_SECRET,
  WHATSAPP_VERIFY_TOKEN,
  WHATSAPP_PHONE_NUMBER_ID,
  WHATSAPP_GRAPH_VERSION,
  WHATSAPP_DEFAULT_LANG,
  COLLECTIONS,
  PROVIDER_ROLES,
  APPOINTMENT_STATUS,
  ORDER_STATUS,
  ORDER_STATUS_LABEL,
  LAB_SERVICE_REQUEST_TYPES,
  LAB_STATUS_LABEL,
  LAB_REPORT_READY_STATUS,
  PAYMENT_STATUS,
  SETTLEMENT_STATUS,
};
