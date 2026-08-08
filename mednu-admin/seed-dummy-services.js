// ============================================
//  MEDNU ADMIN — DUMMY SERVICES SEED SCRIPT
// ============================================
// HOW TO RUN:
//   1. Open the MedNu Admin panel in your browser and make sure you're
//      logged in (so Firestore write rules pass).
//   2. Open DevTools (F12) → Console tab.
//   3. Paste this whole script and press Enter.
//   4. It inserts 2 dummy services into each currently-empty category.
//      All dummy docs are named starting with "[TEST] " and have
//      isEnabled:false so they won't show up to real customers, but
//      will show counts/cards in this admin dashboard.
//   5. To remove them later, run: window.__removeDummyServices()
// ============================================

(async function seedDummyServices() {
  if (typeof db === 'undefined') {
    console.error('Firestore `db` not found — run this on the MedNu Admin page, not elsewhere.');
    return;
  }

  const dummyByCategory = {
    diagnostics: [
      { name: '[TEST] Full Body Checkup',       price: 1499, priceUnit: 'per_session', duration: '90 min', description: 'Comprehensive diagnostic panel including blood work and vitals.' },
      { name: '[TEST] X-Ray (Chest)',            price: 499,  priceUnit: 'per_session', duration: '20 min', description: 'Single-view chest X-ray at home or clinic.' },
    ],
    physiotherapy: [
      { name: '[TEST] Home Physiotherapy Session', price: 899, priceUnit: 'per_session', duration: '45 min', description: 'One-on-one physiotherapy visit at your home.' },
      { name: '[TEST] Post-Surgery Rehab Package',  price: 6999, priceUnit: 'per_package', duration: '10 sessions', description: 'Structured rehab plan after orthopedic surgery.' },
    ],
    care_assistant: [
      { name: '[TEST] 12-Hour Care Assistant', price: 1200, priceUnit: 'per_day', duration: '12 hrs', description: 'Trained care assistant for daily living support.' },
      { name: '[TEST] 24-Hour Care Assistant', price: 2200, priceUnit: 'per_day', duration: '24 hrs', description: 'Round-the-clock care assistant support.' },
    ],
    caregivers: [
      { name: '[TEST] Elderly Care Companion', price: 999, priceUnit: 'per_day', duration: '8 hrs', description: 'Companionship and daily support for elderly patients.' },
      { name: '[TEST] Post-Hospitalization Caregiver', price: 1499, priceUnit: 'per_day', duration: '12 hrs', description: 'Dedicated caregiver for recovery after hospital discharge.' },
    ],
    equipment: [
      { name: '[TEST] Wheelchair (Standard)', price: 99, priceUnit: 'per_day', duration: null, description: 'Standard foldable wheelchair rental.', purchasePrice: 4999, deposit: 1000 },
      { name: '[TEST] Hospital Bed (Electric)', price: 299, priceUnit: 'per_day', duration: null, description: 'Electric adjustable hospital bed rental.', purchasePrice: 24999, deposit: 3000 },
    ],
    consultation: [
      { name: '[TEST] General Physician Consult', price: 499, priceUnit: 'per_session', duration: '20 min', description: 'Video consultation with a general physician.' },
      { name: '[TEST] Specialist Consult',        price: 899, priceUnit: 'per_session', duration: '30 min', description: 'Video consultation with a specialist doctor.' },
    ],
    nutrition: [
      { name: '[TEST] Diet Consultation',      price: 599,  priceUnit: 'per_session', duration: '30 min', description: 'Personalized diet plan consultation with a nutritionist.' },
      { name: '[TEST] Monthly Nutrition Plan', price: 2999, priceUnit: 'per_package', duration: '1 month', description: 'Ongoing nutrition coaching with weekly check-ins.' },
    ],
    counselling: [
      { name: '[TEST] Individual Therapy Session', price: 999, priceUnit: 'per_session', duration: '50 min', description: 'One-on-one counselling session with a licensed therapist.' },
      { name: '[TEST] Couples Counselling',        price: 1499, priceUnit: 'per_session', duration: '60 min', description: 'Joint counselling session for couples.' },
    ],
    medicine_delivery: [
      { name: '[TEST] Same-Day Medicine Delivery', price: 49,  priceUnit: 'per_order', duration: 'Same day', description: 'Fast delivery of prescribed medicines.' },
      { name: '[TEST] Monthly Medicine Subscription', price: 299, priceUnit: 'per_month', duration: 'Monthly', description: 'Recurring monthly delivery of chronic-care medicines.' },
    ],
  };

  const batch = db.batch();
  const createdRefs = [];
  let count = 0;

  Object.entries(dummyByCategory).forEach(([type, services]) => {
    services.forEach(svc => {
      const ref = db.collection('services').doc();
      createdRefs.push(ref.id);
      batch.set(ref, {
        name: svc.name,
        type,
        price: svc.price ?? null,
        priceUnit: svc.priceUnit || 'per_session',
        duration: svc.duration || null,
        description: svc.description || null,
        deposit: svc.deposit ?? null,
        purchasePrice: svc.purchasePrice ?? null,
        imageUrl: '',
        storagePath: '',
        isEnabled: false,
        isFeatured: false,
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedBy: (auth.currentUser && auth.currentUser.email) || 'admin-seed-script',
      });
      count++;
    });
  });

  await batch.commit();
  console.log(`✓ Seeded ${count} dummy services across ${Object.keys(dummyByCategory).length} categories.`);
  console.log('Doc IDs:', createdRefs);

  window.__dummyServiceIds = createdRefs;
  window.__removeDummyServices = async function () {
    const ids = window.__dummyServiceIds || [];
    if (!ids.length) { console.log('No dummy service IDs tracked in this session.'); return; }
    const delBatch = db.batch();
    ids.forEach(id => delBatch.delete(db.collection('services').doc(id)));
    await delBatch.commit();
    console.log(`✓ Removed ${ids.length} dummy services.`);
  };
})();
