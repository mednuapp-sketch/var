# MedNu Platform: Client Handover

Plain-language summary of what the platform does now, what you control from the admin panel, and what is still open. Items marked **(to verify)** were not confirmed in the code and should be checked during testing. Nothing here is live until the deployment in `GO_LIVE_CHECKLIST.md` is done.

## 1. Money model: fee only, no commission

- The partner (doctor, lab, pharmacy, driver, etc.) always receives the **base price** of the service.
- MedNu earns **only a platform fee**, set by the admin. There is no percentage commission.
- The fee can be set three ways, most specific wins: **per partner**, then **per service**, then the **default fee**. There is also an overall on/off switch.
- The customer sees the fee at checkout. The server re-checks the price and fee before taking money and rejects a mismatch.

### Worked example: Rs 500 service, Rs 20 fee, optional Rs 50 coupon

| | Without coupon | With Rs 50 coupon |
|---|---|---|
| Service price | Rs 500 | Rs 500 |
| Platform fee | Rs 20 | Rs 20 |
| Coupon | none | minus Rs 50 |
| **Customer pays** | **Rs 520** | **Rs 470** |
| Partner receives | Rs 500 | Rs 450 (current build) or Rs 500 (if you choose "MedNu absorbs coupons") |
| MedNu keeps | Rs 20 | Rs 20 |

The coupon row depends on an open decision (section 9): today the partner's share is reduced by the coupon.

## 2. Real-payments switch

- Admin panel, **Settlements** page, **Money Settings** card, **"Require real payments"** (Director only).
- OFF: test bookings without payment are allowed. ON: every booking must be paid by Razorpay or wallet; free (Rs 0) bookings are created by the server.
- Switching OFF again is instant and needs no app release (rollback).
- Only builds that contain the switch obey it. That is why the forced update (section 8) exists.

## 3. Partner documents per role

| Role | Required documents |
|---|---|
| Doctor | Doctor document set (dental doctors see a dental set, for example State Dental Council Registration). A doctor counts as dental if the specialty is Dental/Dentist/Dentistry/Orthodontics etc. |
| Lab | Lab Licence; **Maridi Certificate (Waste Disposal)**; Lab Technician Details; Biochemist/Pathologist/Microbiologist Details; GST Certificate. Trade Licence optional |
| Pharmacy and Equipment vendor | Drug Licence Forms; Pharmacist Details; Trade Licence; GST Certificate |
| Ambulance | Driver's Licence; Ambulance Certificate; C Book (RC); Insurance; Pollution Certificate |
| Nurse | Qualification (ANM/GNM/B.Sc. Nursing); Government ID. Resume optional |
| Care Assistant | Government ID only |
| Counsellor | Government ID; Certifications |
| Physiotherapist (also used for dental support set) | UG Degree; Renewal Certificate; Registration State; Registration National. PG Degree and Others optional |
| Dietician | UG Degree; Registration Certificate. PG Degree and Others optional |
| Hospital | DM&HO Licence; Fire Certificate; **Maridi Certificate (Waste Disposal)**; GVMC Certificate; Pollution Certificate; Trade Licence; GST Certificate. Hospital Resume optional |

- **Other documents:** every partner, including already-approved ones, can add up to 5 extra documents with their own title. These never block approval.
- Old uploads stay attached where the document type is unchanged.
- The Physiotherapist role stays physio only; dentists register as doctors with the Dental specialty.
- Only the Director can approve registrations.

## 4. Refunds policy

| Situation | What happens |
|---|---|
| Customer cancels **before** the partner accepts | **Automatic full refund** |
| Customer cancels **after** accept, before service starts | **No automatic refund.** A refund request goes to the admin (Refunds page) to approve or reject |
| Service already started | No cancel, no refund |
| Partner cancels, rejects or request expires | Refunded automatically |
| Hospital appointments | After-accept path (admin review) **(to verify: pre-accept list is empty for hospitals)** |

### Weight-loss plan rules

- Customer **pays upfront** for the plan: monthly price x months (2, 4 or 6 months) plus the platform fee once.
- **One consultation per month**, booked by the customer in each monthly window; reminders are sent at window start and in the last 3 days.
- **Cancel before any consultation is completed:** plan price refunded, **platform fee non-refundable**.
- **Cancel after one is completed:** no automatic refund; booked sessions are honoured. Optional admin setting can record the unused share for a manual refund (off by default).
- **Unused consultations lapse** when their month passes: no refund and no dietician payout (default). A wallet-refund option exists but is off by default.

## 5. Ambulance

- Vehicle types: **Basic, Advanced Life Support (ALS), ICU**. Admin sets a **rate range (min to max)** per type.
- Customer sees the range and is held at the **maximum** at booking; the driver sets their own rate within the range and the final fare is that rate.
- **Pay after trip:** the patient pays when the trip completes. A new booking is blocked while a trip payment is due.
- **Unpaid reminders** are sent automatically after about 2 hours and 24 hours. Admin sees an **Unpaid ambulance trips** list.
- **Write-off (Director only):** forgives the customer's debt and lifts the booking block; **MedNu pays the driver** the fare.
- Admin is alerted once if no ambulance accepts a request after a set number of minutes (default 10).
- Matching today picks the nearest online driver and **ignores vehicle type** (open decision 3).

## 6. Dietician, physio, counselling

- Customers pick from the partner's real available slots; taken or blocked slots cannot be booked and the server settles races.
- Physio and counselling sessions can be **rescheduled** by the patient while pending/accepted (not once started). Nutrition has its own reschedule screen.
- Dieticians must **re-save their availability** once after the update so slots are indexed (see runbook).

## 7. Vendors not accepting, referrals, notifications

- **Not accepting:** pharmacies, labs and equipment vendors who switch off orders/bookings are shown **greyed out** to patients and cannot be ordered from.
- **Referral reward:** paid to the **referrer only**, once, **after the referred person's first booking is completed** (not on sign-up). The referred person gets nothing. The amount and on/off are set by admin.
- **Push notifications on a new phone:** the phone's notification address is saved on every sign-in and when it refreshes, so a new phone receives notifications after logging in. Call delivery uses the newest phone **(to verify on two devices)**.

## 8. Forced app update

Admin sets a minimum version for the patient app and for the partner app. Older builds see a blocking "Update required" screen. If the setting is empty or unreadable the app is **not** blocked. The iOS update button needs an App Store link that does not exist yet.

## 9. What you control in the admin panel

| Setting | Where | Who |
|---|---|---|
| Require real payments, minimum app version, referral reward, platform fees (default, per service, per partner), test-credit switch | Settlements page, **Money Settings** card | Director |
| Ambulance rate ranges and unaccepted-alert minutes | Settlements page, Ambulance Rates card | Director |
| Unpaid ambulance trips, write-off | Settlements page | Director and Finance see; write-off Director only |
| Settlement frequency, approve/hold/pay, refunds | Settlements, Refunds | Director, Finance |
| Coupons | Coupons page | Director, Finance |
| Weight-loss plan | Nutrition Programs, diet plan titled "Weight Loss Plan" with price like Rs 999/month | Director, HR |
| Plan lapse/refund options | Database document `app_config/nutrition_plans` (no admin screen found) | Technical |
| Referral program rules (limit, expiry) | Referrals page | Finance, HR, Director |

### Role permissions

| Role | Can open |
|---|---|
| Director | Everything; approves registrations; only role that changes money settings |
| Finance | Revenue, wallet, settlements, coupons, refunds, referrals, reports, discounts; can move money |
| HR | Partner accounts, finance, support, marketing, quality, most directories. **Money pages are view-only**. No Prescriptions or Health Data |
| Support | Patients, appointments, tickets, tracking, requests, feedback |
| Marketing | Campaigns, banners, broadcasts, website ads, health articles, feedback |

## 10. Decisions still open

| # | Decision | Where |
|---|---|---|
| 1 | **Coupon bearer:** partner share reduced by coupon (current), MedNu absorbs coupons, or partner gets the fee too | QA_open_questions B1 |
| 2 | **iOS App Store link** for the forced-update button | not yet available |
| 3 | Should an ICU request only match ICU drivers (recommended yes)? | QA_open_questions B3 |
| 4 | Date real payments go live (to align deploy and forced update) | QA_open_questions B12 |
| 5 | Confirm test credit stays off in production | QA_open_questions A4 |
| 6 | Final full code review before deploy | QA_open_questions C1 |
| 7 | Commission for services with no rule (now moot under fee-only model) | QA_clarifications 1.3 **(to verify if still relevant)** |

Closed already: weight-loss plan, dental, nurse plus care assistant in one account (not needed), Maridi certificate, other documents, automatic Razorpay refund, referral code on home screen.


---

## Partner payouts (withdrawals), all 11 provider roles

Every provider (doctor, lab, pharmacy, equipment vendor, ambulance, nurse, care assistant, physiotherapist, counsellor, dietician, hospital) can now be paid out on request.

1. **Payout details.** The provider saves holder name, account number, IFSC, bank name and an optional UPI id on one shared screen. It is reachable from their Earnings screen and from Settings. Editing the details sends them back to "pending verification".
2. **Verification.** Finance or Director verifies the account (or rejects it with a reason) in the admin panel, in the "Payout accounts" card on the Settlements page. Payouts only go to a verified account. HR and support cannot see bank details.
3. **Request payout.** The provider taps "Request payout" on their earnings card. It works only when the account is verified, earnings reach the minimum (default ₹500, set by the Director in Money Settings) and no other request is open. They can cancel while it is still "Requested".
4. **Approval and transfer.** The request appears in Settlements with a "Requested by partner" badge and the bank destination. Finance or Director approves it, transfers the money outside the app, then marks it paid. The provider is notified.
5. **Recoveries.** If a refund earlier clawed back earnings the provider had already been paid, the amount is netted from the payout. Example: ₹3,000 eligible, ₹999 owed, payout ₹2,001.

Money still moves outside the app. This is a request-and-approve flow, not an instant bank transfer. Instant transfers would need a payout provider such as Razorpay Payouts.

Providers who never request a payout are still batched by the daily settlement. Admin then looks their bank details up in "Payout accounts".
