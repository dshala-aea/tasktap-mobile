import 'package:flutter_test/flutter_test.dart';
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
}
