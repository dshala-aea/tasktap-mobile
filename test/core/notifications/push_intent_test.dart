// The push payload → route decision, tested without Firebase.
//
// The backend already puts `notificationId` in the FCM data (alongside type and the optional
// entity pair), so an entity-less push can open the notification's own page. This is the pure
// mapping the tap handler uses.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';

void main() {
  test('an entity-less push with a notificationId resolves to the detail page', () {
    final intent = intentFromPushData({
      'notificationId': 'n-1',
      'type': 'SystemAnnouncement',
      'relatedEntityType': '',
      'relatedEntityId': '',
    });

    expect(intent, isNotNull);
    expect(intent!.resolveRoute(), '/altro/notifiche/n-1');
  });

  test('an entity push still resolves to the entity', () {
    final intent = intentFromPushData({
      'notificationId': 'n-1',
      'type': 'TicketAssigned',
      'relatedEntityType': 'Ticket',
      'relatedEntityId': 't-1',
    });

    expect(intent, isNotNull);
    expect(intent!.resolveRoute(), '/ticket/t-1');
  });

  test('an empty payload opens nothing', () {
    expect(intentFromPushData(const {}), isNull);
  });
}
