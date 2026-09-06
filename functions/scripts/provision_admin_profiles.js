// One-off provisioning: creates the 5 admin-panel login profiles (Director,
// HR, Finance, Marketing, Support and Tele-calling) as Firebase Auth users
// and writes their admins/{uid} doc with a `role` field, matching the
// ROLE_TAB_ACCESS gating in mednu-admin/js/app.js.
//
// Setup:
//   1. Firebase Console -> Project Settings -> Service Accounts ->
//      "Generate new private key" for the mednu-healthcare-app project.
//   2. Save the downloaded JSON as service-account.json in this same
//      functions/ folder (it's already git-ignored alongside node_modules —
//      double check before committing anything).
//   3. Run:  node scripts/provision_admin_profiles.js --dry-run
//      to preview, then re-run without --dry-run to actually create.
//
// Idempotent: an email that already has a Firebase Auth account is left
// alone (password untouched) — only its admins/{uid}.role gets (re)written.
// Generated passwords are printed once at the end and nowhere else; copy
// them out immediately and have each profile owner change theirs on first
// login (Firebase Auth has no forced-change-on-first-login flag).

const path = require('path');
const admin = require('firebase-admin');
const crypto = require('crypto');

const DRY_RUN = process.argv.includes('--dry-run');

const PROFILES = [
  { role: 'director',  email: 'director@mednu.com',  displayName: 'Director' },
  { role: 'hr',         email: 'hr@mednu.com',         displayName: 'HR' },
  { role: 'finance',    email: 'finance@mednu.com',    displayName: 'Finance' },
  { role: 'marketing',  email: 'marketing@mednu.com',  displayName: 'Marketing' },
  { role: 'support',    email: 'support@mednu.com',    displayName: 'Support & Tele-calling' },
];

function generatePassword() {
  return crypto.randomBytes(12).toString('base64url'); // 16 chars, URL-safe
}

async function main() {
  const serviceAccountPath = path.join(__dirname, '..', 'service-account.json');
  let serviceAccount;
  try {
    serviceAccount = require(serviceAccountPath);
  } catch (e) {
    console.error(`Could not load service account key at ${serviceAccountPath}`);
    console.error('Download one from Firebase Console -> Project Settings -> Service Accounts.');
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  const created = [];

  for (const profile of PROFILES) {
    let userRecord;
    let isNew = false;
    try {
      userRecord = await admin.auth().getUserByEmail(profile.email);
      console.log(`[exists] ${profile.email} (uid ${userRecord.uid}) — leaving password untouched.`);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
      if (DRY_RUN) {
        console.log(`[dry-run] would create ${profile.email} with role=${profile.role}`);
        continue;
      }
      const password = generatePassword();
      userRecord = await admin.auth().createUser({
        email: profile.email,
        password,
        displayName: profile.displayName,
      });
      isNew = true;
      created.push({ ...profile, uid: userRecord.uid, password });
      console.log(`[created] ${profile.email} (uid ${userRecord.uid})`);
    }

    if (!DRY_RUN) {
      await db.collection('admins').doc(userRecord.uid).set({
        role: profile.role,
        email: profile.email,
        displayName: profile.displayName,
        ...(isNew ? { createdAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
      }, { merge: true });
      console.log(`  -> admins/${userRecord.uid}.role = ${profile.role}`);
    }
  }

  if (!DRY_RUN && created.length) {
    console.log('\nGenerated passwords — copy these out now, they are not stored anywhere:\n');
    created.forEach(r => console.log(`  ${r.role.padEnd(10)} ${r.email.padEnd(24)} ${r.password}`));
  }
}

main().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(1); });
