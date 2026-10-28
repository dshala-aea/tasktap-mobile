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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/badge/badge_api_client.dart';
import '../../data/badge/badge_models.dart';

/// How long a code already handled is ignored when it shows up again.
const Duration badgeScanDedupeWindow = Duration(seconds: 3);

/// One scan attempt as the leader sees it. Exactly one of the three payloads is set.
class BadgeScanEntry {
  const BadgeScanEntry.outcome(this.at, BadgeScanOutcome this.outcome)
    : error = null,
      unexpectedError = null;
  const BadgeScanEntry.failure(this.at, BadgeApiException this.error)
    : outcome = null,
      unexpectedError = null;

  /// Anything that is not a [BadgeApiException] (malformed body, TypeError, ...).
  const BadgeScanEntry.unexpected(this.at, Object this.unexpectedError)
    : outcome = null,
      error = null;

  final DateTime at;
  final BadgeScanOutcome? outcome;
  final BadgeApiException? error;
  final Object? unexpectedError;
}

/// Clock seam, overridden in tests.
final badgeScanClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class BadgeScanController extends AutoDisposeFamilyNotifier<List<BadgeScanEntry>, String> {
  String? _lastCode;
  DateTime? _lastCodeAt;
  bool _inFlight = false;
  bool _disposed = false;
  static const _uuid = Uuid();

  @override
  List<BadgeScanEntry> build(String cantiereId) {
    ref.onDispose(() => _disposed = true);
    return const [];
  }

  /// True while a scan request is in flight (new codes are ignored meanwhile).
  bool get inFlight => _inFlight;

  Future<void> onCode(String code) async {
    if (code.isEmpty || _inFlight) return;
    final now = ref.read(badgeScanClockProvider)();
    final lastAt = _lastCodeAt;
    if (code == _lastCode && lastAt != null && now.difference(lastAt) < badgeScanDedupeWindow) {
      return;
    }
    _lastCode = code;
    _lastCodeAt = now;
    _inFlight = true;
    BadgeScanEntry entry;
    try {
      final outcome = await ref
          .read(badgeApiClientProvider)
          .scan(cantiereId: arg, token: code, clientScanId: _uuid.v4());
      entry = BadgeScanEntry.outcome(now, outcome);
    } on BadgeApiException catch (e) {
      entry = BadgeScanEntry.failure(now, e);
    } catch (e) {
      // Never let an exception escape and never read as success: a malformed body, a TypeError.
      entry = BadgeScanEntry.unexpected(now, e);
    } finally {
      _inFlight = false;
    }
    if (_disposed) return;
    state = [entry, ...state];
  }
}

final badgeScanControllerProvider = NotifierProvider.autoDispose
    .family<BadgeScanController, List<BadgeScanEntry>, String>(BadgeScanController.new);
