/**
 * Free-slot lookup for rescheduling an appointment over WhatsApp.
 *
 * Mirrors the patient app's booking screen
 * (`mednu/lib/features/doctors/screens/doctor_profile_screen.dart`'s
 * `_slotsForDate` / `_blockedSlotsForDate` / `_isSlotExpiredForDate`) so a
 * WhatsApp patient is offered exactly the times the app would offer:
 * the doctor's weekly `availability.schedule` (or the app's default slots
 * when none is set), minus `availability.blockedSlots`, minus slots already
 * held in `appointment_slots`, minus times that have passed — over the same
 * 10-day window. All "today"/"now" logic is in Asia/Kolkata, since the
 * stored date/time strings are IST wall-clock values.
 */

const {getFirestore} = require("firebase-admin/firestore");
const {COLLECTIONS} = require("./config");
const {parseApptDateTime} = require("./notify");

const WINDOW_DAYS = 10;
const DEFAULT_SLOTS = [
  "09:00 AM", "10:00 AM", "11:00 AM", "12:00 PM",
  "02:00 PM", "03:00 PM", "04:00 PM", "05:00 PM", "06:00 PM",
];

/** "yyyy-MM-dd" for `date` as seen in IST. */
function istDateKey(date) {
  return new Intl.DateTimeFormat("en-CA", {timeZone: "Asia/Kolkata"}).format(date);
}

/** The next WINDOW_DAYS IST date keys, starting today. */
function _windowDateKeys(now = new Date()) {
  const keys = [];
  for (let i = 0; i < WINDOW_DAYS; i++) {
    keys.push(istDateKey(new Date(now.getTime() + i * 86400000)));
  }
  return keys;
}

/** "Mon".."Sun" for a "yyyy-MM-dd" key — what availability.schedule is keyed by. */
function _weekdayOf(dateKey) {
  const [y, m, d] = dateKey.split("-").map(Number);
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
}

/** "Fri, 3 Oct" for a "yyyy-MM-dd" key. */
function dayLabel(dateKey) {
  const [y, m, d] = dateKey.split("-").map(Number);
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${_weekdayOf(dateKey)}, ${d} ${months[m - 1]}`;
}

function _pad(n) {
  return String(n).padStart(2, "0");
}

/** All slot strings ("05:30 PM") the doctor's schedule offers on dateKey. */
function _scheduledSlots(availability, dateKey) {
  if (!availability || !availability.schedule) return DEFAULT_SLOTS.slice();
  const ds = availability.schedule[_weekdayOf(dateKey)];
  if (!ds || ds.enabled !== true) return [];
  const duration = Number(availability.slotDuration) || 30;
  try {
    const [sh, sm] = String(ds.start || "09:00").split(":").map(Number);
    const [eh, em] = String(ds.end || "17:00").split(":").map(Number);
    const startMins = sh * 60 + sm;
    const endMins = eh * 60 + em;
    if (Number.isNaN(startMins) || Number.isNaN(endMins)) return DEFAULT_SLOTS.slice();
    const slots = [];
    for (let m = startMins; m + duration <= endMins; m += duration) {
      const h = Math.floor(m / 60);
      const period = h < 12 ? "AM" : "PM";
      const displayH = h === 0 ? 12 : (h > 12 ? h - 12 : h);
      slots.push(`${_pad(displayH)}:${_pad(m % 60)} ${period}`);
    }
    const blocked = new Set(((availability.blockedSlots || {})[dateKey]) || []);
    return slots.filter((s) => !blocked.has(s));
  } catch (_) {
    return DEFAULT_SLOTS.slice();
  }
}

/**
 * Free slots per day for `doctorId` over the booking window. Every held
 * slot counts as taken, including the current slot of the appointment being moved.
 * @return {Promise<Map<string, string[]>>} dateKey -> free slot strings, in
 *   order; only days with at least one free slot are included.
 */
async function freeSlotsByDay(doctorId, now = new Date()) {
  const db = getFirestore();
  const keys = _windowDateKeys(now);
  const [doctorSnap, takenSnap] = await Promise.all([
    db.collection(COLLECTIONS.doctors).doc(doctorId).get(),
    // Single-field equality only (no composite index needed); the date
    // window is applied below — one doctor's held slots is a small set.
    db.collection("appointment_slots").where("doctorId", "==", doctorId).get(),
  ]);
  const availability = doctorSnap.exists ? doctorSnap.data().availability : null;

  const inWindow = new Set(keys);
  const taken = new Set();
  takenSnap.forEach((d) => {
    const s = d.data();
    // Its own current slot counts as taken too — moving to the same time
    // isn't a reschedule.
    if (inWindow.has(s.date)) taken.add(`${s.date}|${s.time}`);
  });

  const result = new Map();
  for (const dateKey of keys) {
    const free = _scheduledSlots(availability, dateKey).filter((slot) => {
      if (taken.has(`${dateKey}|${slot}`)) return false;
      const at = parseApptDateTime(dateKey, slot);
      return at && at > now;
    });
    if (free.length) result.set(dateKey, free);
  }
  return result;
}

/** Picks at most `max` items spread evenly across `list` (keeps first and last). */
function spread(list, max = 10) {
  if (list.length <= max) return list.slice();
  const out = [];
  for (let i = 0; i < max; i++) out.push(list[Math.round((i * (list.length - 1)) / (max - 1))]);
  return [...new Set(out)];
}

/** "05:30 PM" <-> "0530PM": slot strings contain ':' and ' ', which the
 * "ACTION:refId:..." payload format uses as a separator. */
function encodeSlot(slot) {
  return slot.replace(/[: ]/g, "");
}
function decodeSlot(code) {
  const m = /^(\d{2})(\d{2})(AM|PM)$/.exec(code || "");
  return m ? `${m[1]}:${m[2]} ${m[3]}` : null;
}

module.exports = {freeSlotsByDay, dayLabel, spread, encodeSlot, decodeSlot, istDateKey};
