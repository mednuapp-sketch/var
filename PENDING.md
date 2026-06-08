# MedNU — Pending Tasks
> Last updated: 2026-05-17

---

## 🔴 CRITICAL — Must do before production

### 1. Google Cloud Console — Enable APIs
**What:** Enable the following APIs for key `AIzaSyBh_sDZlUDbE-u-c_4-sWsT1gxvfTYqoco`
- Maps SDK for Android
- Maps SDK for iOS
- Geocoding API
- Places API
- Directions API

**How:**
1. Go to console.cloud.google.com
2. Select project `mednu-healthcare-app`
3. APIs & Services → Library → search and enable each one
4. APIs & Services → Credentials → restrict the key to your app package + SHA-1

---

### 2. iOS — Download GoogleService-Info.plist
**What:** Firebase does not work on iOS without this file
**How:**
1. Go to console.firebase.google.com
2. Select project `mednu-healthcare-app`
3. Project Settings → Your apps → iOS app
4. Download `GoogleService-Info.plist`
5. Paste it inside `mednu/ios/Runner/` folder

---

### 3. Razorpay Key ID
**What:** Replace placeholder key in `payment_screen.dart`
**File:** `mednu/lib/features/payment/screens/payment_screen.dart` line 10
**Current value:** `rzp_test_REPLACE_WITH_YOUR_KEY`
**How:**
1. Log in to dashboard.razorpay.com
2. Settings → API Keys → Generate Test Key
3. Copy the Key ID (starts with `rzp_test_`)
4. Replace the placeholder in payment_screen.dart
5. For production use `rzp_live_` key

---

### 4. Bundle ID — Change from placeholder
**What:** `com.example.mednu` is a placeholder and will cause Play Store / App Store rejection
**Files to update:**
- `mednu/android/app/build.gradle.kts` → `applicationId`
- `mednu/android/app/google-services.json` → `package_name`
- `mednu/ios/Runner.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER`
- Firebase Console → update both Android and iOS app package names
- Re-download `google-services.json` and `GoogleService-Info.plist` after change

**Suggested ID:** `com.mednuhealthcare.app` or `in.mednu.app`

---

### 5. Agora App ID — Replace with production key
**What:** The Agora App ID in the video call service is a development/test key
**File:** Search for `b0143ffdfef74f399a420c7cd73c9e8b` in the codebase
**How:**
1. Log in to console.agora.io
2. Create or open your project
3. Copy the App ID
4. Replace the hardcoded value with your production App ID

---

## 🟡 FEATURES — Implement when ready (Claude will do these)

### 6. OTP Authentication
**What:** OTP-based phone number login/verification flow needs to be implemented or fixed
**Scope:** Firebase Phone Auth + OTP screen UI + resend timer + error handling
**Tell Claude:** "implement OTP authentication"

---

### 7. Banner Upload — Admin Panel + Flutter App
**What:** Promotional banner upload (admin creates banners → app shows popup)
**Scope:** Admin panel image upload to Firebase Storage + Flutter banner popup with deep link
**Tell Claude:** "implement banner upload"

---

## 🟢 ONE-TIME CONSOLE SETUPS (manual, ~5 min each)

| # | Task | Console | Time |
|---|------|---------|------|
| 1 | Enable Maps/Places/Geocoding APIs | console.cloud.google.com | 5 min |
| 2 | Download GoogleService-Info.plist | console.firebase.google.com | 2 min |
| 3 | Get Razorpay Test Key ID | dashboard.razorpay.com | 3 min |
| 4 | Get Agora Production App ID | console.agora.io | 5 min |
| 5 | Deploy Firestore indexes | `firebase deploy --only firestore:indexes` in terminal | 2 min |

---

## 📋 Deploy Firestore Indexes
Run this once in the `var/` folder after Firebase CLI is set up:
```
firebase deploy --only firestore:indexes
```
This deploys `firestore.indexes.json` which has all 40+ composite indexes needed.

---

## ✅ Already Done

- [x] Google Maps API key added to AndroidManifest.xml
- [x] Google Places API service (autocomplete + details)
- [x] MapsLauncher utility (open/navigate in Google Maps)
- [x] Address book route registered in GoRouter
- [x] Location picker upgraded to Google Places API
- [x] Map picker — Open in Google Maps + Navigate buttons
- [x] Admin panel — location block with Navigate + Open in Maps
- [x] iOS Info.plist — all permissions added (Camera, Mic, Photos, Health, Face ID, Location, Contacts)
- [x] Android Manifest — all permissions + FCM channel + url_launcher queries
- [x] Android colors.xml — notification color resource
- [x] Firestore indexes — 40+ composite indexes for all collections
- [x] FCM (Firebase Cloud Messaging) — fully wired in main.dart
- [x] Razorpay SDK — wired up in payment_screen.dart (needs real key)
- [x] Google Maps JS SDK — added to admin panel index.html
- [x] Health trackers — Water & period trackers (Firestore + notifications)
- [x] Promotional banner system — Firestore banners collection
- [x] MedNu Doctor app — full audit, 13 bugs fixed
