// ============================================
//  MEDNU ADMIN — DUMMY CAREGIVERS SEED SCRIPT
// ============================================
// HOW TO RUN:
//   1. Open the MedNu Admin panel in your browser, logged in.
//   2. Open DevTools (F12) → Console tab.
//   3. Paste this whole script and press Enter.
//   4. It inserts a few [TEST] caregivers into the `caregivers` collection
//      with isActive:true so you can confirm the Caregivers screen in the
//      consumer app actually renders them.
//   5. IMPORTANT: these ARE visible to real users while active. Once you've
//      confirmed the screen works, run window.__removeDummyCaregivers()
//      in the same console session to delete them.
// ============================================

(async function seedDummyCaregivers() {
  if (typeof db === 'undefined') {
    console.error('Firestore `db` not found — run this on the MedNu Admin page, not elsewhere.');
    return;
  }

  const dummyCaregivers = [
    { name: '[TEST] Anita Sharma', type: 'Nurse', gender: 'Female', location: 'Bengaluru', specialty: 'Post-operative care', experience: '5 years', ratePerDay: 1200, rateUnit: 'per_day', rating: 4.7, phone: '9999900001', bio: 'Experienced nurse specializing in post-operative and elderly care.' },
    { name: '[TEST] Ramesh Kumar', type: 'Attendant', gender: 'Male', location: 'Bengaluru', specialty: 'Mobility assistance', experience: '3 years', ratePerDay: 900, rateUnit: 'per_day', rating: 4.5, phone: '9999900002', bio: 'Attendant with experience in mobility support and daily living assistance.' },
    { name: '[TEST] Priya Nair', type: 'Physiotherapist', gender: 'Female', location: 'Bengaluru', specialty: 'Orthopedic rehab', experience: '7 years', ratePerDay: 1500, rateUnit: 'per_day', rating: 4.9, phone: '9999900003', bio: 'Physiotherapist focused on orthopedic and neurological rehabilitation.' },
  ];

  const unitMap = { per_day: 'day', per_hour: 'hr', per_week: 'week', per_month: 'month' };
  const batch = db.batch();
  const createdRefs = [];

  dummyCaregivers.forEach(c => {
    const ref = db.collection('caregivers').doc();
    createdRefs.push(ref.id);
    batch.set(ref, {
      name: c.name,
      type: c.type,
      gender: c.gender,
      location: c.location,
      specialty: c.specialty || null,
      experience: c.experience || null,
      ratePerDay: c.ratePerDay,
      rateUnit: c.rateUnit || 'per_day',
      rate: `₹${c.ratePerDay.toLocaleString('en-IN')}/${unitMap[c.rateUnit] || 'day'}`,
      rating: c.rating ?? null,
      phone: c.phone || null,
      bio: c.bio || null,
      isActive: true,
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedBy: (auth.currentUser && auth.currentUser.email) || 'admin-seed-script',
    });
  });

  await batch.commit();
  console.log(`✓ Seeded ${createdRefs.length} dummy caregivers (isActive:true). Check the consumer app's Caregivers screen now.`);
  console.log('Doc IDs:', createdRefs);

  window.__dummyCaregiverIds = createdRefs;
  window.__removeDummyCaregivers = async function () {
    const ids = window.__dummyCaregiverIds || [];
    if (!ids.length) { console.log('No dummy caregiver IDs tracked in this session.'); return; }
    const delBatch = db.batch();
    ids.forEach(id => delBatch.delete(db.collection('caregivers').doc(id)));
    await delBatch.commit();
    console.log(`✓ Removed ${ids.length} dummy caregivers.`);
  };
})();
