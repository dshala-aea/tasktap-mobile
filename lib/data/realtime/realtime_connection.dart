// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// RealtimeConnection
//
// One persistent SignalR connection to NotificationHub, regardless of how many screens are
// open. Two independent message kinds arrive on it:
//   - "ReceiveEvent": tenant-wide broadcast messages (`{type,data,occurredAt}`), parsed into
//     [RealtimeEvent] and exposed via [events].
//   - "ReceiveNotification": per-user real notifications (`{id,title,message,createdAt}` — every
//     ticket-assigned/report-reviewed/etc. notification the backend creates for this user),
//     parsed into [RealtimeNotificationMessage] and exposed via [notifications]. The web frontend
//     already listens for this; this is the mobile side of the same delivery path.
//
// Auth is via an
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

import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// A parsed `"ReceiveNotification"` hub message: `{ id, title, message, createdAt }` on the
/// wire — a per-user real notification (the same row `GET /api/notifications` would eventually
/// return), not a tenant-wide broadcast. Mirrors [RealtimeEvent]'s `extension type` pattern for
/// structural consistency with the rest of this file.
extension type RealtimeNotificationMessage._(
  ({String id, String title, String message, DateTime createdAt}) _value
) {
  factory RealtimeNotificationMessage.fromHubPayload(Map<String, dynamic> raw) =>
      RealtimeNotificationMessage._((
        id: raw['id'] as String,
        title: raw['title'] as String,
        message: raw['message'] as String,
        createdAt: DateTime.parse(raw['createdAt'] as String),
      ));

  String get id => _value.id;
  String get title => _value.title;
  String get message => _value.message;
  DateTime get createdAt => _value.createdAt;
}

class RealtimeConnection {
  RealtimeConnection({required String Function() accessTokenProvider})
    : _accessTokenProvider = accessTokenProvider;

  final String Function() _accessTokenProvider;
  HubConnection? _connection;
  final _eventsController = StreamController<RealtimeEvent>.broadcast();
  final _notificationsController = StreamController<RealtimeNotificationMessage>.broadcast();

  /// Parsed `ReceiveEvent` messages. A plain broadcast stream — safe for any number of
  /// listeners (or none), and never closes on connection loss.
  Stream<RealtimeEvent> get events => _eventsController.stream;

  /// Parsed `ReceiveNotification` messages — this user's own real notifications, delivered as
  /// they're created rather than waiting for the next poll/resume. Same broadcast-stream
  /// contract as [events].
  Stream<RealtimeNotificationMessage> get notifications => _notificationsController.stream;

  /// Connects if not already connected/connecting. No-op when there's no access token
  /// (unauthenticated), no configured API base URL, or a connection attempt is already in
  /// flight/established.
  ///
  /// The "already in flight/established" check is state-aware, not just null-aware: the
  /// package's automatic-reconnect retry policy (`withAutomaticReconnect()`'s default delays,
  /// `[0, 2000, 10000, 30000, null]`) gives up permanently after ~42s of failed retries, and
  /// nothing about that gives up transitions `_connection` back to null on its own — the
  /// `onclose` handler registered below is what does that, for exactly this reason. Without it,
  /// a `_connection` left non-null-but-actually-`disconnected` would make this method a
  /// permanent no-op for the rest of the app session.
  ///
  /// Never throws: a failed connection (including a build-time failure, e.g. a malformed/empty
  /// URL) just leaves this best-effort feature dark, callers don't need to handle it.
  Future<void> connect() async {
    final existing = _connection;
    if (existing != null && existing.state != HubConnectionState.disconnected) return;

    if (_accessTokenProvider().isEmpty || Env.apiBaseUrl.isEmpty) return;

    try {
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

      connection.on('ReceiveNotification', _handleReceiveNotification);

      // Fires on ANY close — a clean stop(), the server closing it, or the automatic-reconnect
      // policy above exhausting its retries and giving up. Clearing `_connection` here (rather
      // than only in the start() failure path below) is what keeps the guard above accurate: a
      // connection that's truly dead must look dead to the next connect() call.
      connection.onclose(({Object? error}) => _connection = null);

      _connection = connection;

      await connection.start();
    } catch (_) {
      // Best-effort: a build-time throw (malformed/empty URL) or a negotiation/handshake
      // failure (offline, hub unreachable, expired token, ...) must not propagate. Clear so a
      // later connect()/reconnect() can retry.
      _connection = null;
    }
  }

  /// Parses and emits a `ReceiveNotification` hub message, in the same defensive style as the
  /// `ReceiveEvent` registration above (missing/empty `arguments`, or a non-`Map` payload, are
  /// silently dropped). Additionally wrapped in try/catch around the field-level parse itself:
  /// unlike `ReceiveEvent`'s payload (already tolerant of an unknown `type` downstream —
  /// realtime_event_router.dart just ignores it), a per-user notification with a missing/
  /// malformed field has no safe partial-render, so the only best-effort move is to drop the
  /// whole message rather than let it take down the app's one realtime connection.
  void _handleReceiveNotification(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    final raw = arguments[0];
    if (raw is! Map) return;
    try {
      _notificationsController.add(
        RealtimeNotificationMessage.fromHubPayload(raw.cast<String, dynamic>()),
      );
    } catch (_) {
      // Best-effort — see connect()'s own doc comment.
    }
  }

  /// Test-only hook that invokes [_handleReceiveNotification] directly, the same way SignalR
  /// itself would call it via `connection.on('ReceiveNotification', ...)`. Exists because the
  /// real registration only happens inside [connect] against a live `HubConnection`, which
  /// (per this file's own test suite) can't be faked without a real server on the other end of a
  /// websocket handshake — this lets the defensive parsing behavior stay unit-testable anyway.
  @visibleForTesting
  void handleReceiveNotificationForTest(List<Object?>? arguments) =>
      _handleReceiveNotification(arguments);

  /// Forces a fresh connection attempt (e.g. after the access token changes, or the app
  /// resumes from background). `withAutomaticReconnect()` already handles transient drops
  /// on its own — this is for cases that need an explicit restart.
  Future<void> reconnect() async {
    await stop();
    await connect();
  }

  /// Stops the underlying connection (if any) without closing [events] — unlike [dispose], this
  /// instance stays reusable for a later [connect()] call. Used when a caller needs the
  /// connection genuinely torn down (e.g. HomeShell.dispose() on a forced sign-out) but the
  /// `RealtimeConnection` instance itself survives, because it's a root-scoped provider that the
  /// next mount (possibly a different signed-in user/tenant) will reuse rather than recreate —
  /// see realtime_event_router.dart's `initRealtimeEventWatcher` for why that matters.
  Future<void> stop() async {
    try {
      await _connection?.stop();
    } catch (_) {
      // Best-effort — see connect()'s own doc comment. A stop() failure must not block clearing
      // `_connection` below, which is what actually matters: it's what lets the next connect()
      // treat this as a fresh start rather than "already connected".
    }
    _connection = null;
  }

  Future<void> dispose() async {
    await stop();
    await _eventsController.close();
    await _notificationsController.close();
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
