# MedNu QA: questions for the owner

Please answer each question by writing your choice after **Answer:** (for example "A", "Yes", or a sentence).
"My pick" is what I would do if you have no preference. Nothing below is deployed.

---

## 1. Money and wallet

**1.1 Test credit switch in the admin panel.** Test bookings only credit partner wallets when a switch (`testCreditEnabled`) is on in the Firebase console. The admin panel has no button for it.
- A) Add a toggle in the admin panel
- B) Keep it console-only
- My pick: A, with a warning label "test projects only".
- Answer:

**1.2 Where test money lands.** Test credits go to "Pending earnings", so "Total Earnings" shows ₹0 while Pending and the transaction list show the money.
- A) Keep pending
- B) Show it as available balance
- My pick: A, because it matches how real money flows.
- Answer:

**1.3 Commission for services with no rule.** Nutrition, physiotherapy and counselling have no commission rule, so partners get 100%. Hospital rates can now be set in admin. Care assistants share the nurse rule.
- A) Set a commission % for each service (tell me the numbers)
- B) 0% is intended
- C) Care assistants need their own rate
- Answer:

**1.4 Equipment sold through the pharmacy pool** is settled under the pharmacy commission rule. OK?
- Yes / No (use the equipment rule)
- Answer:

**1.5 Weight-loss plan charging.** The picker shows monthly price × months. The booking charges only one consultation fee and books one slot.
- A) Charge the full plan total up front, and book or remind for one consultation every month
- B) Charge per month, one appointment each month
- C) Keep today's behaviour (one consultation only) for now
- Answer:

**1.6 Customer cancels a paid booking.** Today only provider-side cancels, rejections and expiries are refunded automatically.
- A) Refund automatically
- B) Admin refunds manually
- Answer:

**1.7 Ambulance payment.** Ambulance requests never open the payment screen.
- A) Require payment when real payments go live
- B) Pay the driver in cash, no in-app payment
- Answer:

**1.8 Wallet-only payment failure.** If the booking fails after the wallet was debited, the customer loses the money with no booking. Should that be refunded automatically?
- Yes / No
- My pick: Yes.
- Answer:

**1.9 Doctor no-show.** A doctor is credited if they end the call alone, even if the patient never joined.
- A) Credit only if the patient joined
- B) Credit anyway
- Answer:

**1.10 Earnings screen for doctors** counts only scheduled appointments, not quick consultations (the wallet card does include them). Include quick consultations?
- Yes / No
- Answer:

---

## 2. Partner documents and sign-up

**2.1 Partners approved before the new document lists.** Approved partners of every role whose list changed hold the old document names. They are now asked for the new documents and, once active, cannot upload them. This affects at least physio, dietician, counsellor, lab, pharmacy, equipment, ambulance, nurse and hospital.
- A) Grandfather them: treat already-approved partners as complete
- B) Admin unlocks them so they re-upload the new documents
- C) Both: grandfather now, ask for new documents at renewal
- Answer:

**2.2 Hospital documents.** The client's list dropped the old "Authorization Letter" and "Contact Person ID", which proved the applicant acts for the hospital (a billing-desk login can read that hospital's payments).
- A) Keep both as extra required documents
- B) Follow the client's list exactly
- My pick: A.
- Answer:

**2.3 Dental.** The client wrote "Physiotherapy/Dental" as one list. Today there is only a Physiotherapist role.
- A) Dental professionals register as Physiotherapist
- B) Add a separate Dental role
- Answer:

**2.4 "Details" documents** (lab technician details, pharmacist details, biochemist/pathologist/microbiologist details). Today these are file uploads.
- A) File upload is fine
- B) Also ask for typed details (name, registration number)
- Answer:

**2.5 Dietician "Others"** is optional in the app (the client list did not say). Correct?
- Yes / No (make it required)
- Answer:

**2.6 Spelling.** The client wrote "Maridi" (lab and hospital). Is that the correct name to show partners?
- Yes / Correct spelling is: ______
- Answer:

**2.7 Rejected or suspended partners** cannot resubmit. Add a "fix and resubmit" flow?
- Yes / No
- Answer:

**2.8 Hospital profile edits** go live without admin review once approved (other roles are reviewed). Intended?
- A) Intended
- B) Require review like the others
- Answer:

---

## 3. Orders and daily operations

**3.1 A lab or pharmacy declines an open (unassigned) job.** Today it cancels the job for everyone and refunds the customer.
- A) Decline only hides it for that partner; other partners can still take it
- B) Keep today's behaviour
- My pick: A.
- Answer:

**3.2 Doctor reschedule.** A doctor can move an appointment to any date and time, with no check against their schedule, blocked slots or other bookings.
- A) Add checks
- B) Intended
- Answer:

**3.3 A cancelled appointment** can be overwritten as "completed" when a prescription is written. Block that?
- Yes / No
- Answer:

**3.4 Nurses and care assistants.**
- Can they cancel a visit they accepted? Yes / No
- Should a nurse booked directly get an explicit Accept step, like care assistants? Yes / No
- Answer:

**3.5 Ambulance pricing.** Prices are fixed in the patient app (500 / 1200 / 2500 by type). Should drivers set their own rates?
- Yes / No
- Answer:

**3.6 Unmatched ambulance request** sits in the open pool for up to 2 hours before auto-cancelling. Is 2 hours right?
- Yes / Use ____ minutes
- Answer:

**3.7 Partner "accepting orders" switch** is enforced only for equipment when an order is pinned to a partner. Enforce for lab and pharmacy too?
- Yes / No
- Answer:

**3.8 Customer cancel after arrival.** Should a customer be able to cancel once the ambulance or caregiver has arrived?
- Yes / No
- Answer:

**3.9 Cart quantity.** A quantity of 2 for a physio, nurse or lab test makes one booking with a doubled amount.
- A) Make two separate bookings
- B) Keep one booking
- Answer:

**3.10 Slots and rescheduling for physio, counselling and dietician.** Partners cannot publish slots (patients type a date and time), and neither side can reschedule.
- Build slot publishing and reschedule? Yes / No / Later
- Answer:

---

## 4. Patient app behaviour

**4.1 ₹20 platform fee.** Booking from the Schedule tab adds ₹20, but booking from a doctor's profile does not.
- A) Both add ₹20  B) Neither  C) Only on the Schedule tab (as now)
- Answer:

**4.2 Quick Connect (instant) consultations** do not get the "book a follow-up" popup when they end.
- Add it? Yes / No
- Answer:

**4.3 Biometric lock** shows on a logged-out device too. Apply only while logged in?
- Yes / No
- Answer:

**4.4 Test-mode receipt** says "Amount Paid ₹X" with a "NOPAY-" id. Change to "No charge (test mode)"?
- Yes / No
- Answer:

**4.5 Referral codes** entered at sign-up are silently ignored (they need a server lookup). Make them work?
- Yes / No
- Answer:

**4.6 Cart "Clear" button** has no confirmation. Add one?
- Yes / No
- Answer:

---

## 5. Partner app behaviour

**5.1 Going offline.** Physio, counsellor and ambulance partners are set offline when they leave the dashboard tab. Intended?
- A) Intended  B) Keep them online until they switch off
- My pick: B.
- Answer:

**5.2 Booking notifications** (new booking, order or session) do nothing when tapped. Open that role's bookings list?
- Yes / No
- Answer:

**5.3 Push tokens after approval.** Approved partners cannot update the push token on their role profile. Allow it?
- Yes / No
- Answer:

**5.4 Doctor sign-out** asks no confirmation (other roles do). Add one?
- Yes / No
- Answer:

---

## 6. Release safety

**6.1 Test credit in production.** The test-credit switch must stay off in production, otherwise a customer can fake a booking and credit a partner. Confirm it will only ever be turned on in a test project.
- Confirmed / Discuss
- Answer:

**6.2 Deploy.** Rules, indexes, Cloud Functions, admin hosting and both app releases ship together. Should I run the Firestore rules through the emulator before you deploy? (It needs Java installed on this PC.)
- Yes / No
- Answer:
