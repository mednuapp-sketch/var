import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../health/screens/prescription_viewer_screen.dart' show sharePrescription;
import '../../../core/widgets/ux_widgets.dart';

class RecordsScreen extends StatefulWidget {
  final String? memberId;
  final String? memberName;
  /// 0=Prescriptions, 1=Reports, 2=Consultations
  final int? initialTab;

  const RecordsScreen({super.key, this.memberId, this.memberName, this.initialTab});

  bool get isMemberView => memberId != null;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  StreamSubscription? _prescSub;
  List<Map<String, dynamic>> _prescriptions = [];
  bool _prescLoading = true;

  StreamSubscription? _reportsSub;
  List<Map<String, dynamic>> _reports = [];
  bool _reportsLoading = true;

  StreamSubscription? _consultSub;
  List<Map<String, dynamic>> _consultations = [];
  bool _consultLoading = true;

  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialTab ?? 0);
    _subscribePrescriptions();
    _subscribeReports();
    _subscribeConsultations();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _subscribePrescriptions() {
    if (_uid.isEmpty) { setState(() => _prescLoading = false); return; }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('prescriptions')
        .where('patientId', isEqualTo: _uid);

    if (widget.memberId != null) {
      q = q.where('memberId', isEqualTo: widget.memberId);
    }

    _prescSub = q.orderBy('createdAt', descending: true).limit(50).snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _prescriptions = snap.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return data;
        }).toList();
        _prescLoading = false;
      });
    }, onError: (_) { if (mounted) setState(() => _prescLoading = false); });
  }

  void _subscribeReports() {
    if (_uid.isEmpty) { setState(() => _reportsLoading = false); return; }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('reports')
        .where('patientId', isEqualTo: _uid);

    if (widget.memberId != null) {
      q = q.where('memberId', isEqualTo: widget.memberId);
    }

    _reportsSub = q.orderBy('createdAt', descending: true).limit(50).snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _reports = snap.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return data;
        }).toList();
        _reportsLoading = false;
      });
    }, onError: (_) { if (mounted) setState(() => _reportsLoading = false); });
  }

  void _subscribeConsultations() {
    if (_uid.isEmpty) { setState(() => _consultLoading = false); return; }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('consultations')
        .where('patientId', isEqualTo: _uid)
        .where('status', isEqualTo: 'ended');

    if (widget.memberId != null) {
      q = q.where('memberId', isEqualTo: widget.memberId);
    }

    _consultSub = q.orderBy('createdAt', descending: true).limit(50).snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _consultations = snap.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return data;
        }).toList();
        _consultLoading = false;
      });
    }, onError: (_) { if (mounted) setState(() => _consultLoading = false); });
  }

  @override
  void dispose() {
    _tab.dispose();
    _prescSub?.cancel();
    _reportsSub?.cancel();
    _consultSub?.cancel();
    super.dispose();
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DateFormat('d MMM yyyy').format(dt);
  }

  String _formatDateTime(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DateFormat('d MMM yyyy, h:mm a').format(dt);
  }

  String _callDuration(dynamic createdAt, dynamic endedAt) {
    if (createdAt == null || endedAt == null) return '';
    final start = (createdAt as Timestamp).toDate();
    final end = (endedAt as Timestamp).toDate();
    final diff = end.difference(start);
    if (diff.inMinutes < 1) return '< 1 min';
    return '${diff.inMinutes} min';
  }

  Color _specialtyColor(String? specialty) {
    switch ((specialty ?? '').toLowerCase()) {
      case 'cardiologist': return const Color(0xFFC2185B);
      case 'dermatologist': return const Color(0xFF00897B);
      case 'neurologist': return const Color(0xFF5E35B1);
      case 'pediatrician': return const Color(0xFFE65100);
      case 'orthopedic': return const Color(0xFF1565C0);
      default: return AppColors.primary;
    }
  }

  IconData _specialtyIcon(String? specialty) {
    switch ((specialty ?? '').toLowerCase()) {
      case 'cardiologist': return Icons.favorite_rounded;
      case 'dermatologist': return Icons.face_rounded;
      case 'neurologist': return Icons.psychology_rounded;
      case 'pediatrician': return Icons.child_care_rounded;
      case 'orthopedic': return Icons.accessibility_new_rounded;
      default: return Icons.local_hospital_rounded;
    }
  }

  // ── Upload Report ──────────────────────────────────────────

  Future<void> _uploadReport() async {
    // 1. Ask report name first
    final nameCtrl = TextEditingController();
    final reportName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Report Name',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Blood Test, X-Ray...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, nameCtrl.text.trim());
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (reportName == null || !mounted) return;

    // 2. Choose source
    final ImageSource? src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SourcePicker(),
    );
    if (src == null || !mounted) return;

    // 3. Pick image
    File? file;
    try {
      final picked = await ImagePicker().pickImage(source: src, imageQuality: 85);
      if (picked == null) return;
      file = File(picked.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access camera/gallery')));
      }
      return;
    }

    setState(() => _uploading = true);
    try {
      // 4. Upload to Storage
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'reports/$_uid/${ts}_${reportName.replaceAll(' ', '_')}.jpg';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final downloadUrl = await ref.getDownloadURL();

      // 5. Save to Firestore
      await FirebaseFirestore.instance.collection('reports').add({
        'patientId': _uid,
        if (widget.memberId != null) 'memberId': widget.memberId,
        'name': reportName,
        'imageUrl': downloadUrl,
        'storagePath': storagePath,
        'status': 'Uploaded',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Report uploaded successfully'),
          ]),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
        ));
        // Switch to Reports tab
        _tab.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isMemberView
        ? "${widget.memberName}'s Records"
        : 'My Health Records';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Prescriptions'),
            Tab(text: 'Reports'),
            Tab(text: 'Consultations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildPrescriptionsTab(),
          _buildReportsTab(),
          _buildConsultationsTab(),
        ],
      ),
      floatingActionButton: widget.isMemberView
          ? null
          : Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFC2185B), Color(0xFF7B1FA2)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha:0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: _uploading ? null : _uploadReport,
                backgroundColor: Colors.transparent,
                elevation: 0,
                icon: _uploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.upload_file_rounded, color: Colors.white),
                label: Text(
                  _uploading ? 'Uploading...' : 'Upload Report',
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
    );
  }

  // ── Prescriptions Tab ──────────────────────────────────────────────────────

  Widget _buildPrescriptionsTab() {
    if (_prescLoading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: List.generate(5, (_) => const SkeletonListTile()),
      );
    }

    if (_prescriptions.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha:0.08), shape: BoxShape.circle),
            child: const Icon(Icons.receipt_long_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('No prescriptions yet',
              style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Prescriptions from your doctors\nwill appear here after consultations',
              style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _prescriptions.length,
      itemBuilder: (context, i) {
        final rx = _prescriptions[i];
        final color = _specialtyColor(rx['doctorSpecialty'] as String?);
        final medicineList = rx['medicines'] as List<dynamic>? ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push(AppRoutes.prescriptionViewer, extra: rx),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.receipt_long_rounded, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rx['doctorName'] as String? ?? 'Doctor', style: AppTextStyles.labelLarge),
                    if ((rx['doctorSpecialty'] as String? ?? '').isNotEmpty)
                      Text(rx['doctorSpecialty'] as String, style: AppTextStyles.bodySmall.copyWith(color: color)),
                    Text(_formatDate(rx['createdAt']), style: AppTextStyles.bodySmall),
                    Text('${medicineList.length} medicine${medicineList.length == 1 ? '' : 's'} prescribed',
                        style: AppTextStyles.bodySmall),
                  ])),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.visibility_rounded, color: AppColors.primary),
                      tooltip: 'View',
                      onPressed: () => context.push(AppRoutes.prescriptionViewer, extra: rx),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: AppColors.textHint),
                      tooltip: 'Share',
                      onPressed: () => sharePrescription(rx),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Reports Tab ────────────────────────────────────────────────────────────

  Widget _buildReportsTab() {
    if (_reportsLoading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: List.generate(5, (_) => const SkeletonListTile()),
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
                color: const Color(0xFF0097A7).withValues(alpha:0.08), shape: BoxShape.circle),
            child: const Icon(Icons.science_rounded, size: 40, color: Color(0xFF0097A7)),
          ),
          const SizedBox(height: 16),
          Text('No reports uploaded yet',
              style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Tap "Upload Report" to add your lab reports,\nX-rays, or scans',
              style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (!widget.isMemberView)
            ElevatedButton.icon(
              onPressed: _uploading ? null : _uploadReport,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Upload Report'),
            ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _reports.length,
      itemBuilder: (context, i) {
        final r = _reports[i];
        final name = r['name'] as String? ?? 'Report';
        final status = r['status'] as String? ?? 'Uploaded';
        final imageUrl = r['imageUrl'] as String? ?? '';
        final dateStr = _formatDate(r['createdAt']);

        Color statusColor;
        switch (status.toLowerCase()) {
          case 'normal': statusColor = const Color(0xFF2E7D32); break;
          case 'review': statusColor = const Color(0xFFE65100); break;
          case 'high':   statusColor = const Color(0xFFC62828); break;
          default:       statusColor = AppColors.primary;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: imageUrl.isNotEmpty ? () => _viewReport(r) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  // Thumbnail or icon
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl.isNotEmpty
                        ? Image.network(imageUrl, width: 46, height: 46, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _reportIcon())
                        : _reportIcon(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: AppTextStyles.labelLarge),
                    if (dateStr.isNotEmpty) Text(dateStr, style: AppTextStyles.bodySmall),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(status,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                  const SizedBox(width: 4),
                  if (imageUrl.isNotEmpty)
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _reportIcon() => Container(
    width: 46, height: 46,
    decoration: BoxDecoration(
        color: const Color(0xFF0097A7).withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
    child: const Icon(Icons.science_rounded, color: Color(0xFF0097A7), size: 24),
  );

  void _viewReport(Map<String, dynamic> r) {
    final imageUrl = r['imageUrl'] as String? ?? '';
    final name = r['name'] as String? ?? 'Report';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text(name, style: AppTextStyles.h4),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(imageUrl, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 80, color: Colors.grey)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Consultations Tab ──────────────────────────────────────

  Widget _buildConsultationsTab() {
    if (_consultLoading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: List.generate(5, (_) => const SkeletonListTile()),
      );
    }

    if (_consultations.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha:0.08), shape: BoxShape.circle),
          child: const Icon(Icons.video_call_rounded, size: 40, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text('No consultations yet', style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Video call history will appear here', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _consultations.length,
      itemBuilder: (context, index) {
        final c = _consultations[index];
        final specialty = c['doctorSpecialty'] as String?;
        final color = _specialtyColor(specialty);
        final icon = _specialtyIcon(specialty);
        final dateStr = _formatDateTime(c['createdAt']);
        final durStr = _callDuration(c['createdAt'], c['endedAt']);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['doctorName'] as String? ?? 'Doctor', style: AppTextStyles.labelLarge),
              if (specialty != null && specialty.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(specialty, style: AppTextStyles.bodySmall.copyWith(color: color)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.schedule_rounded, size: 13, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(dateStr, style: AppTextStyles.bodySmall),
              ]),
              if (durStr.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.timer_outlined, size: 13, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Text('Duration: $durStr', style: AppTextStyles.bodySmall),
                ]),
              ],
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
              child: const Text('Completed',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
            ),
          ]),
        );
      },
    );
  }
}

// ── Source picker ──────────────────────────────────────────

class _SourcePicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text('Upload Report', style: AppTextStyles.h4),
        const SizedBox(height: 6),
        Text('Take a photo or upload from gallery', style: AppTextStyles.bodySmall),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context, ImageSource.camera),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha:0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha:0.3)),
                ),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.camera_alt_rounded, color: Color(0xFF2E7D32), size: 32),
                  SizedBox(height: 8),
                  Text('Camera', style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: Color(0xFF2E7D32))),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context, ImageSource.gallery),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha:0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1565C0).withValues(alpha:0.3)),
                ),
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.photo_library_rounded, color: Color(0xFF1565C0), size: 32),
                  SizedBox(height: 8),
                  Text('Gallery', style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: Color(0xFF1565C0))),
                ]),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
