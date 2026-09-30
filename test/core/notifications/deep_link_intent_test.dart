// Route mapping for notification taps (list tap and push tap share DeepLinkIntent).

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/notification_service.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';

String? _route(String type, [String id = 'abc-1']) =>
    DeepLinkIntent(entityType: type, entityId: id).resolveRoute();

void main() {
  group('DeepLinkIntent.resolveRoute routable types', () {
    test('Ticket -> ticket detail', () {
      expect(_route('Ticket'), AppRoutes.ticketDetailPath('abc-1'));
      expect(_route('Ticket'), '/ticket/abc-1');
    });
    test('Cantiere -> cantiere detail', () {
      expect(_route('Cantiere'), AppRoutes.cantieriDetailPath('abc-1'));
      expect(_route('Cantiere'), '/cantieri/abc-1');
    });
    test('Report -> report view by id (not the list)', () {
      expect(_route('Report'), '/altro/rapportini/view/abc-1');
    });
    test('AbsenceRequest -> ferie list', () {
      expect(_route('AbsenceRequest'), AppRoutes.altroFerie);
    });
    test('Schedule -> calendario', () {
      expect(_route('Schedule'), AppRoutes.calendario);
    });
  });

  group('DeepLinkIntent.resolveRoute types without a mobile destination', () {
    for (final t in const [
      'WorkLog',
      'ProdottoAssistenza',
      'User',
      'Magazzino',
      'Tenant',
      'License',
      'Unknown',
      '',
    ]) {
      test('$t -> null', () => expect(_route(t), isNull));
    }
  });
}
