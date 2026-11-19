import 'package:firebase_storage/firebase_storage.dart';

/// Verification documents are stored as Firebase Storage PATHS, never as
/// tokenised download URLs: a `?token=` URL bypasses Storage rules, so one
/// stored in a world-readable profile doc would expose the file to every
/// signed-in user. The owner/admin resolve a fresh URL on demand through the
/// authenticated SDK instead (`getDownloadURL` needs Storage read permission,
/// which `storage.rules` grants only to the owner and admins).
///
/// Legacy entries (written before this change) still hold an http(s) URL and
/// are returned unchanged until the migration script rewrites them.
bool isHttpUrl(String value) {
  final v = value.trim().toLowerCase();
  return v.startsWith('http://') || v.startsWith('https://');
}

final Map<String, Future<String>> _urlCache = <String, Future<String>>{};

/// Returns a viewable URL for [pathOrUrl]: legacy http(s) values pass through,
/// anything else is treated as a Storage path and resolved (cached per path).
/// A failed resolution is not cached, so a retry hits the network again.
Future<String> resolveDocumentUrl(String pathOrUrl) {
  final value = pathOrUrl.trim();
  if (value.isEmpty) return Future<String>.error('No document path');
  if (isHttpUrl(value)) return Future<String>.value(value);
  return _urlCache.putIfAbsent(value, () {
    final future = FirebaseStorage.instance.ref(value).getDownloadURL();
    future.catchError((Object _) {
      _urlCache.remove(value);
      return '';
    });
    return future;
  });
}
