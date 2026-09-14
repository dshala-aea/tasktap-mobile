// test/core/location/geocoding_service_test.dart
//
// Unit tests for GeocodingService. Uses mocktail to mock Dio — no real network calls, and never
// hits the real Nominatim API (see this file's own tests for what happens on failure: silent
// null, never a thrown exception, so a test hitting the real API by accident would fail loudly
// rather than passing coincidentally).

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

void main() {
  late MockDio mockDio;
  late GeocodingService service;

  setUp(() {
    mockDio = MockDio();
    service = GeocodingService(dio: mockDio);
  });

  group('geocode', () {
    test(
      'returns the first match\'s lat/lng on a successful response',
      () async {
        when(
          () => mockDio.get<List<dynamic>>(
            '/search',
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer(
          (_) async => _okResponse([
            {'lat': '45.4642', 'lon': '9.1900'},
          ], '/search'),
        );

        final result = await service.geocode('Via Roma 1, Milano');

        expect(result, isNotNull);
        expect(result!.lat, 45.4642);
        expect(result.lng, 9.1900);
      },
    );

    test('sends the address as q, format=json and limit=1', () async {
      when(
        () => mockDio.get<List<dynamic>>(
          '/search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/search'));

      await service.geocode('Via Roma 1, Milano');

      final captured = verify(
        () => mockDio.get<List<dynamic>>(
          '/search',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;

      final params = captured.first as Map<String, dynamic>;
      expect(params['q'], 'Via Roma 1, Milano');
      expect(params['format'], 'json');
      expect(params['limit'], 1);
    });

    test('returns null for a blank address without calling Dio', () async {
      final result = await service.geocode('   ');

      expect(result, isNull);
      verifyNever(
        () => mockDio.get<List<dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      );
    });

    test('returns null when Nominatim finds no match', () async {
      when(
        () => mockDio.get<List<dynamic>>(
          '/search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/search'));

      final result = await service.geocode('Indirizzo inesistente');

      expect(result, isNull);
    });

    test('returns null (never throws) on a DioException', () async {
      when(
        () => mockDio.get<List<dynamic>>(
          '/search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        DioException(requestOptions: RequestOptions(path: '/search')),
      );

      final result = await service.geocode('Via Roma 1, Milano');

      expect(result, isNull);
    });

    test('returns null when the match has no parseable coordinates', () async {
      when(
        () => mockDio.get<List<dynamic>>(
          '/search',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse([
          {'lat': 'not-a-number', 'lon': '9.19'},
        ], '/search'),
      );

      final result = await service.geocode('Via Roma 1, Milano');

      expect(result, isNull);
    });
  });
}
