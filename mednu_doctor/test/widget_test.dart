import 'package:flutter_test/flutter_test.dart';
import 'package:mednu_doctor/shared_core/documents/partner_document_models.dart';

Map<String, dynamic> _doc() => {'url': 'https://example.com/f.pdf'};

void main() {
  group('PartnerDocumentType.missingFor', () {
    test('null or non-map documents: every required label is missing', () {
      for (final role in [
        'lab', 'pharmacy', 'equipment', 'ambulance', 'caregiver',
        'care_assistant', 'counsellor', 'physiotherapist', 'nutritionist',
        'hospital',
      ]) {
        final required =
            PartnerDocumentType.forRole(role).where((t) => !t.optional).length;
        expect(PartnerDocumentType.missingFor(role, null).length, required,
            reason: role);
        expect(PartnerDocumentType.missingFor(role, 'junk').length, required,
            reason: role);
      }
    });

    test('care assistant needs only an ID', () {
      expect(PartnerDocumentType.missingFor('care_assistant', const {}),
          ['Government ID Proof']);
      expect(
          PartnerDocumentType.missingFor(
              'care_assistant', {'caregiver_id': _doc()}),
          isEmpty);
    });

    test('nurse: optional resume never blocks', () {
      final docs = {'certificates': _doc(), 'caregiver_id': _doc()};
      expect(PartnerDocumentType.missingFor('caregiver', docs), isEmpty);
    });

    test('entries without a url do not count as uploaded', () {
      expect(
          PartnerDocumentType.missingFor(
              'care_assistant', {'caregiver_id': {'url': ''}}),
          hasLength(1));
    });

    test('unknown role has no requirements', () {
      expect(PartnerDocumentType.missingFor('nope', null), isEmpty);
    });

    test('equipment shares the pharmacy checklist', () {
      expect(PartnerDocumentType.forRole('equipment'),
          PartnerDocumentType.forRole('pharmacy'));
    });
  });

  group('other documents', () {
    test('next free slot skips used keys and stops at the cap', () {
      expect(PartnerDocumentType.nextFreeOtherDocKey(const []), 'other_doc_1');
      expect(PartnerDocumentType.nextFreeOtherDocKey(['other_doc_1']),
          'other_doc_2');
      expect(
          PartnerDocumentType.nextFreeOtherDocKey(
              [for (var i = 1; i <= 5; i++) 'other_doc_$i']),
          isNull);
    });
  });
}
