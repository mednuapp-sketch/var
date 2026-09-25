import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/r.dart';

/// KYC-style personal documents the patient can keep on file for quick
/// access during hospital admission / insurance claims — separate from
/// medical records (RecordsScreen) since these aren't health data.
class _DocType {
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  const _DocType(this.key, this.label, this.subtitle, this.icon, this.color);
}

const _docTypes = [
  _DocType('aadhaar', 'Aadhaar Card', 'Government ID proof',
      Icons.badge_rounded, Color(0xFF1565C0)),
  _DocType('lifeInsurance', 'Life Insurance', 'Policy document',
      Icons.shield_rounded, Color(0xFF2E7D32)),
];

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  String? _uploadingKey;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _upload(_DocType type) async {
    final uid = _uid;
    if (uid.isEmpty) return;

    final ImageSource? src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SourcePicker(title: type.label),
    );
    if (src == null || !mounted) return;

    File file;
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

    setState(() => _uploadingKey = type.key);
    try {
      final storagePath = 'documents/$uid/${type.key}.jpg';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final signedUrl = await ref.getDownloadURL();
      final downloadUrl =
          Uri.parse(signedUrl).replace(queryParameters: {'alt': 'media'}).toString();

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'documents.${type.key}': {
          'url': downloadUrl,
          'storagePath': storagePath,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${type.label} uploaded successfully'),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingKey = null);
    }
  }

  Future<void> _remove(_DocType type, String storagePath) async {
    final uid = _uid;
    if (uid.isEmpty) return;

    setState(() => _uploadingKey = type.key);
    try {
      try {
        await FirebaseStorage.instance.ref().child(storagePath).delete();
      } catch (_) {}
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'documents.${type.key}': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${type.label} removed'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingKey = null);
    }
  }

  void _viewDocument(_DocType type, String url) {
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
              color: context.appSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                  child: Text(type.label,
                      style: AppTextStyles.h4, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.broken_image_rounded, size: 80, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showOptions(_DocType type, {required bool hasDoc, String? url, String? storagePath}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.r(context, 24))),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(R.p(context, 20), R.p(context, 12), R.p(context, 20), R.p(context, 20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: R.w(context, 40), height: R.h(context, 4),
                margin: EdgeInsets.only(bottom: R.p(context, 20)),
                decoration: BoxDecoration(color: context.appBorder, borderRadius: BorderRadius.circular(R.r(context, 2))),
              ),
              Text(type.label,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: R.h(context, 20)),
              if (hasDoc && url != null) ...[
                _SheetOption(
                  icon: Icons.visibility_rounded,
                  label: 'View Document',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(context);
                    _viewDocument(type, url);
                  },
                ),
                SizedBox(height: R.h(context, 12)),
              ],
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: hasDoc ? 'Replace from Gallery' : 'Choose from Gallery',
                color: type.color,
                onTap: () {
                  Navigator.pop(context);
                  _upload(type);
                },
              ),
              SizedBox(height: R.h(context, 12)),
              _SheetOption(
                icon: Icons.camera_alt_rounded,
                label: hasDoc ? 'Retake Photo' : 'Take a Photo',
                color: AppColors.secondary,
                onTap: () {
                  Navigator.pop(context);
                  _upload(type);
                },
              ),
              if (hasDoc && storagePath != null) ...[
                SizedBox(height: R.h(context, 12)),
                _SheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove',
                  color: AppColors.error,
                  onTap: () {
                    Navigator.pop(context);
                    _remove(type, storagePath);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic ts) {
    if (ts is! Timestamp) return '';
    return DateFormat('d MMM yyyy').format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        title: const Text(
          'My Documents',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Colors.white, fontSize: 18),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: uid.isEmpty
          ? const Center(child: Text('Please sign in to manage your documents.'))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() as Map<String, dynamic>?;
                final documents = (data?['documents'] as Map<String, dynamic>?) ?? {};

                return ListView(
                  padding: EdgeInsets.fromLTRB(R.p(context, 16), R.p(context, 16), R.p(context, 16), R.p(context, 40)),
                  children: [
                    Container(
                      padding: EdgeInsets.all(R.p(context, 14)),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(R.r(context, 14)),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline_rounded, color: AppColors.primary, size: R.w(context, 20)),
                        SizedBox(width: R.w(context, 10)),
                        Expanded(
                          child: Text(
                            'Keep your Aadhaar card and life insurance details handy for hospital admissions and claims.',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                          ),
                        ),
                      ]),
                    ),
                    SizedBox(height: R.h(context, 20)),
                    ..._docTypes.map((type) {
                      final doc = documents[type.key] as Map<String, dynamic>?;
                      final url = doc?['url'] as String?;
                      final storagePath = doc?['storagePath'] as String?;
                      final uploadedAt = doc?['uploadedAt'];
                      final hasDoc = url != null && url.isNotEmpty;
                      final isBusy = _uploadingKey == type.key;

                      return Padding(
                        padding: EdgeInsets.only(bottom: R.h(context, 14)),
                        child: Material(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(R.r(context, 16)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(R.r(context, 16)),
                            onTap: isBusy
                                ? null
                                : () => _showOptions(type, hasDoc: hasDoc, url: url, storagePath: storagePath),
                            child: Container(
                              padding: EdgeInsets.all(R.p(context, 14)),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(R.r(context, 16)),
                                border: Border.all(color: context.appBorder),
                              ),
                              child: Row(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(R.r(context, 12)),
                                  child: hasDoc
                                      ? CachedNetworkImage(
                                          imageUrl: url,
                                          width: R.w(context, 52),
                                          height: R.h(context, 52),
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => _docIcon(type),
                                          errorWidget: (_, __, ___) => _docIcon(type),
                                        )
                                      : _docIcon(type),
                                ),
                                SizedBox(width: R.w(context, 14)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(type.label, style: AppTextStyles.labelLarge),
                                      SizedBox(height: R.h(context, 3)),
                                      Text(
                                        hasDoc
                                            ? 'Uploaded${_formatDate(uploadedAt).isNotEmpty ? ' on ${_formatDate(uploadedAt)}' : ''}'
                                            : type.subtitle,
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: hasDoc ? const Color(0xFF2E7D32) : context.appTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isBusy)
                                  SizedBox(
                                    width: R.w(context, 20), height: R.h(context, 20),
                                    child: const CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  Icon(
                                    hasDoc ? Icons.more_vert_rounded : Icons.upload_file_rounded,
                                    color: hasDoc ? context.appTextHint : type.color,
                                  ),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
    );
  }

  static Widget _docIcon(_DocType type) => Container(
        width: 52, height: 52,
        decoration: BoxDecoration(color: type.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Icon(type.icon, color: type.color, size: 26),
      );
}

class _SourcePicker extends StatelessWidget {
  final String title;
  const _SourcePicker({required this.title});

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
        Text('Upload $title', style: AppTextStyles.h4),
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
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
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
                  color: const Color(0xFF1565C0).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
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

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetOption({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: R.p(context, 16), vertical: R.p(context, 14)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(R.r(context, 14)),
          ),
          child: Row(children: [
            Container(
              width: R.w(context, 40),
              height: R.h(context, 40),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(R.r(context, 10))),
              child: Icon(icon, color: color, size: R.w(context, 20)),
            ),
            SizedBox(width: R.w(context, 14)),
            Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      );
}
