import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import 'partner_document_models.dart';
import '../services/pending_profile_edit_service.dart';
import 'partner_document_service.dart';

/// Asks for the short title of an optional "Other document" (e.g. "Fellowship
/// certificate"). Returns the trimmed title, or null when cancelled.
Future<String?> askOtherDocumentTitle(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _OtherDocTitleDialog(),
  );
}

class _OtherDocTitleDialog extends StatefulWidget {
  const _OtherDocTitleDialog();

  @override
  State<_OtherDocTitleDialog> createState() => _OtherDocTitleDialogState();
}

class _OtherDocTitleDialogState extends State<_OtherDocTitleDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _ctrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a short title for this document');
      return;
    }
    Navigator.pop(context, title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Document title'),
      content: SingleChildScrollView(
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: PartnerDocumentType.maxOtherLabelLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'e.g. Fellowship certificate',
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Choose file')),
      ],
    );
  }
}

/// Photo / gallery / PDF chooser shared by the "Other documents" flows.
/// Returns null when cancelled.
Future<File?> pickOtherDocumentFile(
  BuildContext context,
  PartnerDocumentService service,
  String title,
) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLarge),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: const Text('Upload a PDF'),
              onTap: () => Navigator.pop(sheetContext, 'pdf'),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return null;
  return switch (source) {
    'camera' => await service.pickImage(source: ImageSource.camera),
    'gallery' => await service.pickImage(source: ImageSource.gallery),
    _ => await service.pickPdf(),
  };
}

/// "Add another document" button for an already-registered (not yet active)
/// partner: title ➜ file ➜ immediate upload to the next free `other_doc_N`.
class AddOtherDocumentButton extends StatefulWidget {
  final String role;
  final String uid;

  /// `other_doc_N` keys already on the profile.
  final List<String> usedKeys;

  /// True once the profile is 'active'. The live `documents` map is then
  /// locked by firestore.rules, so the new document is queued for admin review
  /// as a `pendingChanges.documents.other_doc_N` entry instead of being written
  /// directly.
  final bool active;

  const AddOtherDocumentButton({
    super.key,
    required this.role,
    required this.uid,
    required this.usedKeys,
    this.active = false,
  });

  @override
  State<AddOtherDocumentButton> createState() => _AddOtherDocumentButtonState();
}

class _AddOtherDocumentButtonState extends State<AddOtherDocumentButton> {
  bool _busy = false;
  double? _progress;

  Future<void> _add() async {
    final key = PartnerDocumentType.nextFreeOtherDocKey(widget.usedKeys);
    if (key == null) return;
    final title = await askOtherDocumentTitle(context);
    if (title == null || !mounted) return;
    final service = PartnerDocumentService(widget.role, widget.uid);
    final file = await pickOtherDocumentFile(context, service, title);
    if (file == null || !mounted) return;

    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      if (widget.active) {
        // Approved partner: Storage only accepts `other_doc_N` files for them
        // (storage.rules), and the metadata goes through the pending-review
        // path. `pendingChanges` is deep-merged by set(merge: true), so
        // earlier pending documents are kept.
        final meta = await service.uploadToStorage(
          docType: key,
          file: file,
          label: title,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
        await PendingProfileEditService.apply(
          ref: FirebaseFirestore.instance
              .collection('${widget.role}_profiles')
              .doc(widget.uid),
          currentStatus: 'active',
          fields: {
            'documents': {
              key: {...meta, 'uploadedAt': Timestamp.now()},
            },
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Document submitted for admin review.'),
          ));
        }
      } else {
        await service.uploadDocument(
          docType: key,
          file: file,
          label: title,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final atCap = widget.usedKeys.length >= PartnerDocumentType.maxOtherDocs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (atCap || _busy) ? null : _add,
            icon: _busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, value: _progress),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(atCap
                ? 'Maximum ${PartnerDocumentType.maxOtherDocs} documents added'
                : 'Add another document'),
          ),
        ),
        if (!atCap)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Photo or PDF · max 20 MB · up to 5 documents',
              style: AppTextStyles.caption,
            ),
          ),
      ],
    );
  }
}

/// Section heading used above the "Other documents" blocks.
class OtherDocumentsHeading extends StatelessWidget {
  const OtherDocumentsHeading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Other documents (optional)',
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
    );
  }
}
