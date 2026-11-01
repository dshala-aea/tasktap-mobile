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

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/notifications/notification_api_client.dart';

class MockDio extends Mock implements Dio {}

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

    test('ordinals past the end of the known list decode to Unknown without throwing', () {
      // A server newer than this build (a type appended after WorkLogCorrected, ordinal 24)
      // must degrade to the neutral label, never crash the list.
      for (final ordinal in const [25, 26, 999, -1]) {
        final dto = NotificationDto.fromJson(_baseJson(type: ordinal, deliveryType: 0));
        expect(dto.type, 'Unknown', reason: 'ordinal $ordinal');
      }
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
        'AbsenceRequestDecided',
        'MaintenanceDue',
        'OvertimeThresholdCrossed',
        'ReportReviewed',
        'ReportRejected',
        'ReportCancelled',
        'AbsenceRequestSubmitted',
        'CantiereAssigned',
        'SeatLimitAlert',
        'TicketOverdueDigest',
        'WorkLogCorrected',
      ];

      for (var i = 0; i < expected.length; i++) {
        final dto = NotificationDto.fromJson(_baseJson(type: i, deliveryType: 0));
        expect(dto.type, expected[i], reason: 'ordinal $i');
      }
    });

    test('a WorkLogCorrected name string (FCM data.type shape) passes through unchanged', () {
      final dto = NotificationDto.fromJson(_baseJson(type: 'WorkLogCorrected', deliveryType: 0));
      expect(dto.type, 'WorkLogCorrected');
    });
  });

  group('getNotification', () {
    late MockDio dio;
    late NotificationApiClient client;

    setUp(() {
      dio = MockDio();
      client = NotificationApiClient(dio);
      registerFallbackValue(Options());
    });

    test('parses the by-id entity payload and ignores the fields the DTO does not model', () async {
      when(() => dio.get<dynamic>('/api/notifications/n1')).thenAnswer(
        (_) async => Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/notifications/n1'),
          statusCode: 200,
          data: {
            ..._baseJson(type: 11, deliveryType: 0),
            'readAt': null,
            'relatedEntityId': null,
            'relatedEntityType': null,
            'scheduledFor': null,
            'sentAt': null,
            // The by-id endpoint returns the entity, which also carries these.
            'deliveryError': 'smtp timeout',
            'retryCount': 2,
          },
        ),
      );

      final dto = await client.getNotification('n1');

      expect(dto.id, 'n1');
      expect(dto.title, 'Titolo');
      expect(dto.message, 'Messaggio');
      expect(dto.type, 'SystemAnnouncement');
      expect(dto.isRead, isFalse);
    });

    test('surfaces a 404 as a DioException the caller can classify', () async {
      final options = RequestOptions(path: '/api/notifications/missing');
      when(() => dio.get<dynamic>('/api/notifications/missing')).thenThrow(
        DioException(
          requestOptions: options,
          response: Response<dynamic>(requestOptions: options, statusCode: 404),
          type: DioExceptionType.badResponse,
        ),
      );

      await expectLater(
        client.getNotification('missing'),
        throwsA(
          isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 404),
        ),
      );
    });
  });
}
