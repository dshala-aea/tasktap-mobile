// dart format width=100
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// ══════════════════════════════════════════════════════════════════════════════
// CaptureStore — an app-owned, durable home for everything the technician picks or captures
//
// Why it exists (audit finding F6 / offline slice O-3 P0-5): `image_picker` and `file_picker`
// hand back a path in the OS cache / temp directory, and that is the path the app used to persist
// and later upload. Nothing guarantees that file is still there by upload time — an OS cache
// purge, a "free up space" action or a low-storage cleanup turns a queued photo into a permanent
// "File non trovato" at submit, which is exactly the one moment the technician can no longer
// re-take it (the customer has signed and left).
//
// So a pick is copied into `<app documents>/captures/` immediately, and the durable path is what
// the draft row / pending attachment row / UI holds. Documents (unlike the cache dir) are the
// app's own storage: the OS does not purge it.
//
// Files are deliberately NOT deleted here. A report allegato stays referenced by the draft and by
// the read-only view (which renders it from this path) long after its upload is acknowledged, and
// a delete-on-upload would blank the thumbnail. Housekeeping (a size budget / sweep for captures
// no row references) is a separate concern; deleting eagerly is how you lose a photo the server
// never actually stored.
// ══════════════════════════════════════════════════════════════════════════════

/// A picked/captured file, now living in the app's own storage.
class CapturedFile {
  const CapturedFile({
    required this.path,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
  });

  /// Durable path inside the app documents directory — never a picker temp path.
  final String path;

  /// The user-facing name (`IMG_0001.jpg`, `rapportino.pdf`), kept for display and upload.
  final String fileName;

  /// The MIME type derived from [fileName], e.g. `image/jpeg` or `application/pdf`.
  final String contentType;

  final int sizeBytes;
}

class CaptureStore {
  CaptureStore(this.directory);

  /// The app documents directory (survives restarts, unlike the temp dir pickers write to).
  static Future<CaptureStore> forApp() async {
    final docs = await getApplicationDocumentsDirectory();
    return CaptureStore(Directory(p.join(docs.path, folderName)));
  }

  static const String folderName = 'captures';

  final Directory directory;

  /// Copies [sourcePath] into this store under a fresh id and returns the durable file.
  ///
  /// Throws on any failure (no space, unreadable source, permissions): the caller must treat that
  /// as "the pick did not happen" and say so — never persist or queue the source's temp path,
  /// which is the whole bug this exists to prevent.
  Future<CapturedFile> save(
    String sourcePath, {
    required String fileName,
    String? contentType,
  }) async {
    final source = File(sourcePath);
    final base = p.basename(fileName.isEmpty ? sourcePath : fileName);

    await directory.create(recursive: true);
    // Keep the extension: the submit path and the PDF viewer both key off it. Anything weird is
    // dropped rather than propagated into a file name.
    final ext = _safeExtension(base);
    final target = File(p.join(directory.path, '${const Uuid().v4()}$ext'));
    await source.copy(target.path);

    return CapturedFile(
      path: target.path,
      fileName: base,
      contentType: contentType ?? contentTypeForFileName(base),
      sizeBytes: await target.length(),
    );
  }

  static String _safeExtension(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    // A short alphanumeric suffix only: ".pdf", ".jpg", or nothing.
    return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '';
  }

  /// Deletes a capture that was refused before anything referenced it (today: the 10 MB ticket
  /// attachment cap). Never call this for a file a draft or pending row points at — the read-only
  /// view renders from this path (see the class comment). Refuses paths outside this store, so a
  /// bad [CapturedFile] can never delete an arbitrary file.
  Future<void> discard(CapturedFile file) async {
    if (!p.isWithin(directory.path, file.path)) return;
    final target = File(file.path);
    if (await target.exists()) await target.delete();
  }
}

/// The MIME type a picked file actually is, from its extension.
///
/// Previously every image was hard-coded `image/jpeg`, which mislabels a PNG or a HEIC the gallery
/// handed back and makes the server store a wrong content type (the attachment then renders
/// wrong, or is refused by a stricter MIME allow-list). [fallback] is for the call sites that know
/// what kind of file they asked for: a camera/gallery pick with `imageQuality` set is re-encoded
/// to JPEG by the plugin, so an extensionless or unknown-named pick is still `image/jpeg`.
String contentTypeForFileName(
  String fileName, {
  String fallback = 'application/octet-stream',
}) {
  switch (p.extension(fileName).toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    case '.gif':
      return 'image/gif';
    case '.heic':
    case '.heif':
      return 'image/heic';
    case '.pdf':
      return 'application/pdf';
    default:
      return fallback;
  }
}

/// The app-wide capture store. `FutureProvider` because resolving the documents directory is
/// async (`path_provider`); overridable in tests with a store pointed at a temp directory.
final captureStoreProvider = FutureProvider<CaptureStore>((ref) => CaptureStore.forApp());
