import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';

/// Shares a prescription summary as text using the system share sheet.
Future<void> sharePrescription(Map<String, dynamic> rx) async {
  final doctor    = rx['doctorName']      as String? ?? 'Doctor';
  final specialty = rx['doctorSpecialty'] as String? ?? '';
  final diagnosis = rx['diagnosis']       as String? ?? '';
  final medicines = (rx['medicines'] as List? ?? [])
      .map((m) {
        final name = m['medicineName'] as String?
            ?? m['name'] as String? ?? '';
        final dosage = m['dosage'] as String? ?? '';
        final freq   = m['frequency'] as String? ?? '';
        return '$name — $dosage, $freq';
      })
      .join('\n');

  final text = '''
MedNU Prescription
Doctor: $doctor${specialty.isNotEmpty ? ' ($specialty)' : ''}
Diagnosis: $diagnosis
${medicines.isNotEmpty ? 'Medicines:\n$medicines' : ''}

Shared via MedNU App'''.trim();

  await Share.share(text, subject: 'Prescription from $doctor');
}

// ── Prescription data shape ──────────────────────────────────────────────────
//
// New format (written by updated doctor app):
// {
//   rxId, doctorId, doctorName, doctorSpecialty, doctorRegNo, doctorHospital,
//   patientId, patientName, patientAge, patientGender,
//   chiefComplaints, history, examination,
//   investigations: [String],
//   diagnosis,
//   medicines: [{serialNo, medicineName, strength, morning, afternoon, night,
//               foodTiming, duration, instruction, name, dosage, frequency, timing}],
//   specialInstructions, additionalNotes,
//   followUpRequired, followUpDays,
//   createdAt, status,
// }
//
// Legacy format (older prescriptions):
// { advice: [String], historyComorbidities: String, medicines: [{name, dosage, frequency, duration, timing}] }

class PrescriptionViewerScreen extends StatefulWidget {
  final Map<String, dynamic>? data;
  const PrescriptionViewerScreen({super.key, this.data});

  @override
  State<PrescriptionViewerScreen> createState() =>
      _PrescriptionViewerScreenState();
}

class _PrescriptionViewerScreenState
    extends State<PrescriptionViewerScreen> {
  bool _pdfBusy = false;

  // ── Data accessors ───────────────────────────────────────────────────────

  Map<String, dynamic> get _d => widget.data ?? {};

  String get _doctorName    => _d['doctorName']      as String? ?? 'Doctor';
  String get _specialty     => _d['doctorSpecialty'] as String? ?? '';
  String get _regNo         => _d['doctorRegNo']     as String? ?? '';
  String get _hospital      => _d['doctorHospital']  as String? ?? '';
  String get _patientName   => _d['patientName']     as String? ?? 'Patient';
  String get _patientAge    => _d['patientAge']      as String? ?? '--';
  String get _patientGender => _d['patientGender']   as String? ?? '--';
  String get _patientPhone  => _d['patientPhone']    as String? ?? '';
  String get _diagnosis     => _d['diagnosis']       as String? ?? '';
  String get _rxId          =>
      _d['rxId'] as String? ?? _d['id'] as String? ?? 'RX-0000';
  String get _signatureUrl  => _d['doctorSignatureUrl'] as String? ?? '';

  // New fields with legacy fallbacks
  String get _chiefComplaints    => _d['chiefComplaints']    as String? ?? '';
  String get _history            =>
      _d['history'] as String?
          ?? _d['historyComorbidities'] as String? ?? '';
  String get _examination        => _d['examination']        as String? ?? '';
  String get _specialInstructions => _d['specialInstructions'] as String? ?? '';
  String get _additionalNotes    => _d['additionalNotes']    as String? ?? '';

  List<String> get _investigations {
    final raw = _d['investigations'];
    if (raw == null) return [];
    return (raw as List).map((e) => e.toString()).toList();
  }

  bool get _followUpRequired =>
      _d['followUpRequired'] as bool? ?? false;
  int  get _followUpDays     =>
      (_d['followUpDays'] as num?)?.toInt() ?? 7;

  String get _dateStr {
    final ts = _d['createdAt'];
    if (ts == null) return DateFormat('d MMM yyyy').format(DateTime.now());
    if (ts is Timestamp) {
      return DateFormat('d MMM yyyy  hh:mm a').format(ts.toDate());
    }
    return DateFormat('d MMM yyyy').format(DateTime.now());
  }

  List<Map<String, dynamic>> get _medicines {
    final raw = _d['medicines'];
    if (raw == null) return [];
    return (raw as List)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  // Legacy advice / new special instructions merged
  List<String> get _adviceLines {
    final legacy = _d['advice'];
    if (legacy != null && (legacy as List).isNotEmpty) {
      return legacy.map((e) => e.toString()).toList();
    }
    if (_specialInstructions.isNotEmpty) {
      return _specialInstructions
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }
    return [];
  }

  String _medicineName(Map<String, dynamic> m) =>
      (m['medicineName'] as String?
              ?? m['name'] as String? ?? '')
          .toUpperCase();

  // ── Signature bytes ──────────────────────────────────────────────────────

  Future<Uint8List?> _fetchSignatureBytes() async {
    final url = _signatureUrl;
    if (url.isEmpty) return null;
    try {
      final response = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  // ── PDF ──────────────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdf() async {
    final sigBytes = await _fetchSignatureBytes();
    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 30),
      header: (ctx) => _pdfHeader(),
      footer: (ctx) => _pdfFooter(ctx),
      build: (ctx) => [
        pw.SizedBox(height: 10),
        _pdfDoctorPatientRow(),
        pw.SizedBox(height: 10),
        if (_chiefComplaints.isNotEmpty) ...[
          _pdfSectionBox(
            label: 'Chief Complaints',
            content: _chiefComplaints,
            bg: PdfColors.red50,
            border: PdfColors.red200,
            labelColor: PdfColors.red800,
          ),
          pw.SizedBox(height: 10),
        ],
        if (_history.isNotEmpty) ...[
          _pdfSectionBox(
            label: 'History & Comorbidities',
            content: _history,
            bg: PdfColors.purple50,
            border: PdfColors.purple200,
            labelColor: PdfColors.purple800,
          ),
          pw.SizedBox(height: 10),
        ],
        if (_examination.isNotEmpty) ...[
          _pdfSectionBox(
            label: 'Examination / Vitals',
            content: _examination,
            bg: PdfColors.blue50,
            border: PdfColors.blue200,
            labelColor: PdfColors.blue800,
          ),
          pw.SizedBox(height: 10),
        ],
        if (_investigations.isNotEmpty) ...[
          _pdfInvestigations(),
          pw.SizedBox(height: 10),
        ],
        _pdfDiagnosis(),
        pw.SizedBox(height: 12),
        _pdfRxMedicines(),
        pw.SizedBox(height: 10),
        if (_adviceLines.isNotEmpty) ...[
          _pdfSpecialInstructions(),
          pw.SizedBox(height: 10),
        ],
        if (_additionalNotes.isNotEmpty) ...[
          _pdfSectionBox(
            label: 'Additional Notes',
            content: _additionalNotes,
            bg: PdfColors.grey50,
            border: PdfColors.grey300,
            labelColor: PdfColors.grey700,
          ),
          pw.SizedBox(height: 10),
        ],
        if (_followUpRequired) ...[
          _pdfFollowUp(),
          pw.SizedBox(height: 10),
        ],
        pw.SizedBox(height: 6),
        _pdfSignature(sigBytes),
      ],
    ));

    return doc.save();
  }

  pw.Widget _pdfHeader() => pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFC2185B)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              pw.Text('MedNU Healthcare',
                  style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold)),
              if (_hospital.isNotEmpty)
                pw.Text(_hospital,
                    style: const pw.TextStyle(
                        color: PdfColors.grey200, fontSize: 10)),
              pw.Text('Digital Prescription',
                  style: const pw.TextStyle(
                      color: PdfColors.grey200, fontSize: 11)),
            ]),
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
              pw.Text('Rx  $_rxId',
                  style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 13)),
              pw.Text('Date: $_dateStr',
                  style: const pw.TextStyle(
                      color: PdfColors.grey200, fontSize: 9)),
            ]),
          ],
        ),
      );

  pw.Widget _pdfFooter(pw.Context ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}  |  Generated by MedNU — $_rxId',
          style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 8),
        ),
      );

  pw.Widget _pdfDoctorPatientRow() => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
              child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(6))),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              pw.Text('Doctor Details',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                      color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text('Dr. $_doctorName',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text(_specialty,
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey700)),
              pw.Text('Reg. No: $_regNo',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
              if (_hospital.isNotEmpty)
                pw.Text(_hospital,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
            ]),
          )),
          pw.SizedBox(width: 10),
          pw.Expanded(
              child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(6))),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              pw.Text('Patient Details',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                      color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(_patientName,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 13)),
              pw.Text(
                  'Age: $_patientAge  |  Gender: $_patientGender',
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey700)),
              if (_patientPhone.isNotEmpty)
                pw.Text('Phone: $_patientPhone',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey600)),
            ]),
          )),
        ],
      );

  pw.Widget _pdfSectionBox({
    required String   label,
    required String   content,
    required PdfColor bg,
    required PdfColor border,
    required PdfColor labelColor,
  }) =>
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: bg,
          border: pw.Border.all(color: border),
          borderRadius:
              const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: labelColor)),
          pw.SizedBox(height: 4),
          pw.Text(content,
              style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey800,
                  lineSpacing: 3)),
        ]),
      );

  pw.Widget _pdfInvestigations() => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.teal50,
          border: pw.Border.all(color: PdfColors.teal200),
          borderRadius:
              const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
          pw.Text('Suggested Investigations',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: PdfColors.teal800)),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _investigations
                .map((inv) => pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border:
                            pw.Border.all(color: PdfColors.teal300),
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(4)),
                      ),
                      child: pw.Text(inv,
                          style: pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.teal800,
                              fontWeight: pw.FontWeight.bold)),
                    ))
                .toList(),
          ),
        ]),
      );

  pw.Widget _pdfDiagnosis() => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.green50,
          border: pw.Border.all(color: PdfColors.green300, width: 1.5),
          borderRadius:
              const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
          pw.Text('DIAGNOSIS',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: PdfColors.green800,
                  letterSpacing: 1.2)),
          pw.SizedBox(height: 5),
          pw.Text(_diagnosis,
              style: pw.TextStyle(
                  fontSize: 13,
                  color: PdfColors.green900,
                  fontWeight: pw.FontWeight.bold,
                  lineSpacing: 3)),
        ]),
      );

  pw.Widget _pdfRxMedicines() {
    if (_medicines.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        child: pw.Text('No medicines prescribed.',
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey600)),
      );
    }

    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
      pw.Row(children: [
        pw.Text('Rx',
            style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.pink800,
                fontStyle: pw.FontStyle.italic)),
        pw.SizedBox(width: 8),
        pw.Text('Prescribed Medicines',
            style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, fontSize: 14)),
      ]),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(20),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(1.5),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(1.5),
          5: const pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFC2185B)),
            children: [
              '#', 'MEDICINE', 'STRENGTH', 'DOSE', 'DURATION', 'FOOD'
            ]
                .map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 5, vertical: 5),
                      child: pw.Text(h,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 8,
                              color: PdfColors.white)),
                    ))
                .toList(),
          ),
          ..._medicines.asMap().entries.map((e) {
            final m     = e.value;
            final name  = _medicineName(m);
            final strength = m['strength'] as String? ?? m['dosage'] as String? ?? '';
            final morn  = m['morning']   as bool? ?? false;
            final aft   = m['afternoon'] as bool? ?? false;
            final night = m['night']     as bool? ?? false;
            final freq  = m['frequency'] as String? ?? '';
            final doseStr = [
              if (morn)  'M',
              if (aft)   'A',
              if (night) 'N',
            ].join('-');
            final finalDose = doseStr.isNotEmpty ? doseStr : freq;
            final duration  = m['duration']   as String? ?? '';
            final food      = m['foodTiming'] as String? ?? m['timing'] as String? ?? '';
            final isEven = e.key % 2 == 1;

            return pw.TableRow(
              decoration: pw.BoxDecoration(
                  color: isEven ? PdfColors.grey50 : PdfColors.white),
              children: [
                _pdfMedCell('${e.key + 1}', bold: true),
                _pdfMedCell(name, bold: true),
                _pdfMedCell(strength),
                _pdfMedCell(finalDose),
                _pdfMedCell(duration),
                _pdfMedCell(food),
              ],
            );
          }),
        ],
      ),
    ]);
  }

  pw.Widget _pdfMedCell(String t, {bool bold = false}) => pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  pw.Widget _pdfSpecialInstructions() => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.orange300, width: 1.5),
          borderRadius:
              const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
          pw.Text('Special Instructions',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                  color: PdfColors.orange800)),
          pw.SizedBox(height: 6),
          ..._adviceLines.map((a) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                  pw.Text('• ',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.orange700)),
                  pw.Expanded(
                      child: pw.Text(a,
                          style: const pw.TextStyle(
                              fontSize: 10, lineSpacing: 2))),
                ]),
              )),
        ]),
      );

  pw.Widget _pdfFollowUp() => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.orange50,
          border: pw.Border.all(color: PdfColors.orange300),
          borderRadius:
              const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Row(children: [
          pw.Text('Follow-up Required: ',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: PdfColors.orange800)),
          pw.Text('Please visit after $_followUpDays days',
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey800)),
        ]),
      );

  pw.Widget _pdfSignature(Uint8List? sigBytes) {
    final sigImage =
        sigBytes != null ? pw.MemoryImage(sigBytes) : null;

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Digitally Signed By',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 6),
          if (sigImage != null)
            pw.Container(
              height: 60,
              width: 200,
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(color: PdfColors.grey200),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Image(sigImage, fit: pw.BoxFit.contain),
            )
          else
            pw.Text('Dr. $_doctorName',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                    fontStyle: pw.FontStyle.italic)),
          pw.SizedBox(height: 6),
          pw.Text('Dr. $_doctorName',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.Text('$_specialty  •  Reg: $_regNo',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                border: pw.Border.all(color: PdfColors.green300),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text('DIGITALLY SIGNED & VERIFIED by MedNU',
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green800)),
            ),
            pw.Spacer(),
            pw.Text('Rx: $_rxId',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey500)),
          ]),
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<File> _savePdfToTemp() async {
    final bytes = await _buildPdf();
    final dir   = await getTemporaryDirectory();
    final file  = File('${dir.path}/prescription_$_rxId.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _handleShare() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final file = await _savePdfToTemp();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Prescription from $_doctorName',
        text: 'Prescription issued on $_dateStr by Dr. $_doctorName',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to share: $e')));
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _handleDownload() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes    = await _buildPdf();
      final dir      = await getApplicationDocumentsDirectory();
      final filename = 'MedNu_Rx_$_rxId.pdf';
      final file     = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved as $filename'),
          action: SnackBarAction(label: 'Share', onPressed: _handleShare),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Prescription',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontSize: 18,
            )),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_pdfBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Download PDF',
              onPressed: _handleDownload,
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded, color: Colors.white),
              tooltip: 'Share',
              onPressed: _handleShare,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Premium Header ──────────────────────────────────
            _buildHeaderCard(),
            const SizedBox(height: 16),

            // ── Patient Details ─────────────────────────────────
            _buildPatientCard(),
            const SizedBox(height: 16),

            // ── Chief Complaints ────────────────────────────────
            if (_chiefComplaints.isNotEmpty) ...[
              _buildSectionCard(
                icon: Icons.sick_rounded,
                iconColor: const Color(0xFFE53935),
                title: 'Chief Complaints',
                child: _buildContentBox(
                    _chiefComplaints, const Color(0xFFE53935)),
              ),
              const SizedBox(height: 16),
            ],

            // ── History & Comorbidities ─────────────────────────
            if (_history.isNotEmpty) ...[
              _buildSectionCard(
                icon: Icons.history_edu_rounded,
                iconColor: const Color(0xFF7B1FA2),
                title: 'History & Comorbidities',
                child: _buildContentBox(
                    _history, const Color(0xFF7B1FA2)),
              ),
              const SizedBox(height: 16),
            ],

            // ── Examination ─────────────────────────────────────
            if (_examination.isNotEmpty) ...[
              _buildSectionCard(
                icon: Icons.monitor_heart_rounded,
                iconColor: const Color(0xFF1565C0),
                title: 'Examination / Vitals',
                child: _buildVitalsBox(_examination),
              ),
              const SizedBox(height: 16),
            ],

            // ── Investigations ──────────────────────────────────
            if (_investigations.isNotEmpty) ...[
              _buildSectionCard(
                icon: Icons.biotech_rounded,
                iconColor: const Color(0xFF00838F),
                title: 'Suggested Investigations',
                child: _buildInvestigationsChips(),
              ),
              const SizedBox(height: 16),
            ],

            // ── Diagnosis ───────────────────────────────────────
            _buildDiagnosisCard(),
            const SizedBox(height: 16),

            // ── Rx Medicines ────────────────────────────────────
            _buildMedicinesCard(),
            const SizedBox(height: 16),

            // ── Special Instructions ────────────────────────────
            if (_adviceLines.isNotEmpty) ...[
              _buildSectionCard(
                icon: Icons.lightbulb_rounded,
                iconColor: const Color(0xFFF57F17),
                title: 'Special Instructions',
                child: _buildAdviceList(),
              ),
              const SizedBox(height: 16),
            ],

            // ── Additional Notes ────────────────────────────────
            if (_additionalNotes.isNotEmpty) ...[
              _buildSectionCard(
                icon: Icons.notes_rounded,
                iconColor: context.appTextSecondary,
                title: 'Additional Notes',
                child: _buildContentBox(
                    _additionalNotes, context.appTextSecondary),
              ),
              const SizedBox(height: 16),
            ],

            // ── Follow-up ───────────────────────────────────────
            if (_followUpRequired) ...[
              _buildFollowUpCard(),
              const SizedBox(height: 16),
            ],

            // ── Doctor Signature ────────────────────────────────
            _buildSignatureCard(),
            const SizedBox(height: 16),

            // ── Action Buttons ──────────────────────────────────
            _buildActionButtons(context),
            const SizedBox(height: 12),

            // ── Refill Reminder ─────────────────────────────────
            _buildRefillReminderButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildRefillReminderButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7B1FA2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        icon: const Icon(Icons.notification_add_rounded, size: 18),
        label: const Text(
          'Set Refill Reminder',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now().add(const Duration(days: 7)),
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF7B1FA2),
                ),
              ),
              child: child!,
            ),
          );
          if (picked != null && context.mounted) {
            final formatted =
                DateFormat('d MMM yyyy').format(picked);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Reminder set for $formatted'),
                backgroundColor: const Color(0xFF7B1FA2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    );
  }

  // ── Card builders ─────────────────────────────────────────────────────────

  Widget _buildHeaderCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle),
              child: const Icon(Icons.local_hospital_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('MedNU Healthcare',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    )),
                if (_hospital.isNotEmpty)
                  Text(_hospital,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: Colors.white70,
                      )),
                const Text('Digital Prescription',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white70,
                    )),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('VERIFIED',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
            ),
          ]),
          const Divider(color: Colors.white24, height: 22),
          Row(children: [
            Expanded(
                child: _PrescriptionInfoChip('Doctor',
                    'Dr. $_doctorName')),
            Expanded(
                child: _PrescriptionInfoChip(
                    'Specialty', _specialty.isNotEmpty ? _specialty : '--')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _PrescriptionInfoChip('Date', _dateStr)),
            Expanded(
                child: _PrescriptionInfoChip('Rx ID', _rxId)),
          ]),
        ]),
      );

  Widget _buildPatientCard() => _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Patient Details', style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _DetailItem('Name', _patientName)),
            Expanded(child: _DetailItem('Age', _patientAge)),
          ]),
          const SizedBox(height: 8),
          _DetailItem('Gender', _patientGender),
          if (_patientPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailItem('Phone', _patientPhone),
          ],
        ]),
      );

  Widget _buildSectionCard({
    required IconData icon,
    required Color    iconColor,
    required String   title,
    required Widget   child,
  }) =>
      _card(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title, style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _buildContentBox(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Text(text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: context.appTextSecondary,
              height: 1.55,
            )),
      );

  Widget _buildVitalsBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1565C0).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFF1565C0).withValues(alpha: 0.15)),
        ),
        child: Text(text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: context.appTextSecondary,
              height: 1.7,
            )),
      );

  Widget _buildInvestigationsChips() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _investigations
            .map((inv) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00838F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF00838F)
                            .withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.science_outlined,
                        size: 13, color: Color(0xFF00838F)),
                    const SizedBox(width: 5),
                    Text(inv,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00838F),
                        )),
                  ]),
                ))
            .toList(),
      );

  Widget _buildDiagnosisCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF2E7D32).withValues(alpha: 0.08),
              const Color(0xFF2E7D32).withValues(alpha: 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
              width: 1.5),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.medical_information_rounded,
                  color: Color(0xFF2E7D32), size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Diagnosis',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2E7D32),
                )),
          ]),
          const SizedBox(height: 12),
          Text(_diagnosis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.appTextPrimary,
                height: 1.5,
              )),
        ]),
      );

  Widget _buildMedicinesCard() {
    final medColors = [
      const Color(0xFFC2185B),
      const Color(0xFF1565C0),
      const Color(0xFF2E7D32),
      const Color(0xFF7B1FA2),
      const Color(0xFF00838F),
    ];

    return _card(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          // Rx mark
          const Text('Rx',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: AppColors.primary,
              )),
          const SizedBox(width: 10),
          Text('Prescribed Medicines', style: AppTextStyles.h4),
          const Spacer(),
          if (_medicines.isNotEmpty)
            GestureDetector(
              onTap: () =>
                  context.push(AppRoutes.medicine, extra: _medicines),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Icon(Icons.shopping_cart_rounded,
                      size: 13, color: Colors.white),
                  SizedBox(width: 5),
                  Text('Order All',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      )),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        if (_medicines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No medicines prescribed.',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: context.appTextHint)),
          ),
        ..._medicines.asMap().entries.map((e) {
          final m     = e.value;
          final color = medColors[e.key % medColors.length];
          final name  = _medicineName(m);
          final strength  = m['strength']   as String? ?? '';
          final morning   = m['morning']   as bool? ?? false;
          final afternoon = m['afternoon'] as bool? ?? false;
          final night     = m['night']     as bool? ?? false;
          final foodTiming = m['foodTiming'] as String?
              ?? m['timing'] as String? ?? '';
          final duration  = m['duration']   as String? ?? '';
          final instruction = m['instruction'] as String? ?? '';
          final hasDose = morning || afternoon || night;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: color.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.07),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13)),
                ),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                    child: Center(
                      child: Text('${e.key + 1}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          )),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: color,
                          )),
                      if (strength.isNotEmpty)
                        Text(strength,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: context.appTextSecondary,
                            )),
                    ]),
                  ),
                  const Icon(Icons.medication_rounded,
                      size: 20, color: Colors.white60),
                ]),
              ),

              // Dosage chips
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (hasDose || foodTiming.isNotEmpty || duration.isNotEmpty)
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (morning)
                        _DoseChip(Icons.wb_sunny_outlined,
                            'Morning', const Color(0xFFFF9800)),
                      if (afternoon)
                        _DoseChip(Icons.wb_twilight_rounded,
                            'Afternoon', const Color(0xFFF44336)),
                      if (night)
                        _DoseChip(Icons.nights_stay_outlined,
                            'Night', const Color(0xFF5C6BC0)),
                      if (!hasDose) ...[
                        // Legacy format chips
                        if ((m['frequency'] as String? ?? '').isNotEmpty)
                          _MedChip(m['frequency'] as String, color),
                        if ((m['dosage'] as String? ?? '').isNotEmpty)
                          _MedChip(m['dosage'] as String, color),
                      ],
                      if (foodTiming.isNotEmpty)
                        _MedChip(foodTiming, AppColors.accent),
                      if (duration.isNotEmpty)
                        _MedChip(duration, const Color(0xFF7B1FA2)),
                    ]),
                  if (instruction.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(instruction,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: context.appTextSecondary,
                          fontStyle: FontStyle.italic,
                        )),
                  ],
                ]),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildAdviceList() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _adviceLines
            .map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF57F17),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(a,
                            style: AppTextStyles.bodyMedium
                                .copyWith(height: 1.5))),
                  ]),
                ))
            .toList(),
      );

  Widget _buildFollowUpCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.4),
              width: 1.5),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE0B2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event_repeat_rounded,
                color: Color(0xFFE65100), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Follow-up Required',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE65100),
                  )),
              Text(
                  'Please schedule a follow-up in $_followUpDays days.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: context.appTextSecondary,
                    height: 1.4,
                  )),
            ]),
          ),
        ]),
      );

  Widget _buildSignatureCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Digitally Signed By',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: context.appTextHint,
                )),
            const SizedBox(height: 10),
            // Actual handwritten signature image
            if (_signatureUrl.isNotEmpty)
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.network(
                    _signatureUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(Icons.draw_rounded,
                          color: context.appTextHint, size: 28),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text('Dr. $_doctorName',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                )),
            Text(
                '$_specialty${_regNo.isNotEmpty ? '  •  Reg. No: $_regNo' : ''}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: context.appTextSecondary,
                )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_rounded,
                    color: AppColors.accent, size: 16),
                SizedBox(width: 6),
                Text('Digitally Signed & Verified by MedNU',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    )),
              ]),
            ),
          ],
        ),
      );


  Widget _buildActionButtons(BuildContext context) => Column(children: [
        // Download + Share row
        Row(children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.download_rounded,
              label: 'Download PDF',
              color: AppColors.primary,
              onTap: _handleDownload,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.share_rounded,
              label: 'Share PDF',
              color: const Color(0xFF1565C0),
              onTap: _handleShare,
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // Book Follow-up + Order Medicines row
        Row(children: [
          if (_followUpRequired)
            Expanded(
              child: _ActionButton(
                icon: Icons.event_rounded,
                label: 'Book Follow-up',
                color: const Color(0xFFE65100),
                onTap: () => context.push(AppRoutes.consultation),
              ),
            ),
          if (_followUpRequired) const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.shopping_cart_rounded,
              label: 'Order Medicines',
              color: const Color(0xFF2E7D32),
              onTap: () =>
                  context.push(AppRoutes.medicine, extra: _medicines),
            ),
          ),
        ]),
        const SizedBox(height: 12),

        // Book Lab Tests
        if (_investigations.isNotEmpty)
          _ActionButton(
            icon: Icons.science_rounded,
            label: 'Book Lab Tests',
            color: const Color(0xFF00838F),
            onTap: () => context.push(AppRoutes.diagnostics),
            fullWidth: true,
          ),
      ]);

  // ── Shared card wrapper ───────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.appBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _PrescriptionInfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _PrescriptionInfoChip(this.label, this.value);

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 10, color: Colors.white60)),
        Text(value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis),
      ]);
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  const _DetailItem(this.label, this.value);

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.caption),
        Text(value, style: AppTextStyles.labelMedium),
      ]);
}

class _DoseChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _DoseChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              )),
        ]),
      );
}

class _MedChip extends StatelessWidget {
  final String label;
  final Color  color;
  const _MedChip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            )),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  final bool     fullWidth;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  )),
            ],
          ),
        ),
      );
}
