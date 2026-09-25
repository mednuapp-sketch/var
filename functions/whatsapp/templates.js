/**
 * Single source of truth for every WhatsApp template this app sends.
 *
 * `body` is the literal approved template text (for reference/docs only —
 * WhatsApp doesn't need it re-sent, only the ordered param values). `params`
 * lists, in order, what each {{1}}, {{2}}... maps to — this is what callers
 * in triggers.js/reminders.js must supply, in that order. `buttons`, when
 * present, are QUICK_REPLY buttons; `action` is the payload prefix a webhook
 * reply is matched against (see webhook.js), sent as `ACTION:refId`.
 *
 * All templates are category UTILITY with footer "MedNU - Always With You".
 */

const FOOTER = "MedNU - Always With You";
const CATEGORY = "UTILITY";

const TEMPLATES = {
  mednu_booking_received: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hi {{1}}, we have received your booking with Dr. {{2}} for {{3}}. " +
      "We will notify you as soon as the doctor confirms. Booking ID: {{4}}. " +
      "Thank you for choosing MedNU.",
    params: ["patientName", "doctorName", "when", "bookingId"],
    example: ["Ravi", "Navya", "25 Sep, 5:30 PM", "BK1234"],
    buttons: [{text: "Cancel booking", action: "CANCEL"}],
  },

  mednu_booking_confirmed: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hi {{1}}, your appointment with Dr. {{2}} is confirmed for {{3}}. " +
      "Booking ID: {{4}}. Please keep the MedNU app handy at the time of your visit.",
    params: ["patientName", "doctorName", "when", "bookingId"],
    example: ["Ravi", "Navya", "25 Sep, 5:30 PM", "BK1234"],
    buttons: [
      {text: "Reschedule", action: "RESCHEDULE"},
      {text: "Cancel booking", action: "CANCEL"},
    ],
  },

  mednu_appointment_reminder: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Reminder: Hi {{1}}, your appointment with Dr. {{2}} is today at {{3}}. " +
      "Booking ID: {{4}}. Please confirm if you will be available.",
    params: ["patientName", "doctorName", "time", "bookingId"],
    example: ["Ravi", "Navya", "5:30 PM", "BK1234"],
    buttons: [
      {text: "Yes, I'll be there", action: "CONFIRM"},
      {text: "Reschedule", action: "RESCHEDULE"},
      {text: "Cancel booking", action: "CANCEL"},
    ],
  },

  mednu_booking_cancelled: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hi {{1}}, your appointment with Dr. {{2}} on {{3}} has been cancelled. " +
      "Booking ID: {{4}}. Any eligible refund will be processed to your original payment method.",
    params: ["patientName", "doctorName", "when", "bookingId"],
    example: ["Ravi", "Navya", "25 Sep, 5:30 PM", "BK1234"],
  },

  mednu_doctor_on_the_way: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hi {{1}}, Dr. {{2}} is on the way for your home visit and should reach you by {{3}}. " +
      "Booking ID: {{4}}. You can track the visit in the MedNU app.",
    params: ["patientName", "doctorName", "eta", "bookingId"],
    example: ["Ravi", "Navya", "5:45 PM", "BK1234"],
    // Defined per spec but currently unwired: regular doctor appointments
    // have no "on the way" concept in this app (that's ambulance-only) —
    // see triggers.js's comment at the top of the appointments trigger.
  },

  mednu_order_update: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hi {{1}}, your {{2}} order {{3}} is now {{4}}. " +
      "You can track it anytime in the MedNU app.",
    params: ["patientName", "orderType", "orderId", "statusLabel"],
    example: ["Ravi", "medicine", "OD5678", "out for delivery"],
  },

  mednu_report_ready: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hi {{1}}, your report for order {{2}} is ready. " +
      "For your privacy, please open the MedNU app to view it.",
    params: ["patientName", "orderId"],
    example: ["Ravi", "OD5678"],
  },

  mednu_payment_received: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hi {{1}}, we have received your payment of Rs. {{2}} for booking {{3}}. " +
      "Thank you for choosing MedNU.",
    params: ["patientName", "amount", "bookingId"],
    example: ["Ravi", "500", "BK1234"],
  },

  mednu_doctor_new_booking: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hello Dr. {{1}}, you have a new {{2}} booking from {{3}} for {{4}}. " +
      "Please accept or decline it.",
    params: ["doctorName", "visitType", "patientName", "when"],
    example: ["Navya", "video", "Ravi", "25 Sep, 5:30 PM"],
    buttons: [
      {text: "Accept", action: "ACCEPT"},
      {text: "Decline", action: "DECLINE"},
    ],
  },

  mednu_doctor_booking_cancelled: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hello Dr. {{1}}, the booking from {{2}} for {{3}} has been cancelled by the patient. " +
      "Booking ID: {{4}}. Your schedule has been updated in MedNU Service.",
    params: ["doctorName", "patientName", "when", "bookingId"],
    example: ["Navya", "Ravi", "25 Sep, 5:30 PM", "BK1234"],
  },

  mednu_doctor_appointment_reminder: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hello Dr. {{1}}, reminder: you have an appointment with {{2}} today at {{3}}. " +
      "Booking ID: {{4}}. Please be available on time.",
    params: ["doctorName", "patientName", "time", "bookingId"],
    example: ["Navya", "Ravi", "5:30 PM", "BK1234"],
  },

  mednu_doctor_payout_processed: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hello Dr. {{1}}, your payout of Rs. {{2}} has been processed. Reference: {{3}}. " +
      "It may take 1-2 working days to reflect in your bank account.",
    params: ["doctorName", "amount", "reference"],
    example: ["Navya", "5000", "PAYOUT123"],
  },

  // Addition beyond the original 12: the settlements payout trigger covers
  // all 8 partner roles (per explicit request), but "Hello Dr. {{1}}" only
  // reads correctly for a doctor. Same copy, no "Dr." — used for Lab,
  // Pharmacy, Ambulance, Caregiver, Physiotherapist, Counsellor, Nutritionist.
  mednu_partner_payout_processed: {
    category: CATEGORY,
    footer: FOOTER,
    body:
      "Hello {{1}}, your payout of Rs. {{2}} has been processed. Reference: {{3}}. " +
      "It may take 1-2 working days to reflect in your bank account.",
    params: ["partnerName", "amount", "reference"],
    example: ["Priya Lab Services", "5000", "PAYOUT123"],
  },
};

module.exports = {TEMPLATES};
