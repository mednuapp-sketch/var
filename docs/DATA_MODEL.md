# MedNu data model

Documentation of the Firestore model as it exists in code today. It was written
from `functions/index.js`, `firestore.rules`, the admin panel and the apps.
Anything not verified in code is marked **to verify**. Do not rename or merge
collections before release: document aliases first (see "Deprecated and
duplicate collections").

## 1. Conventions

- Timestamps: `createdAt` / `updatedAt` are Firestore server timestamps
  (`FieldValue.serverTimestamp()`), written by the server or the client.
- Money: rupees as numbers (server rounds to 2 decimals with `_round2`).
  Razorpay amounts are converted to paise only at the gateway edge.
- Dates used for slots and plan windows are IST strings `yyyy-MM-dd`.
- Ids:
  - `payments/{paymentId}` and bookings use auto ids; the payment links to its
    booking through `bookingRef: {collection, id}`, and the booking stores
    `paymentId` back.
  - `wallet_ledger` ids are deterministic where idempotency matters, built by
    `_ledgerId(source)` (non `[A-Za-z0-9_:.-]` characters replaced, 400 chars
    max), e.g. `refund:<paymentId>:<suffix>`, `plan:<subId>:<index>`,
    `recovery_applied:<settlementId>`. Replays therefore never double-write.
  - `source` strings on ledger docs look like `payment:<paymentId>:received`.
  - Slot docs are keyed per doctor/date/time (see `reconcileAppointmentSlots`).
    Exact format: **to verify**.
- Admin roles: `admins/{uid}.role` is one of `director`, `hr`, `finance`,
  `support`, `marketing`. A missing `role` means `director`.
- Writers: "client" means a signed-in app user under `firestore.rules`;
  "server" means Cloud Functions (Admin SDK, bypasses rules). Rules are the
  authority on who may write what; this document only summarises.

## 2. Domains and collections

### 2.1 Users and roles
| Collection | Purpose | Writer |
|---|---|---|
| `users/{uid}` | Patient profile, `fcmTokens`, wallet-related flags | client (own doc), server |
| `admins/{uid}` | Admin panel access and `role` | provisioned by script / director (`functions/scripts/provision_admin_profiles.js`) |
| `doctors/{uid}` | Doctor listing and profile (status, isOnline, specialty) | doctor app, admin approval |

### 2.2 Partners: profile doc plus public listing doc
Each partner type has a private `*_profiles` doc (owner writes, admin reviews)
and, for most, a public listing collection that patients read. Triggers named
`on*ProfileWriteForVisibility` copy the profile into the listing.

| Role | Profile | Listing (alias) |
|---|---|---|
| Lab | `lab_profiles` | `lab_tests_catalogue`, inventory docs (`onLabTestInventoryWrite`) |
| Pharmacy | `pharmacy_profiles` | inventory (`onPharmacyInventoryWrite`) |
| Equipment | `equipment_profiles` | `equipment_vendors` |
| Ambulance | `ambulance_profiles` | `ambulances` |
| Nurse / care assistant | `caregiver_profiles` | `caregivers`, `care_assistants` |
| Physiotherapist | `physiotherapist_profiles` | `physiotherapists` |
| Counsellor | `counsellor_profiles` | `counsellors` |
| Nutritionist | `nutritionist_profiles` | `nutritionists` |
| Hospital | `hospital_profiles` | `hospitals` |

Verification documents live in `{role}_profiles/{uid}.documents` (map of
`docType -> {url, storagePath, fileName, contentType, sizeBytes, uploadedAt,
label?}`) with admin-only `documentVerification`. Required lists per role are in
`mednu_doctor/lib/shared_core/documents/partner_document_models.dart`, mirrored
by hand in the admin panel (`DOCTOR_DOC_TYPES`, `PARTNER_ROLES.docSlots`) and in
`firestore.rules`. Storage prefix: `{role}_documents/{uid}/`.

### 2.3 Bookings (five shapes)
| Collection | Used for | Notes |
|---|---|---|
| `consultations` | Video/audio calls (doctor, physio video) | status drives call lifecycle and credit (`consultationCreditDecision`) |
| `appointments` | In-person / scheduled doctor visits | mirrored into `appointment_slots` |
| `nutrition_appointments` | Dietician sessions and weight-loss plans | plan sessions link to `nutrition_subscriptions` |
| `hospital_appointments`, `hospital_bill_payments` | Hospital visits and bills | billing-desk uid resolved per hospital |
| `service_requests/{requestId}` | Pool requests: lab, equipment, ambulance, caregiver, physio, counselling, emergency doctor | `type` field selects the pool |
| Pool docs | `orders` / medicine orders, lab bookings, `ambulance_requests`, `caregiver_visits`, `physio_sessions`, `counselling_sessions`, equipment orders | created by `on*ServiceRequestCreated` triggers from a service request (exact collection per type: **to verify** in each trigger) |

Plan subscriptions: `nutrition_subscriptions` (id `plansub:<paymentId>`).

Status vocabulary (union seen in server code; each collection uses a subset):
`pending`, `accepted`, `approved`, `active`, `ongoing`/`in_progress`,
`completed`, `ended`, `cancelled`, `rejected`/`declined` (two words for the same
refusal), `expired`, `missed`, `scheduled`, `refunded`. The canonical allowed
transitions per collection are **to verify** (they are enforced in rules and
triggers, not in one place). Server stale lists such as
`_APPOINTMENT_STALE_STATUSES` and admin `where('status','in',[...])` queries
hard-code subsets.

### 2.4 Payments and money
| Collection | Purpose | Writer |
|---|---|---|
| `payments/{paymentId}` | One per successful capture. Fields: `paymentId, patientId, providerId, serviceType, bookingRef, originalAmount, discount, couponCode, paidAmount, walletPortionAmount, walletLegs, baseAmount, platformFee, commission (always 0), providerAmount, paymentMethod, razorpayPaymentId, status, settlementStatus, settlementId, createdAt` | server only |
| `razorpay_orders`, `razorpay_payments`, `razorpay_refunds` | Gateway order, signature-verified payment, refund claims (idempotency) | server |
| `refunds`, `refund_requests` | Admin/user refund records and requests | server (admin callables) |
| `wallet_ledger` | Append-only ledger for patient wallet, `provider`, and `platform` entries; `uid`, `walletType`, `type` credit/debit, `category`, `source`, `isTest?` | server only |
| `wallet`, `wallets`, `wallet_transactions`, `transactions`, per-role `*_transactions` | Legacy / per-role ledgers (see section 5) | mixed |
| `provider_wallets/{providerId}` | `pendingEarnings`, `availableBalance`-style balances, `recoverableDebt` (exact field names: **to verify**) | server only |
| `settlements/{id}` | Batches of eligible payments per provider | server |
| `payout_accounts/{providerId}` | Provider bank details | partner via rules / server, **to verify** |
| payout requests | created by `requestPayout`, cancelled by `cancelPayoutRequest` (collection name: **to verify**) | server |
| `coupons/{id}` and `coupons/{id}/redemptions/{uid}` | Coupons | server (admin callables) |
| `audit_logs` | Every admin money/config callable writes one | server only |
| `admin_alerts` | Failures that need a human (`_sendAdminAlert`) | server |

`payments.status`: `completed`, `refunded`. `settlementStatus` values seen:
`pending`, `eligible`, `pending_review`, `plan_hold`, `paid`, `failed`.
Settlement and payout status vocabularies (`created`, `held`, `approved`,
`paid`, `failed`, ...): **to verify** against `_createSettlementForProvider` and
`markSettlementPaid`.

### 2.5 Notifications
`patient_notifications/{uid}/items`, `doctor_notifications`,
`provider_notifications`, plus `broadcast_notifications` / `broadcasts` and
`notifications`. Written by server triggers (`_sendProviderNotification` and
status-change triggers); FCM tokens are read from the user/partner docs.
Dedup uses a `dedupKey` field on items.

### 2.6 Reviews, support, trackers
Reviews: `doctor_reviews`, `appointment_reviews`, `reviews`, `feedbacks`,
`feedback`, `app_ratings`, summary in `doctor_rating_summary` (from
`onReviewCreated` / `onFeedbackCreated`). Support: `support_tickets` and chat
messages. Trackers: `water_tracking`/`water_logs`/`water_tracker`,
`period_*`, `pregnancy_*`, `meal_tracking`, user `settings/water`.

## 3. Mirrors, triggers and reconcile jobs
| Source | Target | Maintainer |
|---|---|---|
| `*_profiles` | listing collections | `on*ProfileWriteForVisibility` |
| `appointments`, `nutrition_appointments`, physio / counselling sessions | `appointment_slots` | `onAppointmentWrittenForSlots`, `onNutritionAppointmentWrittenForSlots`, `onPhysioSessionWrittenForSlots`, `onCounsellingSessionWrittenForSlots`; repaired by `reconcileAppointmentSlots` (every 30 min) |
| reviews / feedbacks | `doctor_rating_summary` | `onReviewCreated`, `onFeedbackCreated` |
| consultation end | appointment completed | `onConsultationEndedCompleteAppointment` |
| completed booking | payment `eligible`, provider wallet pending | `onAppointmentSettlement`, `onConsultationSettlement`, `onNutritionAppointmentSettlement`, `_transitionPaymentToEligible` |
| eligible payments | `settlements` | `runSettlementQueue` (scheduled), `runManualSettlementBatch` |
| captured but unrecorded gateway payments | refund / reconcile | `reconcileRazorpayPayments` |

`onPaymentWritten` and `onSettlementWritten` are exported from
`functions/whatsapp/` (WhatsApp notifications); they are not the money
mirrors. Treat the settlement path above as authoritative.

## 4. Configuration and kill-switches
| Doc | Fields | Effect | Who may write |
|---|---|---|---|
| `app_config/payments` | `requirePayment` | Real payments on/off. Off or missing = bookings can be created without payment (`not_required`). When on, rules block client bookings that skip payment and the server creates free bookings (`createFreeBooking`). | Director via admin panel |
| `app_config/platform_fee` | `enabled`, `defaultAmount` (legacy `amount`), `services{type: n}`, `providers{id: {amount,label}}` | Per-booking platform fee; mirrored in Dart `platform_fee_provider.dart` and `functions/price_helpers.js` (parity test `shared/fee_cases.json`) | Director |
| `app_config/payouts` | payout switches and limits (**to verify** fields) | Controls `requestPayout` | Director |
| `app_config/versions` | `patient.minVersion`, `partner.minVersion`, message | Forced update gate in both apps | Director |
| `app_config/ambulance_rates`, `ambulance_settings`, `nutrition_plans`, `referral` | rates, plan config, referral rewards | Read by functions | Director |
| `settlement_config/global` | `enforcePriceCheck` (fail-closed default), settlement schedule fields (**to verify**) | Server price check and settlement queue | Director |
| `testCreditEnabled` (+ `testCreditEnabledAt` timestamp) | in the settlement/app config doc read by `_creditTestEarningsTx` (**to verify** which doc) | Credits test earnings for `not_required` bookings; auto-expires; MUST be off in production | Director, test projects only |

## 5. Deprecated and duplicate collections
Do not delete data; document first.
- `commission_rules` and `setCommissionRule`: commission is always 0 (fee-only
  model); `_computeCommissionFromRule` is a deprecated wrapper.
- Listing vs profile pairs in section 2.2.
- Wallet ledgers: `wallet`, `wallets`, `wallet_transactions`, `transactions`,
  `provider_wallets`, per-role `lab_/pharmacy_/physio_/counselling_/caregiver_/
  ambulance_/equipment_transactions` versus the authoritative `wallet_ledger`.
- `maternity_cases`, `maternity_alerts`, `ambulance_bookings`: indexes remain,
  code uses `pregnancy_*` and `ambulance_requests`.
- Reviews and trackers: several parallel names (section 2.6).
- Money field drift: server settles on `paidAmount` / `providerAmount` /
  `platformFee`; clients may write `amount`, `fee`, `price`. The server price
  check reconciles per collection.
- Indexes: `firestore.indexes.json` (144 composites). Prefix-duplicates exist;
  remove only after query review.
