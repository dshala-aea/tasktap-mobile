// Smart-working request notifications: where a tap lands.
//
// The backend sends `RelatedEntityType = 'SmartWorkingRequest'` for both the submission and the
// decision notification (the notification *type* stays AbsenceRequestSubmitted/Decided), and the
// request id means nothing to any screen: the list is the only mobile destination.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';

void main() {
  test('smartWorkingRequestNotification_routesToTheSmartWorkingList', () {
    final intent = DeepLinkIntent.fromNotification(
      type: 'AbsenceRequestSubmitted',
      entityType: 'SmartWorkingRequest',
      entityId: 'sw-1',
    );

    expect(intent, isNotNull);
    expect(intent!.resolveRoute(), AppRoutes.altroSmartWorking);
    expect(intent.resolveRoute(), '/altro/smart-working');
  });

  test('a smart-working id no screen can resolve still routes to the list', () {
    // The route is the list, so it must not interpolate the id the way Ticket/Report do.
    for (final id in const ['sw-1', 'not-a-real-id', '..']) {
      final intent = DeepLinkIntent.fromNotification(
        type: 'AbsenceRequestDecided',
        entityType: 'SmartWorkingRequest',
        entityId: id,
      );
      expect(intent?.resolveRoute(), AppRoutes.altroSmartWorking, reason: id);
    }

    expect(
      const DeepLinkIntent(entityType: 'SmartWorkingRequest', entityId: 'anything')
          .resolveRoute(),
      AppRoutes.altroSmartWorking,
    );
  });
}
