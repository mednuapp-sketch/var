import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../core/widgets/ux_widgets.dart';

/// Invoice/receipt for one `payments/{paymentId}` doc — the same
/// server-authoritative record capturePayment/captureCartPayment write
/// (functions/index.js). GST fields are present but default to 0% (most
/// healthcare services are GST-exempt); wired here so a real rate can be
/// turned on later from `commission_rules`/a tax-config doc without another
/// screen rewrite — this pass doesn't add tax-compliance validation beyond
/// showing whatever rate is configured.
class InvoiceScreen extends StatefulWidget {
  final String paymentId;
  const InvoiceScreen({super.key, required this.paymentId});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  bool _busy = false;

  static const _serviceLabels = {
    'consultation': 'Doctor Consultation',
    'video_consultation': 'Video Consultation',
    'diagnostics': 'Lab Test',
    'medicine': 'Medicine Order',
    'pharmacy': 'Pharmacy',
    'ambulance': 'Ambulance Service',
    'caregiver': 'Caregiver Visit',
  };

  String _dateStr(Timestamp? ts) =>
      ts != null ? DateFormat('d MMM yyyy, h:mm a').format(ts.toDate()) : '—';

  Future<Uint8List> _buildPdf(Map<String, dynamic> d) async {
    final doc = pw.Document();
    final serviceType = d['serviceType'] as String? ?? '';
    final serviceLabel = _serviceLabels[serviceType] ?? serviceType;
    final originalAmount = (d['originalAmount'] as num?) ?? 0;
    final discount = (d['discount'] as num?) ?? 0;
    final paidAmount = (d['paidAmount'] as num?) ?? 0;
    final couponCode = d['couponCode'] as String?;
    final paymentMethod = d['paymentMethod'] as String? ?? '';
    final status = d['status'] as String? ?? 'completed';
    final gstRate = (d['gstRate'] as num?) ?? 0;
    final gstAmount = (paidAmount * gstRate / 100);
    final dateStr = _dateStr(d['createdAt'] as Timestamp?);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 30),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF522546)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MedNU Healthcare',
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Payment Receipt', style: const pw.TextStyle(color: PdfColors.grey200, fontSize: 11)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Receipt #${widget.paymentId}',
                          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.Text('Date: $dateStr', style: const pw.TextStyle(color: PdfColors.grey200, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(serviceLabel, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Status: ${status[0].toUpperCase()}${status.substring(1)}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pdfRow('Service Amount', '₹${originalAmount.toStringAsFixed(2)}'),
                  if (discount > 0)
                    _pdfRow('Coupon Discount${couponCode != null ? ' ($couponCode)' : ''}',
                        '-₹${discount.toStringAsFixed(2)}', color: PdfColors.green700),
                  if (gstRate > 0)
                    _pdfRow('GST ($gstRate%)', '₹${gstAmount.toStringAsFixed(2)}'),
                  pw.Divider(color: PdfColors.grey300),
                  _pdfRow('Total Paid', '₹${paidAmount.toStringAsFixed(2)}', bold: true),
                  pw.SizedBox(height: 6),
                  _pdfRow('Payment Method', paymentMethod == 'razorpay' ? 'Online (Razorpay)' : 'MedNU Wallet'),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey300),
            pw.Text(
              'This is a computer-generated receipt and does not require a signature.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: bold ? 13 : 11,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: color)),
          ],
        ),
      );

  Future<void> _shareOrDownload(Map<String, dynamic> d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _buildPdf(d);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_${widget.paymentId}.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'MedNU Payment Receipt',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate receipt: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text('Invoice',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      body: widget.paymentId.isEmpty
          ? const Center(child: Text('Invoice not found'))
          : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('payments').doc(widget.paymentId).get(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data?.data();
                if (d == null) {
                  return const AppEmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Invoice Not Found',
                    message: 'This payment record could not be located.',
                  );
                }
                final serviceType = d['serviceType'] as String? ?? '';
                final serviceLabel = _serviceLabels[serviceType] ?? serviceType;
                final originalAmount = (d['originalAmount'] as num?) ?? 0;
                final discount = (d['discount'] as num?) ?? 0;
                final paidAmount = (d['paidAmount'] as num?) ?? 0;
                final couponCode = d['couponCode'] as String?;
                final paymentMethod = d['paymentMethod'] as String? ?? '';
                final status = d['status'] as String? ?? 'completed';

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(20)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('MedNU Healthcare',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                            const SizedBox(height: 4),
                            const Text('Payment Receipt',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white70)),
                            const Divider(color: Colors.white24, height: 22),
                            Text('Receipt #${widget.paymentId}',
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                            Text(_dateStr(d['createdAt'] as Timestamp?),
                                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(serviceLabel, style: AppTextStyles.h4),
                            const SizedBox(height: 4),
                            Text('Status: ${status[0].toUpperCase()}${status.substring(1)}',
                                style: AppTextStyles.caption),
                            const SizedBox(height: 16),
                            _InvoiceRow('Service Amount', '₹${originalAmount.toStringAsFixed(0)}'),
                            if (discount > 0)
                              _InvoiceRow(
                                'Coupon Discount${couponCode != null ? ' ($couponCode)' : ''}',
                                '-₹${discount.toStringAsFixed(0)}',
                                valueColor: AppColors.success,
                              ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1),
                            ),
                            _InvoiceRow('Total Paid', '₹${paidAmount.toStringAsFixed(0)}', bold: true),
                            const SizedBox(height: 10),
                            _InvoiceRow('Payment Method', paymentMethod == 'razorpay' ? 'Online (Razorpay)' : 'MedNU Wallet'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : () => _shareOrDownload(d),
                          icon: _busy
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.share_rounded, size: 18),
                          label: Text(_busy ? 'Preparing…' : 'Download / Share Receipt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? valueColor;
  const _InvoiceRow(this.label, this.value, {this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: bold ? 14 : 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: context.appTextSecondary,
                )),
            Text(value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: bold ? 16 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: valueColor ?? context.appTextPrimary,
                )),
          ],
        ),
      );
}
