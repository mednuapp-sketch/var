# MedNU Go-Live Runbook

One ordered runbook. Nothing is deployed automatically. Companion files: `HANDOVER_CLIENT.md` (business summary), `functions/deploy_list.txt`, `PENDING.md` (open release items), `TEST_CHECKLIST.md` (older full regression pass), `QA_open_questions.md` (open decisions), `firestore-tests/README.md` (rules tests). Items marked **(to verify)** were not confirmable from the repo.

## 0. Concepts and switches

| Switch | Where | Effect |
|---|---|---|
| `app_config/payments.requirePayment` | Admin > Settlements > Money Settings > "Require real payments" (Director) | ON: bookings must be paid via Razorpay/wallet. Firestore rules reject client-created `paymentStatus` `not_required`/`paid` and any client `paymentId`; free bookings are server-created by `createFreeBooking`. Missing doc = OFF. `kRequirePayment` in `mednu/lib/core/constants/payment_config.dart` (currently `false`) is only the fallback. |
| `app_config/app_version` | Admin > Money Settings > "Minimum app version" (Director) | `{patient:{minVersion,message?}, partner:{minVersion,message?}}`. Older builds show a blocking "Update required" screen. Fails open if the doc is missing or unreadable. |
| `settlement_config/global.testCreditEnabled` (+ `testCreditEnabledAt`) | Admin > Money Settings | Test-wallet credit for completed test bookings. Server honours it only for 7 days after enabling and never when `requirePayment` is ON. **Test projects only; keep OFF in production.** |
| `settlement_config/global.enforcePriceCheck` | Firestore doc (no admin control found) | Price check is enforced unless explicitly `false` (then only logged as `price_mismatch`). Leave unset. |

The min-version gate and runtime payments switch exist only in builds that contain this change. Old builds ignore both.

## 1. Prerequisites

1. **Tools:** Node.js 18+ (20 recommended), `firebase-tools` (`npm i -g firebase-tools`), Flutter (stable), logged in with `firebase login`, project `mednu-healthcare-app` (see `.firebaserc`).
2. **Java 17** (emulators need it). Install (run yourself): `winget install EclipseAdoptium.Temurin.17.JDK` or `choco install temurin17`. Check `java -version` in a NEW terminal.
3. **Run the rules tests** (real `firestore.rules` and `storage.rules`):
   - `cd firestore-tests && npm install`
   - From repo root: `firebase emulators:exec --only firestore,storage --project mednu-rules-test "npm --prefix firestore-tests test"`
   - Same via npm: `cd firestore-tests && npm run test:emulator`. Syntax-only without Java: `npm run check`.
   - Tests tagged `todo` are known mismatches and do not fail the run. Do not proceed on any real failure.
4. **Functions dependencies:** `cd functions && npm install` (and confirm `node --check index.js`).
5. **Razorpay:** live key id for the apps (`--dart-define=RAZORPAY_KEY_ID=rzp_live_...`), live key id and secret in Functions config. Confirm webhook and refund settings in the Razorpay dashboard.
6. Confirm `testCreditEnabled` is OFF in production.
7. Confirm Android package ids and iOS bundle ids (done per `PENDING.md`: `com.mednu.mednu`, `com.mednu.mednu_doctor`, iOS `com.mednu.mednuDoctor`) and `GoogleService-Info.plist` for both iOS apps (Codemagic groups below).
8. Commit everything to git before deploying (the working tree has many uncommitted changes). Release notes: the user batches all deployments, so rules, hosting, functions and both app releases ship together.

## 2. Ordered deployment

Order matters: **indexes, then functions, then rules, then admin hosting, then apps.** New rules deny client-created free bookings while payments are ON, so rules must not ship ahead of `createFreeBooking` and the patient release that calls it. Rules are backward compatible while `requirePayment` is OFF.

1. **Dry run:** `firebase deploy --only firestore --dry-run`.
2. **Indexes:** `firebase deploy --only firestore:indexes` (wait until they finish building in the console).
3. **Cloud Functions:**
   - Preferred: `firebase deploy --only functions`.
   - `functions/deploy_list.txt` is a **partial** list for `--only` (about 90 entries; it omits e.g. `captureTripPayment`, `reconcileRazorpayPayments`, `remindUnpaidAmbulanceTrips`, `sendTripPaymentReminder`, `markTripWrittenOff`, `applyReferralCode`, `reconcileAppointmentSlots`, `settleDeferredAppointments`). Use it only for a partial redeploy and add the missing names.
   - **New callables:** `createFreeBooking`, `bookPlanConsultation`, `cancelWeightLossPlan`, `sendTripPaymentReminder`, `markTripWrittenOff`.
   - **New scheduled functions** (Cloud Scheduler is created on deploy): `reconcileRazorpayPayments` (every 15 min), `remindUnpaidAmbulanceTrips` (every 60 min), `processNutritionPlans` (daily 09:00 IST). Also new trigger: `onNutritionPlanTestBookingCreated`.
   - **Changed:** `capturePayment`, `captureCartPayment`, `captureTripPayment`, `onNutritionAppointment*` triggers, price helpers.
   - **Referral functions:** the six `on*CompletedReferral` triggers (`onServiceRequestCompletedReferral`, `onAppointmentCompletedReferral`, `onOrderCompletedReferral`, `onNutritionAppointmentCompletedReferral`, `onConsultationCompletedReferral`, `onHospitalAppointmentCompletedReferral`) are **current exports in `functions/index.js`. Do not delete them.** The "six old referral functions" to remove could not be identified in the repo. **To verify:** run `firebase functions:list` and delete only deployed functions that no longer exist in `index.js` (the CLI prompts for deletion on a full deploy: answer carefully and read each name).
   - Deploy region/secrets: confirm WhatsApp secrets and Razorpay config are set before deploy.
4. **Rules:** `firebase deploy --only firestore:rules,storage` (storage rules cover partner `{role}_documents`).
5. **Admin hosting:** `firebase deploy --only hosting:admin` (hosting has targets `admin` and `web`; bare `--only hosting` also publishes the website, so be deliberate). Verify the Money Settings card as Director. `PENDING.md` also mentions Vercel for the admin panel: use one host only **(to verify which is current)**.
6. **Seed settings that apps and functions read** (section 3) before the app release so the first users see correct values.
7. **App releases** (both apps): bump `version` in both `pubspec.yaml`, build with the live key (`--dart-define=RAZORPAY_KEY_ID=rzp_live_...`), publish and wait until live in the stores.
   - Android: `flutter build appbundle --release` (or `apk`) in `mednu` and `mednu_doctor`; sign with your keystore (`key.properties`).
   - iOS via Codemagic (`codemagic.yaml`): workflows `mednu-ios` (patient, `com.mednu.mednu`) and `mednu-doctor-ios` (partner, `com.mednu.mednuDoctor`). Each runs `flutter pub get`, restores `GoogleService-Info.plist` from the base64 variable `GOOGLE_SERVICE_INFO_PLIST`, applies signing profiles, `pod install`, `flutter build ipa --release`, and submits to TestFlight. Required Codemagic groups: `appstore_credentials` (App Store Connect API key), `firebase_ios_mednu`, `firebase_ios_mednu_doctor`. The yaml passes no `--dart-define`, so add `RAZORPAY_KEY_ID` to the build command if iOS needs the live key **(to verify)**. There is no Android workflow in `codemagic.yaml`.
8. **Set minimum versions** only after both apps are live in the stores (section 3, item 8).

## 3. Ordered admin setup (all in the admin panel as Director unless noted)

Admin > **Settlements** page > Money Settings and Ambulance Rates cards, plus the listed pages. Docs are written by the panel; the doc path is shown for reference.

| # | Setting | Doc and fields | Notes |
|---|---|---|---|
| 1 | Payments | `app_config/payments` `{requirePayment}` | Leave OFF until section 4 |
| 2 | Platform fee | `app_config/platform_fee` `{enabled, defaultAmount, services{}, providers{}}` | Default fee, per-service fees (consultation, video_consultation, diagnostics, medicine, pharmacy, equipment, ambulance, caregiver, care_assistant, physiotherapy, counselling, nutrition, hospital_op, hospital_bill), per-partner overrides. Blank service = default |
| 3 | Referral | `app_config/referral` `{enabled, rewardAmount}` | Referrer only; paid after first completed booking. Program limit/expiry live in `referralConfig/settings` (Referrals page); `applyReferralCode` reads enable/limit/expiry from there, so keep both consistent **(to verify)** |
| 4 | Ambulance rates | `app_config/ambulance_rates` `{types:{basic,als,icu:{label,min,max}}}` | Defaults 500 / 1200 / 2500 (min = max) until edited |
| 5 | Ambulance alert | `app_config/ambulance_settings` `{unacceptedAlertMinutes 1..240}` | Default 10 |
| 6 | Nutrition plans | `app_config/nutrition_plans` `{refundUnused:false, lapsePolicy:'forfeit'}` | Optional; no admin screen found. Create in the Firebase console. Defaults apply if missing |
| 7 | Weight Loss Plan | Nutrition Programs > diet plan | Create an **active** `diet_plans` doc titled exactly **"Weight Loss Plan"** with a price like **Rs 999/month**. Customers choose 2, 4 or 6 months |
| 8 | Minimum app version | `app_config/app_version` | Patient and partner `x.y.z` = new release; optional message. After step 7 of section 2 only |
| 9 | Test credit | `settlement_config/global` `{testCreditEnabled}` | **Test project only.** Production: OFF |
| 10 | Specialty migration | script | `cd functions`; credentials via `functions/service-account.json` or `GOOGLE_APPLICATION_CREDENTIALS`. Dry run: `node scripts/migrate_general_physician.js`. Review the list, then `node scripts/migrate_general_physician.js --apply`. Safe to re-run |
| 11 | Dietician availability | partner app | Each dietician (and physio/counsellor if slots seem missing) opens availability and **saves once** so slot indexes rebuild |
| 12 | Admin profiles | `functions/scripts/provision_admin_profiles.js` | Create HR, Finance, Support, Marketing logins for testing roles **(to verify usage and arguments before running)** |
| 13 | Partner fees for special partners | Money Settings > Partner-specific fees | Optional |

## 4. Go-live switch sequence (real payments)

1. Confirm sections 1 to 3 are done, both new apps are live, and min versions are set and tested (old build shows Update screen; new build does not).
2. Confirm live Razorpay keys and that `testCreditEnabled` is OFF.
3. Admin > Money Settings > **Require real payments** > confirm. Takes effect live in every build that has the switch.
4. Run the real-money smoke tests (section 5, tests 8 to 13) with small payments, then refund them.
5. Announce launch only after the smoke tests pass.

**Rollback:** switch **Require real payments** OFF (instant, no release). If a bad minimum version locks users out, clear the version fields and Save. If a function misbehaves, redeploy the previous function version from git. Rules can be rolled back with `firebase deploy --only firestore:rules` from the previous commit.

## 5. Real-device test plan

Use two phones (patient app and partner app), plus a second phone for notifications. Mark each item pass or fail.

**Partner sign-up and documents**
1. For each role (doctor, dental doctor, lab, pharmacy, equipment, ambulance, nurse, care assistant, counsellor, physio, dietician, hospital): register, confirm the required document list matches `HANDOVER_CLIENT.md` section 3, upload, submit, approve as Director. Confirm Maridi Certificate on lab and hospital, dental labels for a Dental doctor, and an approved partner can add "Other documents" (max 5) without blocking approval.

**Bookings and payment (after real payments are ON)**
2. One booking per service: doctor (online and in person), pharmacy/cart, lab/diagnostics, physio, counselling, dietician, equipment, nurse, care assistant, hospital OP. Check the platform fee shown, the booking in both apps, a `payments` doc with a real `paymentId`, and no `not_required`.
3. Wallet only, wallet plus Razorpay, and coupon applied. Check the partner credit matches the coupon decision.
4. Free (Rs 0) flow and doctor-initiated consultation still work.
5. Old build: blocked by the Update screen or rejected by rules, never silently free.

**Refunds and wallet**
6. Cancel before accept: automatic full refund (Razorpay and wallet legs). Cancel after accept: Refund request appears; approve and reject once each.
7. Wallet balances, ledger, transfers, referral reward credit.

**Ambulance**
8. Rate range shown; request has `pay_after_trip`; driver sets a rate in range; trip completes; patient pays from the pay-due screen (`captureTripPayment`). Leave one unpaid: patient is blocked from a new booking, receives reminders (2 h, 24 h), appears in Unpaid trips; Director writes it off, block lifts, driver is still paid. Unaccepted-request admin alert fires after the set minutes.

**Nurse**
9. Nurse accepts a visit then cancels or releases it; the visit returns to the pool; decline works.

**Weight-loss plan**
10. Purchase 2 months: total = monthly x months + fee. Book the monthly consultation; second booking in the same month is refused; cancel before any completion (fee non-refundable); a plan with a completed session cancelled (no auto refund); let a window pass to see lapse (use a test plan or check `processNutritionPlans` logs). Old patient build gets "Please update the app to buy this plan."

**Slots and reschedule**
11. Dietician, physio, counsellor: slots appear after re-saving availability; taken slot cannot be double-booked; reschedule works until the session starts.

**Not-accepting vendors**
12. Switch a pharmacy, lab and equipment vendor to not accepting: listing is greyed out and cannot be ordered from; turn back on.

**Notifications, update, admin**
13. Log in on a second phone: push notifications arrive there (and on the first, or only the newest, as designed **(to verify)**). Incoming call reaches the newest phone.
14. Forced update: set min version above the installed build; blocking screen appears; clear it; app unblocks. Airplane mode at startup must not block.
15. Admin as **HR**: money pages are view-only, no action buttons, no Prescriptions or Health Data, cannot save Money Settings. As **Finance**: can approve, hold and pay settlements and refunds; only Finance heading visible. As **Director**: everything, including write-off and approving registrations. Also try Support and Marketing visibility.
16. Referral: new account uses a code; the referrer is rewarded only after the new user's first booking is **completed**; referred user receives nothing.
17. Regression of remaining flows: `TEST_CHECKLIST.md` (video call, pharmacy status steps, lab reports, WhatsApp messages, payouts).

## 6. Monitoring (Cloud Functions logs and admin)

| Watch for | Meaning and action |
|---|---|
| `price_mismatch` | Client price differs from server price. Investigate app or catalogue data; repeated hits on one provider usually mean a missing fee or stale price |
| `price_check_skipped` | Service type price cannot be derived; informational |
| `fee_provider_unverified` | Partner-specific fee could not be verified against the partner profile; fee not applied as expected. Check the partner id in Money Settings |
| `test_credit_skipped_no_amount` | Test credit skipped; expected only in test projects |
| `razorpay_auto_refund_failed`, `razorpay_refund_claim_failed`, `razorpay_refund_failed`, `razorpay_refund_after_capture_failed` | Money not returned automatically. Refund manually in the Razorpay dashboard, then reconcile. Also watch the `razorpay_refunds` collection (`reconcileRazorpayPayments` retries) |
| `auto_refund_failed`, `refund_recovery_pending` | Admin refund needs action (partner already settled: recovery pending) |
| `plan_cancel_post_refund_failed`, `plan_cancel_failed` | Weight-loss plan cancel needs support follow-up |
| `admin_alerts` (admin panel and push) | Unaccepted ambulance, serious complaint, refund failures, plan unused-refund due |

Also check Cloud Scheduler for the three new jobs after deploy, and Firestore `refund_requests` for items waiting on the admin.

## 7. Known limitations

| Limitation | Impact and mitigation |
|---|---|
| A client omitting `paymentStatus` is still allowed by rules (needed for free and provider-created docs) | Real protection relies on server settlement acting only on docs with a real `paymentId`, plus the forced update |
| `appointments` list rule still has the temporary `status == 'booked'` clause (`PENDING.md` item 0) | Other users' upcoming appointments are listable; remove after most users pass patient build 1.0.6+12, then redeploy rules |
| iOS Update screen has no button until an App Store URL exists | Message only |
| Coupon bearer undecided | Partner share currently reduced by the coupon |
| Ambulance matching ignores vehicle type | Type only sets price (open decision 3) |
| No admin screen for `app_config/nutrition_plans` or `enforcePriceCheck` | Edit in the Firebase console |
| `deploy_list.txt` is partial | Use `firebase deploy --only functions` |
| Referral limit/expiry and reward amount are stored in two docs (`referralConfig/settings`, `app_config/referral`) | Keep consistent **(to verify)** |
| `minor_requests` are not written by the apps yet | The admin page stays empty |
| Weight-loss plan: unused consultations lapse with no refund by default | Client-confirmed; wallet-refund option exists but is off |
| Test credit auto-expires after 7 days and is ignored when payments are ON | Test projects only |
| Old app builds ignore the runtime switch and min-version gate | Rely on the forced update after both apps are live |
| `kRequirePayment` fallback is `false` | Used only if the payments doc is unreadable; set the Firestore doc explicitly |
| Nurse and care assistant cannot share one account | Client confirmed not needed |


---

## Partner payouts: extra deploy and setup steps

- **Rules and functions:** `payout_accounts` rules, settlement read access for the provider, and the new callables `requestPayout` and `cancelPayoutRequest` ship with the normal rules and functions deploy. Deploy rules and functions before the partner app and admin hosting.
- **Settings (admin, Director):** in Money Settings > "Partner payouts", confirm payouts are enabled and set the minimum amount (default ₹500 if unset).
- **First-use test:**
  1. As a partner, save payout details; confirm the status shows "Pending verification".
  2. As Finance or Director, verify it in "Payout accounts".
  3. As the partner, request a payout; confirm the settlement appears with the "Requested by partner" badge and the masked bank details.
  4. Cancel the request; confirm earnings return to payable.
  5. Request again, approve, mark paid; confirm the provider's notification and balance.
  6. Repeat for a hospital billing login and for a care assistant.
  7. Confirm HR and support cannot see "Payout accounts" or any money buttons.
- **If Firestore asks for an index on first use:** the payout queries should not need one. If it does, add the index it links to.
- **Known limits:** a hospital's payout account is tied to the billing login that created it. If a partner edits a verified account while a request is open, the payout uses the details saved at request time, so re-check the destination before paying. The payout alert shows to every admin role.
- **Tests:** `node functions/test/run_all.js` (36 tests) and `firestore-tests/payouts.rules.test.js` (needs Java).
