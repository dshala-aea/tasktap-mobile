import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/config/env.dart';
import 'package:tasktap_mobile/data/realtime/realtime_connection.dart';

void main() {
  test('parses a ReceiveEvent payload into a RealtimeEvent', () {
    final raw = {
      'type': 'TicketUpdated',
      'data': {'ticketId': 't1'},
      'occurredAt': '2026-09-04T10:00:00Z',
    };

    final event = RealtimeEvent.fromHubPayload(raw);

    expect(event.type, 'TicketUpdated');
    expect(event.data['ticketId'], 't1');
  });

  // The rest of connect()/reconnect()'s behavior (the state-aware "already connected" guard, the
  // onclose handler that clears `_connection` so a dead automatic-reconnect doesn't wedge future
  // connect() calls forever) exercises the real signalr_hub HubConnection, which this class builds
  // internally rather than accepting as an injectable seam — there's no way to fake its
  // HubConnectionState transitions without a real (or fake) server on the other end of a websocket
  // handshake. That behavior is verified by code inspection instead (see realtime_connection.dart's
  // own doc comments); the tests below cover what *is* cleanly testable without network: the guard
  // clauses that must return before ever touching HubConnectionBuilder.
  group('connect() no-op guards', () {
    test('is a no-op with no configured API base URL (this test suite never sets '
        'API_BASE_URL, matching a misconfigured/unset environment in production)', () async {
      expect(Env.apiBaseUrl, isEmpty);

      final connection = RealtimeConnection(accessTokenProvider: () => 'a-token');

      // Must not throw and must not attempt to build/start a real HubConnection — if it did,
      // stop()/dispose() immediately after would be operating on a live connection instead of a
      // never-started one.
      await connection.connect();
      await connection.stop();
      await connection.dispose();
    });

    test('is a no-op with no access token (unauthenticated)', () async {
      final connection = RealtimeConnection(accessTokenProvider: () => '');

      await connection.connect();
      await connection.stop();
      await connection.dispose();
    });
  });

  test('stop() and dispose() are both safe to call before connect() ever ran', () async {
    final connection = RealtimeConnection(accessTokenProvider: () => '');

    // stop() must be idempotent and non-throwing even with no underlying connection — this is
    // what the reconnect-teardown path (initRealtimeEventWatcher's cancel function, on sign-out)
    // relies on when the app never actually got a connection off the ground.
    await connection.stop();
    await connection.stop();
    await connection.dispose();
  });
}
