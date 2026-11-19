# MedNu: open questions (as of 2026-11-18)

Write your answer after **Answer:** (for example "A", "Yes", or a sentence). Nothing is deployed.

Closed and built: admin hosted on Firebase, hospital refunds always admin review (confirmed), weight-loss plan (prepaid subscription, forfeit policy), dental doctors, nurse and care assistant need not coexist, Maridi certificate, physio video-call fee, vendor-only equipment, approved partners adding "other" documents, automatic Razorpay refund, server checks the partner for fees, home screen referral code, ambulance vehicle-type matching (B3), unpaid ambulance trips (B7), forced app update (B9), go-live as a runtime switch (B12), final review (C1), HR view-only on money actions, written-off trips pay the driver, test credit safeguards (auto-expiry, off when real payments are on).

---

## Open

**1. Coupons (client, B1).** Who bears a discount coupon?
- A) Partner bears it (current): a ₹50 coupon on a ₹500 service means the partner gets ₹450.
- B) Platform bears it: the partner always gets the full ₹500.
- Answer:

**2. iOS store link.** You said yes: please paste the App Store URL (I will not guess it).
- Answer:

**4. Razorpay key on iOS builds.** `codemagic.yaml` passes no build settings for iOS. How does the live Razorpay key reach the iOS apps?
- Answer:

---

## Your actions (not questions)

1. Create an active "Weight Loss Plan" diet plan in the admin with a price like "₹999/month".
2. Install Java 17 and run the rules tests in `firestore-tests` (README has the command).
3. Deploy following `GO_LIVE_CHECKLIST.md`. Do NOT delete deployed functions that still exist in `functions/index.js`.
4. Run `functions/scripts/migrate_general_physician.js` as a dry run, then with `--apply`.
5. Re-save each approved dietician's availability; ambulance drivers must pick a vehicle type.
6. Test the money flows on real phones with a Razorpay test account, and click through the admin as HR, Finance and Director.
