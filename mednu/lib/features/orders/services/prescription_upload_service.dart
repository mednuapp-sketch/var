import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class PrescriptionTooLargeException implements Exception {
  final int sizeBytes;
  const PrescriptionTooLargeException(this.sizeBytes);
}

/// Everything needed to get a prescription photo/PDF from the device onto
/// `orders/{orderId}` lives here — screens never touch
/// `FirebaseStorage`/`ImagePicker`/`FilePicker` directly. This only ever
/// writes the three additive fields a patient is allowed to self-update
/// (see firestore.rules): `prescriptionUrl`, `prescriptionFileType`,
/// `prescriptionUploadedAt`. It never writes `status` or the verification
/// fields — those belong to the pharmacy/Cloud-Function side of this
/// feature.
class PrescriptionUploadService {
  PrescriptionUploadService._();

  static const int maxSizeBytes = 20 * 1024 * 1024; // 20 MB

  static final _picker = ImagePicker();
  static final _storage = FirebaseStorage.instance;
  static final _db = FirebaseFirestore.instance;

  /// A first compression pass happens at capture time via
  /// `imageQuality`/`maxWidth` — cheap, and shrinks the file before it ever
  /// touches disk. [upload] applies a second, real pass via
  /// `flutter_image_compress` (re-encodes rather than just resampling at
  /// pick time), since `image_picker`'s own quality parameter behaves
  /// inconsistently across platforms/gallery sources.
  static Future<File?> pickFromCamera() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1600,
    );
    return x == null ? null : File(x.path);
  }

  static Future<File?> pickFromGallery() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );
    return x == null ? null : File(x.path);
  }

  static Future<File?> pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  static String fileTypeFor(File file) {
    final ext = file.path.toLowerCase();
    return ext.endsWith('.pdf') ? 'pdf' : 'image';
  }

  /// Re-encodes an image file at 70% JPEG quality, capped to 1600px on the
  /// long edge. PDFs pass through untouched — there's nothing to compress
  /// (and re-encoding a scanned PDF as an image would lose text quality).
  /// Falls back to the original file if compression fails for any reason
  /// (e.g. an unsupported image format) rather than blocking the upload.
  static Future<File> _compressIfImage(File file) async {
    if (fileTypeFor(file) == 'pdf') return file;

    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath =
          '${tempDir.path}/rx_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1600,
        minHeight: 1600,
        format: CompressFormat.jpeg,
      );
      if (result == null) return file;

      final compressed = File(result.path);
      // Guard against compression occasionally producing a larger file
      // than the source (rare, but possible for already-compressed
      // images) — use whichever is actually smaller.
      final originalSize = await file.length();
      final compressedSize = await compressed.length();
      return compressedSize < originalSize ? compressed : file;
    } catch (_) {
      return file;
    }
  }

  /// Uploads [file] to `order_prescriptions/{orderId}/...`, reports
  /// progress via [onProgress] (0.0–1.0), then writes the three
  /// patient-owned fields on the order doc. Throws
  /// [PrescriptionTooLargeException] before starting any network call if
  /// the file already exceeds [maxSizeBytes].
  static Future<String> upload({
    required String orderId,
    required File file,
    required void Function(double progress) onProgress,
  }) async {
    final fileType = fileTypeFor(file);
    final uploadFile = await _compressIfImage(file);

    final sizeBytes = await uploadFile.length();
    if (sizeBytes > maxSizeBytes) {
      throw PrescriptionTooLargeException(sizeBytes);
    }

    final fileName = uploadFile.path.split(Platform.pathSeparator).last;
    final storagePath =
        'order_prescriptions/$orderId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final ref = _storage.ref(storagePath);
    final task = ref.putFile(uploadFile);

    // Held so it can be cancelled in the `finally` below: without that, a
    // cancelled/abandoned upload leaves the progress listener attached, and
    // a failed upload surfaces the same error twice — once through `await
    // task` (handled by the caller) and once as an unhandled async error
    // from this subscription.
    final progressSub = task.snapshotEvents.listen(
      (snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      },
      onError: (_) {},
    );

    try {
      await task;
    } finally {
      await progressSub.cancel();
    }

    final downloadUrl = await ref.getDownloadURL();

    await _db.collection('orders').doc(orderId).update({
      'prescriptionUrl': downloadUrl,
      'prescriptionFileType': fileType,
      'prescriptionUploadedAt': FieldValue.serverTimestamp(),
    });

    return downloadUrl;
  }

  /// Same pick/compress/size-guard pipeline as [upload], but for attaching a
  /// prescription *before* an order exists — from the medicine browsing
  /// screen, not post-purchase order detail. There's no `orders/{orderId}`
  /// to scope the upload to yet, so this writes to a uid-keyed path
  /// (`pending_prescriptions/{uid}/...`, see storage.rules) instead and
  /// writes nothing to Firestore — the caller carries the returned URL
  /// forward into the order's own create-time write at checkout
  /// (cart_screen.dart), which firestore.rules permits freely (the
  /// self-update field allow-list only restricts *updates*, not the
  /// document's initial fields on create).
  static Future<({String url, String fileType, String fileName})> uploadPending({
    required String uid,
    required File file,
    required void Function(double progress) onProgress,
  }) async {
    final fileType = fileTypeFor(file);
    final uploadFile = await _compressIfImage(file);

    final sizeBytes = await uploadFile.length();
    if (sizeBytes > maxSizeBytes) {
      throw PrescriptionTooLargeException(sizeBytes);
    }

    final fileName = uploadFile.path.split(Platform.pathSeparator).last;
    final storagePath =
        'pending_prescriptions/$uid/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final ref = _storage.ref(storagePath);
    final task = ref.putFile(uploadFile);

    final progressSub = task.snapshotEvents.listen(
      (snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      },
      onError: (_) {},
    );

    try {
      await task;
    } finally {
      await progressSub.cancel();
    }

    final downloadUrl = await ref.getDownloadURL();
    return (url: downloadUrl, fileType: fileType, fileName: fileName);
  }

  /// Removes the prescription from the order (sets the three fields back
  /// to null). Best-effort Storage delete — a missing/already-deleted
  /// object never blocks clearing the Firestore fields.
  static Future<void> remove({required String orderId, required String? existingUrl}) async {
    if (existingUrl != null) {
      try {
        await _storage.refFromURL(existingUrl).delete();
      } catch (_) {
        // Already gone, or a transient error — the Firestore field clear
        // below is what actually matters to the UI/pharmacy side.
      }
    }
    await _db.collection('orders').doc(orderId).update({
      'prescriptionUrl': null,
      'prescriptionFileType': null,
      'prescriptionUploadedAt': null,
    });
  }
}
