// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/auth_providers.dart' show authStateProvider;
import '../api/dio_client.dart';
import 'punch_snapshot.dart';
import 'worklog_api_client.dart';

final punchSnapshotStoreProvider = Provider<PunchSnapshotStore>((ref) => PunchSnapshotStore());

/// The server's last answer about this person's shift (EPIC 29). Null until the server has answered
/// once on this phone; then the Timbra screen shows it with the unanswered taps laid on top.
///
/// Remembered on disk per session, so a cold start with no network still shows what the server last
/// said instead of guessing from the local log.
class PunchSnapshotNotifier extends Notifier<PunchSnapshot?> {
  @override
  PunchSnapshot? build() {
    final sessionId = ref.watch(authStateProvider).value?.id;
    unawaited(_restore(sessionId));
    return null;
  }

  Future<void> _restore(String? sessionId) async {
    final saved = await ref.read(punchSnapshotStoreProvider).read(sessionId);
    // A fresher answer may have arrived while the disk was read: never overwrite it with the old one.
    if (saved != null && state == null && ref.mounted) state = saved;
  }

  /// Replaces the snapshot with what the server just said, and remembers it.
  void replace(PunchSnapshot snapshot) {
    state = snapshot;
    final sessionId = ref.read(authStateProvider).value?.id;
    if (sessionId != null) unawaited(ref.read(punchSnapshotStoreProvider).write(sessionId, snapshot));
  }
}

final punchSnapshotProvider = NotifierProvider<PunchSnapshotNotifier, PunchSnapshot?>(
  PunchSnapshotNotifier.new,
);

/// Replaces the snapshot with `GET /worklog/state`. This is what the reconciler became for the unified
/// pipeline: it no longer writes synthetic, marked events into the local log to make it agree with the
/// server; it just takes the server's answer. Errors are swallowed (offline is the normal condition of
/// a phone in the field): without an answer the snapshot stays as it was.
class PunchSnapshotRefresher {
  PunchSnapshotRefresher({
    required Future<PunchStateDto> Function() fetch,
    required void Function(PunchSnapshot) onSnapshot,
  }) : _fetch = fetch,
       _onSnapshot = onSnapshot;

  final Future<PunchStateDto> Function() _fetch;
  final void Function(PunchSnapshot) _onSnapshot;

  bool _running = false;

  Future<void> refresh() async {
    if (_running) return;
    _running = true;
    try {
      _onSnapshot((await _fetch()).toSnapshot());
    } catch (_) {
      // Keep the last snapshot.
    } finally {
      _running = false;
    }
  }
}

final punchSnapshotRefresherProvider = Provider<PunchSnapshotRefresher>((ref) {
  final api = WorklogApiClient(ref.watch(dioProvider));
  return PunchSnapshotRefresher(
    fetch: api.fetchPunchState,
    onSnapshot: (s) => ref.read(punchSnapshotProvider.notifier).replace(s),
  );
});
