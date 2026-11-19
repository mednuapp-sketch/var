const assert = require("assert");
const U = require("../../scripts/document_link_utils.js");

const B = "mednu-healthcare-app.firebasestorage.app";
const enc = (p) => encodeURIComponent(p);

// firebasestorage.googleapis.com download URL (token form)
assert.deepStrictEqual(
  U.parseStorageUrl(`https://firebasestorage.googleapis.com/v0/b/${B}/o/${enc("doctors/u1/docs/mbbs_degree.jpg")}?alt=media&token=abc-123`),
  { bucket: B, path: "doctors/u1/docs/mbbs_degree.jpg" });
// token-free alt=media form
assert.deepStrictEqual(
  U.parseStorageUrl(`https://firebasestorage.googleapis.com/v0/b/${B}/o/${enc("lab_documents/u 2/lab_license.pdf")}?alt=media`),
  { bucket: B, path: "lab_documents/u 2/lab_license.pdf" });
// storage.googleapis.com forms
assert.deepStrictEqual(U.parseStorageUrl(`https://storage.googleapis.com/${B}/a/b.jpg`), { bucket: B, path: "a/b.jpg" });
assert.deepStrictEqual(U.parseStorageUrl(`https://storage.googleapis.com/download/storage/v1/b/${B}/o/${enc("a/b.jpg")}?alt=media`), { bucket: B, path: "a/b.jpg" });
// admin-uploaded doctor doc with sanitised filename
assert.strictEqual(U.parseStorageUrl(`https://firebasestorage.googleapis.com/v0/b/${B}/o/${enc("doctor_documents/d1/mbbs_degree_1700000000_scan.pdf")}?alt=media&token=t`).path,
  "doctor_documents/d1/mbbs_degree_1700000000_scan.pdf");
// rejects
for (const bad of ["", null, undefined, 42, "doctors/u1/docs/x.jpg", "https://example.com/x.jpg", "javascript:alert(1)",
  `https://firebasestorage.googleapis.com/v0/b/${B}/o/${enc("../secret")}?alt=media`, "https://firebasestorage.googleapis.com/v0/b/x/o/%E0%A4%A"]) {
  assert.strictEqual(U.parseStorageUrl(bad), null, String(bad));
}

assert.strictEqual(U.isHttpUrl(" HTTPS://x"), true);
assert.strictEqual(U.isHttpUrl("doctors/u/docs/a.jpg"), false);
assert.strictEqual(U.isStoragePath("doctors/u/docs/a.jpg"), true);
assert.strictEqual(U.isStoragePath("https://x/y"), false);
assert.strictEqual(U.isStoragePath(""), false);

// revocation allow-list: documents yes, public images no
for (const ok of ["doctors/u1/docs/mbbs_degree.jpg", "doctors/u1/docs/profile_photo.jpg", "doctor_documents/d1/x_1_a.pdf",
  "lab_documents/u1/lab_license.pdf", "physiotherapist_documents/u1/other_doc_2.jpg", "caregiver_documents/u1/certificates.jpg"]) {
  assert.strictEqual(U.isRevocableDocumentPath(ok), true, ok);
}
for (const no of ["doctors/u1/profile.jpg", "doctors/u1/signature.png", "lab_profiles/u1/profile.jpg",
  "equipment_profiles/u1/items/i1.jpg", "users/u1/profile.jpg", "spec_requests/u1/1.pdf", "", "/lab_documents/u/x.jpg", "lab_documents/../x/y.jpg"]) {
  assert.strictEqual(U.isRevocableDocumentPath(no), false, no);
}
console.log("document_link_utils_test OK");
