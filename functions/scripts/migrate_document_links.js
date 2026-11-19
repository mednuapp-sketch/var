/**
 * One-off migration: stop exposing tokenised Storage download URLs of
 * verification documents in world-readable profile docs, and REVOKE the
 * tokens that already leaked.
 *
 * Why: `doctors/{uid}` and the partner profile docs are readable by any
 * signed-in user, and `documents.*` held `?token=` download URLs that bypass
 * Storage rules. New app builds store only the Storage PATH; owner/admin
 * resolve a fresh URL via the authenticated SDK. This script converts the
 * existing docs and rotates the download token of each document object so the
 * old URLs stop working.
 *
 * Shapes (legacy -> new):
 *   doctors/{uid}.documents.{key}:            "<https download URL>"  ->  "doctors/{uid}/docs/{key}.jpg"
 *   {role}_profiles/{uid}.documents.{key}:    {url, storagePath?, ...} -> {storagePath, ...}  (url removed)
 *   same for pendingChanges.documents.other_doc_N on partner docs.
 *
 * Profile photo special case: the doctor registration used to copy the private
 * documents.profile_photo URL into the public `photoUrl`. Revoking that token
 * would blank the avatar, so for those doctors the file is first copied to the
 * public-read `doctors/{uid}/profile.jpg` (unless it already exists) and
 * `photoUrl` is repointed to its token-free URL. profile.jpg / signature /
 * item images are NEVER token-revoked (see isRevocableDocumentPath).
 *
 * Credentials (as with the other scripts in this folder):
 *   - save a service-account key as functions/service-account.json (git-ignored), or
 *   - set GOOGLE_APPLICATION_CREDENTIALS, or use application default credentials.
 *
 * Run (from the functions/ folder):
 *   DRY RUN (default, writes nothing, copies nothing, revokes nothing):
 *     node scripts/migrate_document_links.js
 *   APPLY (Firestore writes in batches <= 400, then token rotation):
 *     node scripts/migrate_document_links.js --apply
 *   Optional:
 *     --bucket=<name>   override the Storage bucket
 *     --force-revoke    ALSO rotate tokens for entries already in path form
 *                       (use to retry after a "REVOKE FAILED" report)
 *
 * Idempotent: entries already in path form are skipped. Firestore is updated
 * BEFORE tokens are rotated, so no client is ever pointed at a dead URL.
 * Run it only after the new apps/admin panel (which understand paths) are live,
 * otherwise old builds cannot display migrated documents.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const admin = require('firebase-admin');
const { isHttpUrl, parseStorageUrl, isRevocableDocumentPath, isStoragePath } = require('./document_link_utils');

const APPLY = process.argv.includes('--apply');
const FORCE_REVOKE = process.argv.includes('--force-revoke');
const BATCH_SIZE = 400;
const bucketArg = process.argv.find((a) => a.startsWith('--bucket='));
const BUCKET = bucketArg ? bucketArg.slice('--bucket='.length) : 'mednu-healthcare-app.firebasestorage.app';

const PARTNER_COLLECTIONS = [
  'lab_profiles', 'pharmacy_profiles', 'equipment_profiles', 'ambulance_profiles',
  'caregiver_profiles', 'physiotherapist_profiles', 'counsellor_profiles', 'nutritionist_profiles',
];

function init() {
  const keyPath = path.join(__dirname, '..', 'service-account.json');
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(keyPath)) {
    admin.initializeApp({ credential: admin.credential.cert(require(keyPath)), storageBucket: BUCKET });
  } else {
    admin.initializeApp({ storageBucket: BUCKET });
  }
}

const publicUrlFor = (p) =>
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(p)}?alt=media`;

// Path of a legacy value, or null when it cannot be derived / is another bucket.
function derivePath(url, existingPath) {
  if (isStoragePath(existingPath)) return existingPath.trim();
  const parsed = parseStorageUrl(url);
  if (!parsed || parsed.bucket !== BUCKET) return null;
  return parsed.path;
}

// Plans the changes for one profile doc. Returns { updates, revoke:Set, notes:[], photo? } or null.
function planDoc(collection, snap) {
  const data = snap.data() || {};
  const updates = {};
  const revoke = new Set();
  const notes = [];
  const isDoctor = collection === 'doctors';

  const docs = data.documents && typeof data.documents === 'object' ? data.documents : {};
  for (const [key, val] of Object.entries(docs)) {
    if (isDoctor) {
      if (typeof val === 'string' && isHttpUrl(val)) {
        const p = derivePath(val, null);
        if (!p) { notes.push(`documents.${key}: cannot derive path from URL (left unchanged)`); continue; }
        updates[`documents.${key}`] = p;
        notes.push(`documents.${key}: URL -> ${p}`);
        if (isRevocableDocumentPath(p)) revoke.add(p); else notes.push(`  (not revoked: ${p} is not a document path)`);
      } else if (FORCE_REVOKE && isStoragePath(val) && isRevocableDocumentPath(val)) {
        revoke.add(val.trim());
      }
    } else if (val && typeof val === 'object') {
      const hasUrl = isHttpUrl(val.url);
      if (hasUrl) {
        const p = derivePath(val.url, val.storagePath);
        if (!p) { notes.push(`documents.${key}: cannot derive path from URL (left unchanged)`); continue; }
        if (!isStoragePath(val.storagePath)) updates[`documents.${key}.storagePath`] = p;
        updates[`documents.${key}.url`] = admin.firestore.FieldValue.delete();
        notes.push(`documents.${key}: url removed, storagePath=${p}`);
        if (isRevocableDocumentPath(p)) revoke.add(p); else notes.push(`  (not revoked: ${p} is not a document path)`);
      } else if (FORCE_REVOKE && isStoragePath(val.storagePath) && isRevocableDocumentPath(val.storagePath)) {
        revoke.add(val.storagePath.trim());
      }
    }
  }

  // Pending "other document" entries on approved partners (same shape).
  const pend = data.pendingChanges && data.pendingChanges.documents;
  if (!isDoctor && pend && typeof pend === 'object') {
    for (const [key, val] of Object.entries(pend)) {
      if (val && typeof val === 'object' && isHttpUrl(val.url)) {
        const p = derivePath(val.url, val.storagePath);
        if (!p) { notes.push(`pendingChanges.documents.${key}: cannot derive path (left unchanged)`); continue; }
        if (!isStoragePath(val.storagePath)) updates[`pendingChanges.documents.${key}.storagePath`] = p;
        updates[`pendingChanges.documents.${key}.url`] = admin.firestore.FieldValue.delete();
        notes.push(`pendingChanges.documents.${key}: url removed, storagePath=${p}`);
        if (isRevocableDocumentPath(p)) revoke.add(p);
      }
    }
  }

  // Doctor avatar that points at the private docs/profile_photo object.
  let photo = null;
  if (isDoctor && typeof data.photoUrl === 'string' && isHttpUrl(data.photoUrl)) {
    const pp = derivePath(data.photoUrl, null);
    if (pp && isRevocableDocumentPath(pp)) {
      revoke.add(pp);
      photo = { from: pp, to: `doctors/${snap.id}/profile.jpg` };
      updates.photoUrl = publicUrlFor(photo.to);
      notes.push(`photoUrl: points at private ${pp}; will be repointed to ${photo.to} (public)`);
    }
  }

  if (!Object.keys(updates).length && !revoke.size) return null;
  return { ref: snap.ref, updates, revoke, notes, photo };
}

async function ensurePublicPhoto(bucket, photo) {
  const dest = bucket.file(photo.to);
  const [exists] = await dest.exists();
  if (exists) return;
  await bucket.file(photo.from).copy(dest);
  // Do not carry the private object's (soon revoked) token onto the public copy.
  try { await dest.setMetadata({ metadata: { firebaseStorageDownloadTokens: null } }); } catch (_) { /* best effort */ }
}

async function main() {
  init();
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  console.log(APPLY ? 'MODE: APPLY (writing changes)' : 'MODE: DRY-RUN (no writes; pass --apply to write)');
  console.log(`Bucket: ${BUCKET}${FORCE_REVOKE ? '   (--force-revoke on)' : ''}\n`);

  const collections = ['doctors', ...PARTNER_COLLECTIONS];
  const summary = { scanned: 0, docsToChange: 0, entries: 0, revokes: 0, photoRepoints: 0, skipped: 0, failedDocs: 0, revokeFailed: [] };
  const allRevokes = new Set();

  for (const coll of collections) {
    const snap = await db.collection(coll).get();
    const plans = [];
    for (const d of snap.docs) {
      summary.scanned++;
      const plan = planDoc(coll, d);
      if (!plan) { summary.skipped++; continue; }
      plans.push(plan);
      console.log(`${coll}/${d.id}`);
      plan.notes.forEach((n) => console.log('   ' + n));
      if (FORCE_REVOKE) plan.revoke.forEach((p) => console.log(`   revoke token: ${p}`));
    }
    console.log(`-- ${coll}: ${snap.size} doc(s), ${plans.length} to change\n`);
    summary.docsToChange += plans.length;
    plans.forEach((p) => { summary.entries += Object.keys(p.updates).length; if (p.photo) summary.photoRepoints++; });

    if (!APPLY) { plans.forEach((p) => p.revoke.forEach((x) => allRevokes.add(x))); continue; }

    // 1) public avatar copies (before Firestore is repointed). A failed copy skips the doc entirely.
    const ready = [];
    for (const p of plans) {
      if (p.photo) {
        try { await ensurePublicPhoto(bucket, p.photo); } catch (e) {
          console.error(`   SKIPPED ${p.ref.path}: could not create public avatar copy (${e.message})`);
          summary.failedDocs++;
          continue;
        }
      }
      ready.push(p);
    }
    // 2) Firestore, batches <= 400.
    for (let i = 0; i < ready.length; i += BATCH_SIZE) {
      const batch = db.batch();
      ready.slice(i, i + BATCH_SIZE).forEach((p) => {
        if (Object.keys(p.updates).length) {
          batch.update(p.ref, { ...p.updates, documentLinksMigratedAt: admin.firestore.FieldValue.serverTimestamp() });
        }
      });
      await batch.commit();
      console.log(`   committed ${Math.min(i + BATCH_SIZE, ready.length)}/${ready.length}`);
    }
    // 3) token rotation, only for docs whose Firestore write succeeded.
    ready.forEach((p) => p.revoke.forEach((x) => allRevokes.add(x)));
  }

  summary.revokes = allRevokes.size;
  if (APPLY) {
    for (const p of allRevokes) {
      try {
        await bucket.file(p).setMetadata({ metadata: { firebaseStorageDownloadTokens: crypto.randomUUID() } });
        console.log(`revoked: ${p}`);
      } catch (e) {
        console.error(`REVOKE FAILED: ${p} (${e.code || ''} ${e.message})`);
        summary.revokeFailed.push(p);
      }
    }
  } else {
    allRevokes.forEach((p) => console.log(`would revoke token: ${p}`));
  }

  console.log('\n=== SUMMARY ===');
  console.log(`docs scanned:            ${summary.scanned}`);
  console.log(`docs to change/changed:  ${summary.docsToChange}`);
  console.log(`field updates:           ${summary.entries}`);
  console.log(`doctor avatars repointed:${summary.photoRepoints}`);
  console.log(`objects to revoke:       ${summary.revokes}`);
  console.log(`docs already clean:      ${summary.skipped}`);
  if (summary.failedDocs) console.log(`docs skipped (errors):   ${summary.failedDocs}`);
  if (summary.revokeFailed.length) {
    console.log(`REVOKE FAILED for ${summary.revokeFailed.length} object(s); re-run with --apply --force-revoke`);
    process.exitCode = 2;
  }
  if (!APPLY) console.log('\nDry run complete. Re-run with --apply to write.');
}

main().then(() => process.exit(process.exitCode || 0)).catch((e) => {
  console.error('Migration failed:', e);
  process.exit(1);
});
