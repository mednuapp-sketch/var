const assert=require('assert');
function _apptSlotStartMs(dateStr, timeStr) {
  const m = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec((timeStr || "").trim());
  if (!m || !dateStr) return null;
  let hour = parseInt(m[1], 10) % 12;
  if (/pm/i.test(m[3])) hour += 12;
  const minute = parseInt(m[2], 10);
  const iso = `${dateStr}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00+05:30`;
  const ms = Date.parse(iso);
  return Number.isNaN(ms) ? null : ms;
}
function end(startMs,mins){const n=Number(mins);const d=Number.isFinite(n)&&n>0?n:30;return startMs+d*60000;}
const ist=ms=>new Date(ms+19800000).toISOString().slice(0,16);
const t=(d,tm,m)=>ist(end(_apptSlotStartMs(d,tm),m));
assert.equal(t('2026-11-13','12:00 AM',30),'2026-11-13T00:30');
assert.equal(t('2026-11-13','12:00 PM',30),'2026-11-13T12:30');
assert.equal(t('2026-11-13','12:30 PM',45),'2026-11-13T13:15');
assert.equal(t('2026-11-13','11:30 PM',30),'2026-11-14T00:00');
assert.equal(t('2026-11-13','11:30 PM',60),'2026-11-14T00:30');
assert.equal(t('2026-12-31','11:45 PM',45),'2027-01-01T00:30');
assert.equal(t('2026-11-13','09:15 AM',undefined),'2026-11-13T09:45');
assert.equal(t('2026-11-13','09:15 AM',0),'2026-11-13T09:45');
assert.equal(_apptSlotStartMs('2026-11-13','garbage'),null);
console.log('all pass');
