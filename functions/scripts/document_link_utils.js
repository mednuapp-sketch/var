"use strict";
// Pure helpers for scripts/migrate_document_links.js (no firebase-admin import, unit-tested in test/unit/document_link_utils.test.js).

function isHttpUrl(v) {
  return typeof v === "string" && /^https?:\/\//i.test(v.trim());
}

// Extracts { bucket, path } from a Firebase Storage URL, or null.
//   https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<url-encoded path>?alt=media&token=...
//   https://storage.googleapis.com/<bucket>/<path>            (also /download/storage/v1/b/<bucket>/o/<path>)
function parseStorageUrl(url) {
  if (!isHttpUrl(url)) return null;
  let u;
  try { u = new URL(String(url).trim()); } catch (_) { return null; }
  let m;
  if (u.hostname === "firebasestorage.googleapis.com") {
    m = u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
  } else if (u.hostname === "storage.googleapis.com") {
    m = u.pathname.match(/^\/download\/storage\/v1\/b\/([^/]+)\/o\/(.+)$/) || u.pathname.match(/^\/([^/]+)\/(.+)$/);
  }
  if (!m) return null;
  let p;
  try { p = decodeURIComponent(m[2]); } catch (_) { return null; }
  if (!p || p.startsWith("/") || p.split("/").includes("..")) return null;
  return { bucket: m[1], path: p };
}

// Only verification-document objects may have their download token revoked.
// Never profile photos, signatures or item images: those are public and their
// stored token-free URLs must keep working.
function isRevocableDocumentPath(p) {
  if (typeof p !== "string" || !p || p.startsWith("/") || p.split("/").includes("..")) return false;
  if (/(^|\/)profile\.jpg$/.test(p) || /(^|\/)signature\.png$/.test(p) || /\/items\//.test(p)) return false;
  return /^doctors\/[^/]+\/docs\/.+/.test(p) ||
    /^doctor_documents\/.+/.test(p) ||
    /^[a-z_]+_documents\/[^/]+\/.+/.test(p);
}

// True for a stored value that is already a bare Storage path (new shape).
function isStoragePath(v) {
  return typeof v === "string" && v.trim() !== "" && !isHttpUrl(v);
}

module.exports = { isHttpUrl, parseStorageUrl, isRevocableDocumentPath, isStoragePath };
