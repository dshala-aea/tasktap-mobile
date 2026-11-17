// dart format width=100
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/dio_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ReportPdfCache
//
// The report's PDF (`GET /api/Reports/{id}/pdf`) is the document a technician shows and hands to
// the customer — which happens on site, where the radio is worst. It used to be fetched into the
// temp directory on every tap, discarded, and unavailable the moment the signal dropped.
//
// So the last downloaded copy is kept in the app's documents directory, where the OS will not
// reclaim it. Freshness is not traded away for that: online, every resolve re-downloads and
// overwrites, because the server regenerates the PDF whenever the report changes. The cached copy
// is served only when the network is gone — or when a download fails, since on site an hour-old
// PDF beats no document at all.
// ══════════════════════════════════════════════════════════════════════════════

/// Why a PDF could not be produced.
enum ReportPdfFailure {
  /// Offline and this device has never downloaded this report's PDF.
  notDownloaded,

  /// Online, the download failed, and there was no earlier copy to fall back to.
  downloadFailed,
}

class ReportPdfUnavailable implements Exception {
  const ReportPdfUnavailable(this.reason);

  final ReportPdfFailure reason;

  @override
  String toString() => 'ReportPdfUnavailable(${reason.name})';
}

/// Fetches the PDF bytes for one report. Injected so the cache can be tested without a server.
typedef ReportPdfDownload = Future<List<int>> Function(String reportId);

class ReportPdfCache {
  ReportPdfCache({
    required ReportPdfDownload download,
    required Future<Directory> Function() rootLoader,
  }) : _download = download,
       _rootLoader = rootLoader;

  final ReportPdfDownload _download;
  final Future<Directory> Function() _rootLoader;

  Directory? _root;

  Future<Directory> _dir() async {
    final root = _root ??= await _rootLoader();
    final pdfs = Directory(p.join(root.path, 'report_pdfs'));
    if (!await pdfs.exists()) await pdfs.create(recursive: true);
    return pdfs;
  }

  /// Ids are guids; escaping keeps a hostile one from writing outside the cache directory.
  static String _fileName(String reportId) =>
      'report-${reportId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';

  Future<File> _file(String reportId) async =>
      File(p.join((await _dir()).path, _fileName(reportId)));

  /// The copy already on disk, or null. A zero-byte file is a write that never finished, so it is
  /// deleted and reported as absent — never served as a blank document in front of a customer.
  Future<File?> cached(String reportId) async {
    final file = await _file(reportId);
    if (!await file.exists()) return null;
    if (await file.length() == 0) {
      await file.delete();
      return null;
    }
    return file;
  }

  /// The PDF for [reportId], downloading it when [online] and falling back to the cached copy.
  ///
  /// Throws [ReportPdfUnavailable] when neither path can produce a file; a download failure that
  /// does leave a cached copy is not an error — the caller gets the older document.
  Future<File> resolve(String reportId, {required bool online}) async {
    final target = await _file(reportId);

    if (!online) {
      final file = await cached(reportId);
      if (file != null) return file;
      throw const ReportPdfUnavailable(ReportPdfFailure.notDownloaded);
    }

    try {
      final bytes = await _download(reportId);
      if (bytes.isEmpty) throw StateError('empty PDF response');
      // Write-then-rename: a half-written file must never be served as the report it is named after.
      final tmp = File('${target.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
      return target;
    } catch (_) {
      final file = await cached(reportId);
      if (file != null) return file;
      throw const ReportPdfUnavailable(ReportPdfFailure.downloadFailed);
    }
  }
}

/// Wired to the real endpoint. `GET /api/Reports/{id}/pdf` is generated server-side on demand, so
/// every online resolve is the current document, not a stored snapshot.
final reportPdfCacheProvider = Provider<ReportPdfCache>((ref) {
  final dio = ref.watch(dioProvider);
  return ReportPdfCache(
    download: (reportId) async {
      final response = await dio.get<List<int>>(
        '/api/Reports/$reportId/pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? const <int>[];
    },
    rootLoader: getApplicationDocumentsDirectory,
  );
});
