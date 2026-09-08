/// True if a `doctors/{uid}` doc represents an actual Doctor account, not a
/// partner role (Lab, Pharmacy, Ambulance, Caregiver, Physiotherapist,
/// Counsellor, Nutritionist, Hospital) whose sparse `doctors/{uid}`
/// base-identity doc happens to also live in this same collection — see
/// `partner_role_register_screen.dart` (mednu_doctor), which explicitly
/// documents this as "the universal base identity document every role in
/// this app shares".
///
/// Without this filter, every `doctors` collection query in the patient app
/// (Find Doctors, home screen carousels, specialities, Quick Connect, global
/// search, ...) also matched Lab/Pharmacy/etc. accounts by name — a Lab
/// partner showed up in doctor listings and search results tagged as a
/// doctor, since a partner's base-identity doc has no field distinguishing
/// it other than `roles`.
///
/// A doc reads as an actual doctor iff `roles` is absent/empty (legacy
/// doctor-only accounts predating the `roles` field) or explicitly contains
/// 'doctor' — mirrors mednu_doctor's own `AppRoleX.listFrom` default, and the
/// identical fix already applied to mednu-admin's doctors listeners (see
/// app.js's `initOverviewRealtime` / `loadDoctorsRealtime`).
bool isDoctorAccount(Map<String, dynamic>? data) {
  final roles = data?['roles'];
  return roles is! List || roles.isEmpty || roles.contains('doctor');
}
