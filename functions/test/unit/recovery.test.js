const assert = require("assert");
const P = require("../../plan_helpers.js");
assert.deepStrictEqual(P.netRecovery(3000, 999), { recoveryApplied: 999, netTotal: 2001, debtAfter: 0 });
assert.deepStrictEqual(P.netRecovery(500, 800), { recoveryApplied: 500, netTotal: 0, debtAfter: 300 });
assert.deepStrictEqual(P.netRecovery(700, 0), { recoveryApplied: 0, netTotal: 700, debtAfter: 0 });
assert.deepStrictEqual(P.netRecovery(100.1, 0.2), { recoveryApplied: 0.2, netTotal: 99.9, debtAfter: 0 });
assert.deepStrictEqual(P.netRecovery(-5, 10), { recoveryApplied: 0, netTotal: 0, debtAfter: 10 });
assert.deepStrictEqual(P.netRecovery(undefined, undefined), { recoveryApplied: 0, netTotal: 0, debtAfter: 0 });
assert.deepStrictEqual(P.recoveryByProvider([
  { id: "a", providerId: "p1", amount: 333.33 }, { id: "b", providerId: "p1", amount: 333.34 },
  { id: "c", providerId: "p2", amount: 10 }, { id: "d", providerId: "", amount: 5 }, { id: "e", providerId: "p3", amount: 0 },
]), [{ providerId: "p1", amount: 666.67, ids: ["a", "b"] }, { providerId: "p2", amount: 10, ids: ["c"] }]);
console.log("recovery_test ok");
