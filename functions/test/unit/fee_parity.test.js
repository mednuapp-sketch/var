"use strict";
// JS side of the Dart/JS parity suite. Reads shared/fee_cases.json, which is
// also consumed by mednu/test/platform_fee_parity_test.dart and
// mednu_doctor/test/specialty_parity_test.dart.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const H = require("../../price_helpers.js");

const root = path.join(__dirname, "..", "..", "..");
const cases = JSON.parse(fs.readFileSync(path.join(root, "shared", "fee_cases.json"), "utf8"));

for (const c of cases.normalizeFeeServiceType) {
  assert.strictEqual(H.normalizeFeeServiceType(c.input), c.expected, `normalizeFeeServiceType(${JSON.stringify(c.input)})`);
}
for (const c of cases.platformFeeFor) {
  assert.strictEqual(H.platformFeeFor(c.cfg, c.serviceType, c.providerId), c.expected, `platformFeeFor: ${c.name}`);
}
for (const c of cases.feeProviderIdFor) {
  assert.strictEqual(H.feeProviderIdFor(c.serviceType, c.bookingData), c.expected, `feeProviderIdFor: ${c.name}`);
}

// Dental rule: the admin panel's literal (mednu-admin/js/app.js) is read from
// the source so this test breaks if the admin regex drifts from the Dart one.
const adminSrc = fs.readFileSync(path.join(root, "mednu-admin", "js", "app.js"), "utf8");
const m = /const _DENTAL_SPECIALTY_RE = \/(.+)\/([a-z]*);/.exec(adminSrc);
assert.ok(m, "could not find _DENTAL_SPECIALTY_RE in mednu-admin/js/app.js");
const adminRe = new RegExp(m[1], m[2]);
const isDentalSpecialty = (s) => typeof s === "string" && adminRe.test(s.trim());
for (const c of cases.isDentalSpecialty) {
  assert.strictEqual(isDentalSpecialty(c.input), c.expected, `isDentalSpecialty(${JSON.stringify(c.input)})`);
}
// Same pattern text as the Dart source (specialty_utils.dart).
const dartSrc = fs.readFileSync(path.join(root, "mednu_doctor", "lib", "core", "utils", "specialty_utils.dart"), "utf8");
const d = /RegExp\(\s*r'([^']+)'/.exec(dartSrc);
assert.ok(d, "could not find the dental RegExp in specialty_utils.dart");
assert.strictEqual(d[1], m[1], "dental regex differs between Dart and admin JS");

console.log("fee_parity ok");
