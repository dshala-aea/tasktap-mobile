// Smart-working request notifications: where a tap lands.
//
// The backend sends `RelatedEntityType = 'SmartWorkingRequest'` for both the submission and the
// decision notification (the notification *type* stays AbsenceRequestSubmitted/Decided), and the
// request id means nothing to any screen: the list is the only mobile destination.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';

void main() {
  test('smartWorkingRequestSubmission_routesToTheApprovalQueue', () {
    final intent = DeepLinkIntent.fromNotification(
      type: 'AbsenceRequestSubmitted',
      entityType: 'SmartWorkingRequest',
      entityId: 'sw-1',
    );

    expect(intent, isNotNull);
    expect(intent!.resolveRoute(), AppRoutes.approvazioni(tab: 'smart-working'));
    expect(intent.resolveRoute(), '/altro/approvazioni?tab=smart-working');
  });

  test('a submitted smart-working request without an id still reaches the queue', () {
    final intent = DeepLinkIntent.fromNotification(
      type: 'AbsenceRequestSubmitted',
      entityType: 'SmartWorkingRequest',
      entityId: '',
    );

    expect(intent?.resolveRoute(), AppRoutes.approvazioni(tab: 'smart-working'));
  });

  test('an id-less submitted request beats the notification-detail fallback', () {
    final intent = DeepLinkIntent.fromNotification(
      type: 'AbsenceRequestSubmitted',
      entityType: 'AbsenceRequest',
      entityId: '',
      notificationId: 'n-1',
    );

    expect(intent?.resolveRoute(), AppRoutes.approvazioni(tab: 'assenze'));
  });

  test('a submitted notification with no entity type defaults to the absence tab', () {
    final intent = DeepLinkIntent.fromNotification(type: 'AbsenceRequestSubmitted');

    expect(intent?.resolveRoute(), AppRoutes.approvazioni(tab: 'assenze'));
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
