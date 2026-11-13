// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// AuthReconnectWatcher
//
// A cold start with no signal keeps the technician signed-in-but-offline (see
// ZitadelAuthRepository._restore): the stored refresh token is kept and the
// last-known identity is shown, but there is no valid access token yet. This
// registers the offline→online reconnect hook so the real token refresh is
// retried the moment connectivity returns, instead of waiting for the next
// API call to bounce off a 401 (AuthInterceptor already handles that path
// too — this just makes the recovery immediate rather than incidental).
//
// Mirrors submission_queue_watcher.dart / timbra_sync_watcher.dart.
//
// Call [initAuthReconnectWatcher] once from the root widget (after auth).
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth/auth_failure.dart';
import '../../presentation/providers/auth_providers.dart';
import '../sync/connectivity_provider.dart';

/// Call once on app start (e.g. in HomeShell.initState via addPostFrameCallback).
/// Registers the offline→online reconnect hook for the auth session.
///
/// Returns the cancel function to invoke from the caller's `dispose()` — see
/// timbra_sync_watcher.dart's doc comment for why this matters.
VoidCallback initAuthReconnectWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  return connectivity.onReconnect(() async {
    final result = await ref.read(authRepositoryProvider).refreshSession();
    // A confirmed SessionExpired is the same ending the 401 interceptor uses: drop credentials
    // and keep the local data, so the next sign-in can resume the queue (same account) or ask
    // explicitly before discarding it (different account). Network/unknown failures leave the
    // session untouched so the offline-first path can continue.
    if (result.failure is SessionExpired) {
      await ref.read(sessionEnderProvider).endForced();
    }
  });
}
