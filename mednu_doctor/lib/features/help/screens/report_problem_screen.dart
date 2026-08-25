import 'package:flutter/material.dart';
import '../../../core/router/app_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  static const _categories = [
    'App Crash / Error',
    'Video Call Issue',
    'Payment / Earnings Problem',
    'Notification Not Working',
    'Profile / Account Issue',
    'Prescription Not Sending',
    'Patient Not Found',
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

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) {
      _showSnack('Please describe the issue before submitting.', AppColors.error);
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final doctorData = uid.isNotEmpty ? await DoctorAuthService.getProfile(uid) : null;
      final doctorName = doctorData?['name'] as String? ?? 'Doctor';
      final phone = doctorData?['phone'] as String? ?? '';

      String? attachmentUrl;
      if (_screenshot != null) {
        final ticketRef = FirebaseStorage.instance
            .ref('support_attachments/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ticketRef.putFile(_screenshot!);
        attachmentUrl = await ticketRef.getDownloadURL();
      }

      final ticketId = _generateTicketId();
      await FirebaseFirestore.instance.collection('support_tickets').doc(ticketId).set({
        'ticketId':     ticketId,
        'doctorId':     uid,
        'doctorName':   doctorName,
        'phone':        phone,
        'category':     _category,
        'description':  _descCtrl.text.trim(),
        'attachmentUrl': attachmentUrl,
        'status':       'open',
        'priority':     _priorityFor(_category),
        'role':         'doctor',
        'createdAt':    FieldValue.serverTimestamp(),
        'updatedAt':    FieldValue.serverTimestamp(),
        'adminNotes':   '',
        'resolvedAt':   null,
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

  String _priorityFor(String category) {
    if (category.contains('Crash') || category.contains('Call') || category.contains('Login')) {
      return 'high';
    }
    if (category.contains('Payment') || category.contains('Prescription')) return 'medium';
    return 'low';
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Report a Problem',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.safeBack(),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _ticketId != null ? _buildSuccessState() : _buildForm(),
    );
  }

  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 24),
            const Text('Report Submitted!', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Ticket ID: $_ticketId',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Our support team will review your report and respond within 24 hours.\nTrack your ticket via Email Support.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(height: 1.6),
            ),
            const SizedBox(height: 32),
            GradientButton(
              label: 'Back to Help',
              icon: Icons.arrow_back_rounded,
              width: double.infinity,
              height: 52,
              onTap: () => context.safeBack(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha:0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.error.withValues(alpha:0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.bug_report_rounded, color: AppColors.error, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Describe your issue clearly so our team can resolve it quickly. '
                  'A screenshot helps a lot!',
                  style: AppTextStyles.bodySmall.copyWith(height: 1.5),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Category
          const Text('Issue Category', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                style: AppTextStyles.labelLarge,
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c,
                              style: const TextStyle(
                                  fontFamily: 'Inter', fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Description
          const Text('Describe the Issue *', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            maxLines: 5,
            decoration: InputDecoration(
              hintText:
                  'Explain what happened, steps to reproduce, and what you expected...',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Screenshot
          const Text('Attach Screenshot (optional)', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickScreenshot,
            child: Container(
              height: _screenshot != null ? null : 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _screenshot != null
                      ? AppColors.primary.withValues(alpha:0.3)
                      : AppColors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: _screenshot != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(_screenshot!,
                              width: double.infinity,
                              height: 180,
                              fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 8, right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _screenshot = null),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                  color: AppColors.error,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded,
                            color: AppColors.textHint, size: 32),
                        SizedBox(height: 6),
                        Text(
                          'Tap to add a screenshot',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: AppColors.textHint),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 28),

          GradientButton(
            label: 'Submit Report',
            icon: Icons.send_rounded,
            width: double.infinity,
            height: 52,
            isLoading: _submitting,
            colors: const [Color(0xFFB71C1C), AppColors.primary],
            onTap: _submitting ? () {} : _submit,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
