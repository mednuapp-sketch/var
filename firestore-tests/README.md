# MedNu Firestore + Storage rules test suite

Tests the REAL `../firestore.rules` and `../storage.rules` (read from disk at
start-up, no copies) with `@firebase/rules-unit-testing` and the built-in
`node:test` runner (Node >= 18; 20+ recommended).

## Prerequisites

* Node.js >= 18.
* **Java (JDK 11+; 17 recommended) on PATH.** The Firebase Firestore/Storage
  emulators are Java programs. Example install commands (text only, run them
  yourself):
  * `winget install EclipseAdoptium.Temurin.17.JDK`
  * `choco install temurin17`
  * check with `java -version`, then open a NEW terminal.
* `firebase-tools` (`npm i -g firebase-tools` or use `npx firebase-tools`).
* `cd firestore-tests && npm install` (installs `@firebase/rules-unit-testing`).

## Run

From the repo root (uses `firebase.json` emulator ports 8080 / 9199):

```
firebase emulators:exec --only firestore,storage --project mednu-rules-test "npm --prefix firestore-tests test"
```

Same thing via npm: `cd firestore-tests && npm run test:emulator`.

Single areas (inside `emulators:exec`, or with emulators already running):
`npm run test:firestore`, `npm run test:storage`, `npm run test:legacy`.
Syntax-only check without Java: `npm run check`.

`FIRESTORE_EMULATOR_HOST` / `FIREBASE_STORAGE_EMULATOR_HOST` are honoured
(`emulators:exec` sets them); otherwise 127.0.0.1:8080 / :9199 are used.
Tests run with `--test-concurrency=1` because files share one emulator
(each new file uses its own projectId; the four legacy files share one).

## Layout

| File | Area |
| --- | --- |
| `helpers/env.js` | env setup, named auth contexts, `seed` / `seedBase` (`withSecurityRulesDisabled`), `ok` / `no` |
| `appointments.rules.test.js` | 1. appointments |
| `consultations.rules.test.js` | 2. consultations |
| `service_requests.rules.test.js` | 3. service_requests |
| `partner_profiles.rules.test.js` | 4. 9 partner `*_profiles` collections + `doctors` |
| `caregiver_visits.rules.test.js` | 5. caregiver_visits (claim, decline, cancel-after-accept release) |
| `pool_orders.rules.test.js` | 6. diagnostic_bookings / pharmacy_orders pool + pharmacy_order_items |
| `nutrition.rules.test.js` | 7. nutrition_appointments, slot index collections |
| `money_config.rules.test.js` | 8. wallets, ledgers, payments, refunds, razorpay_*, app_config, settlement_config |
| `payments_switch.rules.test.js` | 9. `app_config/payments.requirePayment` (auto-skips if rule absent) |
| `storage.rules.test.js` | 10. storage `{role}_documents`, `doctors/{uid}` |
| `lab`, `orders_prescription`, `appointments_join_call`, `guest_join` | pre-existing suites, unchanged |

## Known mismatches (`todo` tests)

Tests tagged `todo` assert the intended behaviour that the current rules do not
enforce. node:test reports them as TODO and they do not fail the run; they turn
into real failures to chase (or into passing tests) once the rules are fixed.
Rules are never edited by this suite.
