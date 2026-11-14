/**
 * One-off migration: doctors saved with specialty 'General Physician' -> 'General'.
 *
 * Why: the patient app's "General" filter (and the partner-side lists) use
 * 'General'; doctors still stored as 'General Physician' fall outside it.
 * Source of truth is the `doctors` collection (the patient app reads doctor
 * listings straight from `doctors`; no separate listing/mirror collection).
 *
 * Credentials (as with the other scripts in this folder):
 *   - Either save a service-account key as functions/service-account.json
 *     (git-ignored), or
 *   - set GOOGLE_APPLICATION_CREDENTIALS to the key file path, or run where
 *     application default credentials exist (gcloud auth application-default login).
 *
 * Run (from the functions/ folder):
 *   DRY RUN (default, writes nothing):
 *     node scripts/migrate_general_physician.js
 *   APPLY (writes in batches of <= 400):
 *     node scripts/migrate_general_physician.js --apply
 *
 * Only `specialty` (-> 'General') and `specialtyMigratedAt` are written.
 * No other field is touched. Re-running is safe (already-migrated docs no longer match).
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const APPLY = process.argv.includes('--apply');
const OLD_SPECIALTY = 'General Physician';
const NEW_SPECIALTY = 'General';
const BATCH_SIZE = 400;

function init() {
  const keyPath = path.join(__dirname, '..', 'service-account.json');
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(keyPath)) {
    admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  } else {
    // Uses GOOGLE_APPLICATION_CREDENTIALS / application default credentials.
    admin.initializeApp();
  }
}

async function main() {
  init();
  const db = admin.firestore();
  console.log(APPLY ? 'MODE: APPLY (writing changes)' : 'MODE: DRY-RUN (no writes; pass --apply to write)');

  const snap = await db.collection('doctors').where('specialty', '==', OLD_SPECIALTY).get();
  console.log(`Found ${snap.size} doctor(s) with specialty "${OLD_SPECIALTY}".`);
  if (snap.empty) return;

  snap.docs.forEach((d) => {
    const data = d.data();
    console.log(`  ${d.id}  ${data.name || data.fullName || '(no name)'}  "${OLD_SPECIALTY}" -> "${NEW_SPECIALTY}"`);
  });

  if (!APPLY) {
    console.log('\nDry run complete. Re-run with --apply to update.');
    return;
  }

  let updated = 0;
  for (let i = 0; i < snap.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    snap.docs.slice(i, i + BATCH_SIZE).forEach((d) => {
      batch.update(d.ref, {
        specialty: NEW_SPECIALTY,
        specialtyMigratedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    await batch.commit();
    updated += Math.min(BATCH_SIZE, snap.docs.length - i);
    console.log(`Committed ${updated}/${snap.size}`);
  }
  console.log('Done.');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error('Migration failed:', e);
  process.exit(1);
});
