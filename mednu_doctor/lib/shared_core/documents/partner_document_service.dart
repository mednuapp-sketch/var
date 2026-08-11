import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Generic partner verification-document service — one implementation for
/// Lab / Pharmacy / Ambulance / Caregiver rather than four copies.
///
/// Mirrors `ImageUploadService`'s Doctor-side flow (the established template
/// in this codebase: `imageQuality: 90` on the picker *is* the compression
/// step, no extra package) but parameterised by role, and pointed at the
/// private `{role}_documents/{uid}/` Storage prefix instead of `doctors/`.
///
/// Firestore side: this writes `documents.{docType}` on
/// `{role}_profiles/{uid}` and **never** touches `documentVerification`,
/// which `firestore.rules` reserves for admin.
class PartnerDocumentService {
  /// 'lab' | 'pharmacy' | 'ambulance' | 'caregiver'.
  final String role;
  final String uid;

  PartnerDocumentService(this.role, this.uid);

  static final _picker = ImagePicker();
  static final _storage = FirebaseStorage.instance;
  static final _db = FirebaseFirestore.instance;

  /// Matches the 20 MB ceiling in `storage.rules`. Enforced client-side too so
  /// an oversized pick fails immediately with a readable message rather than
  /// after a long upload that the rules then reject.
  static const int maxSizeBytes = 20 * 1024 * 1024;

  String get _collection => '${role}_profiles';

  DocumentReference<Map<String, dynamic>> get _profileRef =>
      _db.collection(_collection).doc(uid);

  // ── Pickers ──────────────────────────────────────────────────────────────

  /// Camera (photograph a physical document) or gallery. `imageQuality: 90`
  /// keeps small print readable while still shrinking the file.
  Future<File?> pickImage({required ImageSource source}) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    return picked == null ? null : File(picked.path);
  }

  Future<File?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  // ── Upload / remove ──────────────────────────────────────────────────────

  /// Uploads to `{role}_documents/{uid}/{docType}.{jpg|pdf}` and records the
  /// result under `documents.{docType}` on the profile doc.
  ///
  /// Throws a message-carrying [Exception] on an oversized file so the caller
  /// can surface it verbatim.
  Future<void> uploadDocument({
    required String docType,
    required File file,
    String? previousStoragePath,
    void Function(double progress)? onProgress,
  }) async {
    final size = await file.length();
    if (size > maxSizeBytes) {
      throw Exception(
        'This file is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB. '
        'Please choose a file under 20 MB.',
      );
    }

    final isPdf = file.path.toLowerCase().endsWith('.pdf');
    final ext = isPdf ? 'pdf' : 'jpg';
    final contentType = isPdf ? 'application/pdf' : 'image/jpeg';
    final storagePath = '${role}_documents/$uid/$docType.$ext';

    final ref = _storage.ref().child(storagePath);
    final task = ref.putFile(file, SettableMetadata(contentType: contentType));

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress(snap.bytesTransferred / snap.totalBytes);
        }
      });
    }

    final snapshot = await task;
    if (snapshot.state != TaskState.success) {
      throw Exception('Upload failed (${snapshot.state.name}). Please retry.');
    }

    final url = await ref.getDownloadURL();

    // `set(merge: true)` rather than `update()` so a partner whose profile doc
    // has not been created yet still gets a valid write (rules allow the owner
    // to create their own profile), and so the nested `documents` map is
    // deep-merged instead of replaced.
    await _profileRef.set({
      'documents': {
        docType: {
          'url': url,
          'storagePath': storagePath,
          'fileName': file.path.split(Platform.pathSeparator).last,
          'contentType': contentType,
          'sizeBytes': size,
          'uploadedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));

    // A replace that switched format (pdf ➜ jpg or back) leaves the old object
    // behind under the other extension — clean it up, best effort.
    if (previousStoragePath != null &&
        previousStoragePath.isNotEmpty &&
        previousStoragePath != storagePath) {
      await _deleteObject(previousStoragePath);
    }
  }

  /// Deletes the Storage object and clears `documents.{docType}`.
  ///
  /// Deliberately leaves `documentVerification.{docType}` untouched: that map
  /// is admin-owned, so a removed-then-reuploaded document keeps its prior
  /// verification history visible until admin re-verifies it.
  Future<void> removeDocument({
    required String docType,
    String? storagePath,
  }) async {
    if (storagePath != null && storagePath.isNotEmpty) {
      await _deleteObject(storagePath);
    } else {
      // Path unknown (a doc written before storagePath was recorded) — the
      // file can only be one of the two allowed extensions.
      await _deleteObject('${role}_documents/$uid/$docType.jpg');
      await _deleteObject('${role}_documents/$uid/$docType.pdf');
    }

    await _profileRef.update({'documents.$docType': FieldValue.delete()});
  }

  Future<void> _deleteObject(String path) async {
    try {
      await _storage.ref().child(path).delete();
    } catch (_) {
      // Already gone / never existed — not worth failing the whole action.
    }
  }
}
