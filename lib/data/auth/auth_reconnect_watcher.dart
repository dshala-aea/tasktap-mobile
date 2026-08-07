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

import '../../presentation/providers/auth_providers.dart';
import '../sync/connectivity_provider.dart';

/// Call once on app start (e.g. in HomeShell.initState via addPostFrameCallback).
/// Registers the offline→online reconnect hook for the auth session.
void initAuthReconnectWatcher(WidgetRef ref) {
  final connectivity = ref.read(connectivityProvider.notifier);
  connectivity.onReconnect(() {
    ref.read(authRepositoryProvider).refreshSession();
  });
}
