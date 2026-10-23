// dart format width=100
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'user_signature_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// UserSignatureCache
//
// The technician's own saved signature, kept on this phone so a rapportino opened with no signal
// can still be pre-filled with it.
//
// The server is the record (`/api/users/me/signature`); this holds the bytes the device last saw
// there. It is written only by a fetch that succeeded or by a deliberate "salva questa firma per
// la prossima volta" that succeeded — never by an ordinary capture, so a signature drawn once is
// not silently retained.
//
// Keyed by the signed-in technician's internal user id, because several technicians sign in on the
// same phone and a signature is authorship: pre-filling one technician's rapportino with another's
// signature would be a false attribution, not a convenience.
// ══════════════════════════════════════════════════════════════════════════════

class UserSignatureCache {
  UserSignatureCache({required Future<Directory> Function() rootLoader})
    : _rootLoader = rootLoader;

  final Future<Directory> Function() _rootLoader;

  /// One `.png` per user id, under a `signatures/` folder. The id comes from the server (a Guid),
  /// but it is sanitised to a single path segment anyway — a cache must not be able to write
  /// outside its own folder because a server field held a slash.
  Future<File> _fileFor(String userId) async {
    final root = await _rootLoader();
    final dir = Directory('${root.path}/signatures');
    await dir.create(recursive: true);
    final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safe.png');
  }

  /// The cached signature for [userId], or null when this phone has none.
  ///
  /// Empty bytes read as a miss: they are what a crash between create and write leaves behind, and
  /// a zero-byte PNG pre-filling the pad would look like a bug in the signature pad itself. A read
  /// that throws is a miss too — the cache is an optimisation and never an error path.
  Future<Uint8List?> read(String userId) async {
    try {
      final file = await _fileFor(userId);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// Write-then-rename, so a crash mid-write leaves the previous copy rather than a half PNG.
  ///
  /// Best effort by design: the server already holds the signature, so a device that cannot write
  /// this file still pre-fills normally while online.
  Future<void> write(String userId, Uint8List bytes) async {
    try {
      final file = await _fileFor(userId);
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    } catch (_) {
      // See the doc comment: a failed cache write is not a failed save.
    }
  }
}

/// The bytes to pre-fill a rapportino's "Firma tecnico" block with.
///
/// Online the server's answer is the answer — including its 404, which means the technician has no
/// saved signature and must draw one: a stale local copy must not outvote that. Offline there is
/// no server to ask, and the last copy this phone saw is exactly what the technician would have
/// drawn again anyway.
///
/// A successful online fetch refreshes the cache, so the offline answer is as current as the last
/// time the technician was connected.
Future<Uint8List?> signatureToPrefill({
  required bool online,
  required String? userId,
  required UserSignatureApiClient api,
  required UserSignatureCache cache,
}) async {
  if (online) {
    final bytes = await api.fetchSavedSignatureContent();
    if (bytes != null && userId != null) await cache.write(userId, bytes);
    return bytes;
  }
  if (userId == null) return null;
  return cache.read(userId);
}

final userSignatureCacheProvider = Provider<UserSignatureCache>(
  (ref) => UserSignatureCache(rootLoader: getApplicationDocumentsDirectory),
);
