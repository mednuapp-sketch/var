import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/r.dart';
import '../../../core/widgets/ux_widgets.dart';

class SubmitTicketScreen extends StatefulWidget {
  const SubmitTicketScreen({super.key});

  @override
  State<SubmitTicketScreen> createState() => _SubmitTicketScreenState();
}

class _SubmitTicketScreenState extends State<SubmitTicketScreen> {
  static const _categories = [
    'App Crash / Error',
    'Payment / Wallet Issue',
    'Appointment / Booking Issue',
    'Prescription / Records Issue',
    'Medicine / Delivery Issue',
    'Doctor / Service Complaint',
    'Login / OTP Issue',
    'Other',
  ];

  final _descCtrl = TextEditingController();
  String _category = 'App Crash / Error';
  File? _screenshot;
  bool _submitting = false;
  String? _ticketId;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (picked != null && mounted) {
        setState(() => _screenshot = File(picked.path));
      }
    } catch (_) {}
  }

  String _generateTicketId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'TKT-$ts';
  }

  String _priorityFor(String category) {
    if (category.contains('Crash') || category.contains('Login') || category.contains('Complaint')) {
      return 'high';
    }
    if (category.contains('Payment') || category.contains('Appointment') ||
        category.contains('Prescription') || category.contains('Delivery')) {
      return 'medium';
    }
    return 'low';
  }

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) {
      _showSnack('Please describe the issue before submitting.', AppColors.error);
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final userDoc = uid.isNotEmpty
          ? await FirebaseFirestore.instance.collection('users').doc(uid).get()
          : null;
      final userData = userDoc?.data();
      final patientName = (userData?['name'] as String?) ?? 'Patient';
      final phone = (userData?['phone'] as String?) ??
          FirebaseAuth.instance.currentUser?.phoneNumber ?? '';

      String? attachmentUrl;
      if (_screenshot != null) {
        final ref = FirebaseStorage.instance
            .ref('support_attachments/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_screenshot!);
        attachmentUrl = await ref.getDownloadURL();
      }

      final ticketId = _generateTicketId();
      await FirebaseFirestore.instance.collection('support_tickets').doc(ticketId).set({
        'ticketId':      ticketId,
        'userId':        uid,
        'patientName':   patientName,
        'phone':         phone,
        'category':      _category,
        'description':   _descCtrl.text.trim(),
        'attachmentUrl': attachmentUrl,
        'status':        'open',
        'priority':      _priorityFor(_category),
        'role':          'patient',
        'createdAt':     FieldValue.serverTimestamp(),
        'updatedAt':     FieldValue.serverTimestamp(),
        'adminNotes':    '',
        'resolvedAt':    null,
      });

      if (mounted) {
        setState(() => _ticketId = ticketId);
      }
    } catch (e) {
      _showSnack('Failed to submit report. Please try again.', AppColors.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text(
          'Submit a Ticket',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
      ),
      body: _ticketId != null ? _buildSuccessState(context) : _buildForm(context),
    );
  }

  Widget _buildSuccessState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(R.p(context, 32)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: R.w(context, 80), height: R.w(context, 80),
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: Colors.white, size: R.w(context, 44)),
            ),
            SizedBox(height: R.h(context, 24)),
            Text(
              'Ticket Submitted!',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700, color: context.appTextPrimary),
            ),
            SizedBox(height: R.h(context, 10)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 10)),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(R.r(context, 12)),
              ),
              child: Text(
                'Ticket ID: $_ticketId',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.primary),
              ),
            ),
            SizedBox(height: R.h(context, 16)),
            Text(
              'Our support team will review your report and respond within 24 hours.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: context.appTextSecondary, height: 1.6),
            ),
            SizedBox(height: R.h(context, 32)),
            AppButton(
              label: 'Back to Help',
              icon: Icons.arrow_back_rounded,
              onPressed: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(R.p(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(R.p(context, 14)),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(R.r(context, 14)),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.bug_report_rounded, color: AppColors.error, size: R.w(context, 22)),
              SizedBox(width: R.w(context, 12)),
              Expanded(
                child: Text(
                  'Describe your issue clearly so our team can resolve it quickly. A screenshot helps a lot!',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: context.appTextSecondary, height: 1.5),
                ),
              ),
            ]),
          ),
          SizedBox(height: R.h(context, 20)),

          Text('Issue Category', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: context.appTextPrimary)),
          SizedBox(height: R.h(context, 8)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 4)),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(R.r(context, 14)),
              border: Border.all(color: context.appBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ),
          SizedBox(height: R.h(context, 16)),

          Text('Describe the Issue *', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: context.appTextPrimary)),
          SizedBox(height: R.h(context, 8)),
          TextField(
            controller: _descCtrl,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Explain what happened, steps to reproduce, and what you expected...',
              hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.appTextHint),
              contentPadding: EdgeInsets.symmetric(horizontal: R.p(context, 14), vertical: R.p(context, 14)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                borderSide: BorderSide(color: context.appBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                borderSide: BorderSide(color: context.appBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
              ),
            ),
          ),
          SizedBox(height: R.h(context, 16)),

          Text('Attach Screenshot (optional)', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: context.appTextPrimary)),
          SizedBox(height: R.h(context, 8)),
          GestureDetector(
            onTap: _pickScreenshot,
            child: Container(
              height: _screenshot != null ? null : R.h(context, 100),
              decoration: BoxDecoration(
                color: context.appSurface,
                borderRadius: BorderRadius.circular(R.r(context, 14)),
                border: Border.all(
                  color: _screenshot != null ? AppColors.primary.withValues(alpha: 0.3) : context.appBorder,
                ),
              ),
              child: _screenshot != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(R.r(context, 14)),
                          child: Image.file(_screenshot!, width: double.infinity, height: R.h(context, 180), fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: R.p(context, 8), right: R.p(context, 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _screenshot = null),
                            child: Container(
                              padding: EdgeInsets.all(R.p(context, 4)),
                              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              child: Icon(Icons.close_rounded, color: Colors.white, size: R.w(context, 16)),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded, color: context.appTextHint, size: R.w(context, 32)),
                        SizedBox(height: R.h(context, 6)),
                        Text('Tap to add a screenshot',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: context.appTextHint)),
                      ],
                    ),
            ),
          ),
          SizedBox(height: R.h(context, 28)),

          AppButton(
            label: 'Submit Ticket',
            icon: Icons.send_rounded,
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          SizedBox(height: R.h(context, 40)),
        ],
      ),
    );
  }
}
