import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // Lab-partner-uploaded results — a separate collection the patient app
  // never read before (root cause of "I can't see any reports": a patient
  // who completes a lab test previously had no screen showing the result at
  // all, since it never landed in `reports`, which only holds self-uploaded
  // photos). See mednu_doctor/lib/features/lab/services/lab_booking_service.dart.
  StreamSubscription? _diagReportsSub;
  List<Map<String, dynamic>> _diagReports = [];
  bool _diagReportsLoading = true;

  StreamSubscription? _consultSub;
  List<Map<String, dynamic>> _consultations = [];
  bool _consultLoading = true;

  bool _uploading = false;

  // Controllers for one-off dialogs/sheets (e.g. _uploadReport's name prompt):
  // disposing them the instant showDialog/showModalBottomSheet's future
  // resolves (right on Navigator.pop) races the dialog's still-animating-out,
  // still-mounted TextField — defer disposal to this screen's own dispose()
  // instead, which only runs after the dialog is long gone.
  final List<TextEditingController> _transientCtrls = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.initialTab ?? 0);
    _subscribePrescriptions();
    _subscribeReports();
    _subscribeDiagnosticReports();
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

  void _subscribeDiagnosticReports() {
    // diagnostic_reports has no memberId field today — lab bookings are
    // always for the account holder, so skip merging it into a family
    // member's records view rather than risk showing someone else's results.
    if (_uid.isEmpty || widget.memberId != null) {
      setState(() => _diagReportsLoading = false);
      return;
    }

    final q = FirebaseFirestore.instance
        .collection('diagnostic_reports')
        .where('patientId', isEqualTo: _uid)
        .orderBy('uploadedAt', descending: true)
        .limit(50);

    _diagReportsSub = q.snapshots().listen((snap) {
      if (!mounted) return;
      setState(() {
        _diagReports = snap.docs.map((doc) {
          final d = doc.data();
          final fileUrl = d['fileUrl'] as String? ?? '';
          final isPdf = (d['fileType'] as String? ?? 'image') == 'pdf';
          return <String, dynamic>{
            'id': doc.id,
            'source': 'lab',
            'name': d['testName'] as String? ?? 'Lab Report',
            'imageUrl': isPdf ? '' : fileUrl,
            'fileUrl': fileUrl,
            'fileType': isPdf ? 'pdf' : 'image',
            'status': 'Uploaded',
            'createdAt': d['uploadedAt'],
          };
        }).toList();
        _diagReportsLoading = false;
      });
    }, onError: (_) { if (mounted) setState(() => _diagReportsLoading = false); });
  }

  List<Map<String, dynamic>> get _allReports {
    final merged = [..._reports, ..._diagReports];
    merged.sort((a, b) {
      final at = a['createdAt'];
      final bt = b['createdAt'];
      final ad = at is Timestamp ? at.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      final bd = bt is Timestamp ? bt.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return merged;
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
    _diagReportsSub?.cancel();
    _consultSub?.cancel();
    for (final c in _transientCtrls) {
      c.dispose();
    }
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
    if (createdAt is! Timestamp || endedAt is! Timestamp) return '';
    final start = createdAt.toDate();
    final end = endedAt.toDate();
    final diff = end.difference(start);
    if (diff.inMinutes < 1) return '< 1 min';
    return '${diff.inMinutes} min';
  }

  Color _specialtyColor(String? specialty) {
    switch ((specialty ?? '').toLowerCase()) {
      case 'cardiologist': return const Color(0xFF522546);
      case 'dermatologist': return const Color(0xFFF9943B);
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
    _transientCtrls.add(nameCtrl);
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
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
      backgroundColor: context.appBackground,
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
            Tab(
              child: Text('Prescriptions',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Tab(
              child: Text('Reports',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Tab(
              child: Text('Consultations',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
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
      // Uploading on a family member's behalf is fully supported by the
      // write path below (_uploadReport already sends memberId) — hiding
      // this FAB for isMemberView was the only thing stopping it.
      floatingActionButton: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF522546), Color(0xFF633058)],
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: List.generate(5, (_) => const _PrescriptionCardSkeleton()),
      );
    }

    if (_prescriptions.isEmpty) {
      return const AppEmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No prescriptions yet',
        message: 'Prescriptions from your doctors will appear here after consultations.',
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
            color: context.appSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.appBorder),
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
                      icon: Icon(Icons.share_rounded, color: context.appTextHint),
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
    if (_reportsLoading || _diagReportsLoading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: List.generate(5, (_) => const _ReportCardSkeleton()),
      );
    }

    final allReports = _allReports;
    if (allReports.isEmpty) {
      return AppEmptyState(
        icon: Icons.science_rounded,
        title: 'No reports uploaded yet',
        message: 'Upload your lab reports, X-rays, or scans for easy access.',
        iconColor: const Color(0xFF0097A7),
        actionLabel: 'Upload Report',
        onAction: _uploading ? null : _uploadReport,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: allReports.length,
      itemBuilder: (context, i) {
        final r = allReports[i];
        final name = r['name'] as String? ?? 'Report';
        final status = r['status'] as String? ?? 'Uploaded';
        final imageUrl = r['imageUrl'] as String? ?? '';
        final isPdf = r['fileType'] == 'pdf';
        final fileUrl = r['fileUrl'] as String? ?? '';
        final isLab = r['source'] == 'lab';
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
            color: context.appSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.appBorder),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: isPdf
                  ? (fileUrl.isNotEmpty ? () => _openExternalFile(fileUrl) : null)
                  : (imageUrl.isNotEmpty ? () => _viewReport(r) : null),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  // Thumbnail or icon
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl.isNotEmpty
                        ? Image.network(imageUrl, width: 46, height: 46, fit: BoxFit.cover,
                            // Reports are user-uploaded camera photos; without a
                            // decode hint a 46px thumbnail decodes at full
                            // resolution (tens of MB each) down the whole list.
                            cacheWidth: 138, cacheHeight: 138,
                            errorBuilder: (_, __, ___) => _reportIcon())
                        : _reportIcon(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(name, style: AppTextStyles.labelLarge, overflow: TextOverflow.ellipsis)),
                      if (isLab) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0097A7).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Lab', style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF0097A7))),
                        ),
                      ],
                    ]),
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
                  if (imageUrl.isNotEmpty || (isPdf && fileUrl.isNotEmpty))
                    Icon(Icons.chevron_right_rounded, color: context.appTextHint, size: 20),
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

  Future<void> _openExternalFile(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this file')),
        );
      }
    }
  }

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
        builder: (sheetCtx, ctrl) => Container(
          decoration: BoxDecoration(
              color: context.appSurface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                  child: Text(name,
                      style: AppTextStyles.h4,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(sheetCtx)),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: List.generate(5, (_) => const _ConsultationCardSkeleton()),
      );
    }

    if (_consultations.isEmpty) {
      return const AppEmptyState(
        icon: Icons.video_call_rounded,
        title: 'No consultations yet',
        message: 'Video call history will appear here after your first consultation.',
      );
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
            color: context.appSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.appBorder),
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
                Icon(Icons.schedule_rounded, size: 13, color: context.appTextHint),
                const SizedBox(width: 4),
                Text(dateStr, style: AppTextStyles.bodySmall),
              ]),
              if (durStr.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.timer_outlined, size: 13, color: context.appTextHint),
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
      decoration: BoxDecoration(
          color: context.appSurface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        const Text('Upload Report', style: AppTextStyles.h4),
        const SizedBox(height: 6),
        const Text('Take a photo or upload from gallery', style: AppTextStyles.bodySmall),
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

class _PrescriptionCardSkeleton extends StatelessWidget {
  const _PrescriptionCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: AppShimmer(
          child: Row(children: [
            SkeletonBox(width: 46, height: 46, radius: 12),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: double.infinity, height: 14, radius: 4),
              SizedBox(height: 5),
              SkeletonBox(width: 160, height: 11, radius: 4),
              SizedBox(height: 5),
              SkeletonBox(width: 120, height: 11, radius: 4),
              SizedBox(height: 5),
              SkeletonBox(width: 140, height: 11, radius: 4),
            ])),
            SizedBox(width: 8),
            Column(mainAxisSize: MainAxisSize.min, children: [
              SkeletonBox(width: 32, height: 32, radius: 8),
              SizedBox(height: 8),
              SkeletonBox(width: 32, height: 32, radius: 8),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ReportCardSkeleton extends StatelessWidget {
  const _ReportCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: AppShimmer(
          child: Row(children: [
            SkeletonBox(width: 46, height: 46, radius: 12),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: double.infinity, height: 14, radius: 4),
              SizedBox(height: 6),
              SkeletonBox(width: 120, height: 11, radius: 4),
            ])),
            SizedBox(width: 8),
            SkeletonBox(width: 60, height: 24, radius: 8),
          ]),
        ),
      ),
    );
  }
}

class _ConsultationCardSkeleton extends StatelessWidget {
  const _ConsultationCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: const AppShimmer(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkeletonBox(width: 48, height: 48, radius: 14),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SkeletonBox(width: double.infinity, height: 14, radius: 4),
            SizedBox(height: 6),
            SkeletonBox(width: 180, height: 11, radius: 4),
            SizedBox(height: 6),
            SkeletonBox(width: 120, height: 11, radius: 4),
            SizedBox(height: 10),
            SkeletonBox(width: 100, height: 28, radius: 8),
          ])),
        ]),
      ),
    );
  }
}
