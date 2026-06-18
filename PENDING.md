# MedNU — Pending Tasks
> Last updated: 2026-06-14

---

## ✅ Already Deployed (Firebase Backend)

| Component | Status | Notes |
|---|---|---|
| Firebase Cloud Functions (14 functions) | ✅ Live | `asia-south1` + `us-central1` |
| Firestore Composite Indexes (40+) | ✅ Live | Deployed 2026-06-14 |
| Firestore Rules | ✅ Live | No change needed |
| Storage Rules | ✅ Live | No change needed |
| Git commit (139 files) | ✅ Done | Full UX overhaul committed |

---

## 🔴 CRITICAL — Must do before Play Store / App Store release

### 1. Change Bundle ID from placeholder
**Problem:** `com.example.mednu` is a placeholder — stores reject it
**Steps (in order):**
1. Go to console.firebase.google.com
2. Select `mednu-healthcare-app` → Project Settings → Your apps
3. Add a new Android app with your chosen ID (e.g. `com.mednuhealthcare.app`)
4. Download the new `google-services.json` → paste into `mednu/android/app/`
5. Then update `mednu/android/app/build.gradle.kts`:
   - `namespace = "com.mednuhealthcare.app"`
   - `applicationId = "com.mednuhealthcare.app"`
6. Repeat for `mednu_doctor` app with its own bundle ID

---

### 2. Razorpay Live Key
**File:** `mednu/lib/features/payment/screens/payment_screen.dart` line 12
**Current:** `rzp_test_REPLACE_WITH_YOUR_KEY`
**Steps:**
1. Log in to dashboard.razorpay.com
2. Settings → API Keys → Generate Key
3. For testing: use `rzp_test_` key
4. For production (real charges): use `rzp_live_` key
5. Replace the placeholder in payment_screen.dart

---

### 3. Agora App ID — Confirm or replace
**File:** `mednu/lib/features/services/consultation/agora_call_service.dart` line 4
**Current:** `b0143ffdfef74f399a420c7cd73c9e8b`
- If this is your own registered Agora App ID → no action needed
- If it's a demo/temp key → go to console.agora.io, create a project, copy App ID, replace it

---

### 4. iOS — GoogleService-Info.plist
**Problem:** Firebase does NOT work on iOS without this file
**Steps:**
1. Go to console.firebase.google.com
2. Select `mednu-healthcare-app` → Project Settings → iOS app
3. Download `GoogleService-Info.plist`
4. Place it at `mednu/ios/Runner/GoogleService-Info.plist`

---

### ~~5. Google Cloud APIs — Enable for Maps~~ ✅ DONE
**Key:** `AIzaSyBh_sDZlUDbE-u-c_4-sWsT1gxvfTYqoco`
Maps SDK, Geocoding, Places, Directions APIs — enabled 2026-06-14
> Reminder: restrict the key to your app package + SHA-1 in Credentials once bundle ID is finalized

---

## 🟡 Admin Panel — Deploy to Vercel

**Files:** `mednu-admin/` (index.html, css/style.css, js/app.js — all updated)

**Steps:**
1. Go to vercel.com → Sign in
2. New Project → Import GitHub repo OR drag-and-drop `mednu-admin/` folder
3. Root Directory: `mednu-admin`, Framework: Other (plain HTML)
4. Deploy → get URL like `https://mednu-admin.vercel.app`

---

## 🟡 Flutter Apps — Build APKs

Once critical blockers (#1–5 above) are resolved:

```bash
# Patient app
cd mednu
flutter build apk --release

# Doctor app
cd mednu_doctor
flutter build apk --release
```

For Play Store: sign with your keystore (set up `mednu/android/key.properties`)
For App Store: requires Mac with Xcode + Apple Developer account

---

## ✅ Already Done (Complete List)

- [x] Firebase Functions deployed (14 triggers in asia-south1 + us-central1)
- [x] Firestore Indexes deployed (40+ composite indexes)
- [x] Firebase Hosting config added to firebase.json
- [x] .firebaserc added — project linked to mednu-healthcare-app
- [x] Full UX/UI overhaul — mednu patient app (100+ screens upgraded)
- [x] Full UX/UI overhaul — mednu_doctor app (all screens upgraded)
- [x] Shared UX widgets (ux_widgets.dart) for both apps
- [x] Google Maps API key added to AndroidManifest.xml
- [x] Google Places API service (autocomplete + details)
- [x] MapsLauncher utility (open/navigate in Google Maps)
- [x] Address book route registered in GoRouter
- [x] Location picker upgraded to Google Places API
- [x] Map picker — Open in Google Maps + Navigate buttons
- [x] Admin panel — location block with Navigate + Open in Maps
- [x] iOS Info.plist — all permissions added
- [x] Android Manifest — all permissions + FCM channel + url_launcher queries
- [x] Android colors.xml — notification color resource
- [x] FCM (Firebase Cloud Messaging) — fully wired in main.dart
- [x] Razorpay SDK — wired up in payment_screen.dart (needs real key)
- [x] Google Maps JS SDK — added to admin panel index.html
- [x] Health trackers — Water & period trackers (Firestore + notifications)
- [x] Promotional banner system — Firestore banners collection
- [x] MedNu Doctor app — full audit, 13 bugs fixed
- [x] Git committed — 139 files, full history preserved
