# MedNU — Pre-release Test Checklist

> Created: 2026-10-01 · Run on **real phones** with the release builds
> (`app-release.aab` / install a release APK), not the debug build.

**Setup before you start**
- Two phones: Phone A = patient app (`mednu`), Phone B = partner app (`mednu_doctor`).
- Both phone numbers must be on WhatsApp. Until the WhatsApp payment method is added,
  they must also be on the Meta test-recipient list.
- One partner account per role you plan to launch (at least Doctor, Pharmacy, Lab, Ambulance).
- Keep Firestore console open on `whatsapp_logs`, `appointments`, `orders`, `service_requests`.

Mark each line ✅ pass / ❌ fail (write what happened next to it).

---

## 1. Patient app (`mednu`)

### Account
- [ ] Fresh install → register with phone OTP → accept Terms → lands on home
- [ ] Log out → log back in → same profile and data
- [ ] Switch language (English / Hindi / Telugu) → screens change, nothing breaks
- [ ] Profile → Settings → WhatsApp updates toggle ON
- [ ] Privacy Policy and Terms links open the correct pages
- [ ] Delete account flow works (use a throwaway account)

### Home screen
- [ ] Home loads with no errors, banners show
- [ ] Search icon / search finds doctors by name and specialization *(bug 6, 23)*
- [ ] Tapping a speciality (General, Cardiology…) shows only that speciality *(bug 7)*
- [ ] Family members: **Add** button works *(bug 9)*, member is clickable/editable *(bug 8)*
- [ ] Back button from another section returns to home; from home asks "exit?" *(bug 2)*

### Doctor booking
- [ ] Open a doctor → pick a slot → book → confirmation shows
- [ ] After booking, app returns to the Appointments screen *(bug 12)*
- [ ] Booking shows in Appointments with correct date and time
- [ ] The same slot can't be booked twice (try from a second account)
- [ ] Cancel the booking → status shows cancelled
- [ ] WhatsApp: "booking received" + "booking confirmed" arrive with **your name, doctor's name, correct time**
- [ ] WhatsApp: cancel message arrives after cancelling
- [ ] WhatsApp reminder arrives about 1 hour before the appointment

### Video consultation
- [ ] Doctor calls / patient joins → both see and hear each other *(bug 17)*
- [ ] Camera on/off, mute, switch camera, end call work
- [ ] Poor network: call drops to lower quality instead of freezing
- [ ] After the call, prescription from the doctor appears for the patient

### Medicine delivery
- [ ] Browse medicines → add to cart → **+ / −** change quantity *(bug 16)*
- [ ] Upload prescription works *(bug 13)*
- [ ] First order asks for name / phone / address; address saved for next time *(bug 14)*
- [ ] Order for a family member / someone else *(bug 14)*
- [ ] Place order → appears in Orders → status updates as pharmacy acts
- [ ] Track order shows map *(bug 15)*
- [ ] WhatsApp order-status messages arrive at each step

### Lab tests
- [ ] Book a lab test → lab receives it on Phone B
- [ ] Status updates show in the patient app
- [ ] Report uploaded by the lab is visible in the patient app *(bug 20)*
- [ ] WhatsApp "report ready" arrives *(needs `mednu_report_ready` approved by Meta)*

### Ambulance / SOS
- [ ] Location is picked up live, or can be set on the map / by search *(bug 18)*
- [ ] Book ambulance → partner receives it → live tracking works
- [ ] SOS button works and is clearly different from service emergency *(bug 11)*

### Other services (only those you are launching)
- [ ] Caregiver booking end to end
- [ ] Physiotherapy booking end to end
- [ ] Counselling booking end to end
- [ ] Nutritionist booking end to end

### Records & notifications
- [ ] Upload a health record → it appears in the list *(bug 21)*
- [ ] Prescriptions can be shared and downloaded; "order all" adds medicines to cart *(bug 19)*
- [ ] Push notifications arrive with the app closed
- [ ] Tapping a notification opens the right screen *(bug 5)*

### Payments (only if `kRequirePayment` is turned on)
- [ ] Razorpay opens with the **live** key, payment succeeds, booking is created
- [ ] Payment failure / back-out → no booking is created
- [ ] WhatsApp "payment received" arrives

---

## 2. Partner app (`mednu_doctor`)

### Account (repeat for each launch role)
- [ ] Register → role picker → fill profile → submit for approval
- [ ] Admin approves in `mednu-admin` → partner can now go online
- [ ] Log out / log in keeps the right role (no role mix-up)
- [ ] Settings → WhatsApp updates toggle ON
- [ ] Privacy Policy link opens the **partner** policy

### Doctor
- [ ] New booking appears on the dashboard
- [ ] WhatsApp "new booking" arrives with Accept / Decline buttons; tapping a button works
- [ ] Start video call to patient (see section 1 Video consultation)
- [ ] Write prescription → patient receives it
- [ ] Cancel from doctor side → patient gets cancel message; doctor does **not** get one
- [ ] WhatsApp appointment reminder arrives for the doctor

### Pharmacy
- [ ] Incoming order appears → verify prescription → packed → out for delivery → delivered
- [ ] Each step updates the patient app and sends WhatsApp to the patient

### Lab
- [ ] Accept request → assign technician → sample collected → upload report
- [ ] Patient sees report

### Ambulance
- [ ] Go online → receive request → accept → live location visible to patient → complete

### Caregiver / Physio / Counsellor / Nutritionist (launch roles only)
- [ ] Receive request → accept → session detail → complete

### Payouts
- [ ] Admin marks a settlement **paid** → partner gets WhatsApp payout message
      (doctor: "Hello Dr. Name", others: full business name)

---

## 3. Admin panel (`mednu-admin`)
- [ ] Log in, approve a partner, view bookings/orders
- [ ] Banners / campaigns / Web Ads edits show on the app and website

## 4. Website (`mednu.in`)
- [ ] Home page loads on phone and desktop, no made-up numbers
- [ ] `mednu.in/privacy-policy` and `mednu.in/partner-privacy-policy` open the policies
- [ ] Download buttons point to the right store listings

---

## 5. Before uploading to Play Store / App Store
- [ ] Decide on payments: `kRequirePayment` true/false; if true, build with
      `--dart-define=RAZORPAY_KEY_ID=rzp_live_...` and set the live secret in Functions
- [ ] Version number bumped in both `pubspec.yaml` files
- [ ] Partner app: add `cupertino_icons` to `mednu_doctor/pubspec.yaml` (some icons could show as boxes)
- [ ] Run `firebase deploy --only firestore:rules,storage` so live rules match the repo
- [ ] Commit all changes to git
- [ ] After most users update past 1.0.6+12: close the `appointments` list rule (PENDING.md item 0)
- [ ] Revoke the old WhatsApp token in Meta; disable `WHATSAPP_TOKEN` secret version 1
