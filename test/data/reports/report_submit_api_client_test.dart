// dart format width=100
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/reports/report_submit_api_client.dart';

class MockDio extends Mock implements Dio {}

/// ReportSubmitApiClient.uploadAttachment — the optional multipart `kind` field that lets a
/// signature be staged through the generic attachments endpoint before the report exists.
void main() {
  late MockDio dio;
  late ReportSubmitApiClient client;
  late File file;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
    registerFallbackValue(Options());
  });

  setUp(() async {
    dio = MockDio();
    client = ReportSubmitApiClient(dio);
    file = await File(
      '${Directory.systemTemp.path}/tasktap_submit_client_${DateTime.now().microsecondsSinceEpoch}.png',
    ).create();
    await file.writeAsBytes(List<int>.filled(16, 1));
  });

  tearDown(() async {
    if (await file.exists()) await file.delete();
  });

  Future<Map<String, String>> uploadAndCaptureFields({String? kind}) async {
    FormData? sent;
    when(
      () => dio.post<Map<String, dynamic>>(
        '/api/reports/r-1/attachments',
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((inv) async {
      sent = inv.namedArguments[#data] as FormData;
      return Response<Map<String, dynamic>>(
        data: {'allegatoId': 'a-1', 'url': '/x'},
        statusCode: 200,
        requestOptions: RequestOptions(path: '/api/reports/r-1/attachments'),
      );
    });
    await client.uploadAttachment(
      reportId: 'r-1',
      localPath: file.path,
      fileName: 'f.png',
      contentType: 'image/png',
      kind: kind,
    );
    return {for (final f in sent!.fields) f.key: f.value};
  }

  test('sends the kind form field when set', () async {
    final fields = await uploadAndCaptureFields(kind: 'signature-customer');
    expect(fields['kind'], 'signature-customer');
  });

  test('omits the kind form field for a photo', () async {
    final fields = await uploadAndCaptureFields();
    expect(fields.containsKey('kind'), isFalse);
  });

  test('a missing local file surfaces as a FileSystemException before any request', () async {
    await file.delete();
    await expectLater(
      client.uploadAttachment(
        reportId: 'r-1',
        localPath: file.path,
        fileName: 'f.png',
        contentType: 'image/png',
      ),
      throwsA(isA<FileSystemException>()),
    );
    verifyNever(
      () => dio.post<Map<String, dynamic>>(any(), data: any(named: 'data'), options: any(named: 'options')),
    );
  });
}
