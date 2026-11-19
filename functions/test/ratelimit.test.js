"use strict";
const test = require("node:test");
const assert = require("node:assert");
const { T, reset } = require("./harness");

test("under the limit passes and counts", async () => {
  const db = reset();
  for (let i = 0; i < 3; i++) await T._rateLimit(db, "k:u1", 3, 60);
  const docs = await db.collection("rate_limits").get();
  assert.strictEqual(docs.size, 1);
  const d = docs.docs[0].data();
  assert.strictEqual(d.count, 3);
  assert.ok(d.expireAt && typeof d.windowStart === "number");
  assert.ok(!docs.docs[0].id.includes("u1"), "doc id must be hashed");
});

test("over the limit throws resource-exhausted", async () => {
  const db = reset();
  await T._rateLimit(db, "k:u2", 2, 60);
  await T._rateLimit(db, "k:u2", 2, 60);
  await assert.rejects(() => T._rateLimit(db, "k:u2", 2, 60), (e) => e.code === "resource-exhausted");
  // other keys unaffected
  await T._rateLimit(db, "k:other", 2, 60);
});

test("window rollover resets the counter", async () => {
  const db = reset();
  const realNow = Date.now;
  let now = realNow.call(Date);
  Date.now = () => now;
  try {
    await T._rateLimit(db, "k:u3", 1, 60);
    await assert.rejects(() => T._rateLimit(db, "k:u3", 1, 60), (e) => e.code === "resource-exhausted");
    now += 61 * 1000;
    await T._rateLimit(db, "k:u3", 1, 60);
  } finally {
    Date.now = realNow;
  }
});

test("fails open when the limiter transaction errors", async () => {
  const brokenDb = {
    collection: () => ({ doc: () => ({}) }),
    runTransaction: async () => { throw new Error("firestore unavailable"); },
  };
  await T._rateLimit(brokenDb, "k:u4", 1, 60);
});

test("_safeId accepts real id shapes and rejects path tricks", () => {
  for (const ok of ["SAVE20", "abc_DEF-1.2", "pay:123:x", "Xy7aB9kLmN0pQrStUvWz"]) assert.strictEqual(T._safeId(ok, "id"), ok);
  for (const bad of ["", " ", "a/b", "a..b", "a b", "x".repeat(129), 5, null, undefined]) {
    assert.throws(() => T._safeId(bad, "id"), (e) => e.code === "invalid-argument");
  }
});
