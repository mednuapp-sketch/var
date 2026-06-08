import 'dart:io';
import 'dart:typed_data';
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
/// Called from home_screen.dart's _RecordsBodyState._sharePrescription.
Future<void> sharePrescription(Map<String, dynamic> rx) async {
  final doctor   = rx['doctorName']     as String? ?? 'Doctor';
  final specialty= rx['doctorSpecialty']as String? ?? '';
  final diagnosis= rx['diagnosis']      as String? ?? '';
  final medicines= (rx['medicines'] as List? ?? [])
      .map((m) {
        final name = m['name'] as String? ?? '';
        final dosage = m['dosage'] as String? ?? '';
        final freq   = m['frequency'] as String? ?? '';
        return '$name — $dosage, $freq';
      })
      .join('\n');

  final text = '''
MedNu Prescription
Doctor: $doctor${specialty.isNotEmpty ? ' ($specialty)' : ''}
Diagnosis: $diagnosis
${medicines.isNotEmpty ? 'Medicines:\n$medicines' : ''}

Shared via MedNu App'''.trim();

  await Share.share(text, subject: 'Prescription from $doctor');
}

// Prescription data is written by the MedNU Doctor app to the 'prescriptions'
// Firestore collection and streamed to this screen via GoRouter extra.
//
// Expected shape of [data]:
// {
//   doctorName: string, doctorSpecialty: string, doctorRegNo: string,
//   patientName: string, patientAge: string, patientGender: string, patientBloodGroup: string,
//   diagnosis: string,
//   medicines: [ { name, dosage, frequency, duration, timing } ],
//   advice: [ string ],
//   rxId: string,
//   createdAt: Timestamp,
// }

class PrescriptionViewerScreen extends StatefulWidget {
  final Map<String, dynamic>? data;
  const PrescriptionViewerScreen({super.key, this.data});

  @override
  State<PrescriptionViewerScreen> createState() => _PrescriptionViewerScreenState();
}

class _PrescriptionViewerScreenState extends State<PrescriptionViewerScreen> {
  bool _pdfBusy = false;

  // ── Data helpers ────────────────────────────────────────────────────────────

  Map<String, dynamic> get _d => widget.data ?? {};

  String get _doctorName    => _d['doctorName']    as String? ?? 'Dr. Priya Sharma';
  String get _specialty     => _d['doctorSpecialty'] as String? ?? 'Gynaecology';
  String get _regNo         => _d['doctorRegNo']   as String? ?? 'MCI-12345';
  String get _patientName   => _d['patientName']   as String? ?? 'Patient';
  String get _patientAge    => _d['patientAge']    as String? ?? '--';
  String get _patientGender => _d['patientGender'] as String? ?? '--';
  String get _bloodGroup    => _d['patientBloodGroup'] as String? ?? '--';
  String get _diagnosis     => _d['diagnosis']     as String? ?? 'Acute Upper Respiratory Tract Infection (URI) with mild fever.';
  String get _rxId          => _d['rxId']          as String? ?? (_d['id'] as String? ?? 'RX-0000');

  String get _dateStr {
    final ts = _d['createdAt'];
    if (ts == null) return DateFormat('d MMM yyyy').format(DateTime.now());
    try {
      // cloud_firestore Timestamp
      final dt = (ts as dynamic).toDate() as DateTime;
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return DateFormat('d MMM yyyy').format(DateTime.now());
    }
  }

  List<Map<String, dynamic>> get _medicines {
    final raw = _d['medicines'];
    if (raw == null) {
      return [
        {'name': 'Paracetamol 500mg', 'dosage': '1 tablet',  'frequency': 'Twice daily',       'duration': '5 days',  'timing': 'After food'},
        {'name': 'Amoxicillin 250mg', 'dosage': '1 capsule', 'frequency': 'Three times daily',  'duration': '7 days',  'timing': 'After food'},
        {'name': 'Omeprazole 20mg',   'dosage': '1 capsule', 'frequency': 'Once daily',          'duration': '14 days', 'timing': 'Before food'},
      ];
    }
    return (raw as List).map((m) => Map<String, dynamic>.from(m as Map)).toList();
  }

  List<String> get _advice {
    final raw = _d['advice'];
    if (raw == null) {
      return [
        'Take complete rest for 2-3 days',
        'Drink plenty of fluids (3+ litres/day)',
        'Avoid cold foods & drinks',
        'Monitor temperature twice daily',
        'Follow-up after 5 days if no improvement',
      ];
    }
    return (raw as List).map((e) => e.toString()).toList();
  }

  // ── PDF Generation ──────────────────────────────────────────────────────────

  Future<Uint8List> _buildPdf() async {
    final doc = pw.Document();
    final medColors = [PdfColors.blue800, PdfColors.green800, PdfColors.purple700, PdfColors.orange800, PdfColors.teal700];

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      header: (ctx) => _pdfHeader(),
      footer: (ctx) => _pdfFooter(ctx),
      build: (ctx) => [
        pw.SizedBox(height: 12),
        _pdfDoctorPatientRow(),
        pw.SizedBox(height: 12),
        _pdfDiagnosis(),
        pw.SizedBox(height: 12),
        _pdfMedicines(medColors),
        pw.SizedBox(height: 12),
        _pdfAdvice(),
        pw.SizedBox(height: 16),
        _pdfSignature(),
      ],
    ));

    return doc.save();
  }

  pw.Widget _pdfHeader() => pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1976D2)),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('MedNU Healthcare', style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Digital Prescription', style: const pw.TextStyle(color: PdfColors.grey200, fontSize: 11)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Rx  $_rxId', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.Text('Date: $_dateStr', style: const pw.TextStyle(color: PdfColors.grey200, fontSize: 10)),
        ]),
      ],
    ),
  );

  pw.Widget _pdfFooter(pw.Context ctx) => pw.Container(
    alignment: pw.Alignment.centerRight,
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Text(
      'Page ${ctx.pageNumber} of ${ctx.pagesCount}  |  Generated by MedNU',
      style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
    ),
  );

  pw.Widget _pdfDoctorPatientRow() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Doctor Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.grey700)),
          pw.SizedBox(height: 6),
          pw.Text(_doctorName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
          pw.Text(_specialty, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Text('Reg. No: $_regNo', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        ]),
      )),
      pw.SizedBox(width: 12),
      pw.Expanded(child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Patient Details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.grey700)),
          pw.SizedBox(height: 6),
          pw.Text(_patientName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
          pw.Text('Age: $_patientAge  |  Gender: $_patientGender', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Text('Blood Group: $_bloodGroup', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        ]),
      )),
    ],
  );

  pw.Widget _pdfDiagnosis() => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(color: PdfColors.blue50, border: pw.Border.all(color: PdfColors.blue200), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Diagnosis', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blue800)),
      pw.SizedBox(height: 4),
      pw.Text(_diagnosis, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800, lineSpacing: 3)),
    ]),
  );

  pw.Widget _pdfMedicines(List<PdfColor> colors) {
    final rows = _medicines.asMap().entries.map((e) {
      final m = e.value;
      return pw.TableRow(children: [
        _pdfCell('${e.key + 1}', bold: true, bg: colors[e.key % colors.length]),
        _pdfCell(m['name'] as String? ?? '', bold: true),
        _pdfCell(m['dosage'] as String? ?? ''),
        _pdfCell(m['frequency'] as String? ?? ''),
        _pdfCell(m['duration'] as String? ?? ''),
        _pdfCell(m['timing'] as String? ?? ''),
      ]);
    }).toList();

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Prescribed Medicines', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(22),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(1.5),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(1.5),
          5: const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: ['#', 'Medicine', 'Dosage', 'Frequency', 'Duration', 'Timing']
                .map((h) => _pdfHeaderCell(h))
                .toList(),
          ),
          ...rows,
        ],
      ),
    ]);
  }

  pw.Widget _pdfHeaderCell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey800)),
  );

  pw.Widget _pdfCell(String t, {bool bold = false, PdfColor? bg}) => pw.Container(
    color: bg != null ? bg.shade(0.85) : null,
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );

  pw.Widget _pdfAdvice() => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Text("Doctor's Advice", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
    pw.SizedBox(height: 6),
    ..._advice.map((a) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('• ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue700)),
        pw.Expanded(child: pw.Text(a, style: const pw.TextStyle(fontSize: 10, lineSpacing: 2))),
      ]),
    )),
  ]);

  pw.Widget _pdfSignature() => pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Digitally Signed By', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.Text(_doctorName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        pw.Text('$_specialty • Reg: $_regNo', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      ]),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(color: PdfColors.green50, border: pw.Border.all(color: PdfColors.green300), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
        child: pw.Text('VERIFIED by MedNU', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
      ),
    ]),
  );

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<File> _savePdfToTemp() async {
    final bytes = await _buildPdf();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/prescription_$_rxId.pdf');
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
        text: 'Prescription issued on $_dateStr by $_doctorName ($_specialty)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _handleDownload() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await _buildPdf();
      // Save to app documents directory (accessible on both platforms)
      final dir = await getApplicationDocumentsDirectory();
      final filename = 'MedNU_Prescription_$_rxId.pdf';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved as $filename'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: _handleShare,
          ),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final medColorPalette = [
      const Color(0xFF1565C0), const Color(0xFF2E7D32), const Color(0xFF7B1FA2),
      const Color(0xFFE65100), const Color(0xFF00838F),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Prescription'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_pdfBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            IconButton(icon: const Icon(Icons.download_rounded), tooltip: 'Download PDF', onPressed: _handleDownload),
            IconButton(icon: const Icon(Icons.share_rounded), tooltip: 'Share', onPressed: _handleShare),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('MedNU Healthcare', style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('Digital Prescription', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: const Text('VERIFIED', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ]),
                const Divider(color: Colors.white24, height: 24),
                Row(children: [
                  Expanded(child: _PrescriptionInfo('Doctor', _doctorName)),
                  Expanded(child: _PrescriptionInfo('Specialty', _specialty)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _PrescriptionInfo('Date', _dateStr)),
                  Expanded(child: _PrescriptionInfo('Rx ID', _rxId)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),

            // Patient info
            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Patient Details', style: AppTextStyles.h4),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _PatientDetail('Name', _patientName)),
                Expanded(child: _PatientDetail('Age', _patientAge)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _PatientDetail('Gender', _patientGender)),
                Expanded(child: _PatientDetail('Blood Group', _bloodGroup)),
              ]),
            ])),
            const SizedBox(height: 16),

            // Diagnosis
            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Diagnosis', style: AppTextStyles.h4),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                child: Text(_diagnosis, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
              ),
            ])),
            const SizedBox(height: 16),

            // Medicines
            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Prescribed Medicines', style: AppTextStyles.h4),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutes.medicine, extra: _medicines),
                  icon: const Icon(Icons.shopping_cart_rounded, size: 14),
                  label: const Text('Order All', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(90, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
                ),
              ]),
              const SizedBox(height: 12),
              ..._medicines.asMap().entries.map((e) {
                final m = e.value;
                final color = medColorPalette[e.key % medColorPalette.length];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Center(child: Text('${e.key + 1}', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, color: color))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(m['name'] as String? ?? '', style: AppTextStyles.labelLarge)),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _MedTag('${m['dosage']}', color),
                      _MedTag('${m['frequency']}', color),
                      _MedTag('${m['duration']}', color),
                      _MedTag('${m['timing']}', color),
                    ]),
                  ]),
                );
              }),
            ])),
            const SizedBox(height: 16),

            // Doctor's advice
            _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Doctor's Advice", style: AppTextStyles.h4),
              const SizedBox(height: 10),
              ..._advice.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(a, style: AppTextStyles.bodyMedium)),
                ]),
              )),
            ])),
            const SizedBox(height: 16),

            // Digital signature
            _card(child: Column(children: [
              const Text('Digitally Signed By', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textHint)),
              const SizedBox(height: 4),
              Text(_doctorName, style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, color: AppColors.primary)),
              Text('$_specialty  •  Reg. No: $_regNo', style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_rounded, color: AppColors.accent, size: 16),
                  const SizedBox(width: 6),
                  const Text('Digitally Verified by MedNU', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
                ]),
              ),
            ])),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
    child: child,
  );
}

class _PrescriptionInfo extends StatelessWidget {
  final String label, value;
  const _PrescriptionInfo(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white60)),
    Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
  ]);
}

class _PatientDetail extends StatelessWidget {
  final String label, value;
  const _PatientDetail(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: AppTextStyles.caption),
    Text(value, style: AppTextStyles.labelLarge),
  ]);
}

class _MedTag extends StatelessWidget {
  final String label;
  final Color color;
  const _MedTag(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.2))),
    child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500, color: color)),
  );
}
