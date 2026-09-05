// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// RealtimeConnection
//
// One persistent SignalR connection to NotificationHub's tenant-broadcast
// "ReceiveEvent" messages, regardless of how many screens are open. Auth is via an
// accessTokenFactory, which signalr_hub appends as ?access_token=<jwt> on the
// websocket handshake URL — matching Program.cs's existing
// JwtBearerEvents.OnMessageReceived handling for the /api/hubs path prefix (the
// backend already built this mechanism for the hub, this just points at it).
// Using a factory rather than baking the token into the URL once means every
// reconnect attempt (automatic or explicit) picks up the *current* token instead
// of replaying whatever was valid when connect() was first called.
//
// Best-effort by design: if the connection never succeeds, or drops and can't
// reconnect, the app must keep working exactly as it does today via existing
// polling/manual refresh. Nothing here may become a hard dependency for any
// screen to function — every failure path below swallows its error rather than
// throwing, and `events` stays a plain broadcast stream nobody is forced to
// listen to.
//
// This class is intentionally Riverpod-agnostic (constructor takes a plain
// `String Function()` token callback) so it stays independently testable; the
// wiring below (`realtimeConnectionProvider`) is what supplies that callback
// from `currentUserProvider`. Task 4 owns actually calling `connect()` and
// subscribing to `events` from the app shell — this file only builds the
// reusable primitive and the provider that hands out a single shared instance.
//
// Package: signalr_hub (not signalr_netcore, the plan's original guess — see
// task-3-report.md for why: signalr_netcore is stale, 130/160 pub points, 56
// open GitHub issues including reconnect-breaking bugs; signalr_hub is its
// actively-maintained, verified-publisher successor with a perfect pub score
// and explicit reconnection-stability fixes).
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signalr_hub/signalr_client.dart';

import '../../core/config/env.dart';
import '../../presentation/providers/auth_providers.dart';

/// A parsed `"ReceiveEvent"` hub message: `{ type, data, occurredAt }` on the wire,
/// `occurredAt` deliberately dropped here (no current consumer needs it — add it back
/// if/when one does).
extension type RealtimeEvent._(({String type, Map<String, dynamic> data}) _value) {
  factory RealtimeEvent.fromHubPayload(Map<String, dynamic> raw) => RealtimeEvent._((
    type: raw['type'] as String,
    data: (raw['data'] as Map).cast<String, dynamic>(),
  ));

  String get type => _value.type;
  Map<String, dynamic> get data => _value.data;
}

class RealtimeConnection {
  RealtimeConnection({required String Function() accessTokenProvider})
    : _accessTokenProvider = accessTokenProvider;

  final String Function() _accessTokenProvider;
  HubConnection? _connection;
  final _eventsController = StreamController<RealtimeEvent>.broadcast();

  /// Parsed `ReceiveEvent` messages. A plain broadcast stream — safe for any number of
  /// listeners (or none), and never closes on connection loss.
  Stream<RealtimeEvent> get events => _eventsController.stream;

  /// Connects if not already connected/connecting. No-op when there's no access token
  /// (unauthenticated) or a connection attempt is already in flight/established.
  ///
  /// Never throws: a failed connection just leaves this best-effort feature dark, callers
  /// don't need to handle it.
  Future<void> connect() async {
    if (_connection != null) return;

    if (_accessTokenProvider().isEmpty) return;

    // accessTokenFactory (not a token baked into the URL) so every reconnect attempt —
    // automatic or via reconnect() — fetches the *current* token rather than replaying
    // whatever was valid when connect() was first called. The package appends it as
    // ?access_token=<token> on the websocket handshake URL itself, matching the backend's
    // JwtBearerEvents.OnMessageReceived handling for the /api/hubs path prefix.
    final connection = HubConnectionBuilder()
        .withUrl(
          '${Env.apiBaseUrl}/api/hubs/notifications',
          options: HttpConnectionOptions(
            accessTokenFactory: () async => _accessTokenProvider(),
          ),
        )
        .withAutomaticReconnect()
        .build();

    connection.on('ReceiveEvent', (arguments) {
      if (arguments == null || arguments.isEmpty) return;
      final raw = arguments[0];
      if (raw is Map) {
        _eventsController.add(RealtimeEvent.fromHubPayload(raw.cast<String, dynamic>()));
      }
    });

    _connection = connection;

    try {
      await connection.start();
    } catch (_) {
      // Best-effort: negotiation/handshake failure (offline, hub unreachable, expired
      // token, ...) must not propagate. Clear so a later connect()/reconnect() can retry.
      _connection = null;
    }
  }

  /// Forces a fresh connection attempt (e.g. after the access token changes, or the app
  /// resumes from background). `withAutomaticReconnect()` already handles transient drops
  /// on its own — this is for cases that need an explicit restart.
  Future<void> reconnect() async {
    await _connection?.stop();
    _connection = null;
    await connect();
  }

  Future<void> dispose() async {
    await _connection?.stop();
    _connection = null;
    await _eventsController.close();
  }
}

/// The single app-wide [RealtimeConnection] instance. Riverpod's default caching gives us
/// the "one persistent connection regardless of how many screens are open" requirement for
/// free — every read returns the same instance until this provider is disposed.
///
/// Does NOT call `connect()` — that's Task 4's job, once the app shell knows it's
/// appropriate (e.g. the user is authenticated).
final realtimeConnectionProvider = Provider<RealtimeConnection>((ref) {
  final connection = RealtimeConnection(
    accessTokenProvider: () => ref.read(currentUserProvider)?.accessToken ?? '',
  );
  ref.onDispose(() => connection.dispose());
  return connection;
});
