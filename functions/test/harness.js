"use strict";
// Loads functions/index.js with firebase-admin Firestore/Messaging/Auth/App and
// razorpay replaced by in-memory fakes. Production code is untouched: the stubs
// are injected through Module._load before index.js is required.
process.env.MEDNU_TEST = "1";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "demo-check";
process.env.RAZORPAY_KEY_ID = "rzp_test_fake";
process.env.RAZORPAY_KEY_SECRET = "fake_secret";

const Module = require("module");
const path = require("path");
const { FakeDb, FieldValue, Timestamp } = require("./fake_firestore");

const state = { db: new FakeDb(), razorpayCalls: [], razorpayRefundImpl: null, razorpayFetchImpl: null };

class FakeRazorpay {
  constructor() {
    this.payments = {
      refund: async (id, body) => {
        state.razorpayCalls.push({ fn: "refund", id, body });
        if (state.razorpayRefundImpl) return state.razorpayRefundImpl(id, body);
        return { id: "rfnd_fake", payment_id: id, amount: body.amount };
      },
      fetch: async (id) => {
        state.razorpayCalls.push({ fn: "fetch", id });
        if (state.razorpayFetchImpl) return state.razorpayFetchImpl(id);
        return { id, amount_refunded: 0 };
      },
    };
    this.orders = { create: async () => ({ id: "order_fake" }) };
  }
}

const messaging = {
  send: async () => "msg", sendEach: async () => ({ responses: [] }),
  sendEachForMulticast: async () => ({ responses: [], successCount: 0, failureCount: 0 }),
  sendMulticast: async () => ({ responses: [], successCount: 0, failureCount: 0 }),
};

const origLoad = Module._load;
Module._load = function (request, parent, isMain) {
  switch (request) {
    case "firebase-admin/firestore":
      return { getFirestore: () => state.db, FieldValue, Timestamp };
    case "firebase-admin/messaging": return { getMessaging: () => messaging };
    case "firebase-admin/auth": return { getAuth: () => ({ getUser: async () => ({}) }) };
    case "firebase-admin/app": return { initializeApp: () => ({}), getApps: () => [], getApp: () => ({}) };
    case "firebase-admin": return { initializeApp: () => ({}), firestore: () => state.db, messaging: () => messaging, apps: [{}] };
    case "razorpay": return FakeRazorpay;
    default: return origLoad.apply(this, arguments);
  }
};

const index = require(path.join(__dirname, "..", "index.js"));
const T = index.__testing;
if (!T) throw new Error("index.js did not expose __testing (MEDNU_TEST=1 required)");

function reset() {
  state.db = new FakeDb();
  state.razorpayCalls.length = 0;
  state.razorpayRefundImpl = null;
  state.razorpayFetchImpl = null;
  return state.db;
}

module.exports = { index, T, state, reset, FieldValue, Timestamp, get db() { return state.db; } };
