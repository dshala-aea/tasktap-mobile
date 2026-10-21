// dart format width=100
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/dio_client.dart';
import '../local/app_database.dart';
import '../sync/connectivity_provider.dart' show isOnlineProvider, onUnmeteredWifi;
import '../sync/sync_service.dart' show appDatabaseProvider;

// ══════════════════════════════════════════════════════════════════════════════
// AttachmentContentCache
//
// Sync mirrors attachment METADATA (O-8a), never the bytes: a photo, signature or PDF that lives
// on the server is a row with a name, a size and a content route. Showing it on site needs the
// bytes, so they are kept here — in the app's documents directory, not temp: the OS reclaims temp
// at will, and this cache is the only reason a server file can be shown offline at all.
//
// Keying is `allegatoId` + `contentHash`, falling back to `allegatoId` + size when the server holds
// no hash (files uploaded before the column existed). The id alone would be wrong: an allegato can
// be replaced, and a hash-named file can never be mistaken for newer content. One file per id
// survives — writing a new key deletes the id's older ones.
//
// The cap is 500 MB (decision D-4 of the 2026-10-21 offline audit). Eviction is LRU by file mtime
// and a hit touches the file, so what a technician actually opens is what survives.
// ══════════════════════════════════════════════════════════════════════════════

/// `AllegatoEntityTypeEnum` as the client stores it: the wire sends ordinals into
/// `report_allegati.entityType`, so both the sync writer and every mirror reader must agree on
/// these values without inventing a Dart enum the API does not expose.
abstract final class AllegatoEntityType {
  static const int ticket = 0;
  static const int report = 1;
  static const int materiale = 2;
}

/// What identifies one cached file. A record, so providers can use it as a family key with
/// structural equality rather than an identity-based class.
typedef AttachmentRef = ({
  String allegatoId,
  String? contentHash,
  int sizeBytes,
  String url,
});

class AttachmentContentCache {
  AttachmentContentCache({
    required this.dio,
    required Future<Directory> Function() rootLoader,
    this.maxBytes = 500 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _rootLoader = rootLoader,
       _clock = clock ?? DateTime.now;

  final Dio dio;
  final int maxBytes;
  final Future<Directory> Function() _rootLoader;
  final DateTime Function() _clock;

  Directory? _root;

  Future<Directory> _dir() async {
    final root = _root ??= await _rootLoader();
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  /// Ids are guids and the stamp is hex/digits, so the name needs no escaping.
  static String _fileName(String allegatoId, String? contentHash, int? sizeBytes) {
    final stamp = (contentHash != null && contentHash.isNotEmpty)
        ? contentHash
        : 'size-${sizeBytes ?? 0}';
    return '${allegatoId}__$stamp';
  }

  static String _prefix(String allegatoId) => '${allegatoId}__';

  /// The cached file, or null. [touch] marks it as just used for the LRU; a caller that is only
  /// checking (the prefetcher) passes false so a sweep does not keep old files alive for ever.
  Future<File?> lookup({
    required String allegatoId,
    String? contentHash,
    int? sizeBytes,
    bool touch = true,
  }) async {
    final dir = await _dir();
    final file = File(p.join(dir.path, _fileName(allegatoId, contentHash, sizeBytes)));
    if (!await file.exists()) return null;
    // A zero-byte file is a write that never finished: treat it as absent rather than as content.
    if (await file.length() == 0) {
      await file.delete();
      return null;
    }
    if (touch) await _touch(file);
    return file;
  }

  /// The cached file, downloading it first when absent. Throws [DioException] on a failed request
  /// (nothing is written) and [StateError] on an empty body.
  Future<File> ensure(AttachmentRef ref) async {
    final cached = await lookup(
      allegatoId: ref.allegatoId,
      contentHash: ref.contentHash,
      sizeBytes: ref.sizeBytes,
    );
    if (cached != null) return cached;

    final response = await dio.get<List<int>>(
      ref.url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('empty attachment response');
    }

    final dir = await _dir();
    final target = File(p.join(dir.path, _fileName(ref.allegatoId, ref.contentHash, ref.sizeBytes)));
    // Write-then-rename: a half-written file must never be served as the photo it is named after.
    final tmp = File('${target.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    await _deleteOtherKeys(dir, ref.allegatoId, keep: target.path);
    await evictIfNeeded();
    return target;
  }

  Future<int> totalBytes() async {
    final dir = await _dir();
    var total = 0;
    await for (final entry in dir.list()) {
      if (entry is! File || entry.path.endsWith('.part')) continue;
      total += await entry.length();
    }
    return total;
  }

  /// Deletes oldest-first until the cache fits [maxBytes]. Returns how many files went.
  Future<int> evictIfNeeded() async {
    final dir = await _dir();
    final entries = <({File file, int size, DateTime modified})>[];
    await for (final entry in dir.list()) {
      if (entry is! File || entry.path.endsWith('.part')) continue;
      final stat = await entry.stat();
      entries.add((file: entry, size: stat.size, modified: stat.modified));
    }
    var total = entries.fold<int>(0, (sum, e) => sum + e.size);
    if (total <= maxBytes) return 0;

    entries.sort((a, b) => a.modified.compareTo(b.modified));
    var removed = 0;
    for (final entry in entries) {
      if (total <= maxBytes) break;
      await entry.file.delete();
      total -= entry.size;
      removed++;
    }
    return removed;
  }

  /// An allegato that was replaced has a new key; the old bytes are unreachable and are deleted
  /// here rather than lingering until eviction notices them.
  Future<void> _deleteOtherKeys(Directory dir, String allegatoId, {required String keep}) async {
    final prefix = _prefix(allegatoId);
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      if (!p.basename(entry.path).startsWith(prefix)) continue;
      if (entry.path == keep) continue;
      await entry.delete();
    }
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(_clock());
    } catch (_) {
      // Some filesystems refuse; a missed touch only makes the file look older than it is.
    }
  }
}

/// Fills the cache right after a sync, on Wi-Fi only.
///
/// The cache alone would only ever hold files a technician opened by hand, which on a site visit
/// is the same as holding none. Decision D-4 asks for the opposite: after sync, download the
/// in-scope attachments in the background — but never over mobile data, since a report's photos
/// can easily be tens of megabytes.
class AttachmentPrefetcher {
  AttachmentPrefetcher({
    required this.db,
    required this.cache,
    required Future<bool> Function() canPrefetch,
  }) : _canPrefetch = canPrefetch;

  final AppDatabase db;
  final AttachmentContentCache cache;
  final Future<bool> Function() _canPrefetch;

  /// Downloads what is missing and returns how many files landed. Stops at the cache cap (no
  /// point thrashing by downloading what eviction would immediately remove) and on the first
  /// network error (the next sync retries); a single bad file is skipped.
  Future<int> run() async {
    if (!await _canPrefetch()) return 0;

    final rows =
        await (db.select(db.reportAllegati)..where(
              (a) =>
                  a.isPendingUpload.equals(false) &
                  a.isActive.equals(true) &
                  a.url.equals('').not(),
            ))
            .get();

    var used = await cache.totalBytes();
    var fetched = 0;
    for (final a in rows) {
      if (used >= cache.maxBytes) break;
      // The key must be the one a READER will use. Report allegati readers hold the row and pass
      // its hash; the ticket Allegati tab reads the server's attachment DTO, which carries no hash
      // (ticket attachments predate the column), so it keys by id + size. Prefetching a ticket
      // file under its hash would fill the cache with a file nothing ever looks up.
      final ref = (
        allegatoId: a.id,
        contentHash: a.entityType == AllegatoEntityType.ticket ? null : a.contentHash,
        sizeBytes: a.sizeBytes,
        url: a.url,
      );
      // No touch: a prefetch sweep must not make an unopened file look recently used.
      final cached = await cache.lookup(
        allegatoId: ref.allegatoId,
        contentHash: ref.contentHash,
        sizeBytes: ref.sizeBytes,
        touch: false,
      );
      if (cached != null) continue;

      try {
        final file = await cache.ensure(ref);
        used += await file.length();
        fetched++;
      } on DioException {
        break;
      } catch (_) {
        continue;
      }
    }
    return fetched;
  }
}

/// The app-wide cache: `<documents>/attachments/`.
final attachmentContentCacheProvider = Provider<AttachmentContentCache>((ref) {
  return AttachmentContentCache(
    dio: ref.watch(dioProvider),
    rootLoader: () async {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, 'attachments'));
    },
  );
});

/// Filled after every successful sync — see [AttachmentPrefetcher] for why it is Wi-Fi-only.
final attachmentPrefetcherProvider = Provider<AttachmentPrefetcher>((ref) {
  return AttachmentPrefetcher(
    db: ref.watch(appDatabaseProvider),
    cache: ref.watch(attachmentContentCacheProvider),
    canPrefetch: onUnmeteredWifi,
  );
});

/// The bytes for one attachment, for anything that draws it: the cached file when there is one,
/// the download when there is network, and null when there is neither.
///
/// Null rather than an error on the offline miss: a thumbnail with no bytes yet is a normal state
/// on a phone that has not synced over Wi-Fi, and every caller already has a placeholder for it.
final attachmentFileProvider = FutureProvider.autoDispose
    .family<File?, AttachmentRef>((ref, attachment) async {
      final cache = ref.watch(attachmentContentCacheProvider);
      final cached = await cache.lookup(
        allegatoId: attachment.allegatoId,
        contentHash: attachment.contentHash,
        sizeBytes: attachment.sizeBytes,
      );
      if (cached != null) return cached;
      if (!ref.watch(isOnlineProvider)) return null;
      return cache.ensure(attachment);
    });
