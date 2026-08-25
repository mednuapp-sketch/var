# MedNU Admin Panel

A complete web admin dashboard for the MedNU app.
Connects directly to your existing Firebase (Firestore) backend.

---

## 📁 File Structure

```
mednu-admin/
├── index.html              ← Main app (open this in browser)
├── css/
│   └── style.css           ← All styles
├── js/
│   ├── firebase-config.js  ← ⚠️ PUT YOUR FIREBASE KEYS HERE
│   └── app.js              ← All logic & Firebase queries
└── README.md
```

---

## 🚀 Setup (3 steps)

### Step 1 — Add your Firebase credentials

Open `js/firebase-config.js` and replace the placeholder values:

```js
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",           // ← replace
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID"
};
```

**How to get these:**
1. Go to https://console.firebase.google.com
2. Open your MedNU project
3. Click ⚙️ Settings → Project Settings
4. Scroll to "Your apps" → Web app → Copy config

---

### Step 2 — Create an Admin user in Firebase

1. Go to Firebase Console → Authentication → Users
2. Click "Add user"
3. Enter admin email + password
4. This is what you'll use to log in to the admin panel

---

### Step 3 — Set Firestore Security Rules

In Firebase Console → Firestore → Rules, add:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null 
        && request.auth.token.email == "YOUR_ADMIN_EMAIL@gmail.com";
    }
  }
}
```

Replace with your actual admin email.

---

## 🗃️ Expected Firestore Collections

The admin panel reads from these collections in your Firestore (matches the actual
Flutter app schema — verified against `mednu/lib` and `mednu_doctor/lib` 2026-08-25):

| Collection         | Fields actually used |
|--------------------|-----------------|
| `doctors`          | name, email, phone, specialty (canonical; `specialisation`/`specialization` kept as legacy fallbacks), status, rating, totalConsultations, createdAt |
| `users`            | patient profiles — name, email, phone, dob (age is computed client-side), gender, role, createdAt. There is **no** separate `patients` collection with profile data — a `patients` collection exists but only ever holds `{fcmToken}`. |
| `payments`         | amount, type, status, userId, doctorId, createdAt. **No** `patientName`/`doctorName`/`paymentId` fields exist — the admin panel resolves display names client-side from the loaded `doctors`/`users` lists. |
| `prescriptions`    | medicines (array; canonical key is `medicineName`, `name` kept as legacy alias), doctorId, doctorName, patientId, patientName, createdAt |
| `support_tickets`  | (not `tickets`) — category, description, doctorName, phone, priority, status, createdAt |
| `reports`          | Patient-uploaded scans only — patientId, name, imageUrl, storagePath, createdAt. Admin-generated report requests are stored separately in `admin_generated_reports` (title, type, range, status, downloadUrl, createdAt) to avoid colliding with patient data. |

> If your Flutter app's field names change, update `js/app.js` to match.

---

## 🌐 How to deploy (optional)

### Option A — Firebase Hosting (free)
```bash
npm install -g firebase-tools
firebase login
firebase init hosting   # select your project, public dir = .
firebase deploy
```

### Option B — Just open the file
For local use, simply open `index.html` in your browser. No server needed.

### Option C — Any web host
Upload the entire `mednu-admin/` folder to any web hosting (Hostinger, Netlify, etc.)

---

## 🔧 Customisation

- **Logo / Name:** Search for "MedNU" in `index.html` and replace
- **Colors:** Edit CSS variables at the top of `css/style.css`
- **Add a new section:** Copy a tab in `index.html`, add nav item, add JS loader in `app.js`

---

Built for MedNU · Firebase + Paytm Stack
