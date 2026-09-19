// dart format width=100
// test/features/ticket/ticket_detail_api_client_upload_test.dart
//
// Covers TicketDetailApiClient.uploadAttachment — the multipart POST behind
// ticket detail's Allegati upload (see TicketAttachmentUploadQueue, which
// owns the offline-queue/retry behaviour built on top of this call).

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  late MockDio mockDio;
  late TicketDetailApiClient client;
  late File tempFile;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
    registerFallbackValue(Options());
  });

  setUp(() async {
    mockDio = MockDio();
    client = TicketDetailApiClient(mockDio);
    tempFile = await File(
      '${Directory.systemTemp.path}/tasktap_upload_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ).create();
    await tempFile.writeAsBytes(List<int>.filled(1024, 1));
  });

  tearDown(() async {
    if (await tempFile.exists()) await tempFile.delete();
  });

  test('posts multipart form data to /api/tickets/{id}/attachments', () async {
    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/tickets/ticket-1/attachments',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => _okResponse({
        'allegatoId': 'att-server-1',
        'contentUrl': '/api/tickets/ticket-1/attachments/att-server-1/content',
      }, '/api/tickets/ticket-1/attachments'),
    );

    final result = await client.uploadAttachment(
      ticketId: 'ticket-1',
      localPath: tempFile.path,
      fileName: 'foto.jpg',
      contentType: 'image/jpeg',
    );

    expect(result.allegatoId, 'att-server-1');
    expect(result.contentUrl, '/api/tickets/ticket-1/attachments/att-server-1/content');

    final captured = verify(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/tickets/ticket-1/attachments',
        data: captureAny(named: 'data'),
        options: any(named: 'options'),
      ),
    ).captured;
    expect(captured.single, isA<FormData>());
  });

  test('propagates a DioException on failure — the queue is what turns it into a sentence', () async {
    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/tickets/ticket-1/attachments',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/api/tickets/ticket-1/attachments'),
        type: DioExceptionType.connectionError,
      ),
    );

    expect(
      () => client.uploadAttachment(
        ticketId: 'ticket-1',
        localPath: tempFile.path,
        fileName: 'foto.jpg',
        contentType: 'image/jpeg',
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('kMaxTicketAttachmentBytes is the backend cap: 10 MB', () {
    expect(kMaxTicketAttachmentBytes, 10 * 1024 * 1024);
  });
}
