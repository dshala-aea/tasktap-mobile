// Seam between "a push was tapped" and "the router can take a push()".

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/deep_link_drainer.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';

void main() {
  late DeepLinkIntent? pending;
  late bool ready;
  late List<String> pushed;
  late DeepLinkDrainer drainer;

  setUp(() {
    pending = null;
    ready = false;
    pushed = [];
    drainer = DeepLinkDrainer(
      take: () {
        final p = pending;
        pending = null;
        return p;
      },
      isReady: () => ready,
      push: pushed.add,
    );
  });

  test('intent emitted before auth is kept, then drained once after auth', () {
    pending = const DeepLinkIntent(entityType: 'Ticket', entityId: 't1');

    drainer.drain(); // not authenticated yet
    expect(pushed, isEmpty);
    expect(pending, isNotNull, reason: 'must not be consumed while not ready');

    ready = true; // auth resolved
    drainer.drain();
    drainer.drain(); // e.g. a second auth/refresh event
    expect(pushed, ['/ticket/t1']);
  });

  test('nothing pending -> no navigation', () {
    ready = true;
    drainer.drain();
    expect(pushed, isEmpty);
  });

  test('unroutable intent is consumed and does not navigate', () {
    ready = true;
    pending = const DeepLinkIntent(entityType: 'Magazzino', entityId: 'm1');
    drainer.drain();
    expect(pushed, isEmpty);
    expect(pending, isNull);
  });
}
