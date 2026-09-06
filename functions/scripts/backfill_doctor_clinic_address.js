// One-off backfill: set a default clinic name/address on doctor records that
// have no consultation address on file (empty or missing clinicAddress AND
// hospitalAddress). Doctors who already have a real address are left untouched.
//
// Setup:
//   1. Firebase Console -> Project Settings -> Service Accounts ->
//      "Generate new private key" for the mednu-healthcare-app project.
//   2. Save the downloaded JSON as service-account.json in this same
//      functions/ folder (it's already git-ignored alongside node_modules —
//      double check before committing anything).
//   3. Run:  node scripts/backfill_doctor_clinic_address.js --dry-run
//      to preview, then re-run without --dry-run to actually write.
//
// Usage:
//   node scripts/backfill_doctor_clinic_address.js [--dry-run]

const path = require('path');
const admin = require('firebase-admin');

const DRY_RUN = process.argv.includes('--dry-run');

const DEFAULT_CLINIC_NAME = 'Medicover Hospitals, Hitech City';
const DEFAULT_CLINIC_ADDRESS =
  'Survey No. 460, Road No. 2, Hitech City, Madhapur, Hyderabad, Telangana 500081';

function nonEmpty(v) {
  const t = typeof v === 'string' ? v.trim() : '';
  return t.length > 0 ? t : null;
}

function hasAddress(data) {
  return nonEmpty(data.clinicAddress) !== null || nonEmpty(data.hospitalAddress) !== null;
}

// Partner/service accounts that happen to live in the `doctors` collection —
// not actual in-person consulting doctors, so a clinic address doesn't apply.
const SKIP_IDS = new Set([
  'ITY1ReTCQ5U5pnRogeSsuTqO9DZ2', // Navya Diagnostics
  'QbVqDY2IwRRt0nP3ERrlE4wme3o2', // Navya Medicals
  'V66jsNdzDbMPNfTh25sIPKULir03', // vars lab
  'tVNXBNzdWBfOpuuNtFKYKE0jwb32', // MedNU Pharmacy
]);

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

  const snap = await db.collection('doctors').get();
  console.log(`Found ${snap.size} doctor document(s).`);

  const toUpdate = [];
  snap.forEach((doc) => {
    const data = doc.data();
    if (!hasAddress(data) && !SKIP_IDS.has(doc.id)) {
      toUpdate.push({ id: doc.id, name: data.name || '(no name)' });
    }
  });

  console.log(`${toUpdate.length} doctor(s) have no clinic/hospital address on file:`);
  toUpdate.forEach((d) => console.log(`  - ${d.id}  (${d.name})`));

  if (toUpdate.length === 0) {
    console.log('Nothing to update.');
    return;
  }

  if (DRY_RUN) {
    console.log('\nDry run only — no writes made. Re-run without --dry-run to apply.');
    return;
  }

  const batchSize = 400; // Firestore batch limit is 500
  for (let i = 0; i < toUpdate.length; i += batchSize) {
    const batch = db.batch();
    for (const d of toUpdate.slice(i, i + batchSize)) {
      batch.update(db.collection('doctors').doc(d.id), {
        clinicName: DEFAULT_CLINIC_NAME,
        clinicAddress: DEFAULT_CLINIC_ADDRESS,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  console.log(`\nUpdated ${toUpdate.length} doctor document(s) with the default clinic address.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
