const assert = require("assert");
const { computeRefundSplit: s } = require("../../razorpay_refund_helpers.js");
const eq = (a, b) => assert.deepStrictEqual(a, b);
eq(s({ paidAmount: 520, walletPortionAmount: 0, paymentMethod: "wallet" }), { refundPaise: 52000, gatewayPaise: 0, walletPaise: 52000 });
eq(s({ paidAmount: 520, walletPortionAmount: 520, paymentMethod: "already_settled" }), { refundPaise: 52000, gatewayPaise: 0, walletPaise: 52000 });
eq(s({ paidAmount: 520, walletPortionAmount: 0, paymentMethod: "razorpay" }), { refundPaise: 52000, gatewayPaise: 52000, walletPaise: 0 });
eq(s({ paidAmount: 520, walletPortionAmount: 300, paymentMethod: "razorpay" }), { refundPaise: 52000, gatewayPaise: 22000, walletPaise: 30000 });
// partial 260 of 520 (300w/220g) -> gateway 110, wallet 150
eq(s({ paidAmount: 520, walletPortionAmount: 300, paymentMethod: "razorpay", refundAmount: 260 }), { refundPaise: 26000, gatewayPaise: 11000, walletPaise: 15000 });
// rounding: 100 paid, 33.33 wallet, refund 10.01
const r = s({ paidAmount: 100, walletPortionAmount: 33.33, paymentMethod: "razorpay", refundAmount: 10.01 });
assert(Number.isInteger(r.gatewayPaise) && Number.isInteger(r.walletPaise));
assert.strictEqual(r.gatewayPaise + r.walletPaise, 1001);
assert(r.gatewayPaise <= 6667);
// refund capped at paid; fully-wallet razorpay record (wallet >= paid)
eq(s({ paidAmount: 100, walletPortionAmount: 100, paymentMethod: "razorpay", refundAmount: 500 }), { refundPaise: 10000, gatewayPaise: 0, walletPaise: 10000 });
// unknown method / zero
eq(s({ paidAmount: 100, walletPortionAmount: 0, paymentMethod: "cash" }), { refundPaise: 10000, gatewayPaise: 0, walletPaise: 0 });
eq(s({ paidAmount: 0, walletPortionAmount: 0, paymentMethod: "razorpay" }), { refundPaise: 0, gatewayPaise: 0, walletPaise: 0 });
// gateway leg never exceeds gateway portion
for (let i = 1; i <= 5200; i += 7) { const x = s({ paidAmount: 52, walletPortionAmount: 30, paymentMethod: "razorpay", refundAmount: i / 100 }); assert(x.gatewayPaise <= 2200 && x.gatewayPaise + x.walletPaise === x.refundPaise); }
console.log("ok");

// per-leg wallet refunds
const H = require("../../price_helpers.js");
{
  const legs = { main: 0, mednuMoney: 300 };
  // Rs500: 300 MedNU Money + 200 Razorpay, full refund
  eq(s({ paidAmount: 500, walletPortionAmount: 300, paymentMethod: "razorpay", walletLegs: legs }),
    { refundPaise: 50000, gatewayPaise: 20000, walletPaise: 30000, walletMednuPaise: 30000, walletMainPaise: 0 });
  // partial 250 -> gateway 100, wallet 150 all MedNU Money
  eq(s({ paidAmount: 500, walletPortionAmount: 300, paymentMethod: "razorpay", walletLegs: legs, refundAmount: 250 }),
    { refundPaise: 25000, gatewayPaise: 10000, walletPaise: 15000, walletMednuPaise: 15000, walletMainPaise: 0 });
  // mixed legs 100 mm + 200 main (wallet 300 of 500), partial 250 -> wallet 150: mm 50 / main 100
  const m = s({ paidAmount: 500, walletPortionAmount: 300, paymentMethod: "razorpay", walletLegs: { main: 200, mednuMoney: 100 }, refundAmount: 250 });
  eq([m.walletMednuPaise, m.walletMainPaise], [5000, 10000]);
  // legs not matching the wallet portion -> ignored (legacy shape)
  eq(s({ paidAmount: 500, walletPortionAmount: 300, paymentMethod: "razorpay", walletLegs: { main: 0, mednuMoney: 100 } }),
    { refundPaise: 50000, gatewayPaise: 20000, walletPaise: 30000 });
  // no legs / plain wallet payment: unchanged
  eq(s({ paidAmount: 500, walletPortionAmount: 0, paymentMethod: "wallet" }), { refundPaise: 50000, gatewayPaise: 0, walletPaise: 50000 });
  eq(s({ paidAmount: 500, walletPortionAmount: 0, paymentMethod: "wallet", walletLegs: { main: 500, mednuMoney: 0 } }),
    { refundPaise: 50000, gatewayPaise: 0, walletPaise: 50000, walletMednuPaise: 0, walletMainPaise: 50000 });
  // legs always sum to walletPaise
  for (let i = 1; i <= 50000; i += 37) { const x = s({ paidAmount: 500, walletPortionAmount: 300, paymentMethod: "razorpay", walletLegs: { main: 123.45, mednuMoney: 176.55 }, refundAmount: i / 100 });
    assert.strictEqual(x.walletMednuPaise + x.walletMainPaise, x.walletPaise); assert(x.walletMednuPaise <= 17655); assert(x.walletMainPaise <= 12345); }
  // ledger -> legs
  const L = (t, a, u = "u1") => ({ uid: u, type: "debit", walletType: t, amount: a });
  eq(H.verifiedDebitLegs([L("mednu_money", 300), null], "u1"), { main: 0, mednuMoney: 300 });
  eq(H.verifiedDebitLegs([L("mednu_money", 100), L("main", 200), L("main", 50, "other")], "u1"), { main: 200, mednuMoney: 100 });
  eq(H.fitWalletLegs({ main: 200, mednuMoney: 100 }, 300), { main: 200, mednuMoney: 100 });
  eq(H.fitWalletLegs({ main: 0, mednuMoney: 500 }, 300), { main: 0, mednuMoney: 300 });
  eq(H.fitWalletLegs({ main: 0, mednuMoney: 100 }, 300), null);
  // cart: 300 wallet (200 mm, 100 main) over items 120/180
  const cl = { main: 100, mednuMoney: 200 };
  const i1 = H.itemWalletLegs(cl, 300, 120, 0, false), i2 = H.itemWalletLegs(cl, 300, 180, i1.mednuMoney, true);
  eq([i1.main + i2.main, i1.mednuMoney + i2.mednuMoney], [100, 200]);
  eq(i1.main + i1.mednuMoney, 120); eq(i2.main + i2.mednuMoney, 180);
}
console.log("legs ok");
