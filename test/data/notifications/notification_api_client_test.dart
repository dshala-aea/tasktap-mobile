// dart format width=100
// test/data/notifications/notification_api_client_test.dart
//
// Regression coverage for NotificationDto.fromJson — `type`/`deliveryType` used to be cast
// `as String`, but NotificationTypeEnum/NotificationDeliveryTypeEnum carry no
// [JsonConverter(JsonStringEnumConverter)] server-side, so the wire value is a raw int ordinal.
// Every real GET /api/notifications response threw "type 'int' is not a subtype of type
// 'String'" inside NotificheNotifier.refresh — silently swallowed there until this session's
// separate fix added error-surfacing, which is what actually caught this bug live. See
// `frontend/src/lib/api/enums.ts`'s `notificationTypeFromWire` for the same bug already found
// and fixed on the web client for this exact field.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/notifications/notification_api_client.dart';

Map<String, dynamic> _baseJson({dynamic type, dynamic deliveryType}) => {
  'id': 'n1',
  'userId': 'u1',
  'title': 'Titolo',
  'message': 'Messaggio',
  'type': type,
  'deliveryType': deliveryType,
  'isRead': false,
  'isDelivered': true,
  'createdAt': '2026-08-31T10:00:00Z',
};

void main() {
  group('NotificationDto.fromJson', () {
    test('decodes an int ordinal type/deliveryType (the real wire shape)', () {
      final dto = NotificationDto.fromJson(_baseJson(type: 9, deliveryType: 0));

      expect(dto.type, 'WorkLogSubmitted');
      expect(dto.deliveryType, 'InApp');
    });

    test('still accepts a string type/deliveryType, if the server ever sends one', () {
      final dto = NotificationDto.fromJson(_baseJson(type: 'TicketAssigned', deliveryType: 'Push'));

      expect(dto.type, 'TicketAssigned');
      expect(dto.deliveryType, 'Push');
    });

    test('falls back to a neutral label for an out-of-range or unrecognised value, no throw', () {
      final dto = NotificationDto.fromJson(_baseJson(type: 999, deliveryType: 'Whatever'));

      expect(dto.type, 'Unknown');
      expect(dto.deliveryType, 'Whatever');
    });

    test('every named NotificationTypeEnum ordinal decodes to its real name', () {
      const expected = [
        'TicketAssigned',
        'TicketStatusChanged',
        'TicketCreated',
        'TicketCompleted',
        'TicketOverdue',
        'ScheduleReminder',
        'ScheduleStarting',
        'LicenseExpiring',
        'LicenseExpired',
        'WorkLogSubmitted',
        'DocumentUploaded',
        'SystemAnnouncement',
        'UserMention',
        'LowStock',
      ];

      for (var i = 0; i < expected.length; i++) {
        final dto = NotificationDto.fromJson(_baseJson(type: i, deliveryType: 0));
        expect(dto.type, expected[i], reason: 'ordinal $i');
      }
    });
  });
}
