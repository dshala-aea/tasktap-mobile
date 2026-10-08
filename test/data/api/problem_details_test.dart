// dart format width=100
// test/data/api/problem_details_test.dart
//
// The reader for this backend's RFC 7807 problem bodies. Pure: an error in, a machine member out —
// no Dio, no database, no queue. It exists because the ticket repair path needs the ONE member the
// server writes when it refuses a reference (`field`), and that member is not where a reader that
// assumed the textbook ProblemDetails shape would look for it.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/api/problem_details.dart';

/// A `not_found` as it actually arrives: a raw [DioException] (dio installs no error mapper in
/// `dioProvider`), carrying the problem body as decoded JSON.
DioException notFound(Map<String, dynamic> body, {int statusCode = 404}) => DioException(
  requestOptions: RequestOptions(path: '/api/tickets'),
  response: Response(
    requestOptions: RequestOptions(path: '/api/tickets'),
    statusCode: statusCode,
    data: body,
  ),
);

void main() {
  test('field is read from the flat root of the problem body', () {
    expect(
      ProblemDetails.fieldOf(notFound({'code': 'not_found', 'field': 'customerId'})),
      'customerId',
    );
  });

  /// The shape a nested reader would have expected, and must NOT be what this accepts: the
  /// extensions are JsonExtensionData, so they sit at the root. A test pinning the wrong shape would
  /// be worse than no test.
  test('a nested extensions object is not where the field lives', () {
    expect(
      ProblemDetails.fieldOf(
        notFound({
          'extensions': {'field': 'customerId'},
        }),
      ),
      isNull,
    );
  });

  test('a 400 is not a FK rejection, however it is shaped', () {
    final e = notFound({'code': 'validation_failed', 'field': 'customerId'}, statusCode: 400);
    expect(ProblemDetails.fieldOf(e), isNull);
  });

  test('an offline failure carries no body and no field', () {
    expect(
      ProblemDetails.fieldOf(
        DioException(
          requestOptions: RequestOptions(path: '/api/tickets'),
          type: DioExceptionType.connectionError,
        ),
      ),
      isNull,
    );
  });

  // `statusOf`/`bodyOf` are the helpers `fieldOf` is built on, and the queue's own catch reads a
  // status to decide. They are asserted directly so a change to either is caught here rather than
  // through a repairable row that quietly stops being repairable.
  test('statusOf reports the response status, and null for a request that never got one', () {
    expect(ProblemDetails.statusOf(notFound({'field': 'customerId'})), 404);
    expect(
      ProblemDetails.statusOf(
        DioException(
          requestOptions: RequestOptions(path: '/api/tickets'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
      isNull,
    );
  });

  test('bodyOf only returns a decoded JSON object — never a string, a list or nothing', () {
    expect(ProblemDetails.bodyOf(notFound({'field': 'customerId'})), {'field': 'customerId'});
    expect(
      ProblemDetails.bodyOf(
        DioException(
          requestOptions: RequestOptions(path: '/api/tickets'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/tickets'),
            statusCode: 502,
            data: '<html>Bad gateway</html>',
          ),
        ),
      ),
      isNull,
    );
    expect(ProblemDetails.bodyOf(Exception('not a DioException')), isNull);
  });

  test('an empty or non-string field is no field at all', () {
    expect(ProblemDetails.fieldOf(notFound({'field': ''})), isNull);
    expect(ProblemDetails.fieldOf(notFound({'field': 42})), isNull);
    expect(ProblemDetails.fieldOf(notFound(const {})), isNull);
  });
}
