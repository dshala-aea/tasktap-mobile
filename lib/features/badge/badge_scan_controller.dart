// ══════════════════════════════════════════════════════════════════════════════
// BadgeScanController — the leader's continuous badge scan session
//
// Holds an in-memory, newest-first list of scan attempts for as long as the scan screen is open
// (autoDispose: leaving the screen drops it). Online-only: nothing is queued. The scanned token is
// passed straight to the API and is never logged, stored in an entry or persisted.
//
//   • the same code seen again within [badgeScanDedupeWindow] is ignored (a camera reports a code
//     many times a second while it sits in frame);
//   • codes arriving while a request is in flight are ignored;
//   • every attempt gets a fresh UUID v4 clientScanId.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/badge/badge_api_client.dart';
import '../../data/badge/badge_models.dart';

/// How long a code that FAILED to get a server answer is ignored before it may be retried.
const Duration badgeScanDedupeWindow = Duration(seconds: 3);

/// How long a code that already got ANY server answer stays suppressed: the token is single-use
/// for 60s, so re-sending it can never change the answer (it would only add a spurious
/// "Codice già usato" on top of the real result). 70s = token life plus margin.
const Duration badgeScanTokenLife = Duration(seconds: 70);

/// One scan attempt as the leader sees it. Exactly one of the three payloads is set.
class BadgeScanEntry {
  const BadgeScanEntry.outcome(this.at, BadgeScanOutcome this.outcome)
    : error = null,
      unexpectedError = null;
  const BadgeScanEntry.failure(this.at, BadgeApiException this.error)
    : outcome = null,
      unexpectedError = null;

  /// Anything that is not a [BadgeApiException] (malformed body, TypeError, ...). Only the type
  /// name is kept: the raw object (e.g. a DioException) could reference the request body, which
  /// carries the token.
  const BadgeScanEntry.unexpected(this.at, String this.unexpectedError)
    : outcome = null,
      error = null;

  final DateTime at;
  final BadgeScanOutcome? outcome;
  final BadgeApiException? error;
  final String? unexpectedError;
}

/// Clock seam, overridden in tests.
final badgeScanClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// True while a scan request is in flight for the cantiere (drives the "Verifica in corso" line).
final badgeScanInFlightProvider = StateProvider.autoDispose.family<bool, String>((ref, id) => false);

class _Handled {
  _Handled(this.at, {required this.answered});
  final DateTime at;
  bool answered;
}

class BadgeScanController extends AutoDisposeFamilyNotifier<List<BadgeScanEntry>, String> {
  // Handled codes keyed by the SHA-256 of the scanned string, so no raw token is retained here.
  // Private to this notifier, never exposed or logged, cleared on dispose.
  final Map<String, _Handled> _handled = {};
  bool _inFlight = false;
  bool _disposed = false;
  static const _uuid = Uuid();

  @override
  List<BadgeScanEntry> build(String cantiereId) {
    ref.onDispose(() {
      _disposed = true;
      _handled.clear();
    });
    return const [];
  }

  bool get inFlight => _inFlight;

  static bool _answered(BadgeApiException e) {
    final s = e.statusCode;
    return !e.isOffline && s != null && s < 500;
  }

  Future<void> onCode(String code) async {
    if (code.isEmpty || _inFlight || _disposed) return;
    final now = ref.read(badgeScanClockProvider)();
    _handled.removeWhere((_, h) => now.difference(h.at) >= badgeScanTokenLife);
    final key = sha256.convert(utf8.encode(code)).toString();
    final prior = _handled[key];
    if (prior != null) {
      if (prior.answered) return;
      if (now.difference(prior.at) < badgeScanDedupeWindow) return;
    }
    final mark = _Handled(now, answered: false);
    _handled[key] = mark;
    _inFlight = true;
    ref.read(badgeScanInFlightProvider(arg).notifier).state = true;
    BadgeScanEntry entry;
    try {
      final outcome = await ref
          .read(badgeApiClientProvider)
          .scan(cantiereId: arg, token: code, clientScanId: _uuid.v4());
      mark.answered = true;
      entry = BadgeScanEntry.outcome(now, outcome);
    } on BadgeApiException catch (e) {
      mark.answered = _answered(e);
      entry = BadgeScanEntry.failure(now, e);
    } catch (e) {
      // Never let an exception escape and never read as success: a malformed body, a TypeError.
      entry = BadgeScanEntry.unexpected(now, e.runtimeType.toString());
    } finally {
      _inFlight = false;
    }
    if (_disposed) return;
    ref.read(badgeScanInFlightProvider(arg).notifier).state = false;
    state = [entry, ...state];
  }
}

final badgeScanControllerProvider = NotifierProvider.autoDispose
    .family<BadgeScanController, List<BadgeScanEntry>, String>(BadgeScanController.new);
