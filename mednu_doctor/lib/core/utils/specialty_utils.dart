/// Single source of truth for "is this a dental specialty?".
///
/// Matching rule (case-insensitive, on the trimmed string): a word that starts
/// with `dental`, `dentist` or `dentistry` (word boundary at the start, so
/// "Resident"/"President" never match), or a word starting with
/// `orthodont`, `endodont`, `periodont` or `prosthodont`.
/// The admin panel (mednu-admin/js/app.js `isDentalSpecialty`) uses the
/// identical regex - keep both in sync.
final RegExp _dentalRe = RegExp(
    r'\b(dental|dentist|dentistry|orthodont|endodont|periodont|prosthodont)',
    caseSensitive: false);

bool isDentalSpecialty(String? specialty) =>
    specialty != null && _dentalRe.hasMatch(specialty.trim());

/// Document labels for the doctor document keys, switching to the dental set
/// when [dental] is true. Storage keys never change.
Map<String, String> doctorDocLabels({required bool dental}) => dental
    ? const {
        'mbbs_degree': 'BDS Degree',
        'spec_cert': 'MDS Degree',
        'mbbs_reg_cert': 'State Dental Council Registration',
        'state_reg_cert_2': 'State Dental Council Registration 2',
        'state_reg_cert_3': 'State Dental Council Registration 3',
        'national_reg_cert': 'Dental Council of India (DCI) Registration',
        'renewal_cert': 'Renewal Certificate',
        'other_cert': 'Other Certificates',
        'resume': 'Resume',
        'profile_photo': 'Profile Photo',
      }
    : const {
        'mbbs_degree': 'UG Degree',
        'spec_cert': 'PG Degree',
        'mbbs_reg_cert': 'State Registration',
        'state_reg_cert_2': 'State Registration 2',
        'state_reg_cert_3': 'State Registration 3',
        'national_reg_cert': 'National Registration',
        'renewal_cert': 'Renewal Certificate',
        'other_cert': 'Other Certificate',
        'resume': 'Resume',
        'profile_photo': 'Profile Photo',
      };
