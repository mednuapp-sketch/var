import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../auth/services/doctor_auth_service.dart';
import '../../../core/widgets/ux_widgets.dart';

class SpecializationChangeRequestScreen extends StatefulWidget {
  const SpecializationChangeRequestScreen({super.key});

  @override
  State<SpecializationChangeRequestScreen> createState() =>
      _SpecializationChangeRequestScreenState();
}

class _SpecializationChangeRequestScreenState
    extends State<SpecializationChangeRequestScreen> {
  static const _specializations = [
    'General Physician', 'Cardiology', 'Dermatology', 'Gynaecology',
    'Paediatrics', 'Orthopaedics', 'Neurology', 'ENT', 'Oncology',
    'Psychiatry', 'Ophthalmology', 'Urology', 'Radiology', 'Anaesthesiology',
    'Gastroenterology', 'Nephrology', 'Endocrinology', 'Pulmonology',
    'Rheumatology', 'Other',
  ];

  String  _currentSpec    = '';
  String  _requestedSpec  = 'General Physician';
  bool    _loading        = true;
  bool    _submitting     = false;

  // Existing pending request (if any)
  Map<String, dynamic>? _existingRequest;
  String? _existingRequestId;

  // Uploaded documents list: {name, file, url, uploading, progress}
  final List<Map<String, dynamic>> _documents = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Load doctor's current specialization
    final profile = await DoctorAuthService.getProfile(uid);
    _currentSpec = (profile?['specialty'] as String?) ?? 'General Physician';

    // Set default requested spec to something different
    _requestedSpec = _specializations.firstWhere(
      (s) => s != _currentSpec,
      orElse: () => _specializations.first,
    );

    // Check for existing pending/under_review request
    final snap = await FirebaseFirestore.instance
        .collection('doctor_specialization_requests')
        .where('doctorId', isEqualTo: uid)
        .where('status', whereIn: ['pending', 'under_review'])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      _existingRequestId = snap.docs.first.id;
      _existingRequest   = snap.docs.first.data();
    }

    if (mounted) setState(() => _loading = false);
  }

  // ── Document pick & upload ────────────────────────────────

  Future<void> _addDocument() async {
    final choice = await _showPickerChoice();
    if (choice == null) return;

    File? file;
    String name = '';

    if (choice == 'pdf') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      file = File(result.files.single.path!);
      name = result.files.single.name;
    } else {
      final source = choice == 'gallery' ? ImageSource.gallery : ImageSource.camera;
      final picked  = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;
      file = File(picked.path);
      name = picked.name;
    }

    final index = _documents.length;
    setState(() {
      _documents.add({
        'name':      name,
        'file':      file,
        'url':       null,
        'uploading': true,
        'progress':  0.0,
        'error':     null,
      });
    });

    await _uploadDocument(index, file!, name);
  }

  Future<void> _uploadDocument(int index, File file, String name) async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    final ext = name.contains('.') ? name.split('.').last : 'jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance
        .ref()
        .child('spec_requests/$uid/$timestamp.$ext');

    final contentType = ext == 'pdf' ? 'application/pdf' : 'image/jpeg';
    final task = ref.putFile(file, SettableMetadata(contentType: contentType));

    task.snapshotEvents.listen((snap) {
      if (!mounted) return;
      if (snap.totalBytes > 0) {
        setState(() {
          _documents[index]['progress'] =
              snap.bytesTransferred / snap.totalBytes;
        });
      }
    });

    try {
      await task;
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() {
        _documents[index]['url']       = url;
        _documents[index]['uploading'] = false;
        _documents[index]['progress']  = 1.0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _documents[index]['uploading'] = false;
        _documents[index]['error']     = 'Upload failed';
      });
    }
  }

  Future<String?> _showPickerChoice() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('Add Document',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Upload certificates, degrees or license documents',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              _PickerOption(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Upload PDF',
                subtitle: 'Certificates, degrees in PDF format',
                color: const Color(0xFFC62828),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
              const SizedBox(height: 10),
              _PickerOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                subtitle: 'Photos of documents from your phone',
                color: AppColors.primary,
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              const SizedBox(height: 10),
              _PickerOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                subtitle: 'Photograph a physical document',
                color: AppColors.secondary,
                onTap: () => Navigator.pop(context, 'camera'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _removeDocument(int index) {
    setState(() => _documents.removeAt(index));
  }

  // ── Submit request ────────────────────────────────────────

  Future<void> _submitRequest() async {
    final uid = DoctorAuthService.currentUid;
    if (uid == null) return;

    if (_requestedSpec == _currentSpec) {
      _snack('Please select a different specialization.', isError: true);
      return;
    }

    final hasUploading = _documents.any((d) => d['uploading'] == true);
    if (hasUploading) {
      _snack('Please wait for all documents to finish uploading.', isError: true);
      return;
    }

    final successDocs = _documents.where((d) => d['url'] != null).toList();
    if (successDocs.isEmpty) {
      _snack('Please upload at least one supporting document.', isError: true);
      return;
    }

    setState(() => _submitting = true);

    try {
      final profile = await DoctorAuthService.getProfile(uid);
      final doctorName = (profile?['name'] as String?) ?? '';

      await FirebaseFirestore.instance
          .collection('doctor_specialization_requests')
          .add({
        'doctorId':              uid,
        'doctorName':            doctorName,
        'oldSpecialization':     _currentSpec,
        'requestedSpecialization': _requestedSpec,
        'documents': successDocs
            .map((d) => {'name': d['name'] as String, 'url': d['url'] as String})
            .toList(),
        'status':       'pending',
        'adminRemarks': '',
        'createdAt':    FieldValue.serverTimestamp(),
        'approvedAt':   null,
      });

      if (!mounted) return;
      _snack('Request submitted! Awaiting admin review.');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to submit: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Specialization Change'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
              child: Column(children: List.generate(5, (_) => const Padding(padding: EdgeInsets.only(bottom: 16), child: SkeletonBox(width: double.infinity, height: 60, radius: 14)))))
          : _existingRequest != null
              ? _buildStatusView()
              : _buildRequestForm(),
    );
  }

  // ── Existing request status view ──────────────────────────

  Widget _buildStatusView() {
    final req    = _existingRequest!;
    final status = req['status'] as String? ?? 'pending';
    final old    = req['oldSpecialization'] as String? ?? '';
    final newS   = req['requestedSpecialization'] as String? ?? '';
    final remark = req['adminRemarks'] as String? ?? '';
    final ts     = req['createdAt'] as Timestamp?;
    final date   = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : '—';

    final (color, bg, icon, label) = switch (status) {
      'approved'     => (AppColors.success,  const Color(0xFFE8F5E9), Icons.check_circle_rounded,    'Approved'),
      'rejected'     => (AppColors.error,    const Color(0xFFFFEBEE), Icons.cancel_rounded,           'Rejected'),
      'under_review' => (AppColors.warning,  const Color(0xFFFFF8E1), Icons.manage_search_rounded,    'Under Review'),
      _              => (AppColors.info,     const Color(0xFFE3F2FD), Icons.hourglass_empty_rounded,  'Pending Approval'),
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha:0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 48),
              const SizedBox(height: 12),
              Text(label,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                      fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 6),
              Text('Your specialization change request is $label.'.toLowerCase(),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      color: color.withValues(alpha:0.8)),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Request details card
        _InfoCard('Request Details', [
          _InfoRow('Submitted On', date),
          _InfoRow('Current Specialization', old),
          _InfoRow('Requested Specialization', newS),
          if (remark.isNotEmpty) _InfoRow('Admin Remarks', remark, highlight: true),
        ]),
        const SizedBox(height: 16),

        // Documents
        if ((req['documents'] as List?)?.isNotEmpty == true) ...[
          _InfoCard('Submitted Documents', [
            ...(req['documents'] as List).map((d) {
              final docName = d['name'] as String? ?? 'Document';
              final docUrl  = d['url']  as String? ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.description_rounded, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(docName,
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (docUrl.isNotEmpty)
                    Text('Uploaded', style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11,
                        color: AppColors.success, fontWeight: FontWeight.w600)),
                ]),
              );
            }),
          ]),
          const SizedBox(height: 16),
        ],

        // Info about what happens next
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.info),
                const SizedBox(width: 8),
                Text('What happens next?',
                    style: AppTextStyles.bodySmall.copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.info)),
              ]),
              const SizedBox(height: 10),
              ...[
                'Admin will review your documents and credentials.',
                'Your current specialization stays active until approved.',
                'You will be notified once a decision is made.',
              ].map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary)),
                        Expanded(child: Text(t,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                color: AppColors.textSecondary))),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── New request form ──────────────────────────────────────

  Widget _buildRequestForm() {
    final allUploading = _documents.any((d) => d['uploading'] == true);
    final canSubmit    = !_submitting && !allUploading;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Verified Process',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                        fontWeight: FontWeight.w700, color: Colors.white)),
                Text('Specialization changes require admin approval and document verification.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: Colors.white.withValues(alpha:0.85))),
              ],
            )),
          ]),
        ),
        const SizedBox(height: 16),

        // Current specialization display
        _FormCard('Current Specialization', [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const Icon(Icons.lock_rounded, size: 16, color: AppColors.textHint),
              const SizedBox(width: 10),
              Text(_currentSpec,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Active',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: FontWeight.w700, color: AppColors.success)),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          Text('This will remain active until your request is approved.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
        ]),
        const SizedBox(height: 12),

        // Requested specialization
        _FormCard('Requested Specialization', [
          DropdownButtonFormField<String>(
            value: _requestedSpec,
            isExpanded: true,
            decoration: const InputDecoration(),
            items: _specializations
                .where((s) => s != _currentSpec)
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _requestedSpec = v!),
          ),
        ]),
        const SizedBox(height: 12),

        // Documents section
        _FormCard('Supporting Documents', [
          Text('Upload your medical certificates, degree proof, or specialization license.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 14),

          // Document list
          ..._documents.asMap().entries.map((entry) {
            final i   = entry.key;
            final doc = entry.value;
            return _DocumentTile(
              name:       doc['name'] as String,
              uploading:  doc['uploading'] as bool,
              progress:   doc['progress'] as double,
              hasError:   doc['error'] != null,
              onRemove:   (doc['uploading'] as bool) ? null : () => _removeDocument(i),
            );
          }),

          if (_documents.isNotEmpty) const SizedBox(height: 10),

          // Add document button
          InkWell(
            onTap: _addDocument,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary.withValues(alpha:0.4), width: 1.5,
                    style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(12),
                color: AppColors.primary.withValues(alpha:0.04),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Add Document',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w600, color: AppColors.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Accepted formats hint
          Wrap(spacing: 6, children: [
            _FormatChip('PDF'),
            _FormatChip('JPG'),
            _FormatChip('PNG'),
          ]),
        ]),
        const SizedBox(height: 12),

        // Required documents hint
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withValues(alpha:0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.checklist_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Text('Recommended Documents',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w700, color: AppColors.warning)),
              ]),
              const SizedBox(height: 8),
              ...[
                'Specialization / Post-Graduate Degree Certificate',
                'Medical Council Registration for New Specialization',
                'Medical License or Practicing Certificate',
              ].map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: AppColors.warning,
                            fontFamily: 'Poppins', fontSize: 12)),
                        Expanded(child: Text(item,
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                color: AppColors.textSecondary))),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Submit button
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: canSubmit ? _submitRequest : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(alpha:0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Submit Request for Review',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _FormCard(this.title, this.children);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.h4),
          const SizedBox(height: 12),
          ...children,
        ]),
      );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoCard(this.title, this.children);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTextStyles.h4),
          const SizedBox(height: 12),
          ...children,
        ]),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _InfoRow(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: Text(value,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: highlight ? AppColors.error : AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

class _DocumentTile extends StatelessWidget {
  final String name;
  final bool uploading;
  final double progress;
  final bool hasError;
  final VoidCallback? onRemove;

  const _DocumentTile({
    required this.name,
    required this.uploading,
    required this.progress,
    required this.hasError,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isPdf = name.toLowerCase().endsWith('.pdf');
    final icon  = isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded;
    final color = isPdf ? const Color(0xFFC62828) : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasError
            ? AppColors.error.withValues(alpha:0.05)
            : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasError
              ? AppColors.error.withValues(alpha:0.3)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(name,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (uploading)
              SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            else if (hasError)
              const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error)
            else
              const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
            if (onRemove != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textHint),
              ),
            ],
          ]),
          if (uploading && progress > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 2),
            Text('${(progress * 100).toStringAsFixed(0)}% uploaded',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    color: AppColors.textHint)),
          ],
          if (hasError) ...[
            const SizedBox(height: 4),
            const Text('Upload failed. Please remove and try again.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  const _FormatChip(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      );
}

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PickerOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w700, color: color)),
              Text(subtitle, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  color: AppColors.textSecondary)),
            ]),
          ]),
        ),
      );
}
