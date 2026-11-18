"use strict";
// Pure helpers for type-aware ambulance matching (no Firestore access, so they
// can be unit-tested standalone).

// Canonical vehicle-type key ('basic' | 'als' | 'icu') from a booking's
// serviceDetails ({ambulanceTypeKey, ambulanceType}) or a bare string.
// Returns null when the request carries no recognisable type (legacy request:
// any driver may take it).
function normalizeAmbulanceTypeKey(raw) {
  const s = String(raw ?? "").trim().toLowerCase();
  if (s === "basic" || s === "basic life support" || s === "bls") return "basic";
  if (s === "als" || s === "advanced life support") return "als";
  if (s === "icu" || s === "icu ambulance") return "icu";
  return null;
}

function requestedAmbulanceTypeKey(details) {
  return normalizeAmbulanceTypeKey(details?.ambulanceTypeKey) ||
    normalizeAmbulanceTypeKey(details?.ambulanceType);
}

// Driver side: only the canonical `vehicleTypeKey` counts (a driver with no key
// has not chosen a type yet and matches no typed request).
function driverVehicleTypeKey(profile) {
  const k = String(profile?.vehicleTypeKey ?? "").trim().toLowerCase();
  return k === "basic" || k === "als" || k === "icu" ? k : null;
}

// requestedKey null => legacy untyped request => every driver matches.
function driverMatchesRequestedType(profile, requestedKey) {
  if (!requestedKey) return true;
  return driverVehicleTypeKey(profile) === requestedKey;
}

const TYPE_LABELS = { basic: "Basic", als: "Advanced Life Support", icu: "ICU" };
function ambulanceTypeLabel(key) {
  return TYPE_LABELS[key] || "ambulance";
}

module.exports = {
  normalizeAmbulanceTypeKey, requestedAmbulanceTypeKey,
  driverVehicleTypeKey, driverMatchesRequestedType, ambulanceTypeLabel,
};
