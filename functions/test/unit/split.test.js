const { T } = require("../harness");
const _computeProviderSplit = T._computeProviderSplit;
const assert = require("assert");
const snap = (d) => ({ exists: !!d, data: () => d });
const cfg = snap({ enabled: true, defaultAmount: 10, services: { consultation: 20 } });

// no coupon: base 500 + fee 20 = 520 paid
let r = _computeProviderSplit(cfg, "consultation", 520, 520);
assert.deepStrictEqual(r, { commission: 0, platformFee: 20, providerAmount: 500, baseAmount: 500 });
// coupon 50: paid 470, provider = 450 (coupon reduces provider)
r = _computeProviderSplit(cfg, "consultation", 470, 520);
assert.strictEqual(r.providerAmount, 450); assert.strictEqual(r.platformFee, 20); assert.strictEqual(r.baseAmount, 500);
// free consultation: settled on original
r = _computeProviderSplit(cfg, "consultation", 520, 520);
assert.strictEqual(r.providerAmount, 500);
// fee 0 (disabled / missing doc)
r = _computeProviderSplit(snap({ enabled: false, defaultAmount: 99 }), "consultation", 500, 500);
assert.strictEqual(r.platformFee, 0); assert.strictEqual(r.providerAmount, 500);
r = _computeProviderSplit(snap(null), "consultation", 500, 500);
assert.strictEqual(r.providerAmount, 500);
// default fee + alias normalisation
r = _computeProviderSplit(cfg, "lab_tests", 110, 110);
assert.strictEqual(r.platformFee, 10); assert.strictEqual(r.providerAmount, 100);
// fee > paid (heavy coupon): provider floors at 0, fee capped at original
r = _computeProviderSplit(cfg, "consultation", 5, 520);
assert.strictEqual(r.providerAmount, 0);
r = _computeProviderSplit(cfg, "consultation", 15, 15);
assert.strictEqual(r.platformFee, 15); assert.strictEqual(r.providerAmount, 0); assert.strictEqual(r.baseAmount, 0);
// zero paid
r = _computeProviderSplit(cfg, "consultation", 0, 0);
assert.strictEqual(r.providerAmount, 0);
{
  const pc = snap({ enabled: true, defaultAmount: 10, services: { medicine: 25 }, providers: { pharmA: { amount: 5 } } });
  let q = _computeProviderSplit(pc, "medicine", 105, 105, "pharmA");
  assert.deepStrictEqual(q, { commission: 0, platformFee: 5, providerAmount: 100, baseAmount: 100 });
  q = _computeProviderSplit(pc, "medicine", 125, 125, "other");
  assert.strictEqual(q.platformFee, 25); assert.strictEqual(q.providerAmount, 100);
  q = _computeProviderSplit(pc, "medicine", 125, 125);
  assert.strictEqual(q.platformFee, 25);
}
console.log("all ok");
