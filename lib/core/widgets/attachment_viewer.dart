// dart format width=100
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import 'app_toast.dart';
import 'screen_header.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';

// ══════════════════════════════════════════════════════════════════════════════
// openAttachment
//
// The one seam every attachment tap (ticket Allegati tab, a rapportino signature, a rapportino
// photo) goes through, so the image-vs-everything-else decision lives in exactly one place.
// Swapping the non-image branch for an in-app PDF renderer later is a change to this one
// function, not to every call site.
//
// [dio] is the caller's own `dioProvider` instance — deliberately, not a fresh bare client:
// `TicketAttachmentDto.contentUrl` is a path relative to the TaskTap API
// (`/api/tickets/{id}/attachments/{id}/content`, confirmed against the ticket detail tests'
// fixtures), not an external presigned storage URL, so it needs the same bearer token and
// baseUrl every other API call already gets from `AuthInterceptor` — a bare `Dio()` here would
// 401 or fail to resolve the relative path at all.
//
// [localPath] takes priority when present — an offline-picked photo or signature not yet
// uploaded has no [url] at all yet, and reading a local file needs no network regardless.
// ══════════════════════════════════════════════════════════════════════════════

Future<void> openAttachment(
  BuildContext context, {
  required Dio dio,
  required String fileName,
  required String contentType,
  String? url,
  String? localPath,
}) async {
  if (contentType.startsWith('image/')) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenImageViewer(
          dio: dio,
          fileName: fileName,
          url: url,
          localPath: localPath,
        ),
      ),
    );
    return;
  }

  // Already on this device (offline-picked, not yet uploaded) — open directly, nothing to fetch.
  if (localPath != null && localPath.isNotEmpty) {
    final result = await OpenFilex.open(localPath);
    if (result.type != ResultType.done && context.mounted) {
      showAppToast(
        context,
        message: 'Impossibile aprire il file: ${result.message}',
        tone: ToastTone.error,
      );
    }
    return;
  }

  if (url == null || url.isEmpty) {
    showAppToast(context, message: 'File non disponibile.', tone: ToastTone.error);
    return;
  }

  try {
    final bytes = await _fetchBytes(dio, url);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done && context.mounted) {
      showAppToast(
        context,
        message: 'Impossibile aprire il file: ${result.message}',
        tone: ToastTone.error,
      );
    }
  } on DioException catch (e) {
    if (!context.mounted) return;
    final offline =
        e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout;
    showAppToast(
      context,
      message: offline
          ? 'Nessuna connessione — riprova quando sei online.'
          : 'Impossibile scaricare il file. Riprova più tardi.',
      tone: ToastTone.error,
    );
  } catch (_) {
    if (!context.mounted) return;
    showAppToast(context, message: 'Impossibile scaricare il file.', tone: ToastTone.error);
  }
}

Future<List<int>> _fetchBytes(Dio dio, String url) async {
  final response = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
  final bytes = response.data;
  if (bytes == null) throw StateError('empty attachment response');
  return bytes;
}

// ══════════════════════════════════════════════════════════════════════════════
// _FullscreenImageViewer
// ══════════════════════════════════════════════════════════════════════════════

/// Full-screen pinch-zoom-pan image view. [InteractiveViewer] is stdlib — no new dependency for
/// what is, functionally, the whole ask for images. The header bar is the app's own
/// [ScreenHeaderBar] (every screen's convention — a raw [AppBar] is the one thing
/// `app_palette_test.dart`'s own repo-wide scan refuses), so it flips with the app theme like
/// every other screen's chrome; only the body — the image itself — stays black regardless of
/// theme, the same "content is dark, chrome recedes" reasoning every OS photo viewer uses.
///
/// Fetches its own bytes (through [dio], not `Image.network`) rather than taking them as a
/// constructor param — `Image.network` has no hook for a caller-supplied [Dio]/auth header, and
/// a remote attachment URL needs one (see [openAttachment]'s own doc comment). A local file
/// needs no fetch at all and renders directly.
class _FullscreenImageViewer extends StatelessWidget {
  const _FullscreenImageViewer({required this.dio, required this.fileName, this.url, this.localPath});

  final Dio dio;
  final String fileName;
  final String? url;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final hasLocal = localPath != null && localPath!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: ScreenHeaderBar(title: fileName),
      body: Center(
        child: hasLocal
            ? InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.file(File(localPath!), errorBuilder: _errorBuilder),
              )
            : (url == null || url!.isEmpty)
            ? _errorBuilder(context, StateError('no source'), null)
            : FutureBuilder<List<int>>(
                future: _fetchBytes(dio, url!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const CircularProgressIndicator(color: Colors.white);
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return _errorBuilder(context, snapshot.error ?? StateError('empty'), null);
                  }
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.memory(
                      Uint8List.fromList(snapshot.data!),
                      errorBuilder: _errorBuilder,
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _errorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.imageOff, size: 48, color: AppColors.WHITE.withAlpha(150)),
        const SizedBox(height: 12),
        Text(
          'Impossibile caricare l\'immagine',
          style: TextStyle(color: AppColors.WHITE.withAlpha(200), fontFamily: 'Inter'),
        ),
      ],
    );
  }
}
